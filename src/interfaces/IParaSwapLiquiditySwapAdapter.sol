// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IBaseParaSwapAdapter} from './IBaseParaSwapAdapter.sol';

/**
 * @title IParaSwapLiquiditySwapAdapter
 * @notice Defines the basic interface for ParaSwapLiquiditySwapAdapter
 * @dev Implement this interface to provide functionality of swapping one collateral asset to another collateral asset
 **/
interface IParaSwapLiquiditySwapAdapter is IBaseParaSwapAdapter {
  struct FlashParams {
    address flashLoanAsset; // the asset to flashloan(collateralAsset)
    uint256 flashLoanAmount; // the amount to flashloan(collateralAmountToSwap)
  }

  struct LiquiditySwapParams {
    address collateralAsset; // the asset you want to swap collateral from
    uint256 collateralAmountToSwap; // the amount you want to swap from
    address newCollateralAsset;  // the asset you want to swap collateral to
    uint256 newCollateralAmount; // the minimum amount of new collateral asset to be received
    uint256 offset; // offset in calldata in case of all collateral is to be swapped
    address user; // the address of user
    bytes paraswapData; // encoded exactIn swap
  }

  /**
   * @dev swaps liquidity(collateral) from one asset to another
   * @param liquiditySwapParams struct describing the liquidity swap
   * @param flashParams optional struct describing flashloan params if needed
   * @param collateralATokenPermit optional permit for collateral aToken
   */
  function swapLiquidity(
    LiquiditySwapParams memory liquiditySwapParams,
    FlashParams memory flashParams,
    PermitInput memory collateralATokenPermit
  ) external;
}
