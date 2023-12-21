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
import {ICreditDelegationToken} from '../interfaces/ICreditDelegationToken.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {IParaSwapRepayAdapter} from '../interfaces/IParaSwapRepayAdapter.sol';

/**
 * @title ParaSwapLiquiditySwapAdapter
 * @notice ParaSwap Adapter to perform a swap of debt to another debt.
 * @author BGD labs
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
    CreditDelegationInput memory creditDelegationPermit,
    PermitInput memory collateralATokenPermit,
    PermitInput memory extraCollateralATokenPermit
  ) external nonReentrant {
    uint256 excessBefore = IERC20Detailed(repayParams.collateralAsset).balanceOf(address(this));
    // delegate credit
    if (creditDelegationPermit.deadline != 0) {
      ICreditDelegationToken(creditDelegationPermit.debtToken).delegationWithSig(
        msg.sender,
        address(this),
        creditDelegationPermit.value,
        creditDelegationPermit.deadline,
        creditDelegationPermit.v,
        creditDelegationPermit.r,
        creditDelegationPermit.s
      );
    }

    repayParams.debtRepayAmount = getDebtRepayAmount(
      IERC20Detailed(repayParams.debtRepayAsset),
      repayParams.debtRepayMode,
      repayParams.offset,
      repayParams.debtRepayAmount,
      msg.sender
    );
    if (repayParams.extraCollateralAsset == address(0)) {
      _swapAndRepay(repayParams, collateralATokenPermit, msg.sender);
    } else {
      _flash(repayParams, collateralATokenPermit, extraCollateralATokenPermit);
    }
    uint256 excessAfter = IERC20Detailed(repayParams.collateralAsset).balanceOf(address(this));
    uint256 excess = excessAfter > excessBefore ? excessAfter - excessBefore : 0;
    if (excess > 0) {
      _conditionalRenewAllowance(repayParams.collateralAsset, excess);
      _supply(repayParams.collateralAsset, excess, msg.sender, REFERRER);
    }
  }

  function _flash(
    RepayParams memory repayParams,
    PermitInput memory collateralATokenPermit,
    PermitInput memory extraCollateralATokenPermit
  ) internal virtual {
    bytes memory params = abi.encode(repayParams, collateralATokenPermit, extraCollateralATokenPermit, msg.sender);
    address[] memory assets = new address[](1);
    assets[0] = repayParams.extraCollateralAsset;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = repayParams.extraCollateralAmount;
    uint256[] memory interestRateModes = new uint256[](1);
    interestRateModes[0] = 2;

    POOL.flashLoan(address(this), assets, amounts, interestRateModes, msg.sender, params, REFERRER);
  }

  /**
   * @notice Executes an operation after receiving the flash-borrowed assets
   * @dev Ensure that the contract can return the debt + premium, e.g., has
   *      enough funds to repay and has approved the Pool to pull the total amount
   * @param assets The addresses of the flash-borrowed assets
   * @param amounts The amounts of the flash-borrowed assets
   * @param initiator The address of the flashloan initiator
   * @param params The byte-encoded params passed when initiating the flashloan
   * @return True if the execution of the operation succeeds, false otherwise
   */
  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata,
    address initiator,
    bytes calldata params
  ) external returns (bool) {
    require(msg.sender == address(POOL), 'CALLER_MUST_BE_POOL');
    require(initiator == address(this), 'INITIATOR_MUST_BE_THIS');

    (
      RepayParams memory repayParams,
      PermitInput memory collateralATokenPermit,
      PermitInput memory extraCollateralATokenPermit,
      address user
    ) = abi.decode(params, (RepayParams, PermitInput, PermitInput, address));

    address flashLoanAsset = assets[0];
    uint256 flashLoanAmount = amounts[0];

    // Supply
    _supply(flashLoanAsset, flashLoanAmount, user, REFERRER);

    _swapAndRepay(repayParams, collateralATokenPermit, user);

    uint256 amountWithdrawn = _pullATokenAndWithdraw(
      flashLoanAsset,
      user,
      IERC20WithPermit(flashLoanAsset).balanceOf(msg.sender),
      extraCollateralATokenPermit
    );

    _conditionalRenewAllowance(flashLoanAsset, amountWithdrawn);

    //repay the flashloan taken on behalf of user
    POOL.repay(
      flashLoanAsset,
      amountWithdrawn,
      2,
      user
    );

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
    _pullATokenAndWithdraw(
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
      repayParams.maxCollateralAmountToSwap,
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
      _supply(repayParams.debtRepayAsset, excess, msg.sender, REFERRER);
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
