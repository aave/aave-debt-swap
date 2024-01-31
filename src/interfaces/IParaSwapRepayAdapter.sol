// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IBaseParaSwapAdapter} from './IBaseParaSwapAdapter.sol';

/**
 * @title IParaSwapRepayAdapter
 * @notice Defines the basic interface for ParaSwapRepayAdapter
 * @dev Implement this interface to provide functionality of repaying debt with collateral
 * @author Aave Labs
 **/
interface IParaSwapRepayAdapter is IBaseParaSwapAdapter {
  struct FlashParams {
    address flashLoanAsset; // the asset to flashloan (collateralAsset)
    uint256 flashLoanAmount; // the amount to flashloan equivalent to the debt to repay
  }

  struct RepayParams {
    address collateralAsset; // the asset you want to swap collateral from
    uint256 maxCollateralAmountToSwap; // the max amount you want to swap from
    address debtRepayAsset; // the asset you want to repay the debt
    uint256 debtRepayAmount; // the amount of debt to repay
    uint256 debtRepayMode; // debt interest rate mode (1 for stable, 2 for variable)
    uint256 offset; // offset in buy calldata in case of swapping all collateral, otherwise 0
    address user; // the address of user
    bytes paraswapData; // encoded paraswap data
  }

  /**
   * @notice Repays with collateral by swapping the collateral asset to debt asset
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
