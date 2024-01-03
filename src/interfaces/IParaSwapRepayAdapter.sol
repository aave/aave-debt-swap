// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import {IERC20WithPermit} from 'solidity-utils/contracts/oz-common/interfaces/IERC20WithPermit.sol';
import {IBaseParaSwapAdapter} from './IBaseParaSwapAdapter.sol';

/**
 * @title IParaSwapRepayAdapter
 * @notice Defines the basic interface for ParaSwapRepayAdapter
 * @dev Implement this interface to provide functionality of swapping one collateral asset to debt asset and repay the debt
 **/
interface IParaSwapRepayAdapter is IBaseParaSwapAdapter {
  struct FlashParams {
    address flashLoanAsset; // the asset to flashloan(collateralAsset)
    uint256 flashLoanAmount; // the amount to flashloan equivalent to the debt to be repaid
  }

  struct RepayParams {
    address collateralAsset; // the asset you want to swap collateral from
    uint256 maxCollateralAmountToSwap; // the max amount you want to swap from
    address debtRepayAsset; // the asset you want to repay the debt
    uint256 debtRepayAmount; // the amount of debt to be paid
    uint256 debtRepayMode; // the type of debt (1 for stable, 2 for variable)
    uint256 offset; // offset in calldata in case of all collateral is to be swapped
    address user; // address of user
    bytes paraswapData; // encoded exactOut swap
  }

  /**
   * @dev swaps liquidity(collateral) from one asset to another asset to repay the debt of received asset from swap.
   * @param repayParams struct describing the repay with collateral swap
   * @param flashParams optional struct describing flashloan params if needed
   * @param collateralATokenPermit optional permit for collateral aToken
   */
  function repayWithCollateral(
    RepayParams memory repayParams,
    FlashParams memory flashParams,
    PermitInput memory collateralATokenPermit
  ) external;
}
