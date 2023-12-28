// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';
import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {IERC20WithPermit} from 'solidity-utils/contracts/oz-common/interfaces/IERC20WithPermit.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {ReentrancyGuard} from 'aave-v3-periphery/contracts/dependencies/openzeppelin/ReentrancyGuard.sol';
import {BaseParaSwapBuyAdapter} from './BaseParaSwapBuyAdapter.sol';
import {IParaSwapAugustusRegistry} from '../interfaces/IParaSwapAugustusRegistry.sol';
import {IParaSwapAugustus} from '../interfaces/IParaSwapAugustus.sol';
import {IFlashLoanReceiver} from '../interfaces/IFlashLoanReceiver.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {IParaSwapRepayAdapter} from '../interfaces/IParaSwapRepayAdapter.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';

/**
 * @title ParaSwapRepayAdapter
 * @notice ParaSwap Adapter to repay a debt of asset with collateral asset.
 * @author AAVE
 **/
abstract contract ParaSwapRepayAdapter is
  BaseParaSwapBuyAdapter,
  ReentrancyGuard,
  IFlashLoanReceiver,
  IParaSwapRepayAdapter
{
  using SafeERC20 for IERC20WithPermit;

  // unique identifier to track usage via flashloan events
  uint16 public constant REFERRER = 13410; // uint16(uint256(keccak256(abi.encode('repay-swap-adapter'))) / type(uint16).max)

  /**
   * @dev Constructor
   * @param addressesProvider The address for a Pool Addresses Provider.
   * @param pool The address of the Aave Pool
   * @param augustusRegistry address of ParaSwap Augustus Registry
   * @param owner The address to transfer ownership to
   */
  constructor(
    IPoolAddressesProvider addressesProvider,
    address pool,
    IParaSwapAugustusRegistry augustusRegistry,
    address owner
  ) BaseParaSwapBuyAdapter(addressesProvider, pool, augustusRegistry) {
    transferOwnership(owner);
    // set initial approval for all reserves
    address[] memory reserves = POOL.getReservesList();
    for (uint256 i = 0; i < reserves.length; i++) {
      IERC20WithPermit(reserves[i]).safeApprove(address(POOL), type(uint256).max);
    }
  }

  function renewAllowance(address reserve) public {
    IERC20WithPermit(reserve).safeApprove(address(POOL), 0);
    IERC20WithPermit(reserve).safeApprove(address(POOL), type(uint256).max);
  }

  ///@inheritdoc IParaSwapRepayAdapter
  function repayWithCollateral(
    RepayParams memory repayParams,
    FlashParams memory flashParams,
    PermitInput memory collateralATokenPermit
  ) external nonReentrant {
    repayParams.debtRepayAmount = getDebtRepayAmount(
      IERC20Detailed(repayParams.debtRepayAsset),
      repayParams.debtRepayMode,
      repayParams.offset,
      repayParams.debtRepayAmount,
      msg.sender
    );
    if (flashParams.flashLoanAmount == 0) {
      uint256 excessBefore = IERC20Detailed(repayParams.collateralAsset).balanceOf(address(this));
      _swapAndRepay(repayParams, collateralATokenPermit, msg.sender);
      uint256 excessAfter = IERC20Detailed(repayParams.collateralAsset).balanceOf(address(this));
      uint256 excess = excessAfter > excessBefore ? excessAfter - excessBefore : 0;
      if (excess > 0) {
        _conditionalRenewAllowance(repayParams.collateralAsset, excess);
        _supply(repayParams.collateralAsset, excess, msg.sender, REFERRER);
    }
    } else {
      _flash(repayParams, flashParams, collateralATokenPermit);
    }
  }

  function _flash(
    RepayParams memory repayParams,
    FlashParams memory flashParams,
    PermitInput memory collateralATokenPermit
  ) internal virtual {
    bytes memory params = abi.encode(repayParams, flashParams, collateralATokenPermit);
    address[] memory assets = new address[](1);
    assets[0] = flashParams.flashLoanAsset;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = flashParams.flashLoanAmount;
    uint256[] memory interestRateModes = new uint256[](1);
    interestRateModes[0] = 0;

    POOL.flashLoan(address(this), assets, amounts, interestRateModes, msg.sender, params, REFERRER);
  }

  /**
   * @notice Executes an operation after receiving the flash-borrowed assets
   * @dev Ensure that the contract can return the debt + premium, e.g., has
   *      enough funds to repay and has approved the Pool to pull the total amount
   * @param assets The addresses of the flash-borrowed assets
   * @param amounts The amounts of the flash-borrowed assets
   * @param premiums The premiums of the flash-borrowed assets
   * @param initiator The address of the flashloan initiator
   * @param params The byte-encoded params passed when initiating the flashloan
   * @return True if the execution of the operation succeeds, false otherwise
   */
  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external returns (bool) {
    require(msg.sender == address(POOL), 'CALLER_MUST_BE_POOL');
    require(initiator == address(this), 'INITIATOR_MUST_BE_THIS');

    (
      RepayParams memory repayParams,
      FlashParams memory flashParams,
      PermitInput memory collateralATokenPermit
    ) = abi.decode(params, (RepayParams, FlashParams, PermitInput));

    address flashLoanAsset = assets[0];
    uint256 flashLoanAmount = amounts[0];
    uint256 flashLoanPremium = premiums[0];

    uint256 excessBefore = IERC20Detailed(repayParams.debtRepayAsset).balanceOf(address(this));
    //swap the flashLoanAsset to debtRepaysset
    uint256 amountSold = _buyOnParaSwap(
      repayParams.offset,
      repayParams.paraswapData,
      IERC20Detailed(flashLoanAsset),
      IERC20Detailed(repayParams.debtRepayAsset),
      flashLoanAmount,
      repayParams.debtRepayAmount
    );
    _conditionalRenewAllowance(repayParams.debtRepayAsset, repayParams.debtRepayAmount);
    POOL.repay(
      repayParams.debtRepayAsset,
      repayParams.debtRepayAmount,
      repayParams.debtRepayMode,
      flashParams.user
    );
    _pullATokenAndWithdraw(
      flashLoanAsset,
      flashParams.user,
      flashLoanAmount + flashLoanPremium - (flashLoanAmount - amountSold), //(flashLoanAmount - amountSold) is the amount remaining in the contract after buy order on paraswap.
      flashParams.flashLoanAssetPermit
    );
    uint256 excessAfter = IERC20Detailed(repayParams.debtRepayAsset).balanceOf(address(this));
    uint256 excess = excessAfter > excessBefore ? excessAfter - excessBefore : 0;
    if (excess > 0) {
      _conditionalRenewAllowance(repayParams.debtRepayAsset, excess);
      _supply(repayParams.debtRepayAsset, excess, flashParams.user, REFERRER);
    }
    _conditionalRenewAllowance(flashLoanAsset, flashLoanAmount + flashLoanPremium);
    return true;
  }

  /**
   * @dev Swaps the collateral asset and repays the debt of new asset received from swap
   * @param repayParams Decoded repay parameters
   * @param collateralATokenPermit Permit for withdrawing collateral token from the pool
   * @param user address of user
   */
  function _swapAndRepay(
    RepayParams memory repayParams,
    PermitInput memory collateralATokenPermit,
    address user
  ) internal returns (uint256) {
    uint256 collateralAmountReceived = _pullATokenAndWithdraw(
      repayParams.collateralAsset,
      user,
      repayParams.maxCollateralAmountToSwap,
      collateralATokenPermit
    );
    uint256 excessBefore = IERC20Detailed(repayParams.debtRepayAsset).balanceOf(address(this));
    uint256 amountSold = _buyOnParaSwap(
      repayParams.offset,
      repayParams.paraswapData,
      IERC20Detailed(repayParams.collateralAsset),
      IERC20Detailed(repayParams.debtRepayAsset),
      collateralAmountReceived,
      repayParams.debtRepayAmount
    );

    _conditionalRenewAllowance(repayParams.debtRepayAsset, repayParams.debtRepayAmount);
    POOL.repay(
      repayParams.debtRepayAsset,
      repayParams.debtRepayAmount,
      repayParams.debtRepayMode,
      user
    );
    uint256 excessAfter = IERC20Detailed(repayParams.debtRepayAsset).balanceOf(address(this));
    uint256 excess = excessAfter > excessBefore ? excessAfter - excessBefore : 0;
    if (excess > 0) {
      _conditionalRenewAllowance(repayParams.collateralAsset, excess);
      _supply(repayParams.debtRepayAsset, excess, user, REFERRER);
    }
    return amountSold;
  }

  function getDebtRepayAmount(
    IERC20Detailed debtAsset,
    uint256 rateMode,
    uint256 buyAllBalanceOffset,
    uint256 debtRepayAmount,
    address initiator
  ) private view returns (uint256) {
    (address vDebtToken, address sDebtToken, ) = _getReserveData(address(debtAsset));

    address debtToken = DataTypes.InterestRateMode(rateMode) == DataTypes.InterestRateMode.STABLE
      ? sDebtToken
      : vDebtToken;

    uint256 currentDebt = IERC20(debtToken).balanceOf(initiator);

    if (buyAllBalanceOffset != 0) {
      require(currentDebt <= debtRepayAmount, 'INSUFFICIENT_AMOUNT_TO_REPAY');
      debtRepayAmount = currentDebt;
    } else {
      require(debtRepayAmount <= currentDebt, 'INVALID_DEBT_REPAY_AMOUNT');
    }

    return debtRepayAmount;
  }

  function _conditionalRenewAllowance(address asset, uint256 minAmount) internal {
    uint256 allowance = IERC20(asset).allowance(address(this), address(POOL));
    if (allowance < minAmount) {
      renewAllowance(asset);
    }
  }
}
