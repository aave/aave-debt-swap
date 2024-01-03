// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';
import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {ReentrancyGuard} from 'aave-v3-periphery/contracts/dependencies/openzeppelin/ReentrancyGuard.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {IParaSwapAugustusRegistry} from '../interfaces/IParaSwapAugustusRegistry.sol';
import {IParaSwapAugustus} from '../interfaces/IParaSwapAugustus.sol';
import {IFlashLoanReceiver} from '../interfaces/IFlashLoanReceiver.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {IParaSwapRepayAdapter} from '../interfaces/IParaSwapRepayAdapter.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {BaseParaSwapBuyAdapter} from './BaseParaSwapBuyAdapter.sol';

/**
 * @title ParaSwapRepayAdapter
 * @notice Implements the logic of swapping collateral asset to another asset and repaying the received asset from swap
 * @dev Swaps the existing collateral asset to another asset. The asset received from swap will be repayed to the Aave pool
 * @author Aave Labs
 **/
abstract contract ParaSwapRepayAdapter is
  BaseParaSwapBuyAdapter,
  ReentrancyGuard,
  IFlashLoanReceiver,
  IParaSwapRepayAdapter
{
  using SafeERC20 for IERC20;

  // unique identifier to track usage via flashloan events
  uint16 public constant REFERRER = 13410; // uint16(uint256(keccak256(abi.encode('repay-swap-adapter'))) / type(uint16).max)

  /**
   * @dev Constructor
   * @param addressesProvider The address of the Aave PoolAddressesProvider contract
   * @param pool The address of the Aave Pool contract
   * @param augustusRegistry The address of the Paraswap AugustusRegistry contract
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
      IERC20(reserves[i]).safeApprove(address(POOL), type(uint256).max);
    }
  }

  /**
   * @notice Renews the reserve's allowance(of this contract) to infinite for the Aave pool
   * @param reserve the address of reserve
   */
  function renewAllowance(address reserve) public {
    IERC20(reserve).safeApprove(address(POOL), 0);
    IERC20(reserve).safeApprove(address(POOL), type(uint256).max);
  }

  /// @inheritdoc IParaSwapRepayAdapter
  function repayWithCollateral(
    RepayParams memory repayParams,
    FlashParams memory flashParams,
    PermitInput memory collateralATokenPermit
  ) external nonReentrant {
    repayParams.debtRepayAmount = getDebtRepayAmount(
      IERC20(repayParams.debtRepayAsset),
      repayParams.debtRepayMode,
      repayParams.offset,
      repayParams.debtRepayAmount,
      repayParams.user
    );
    if (flashParams.flashLoanAmount == 0) {
      uint256 excessBefore = IERC20(repayParams.collateralAsset).balanceOf(address(this));
      _swapAndRepay(repayParams, collateralATokenPermit);
      uint256 excessAfter = IERC20(repayParams.collateralAsset).balanceOf(address(this));
      uint256 excess = excessAfter > excessBefore ? excessAfter - excessBefore : 0;
      if (excess > 0) {
        _conditionalRenewAllowance(repayParams.collateralAsset, excess);
        _supply(repayParams.collateralAsset, excess, repayParams.user, REFERRER);
      }
    } else {
      _flash(repayParams, flashParams, collateralATokenPermit);
    }
  }

  /**
   * @notice Executes an operation after receiving the flash-borrowed assets
   * @dev Ensure that the contract can return the debt + premium, e.g., has
   *      enough funds to repay and has approved the Pool to pull the total amount
   *      only callable by Aave pool. Swaps(exact out) the received flash-borrowed asset to debtRepayAsset
   *      Repays the received debtRepayAsset to Aave pool
   *      flash-borrowed asset should be same as one of the collateral asset
   *      flash-borrowed asset will be pulled from user to repay the flashloan
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

    // swap(exact out) the flashLoanAsset to debtRepayAsset. (flashLoanAmount - amountSold) stays in the contract
    uint256 amountSold = _buyOnParaSwap(
      repayParams.offset,
      repayParams.paraswapData,
      IERC20Detailed(flashLoanAsset),
      IERC20Detailed(repayParams.debtRepayAsset),
      flashLoanAmount,
      repayParams.debtRepayAmount
    );
    // allowance to Aave pool contract for repaying the debt
    _conditionalRenewAllowance(repayParams.debtRepayAsset, repayParams.debtRepayAmount);
    POOL.repay(
      repayParams.debtRepayAsset,
      repayParams.debtRepayAmount,
      repayParams.debtRepayMode,
      repayParams.user
    );
    _pullATokenAndWithdraw(
      flashLoanAsset,
      repayParams.user,
      flashLoanAmount + flashLoanPremium - (flashLoanAmount - amountSold), //(flashLoanAmount - amountSold) is the amount remaining in the contract after buy order on paraswap.
      collateralATokenPermit
    );
    _conditionalRenewAllowance(flashLoanAsset, flashLoanAmount + flashLoanPremium);
    return true;
  }

  /**
   * @dev Swaps the collateral asset and repays the debt of received asset from swap
   * @param repayParams Decoded repay parameters
   * @param collateralATokenPermit Permit for withdrawing collateral token from the pool
   */
  function _swapAndRepay(
    RepayParams memory repayParams,
    PermitInput memory collateralATokenPermit
  ) internal returns (uint256) {
    uint256 collateralAmountReceived = _pullATokenAndWithdraw(
      repayParams.collateralAsset,
      repayParams.user,
      repayParams.maxCollateralAmountToSwap,
      collateralATokenPermit
    );
    // swap(exact out) collateralAsset to debtRepayAsset. It is not guaranteed that collateralAmountReceived will be used. So, there can be 
    // excess of collateralAsset which will be supplied to Aave pool on behalf of user
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
      repayParams.user
    );
    return amountSold;
  }

  /** 
   * @dev encodes the parameter required by executeOperation function of this contract for performing swap and repay.
   *      Flash-borrows the collateral asset from the Aave pool 
   * @param repayParams struct describing the repay swap 
   * @param flashParams struct describing flashloan params
   * @param collateralATokenPermit optional permit for old collateral's aToken
   */
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

    POOL.flashLoan(address(this), assets, amounts, interestRateModes, address(this), params, REFERRER);
  }

  /**
   * @dev Checks if the asset's allowance to Aave pool is greater than or equal to minAmount, 
   *      else renews the asset's allowance to infinite for the Aave pool
   * @param asset address of asset 
   * @param minAmount minimum required allowance to Aave pool
   */
  function _conditionalRenewAllowance(address asset, uint256 minAmount) internal {
    uint256 allowance = IERC20(asset).allowance(address(this), address(POOL));
    if (allowance < minAmount) {
      renewAllowance(asset);
    }
  }

  /** 
   * @dev returns the amount of debt to repay
   * @param debtAsset address of asset to repay the debt
   * @param rateMode interest rate mode for the debt to repay(i.e. STABLE or VARIABLE)
   * @param buyAllBalanceOffset offset in calldata in case of all debt is to be repaid
   * @param debtRepayAmount the amount of debt to repay
   * @param initiator the user for whom the debt is to be repaid
   * @return the amount of debt to be repaid
   */
  function getDebtRepayAmount(
    IERC20 debtAsset,
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
}
