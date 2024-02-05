// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IBaseParaSwapAdapter} from './IBaseParaSwapAdapter.sol';

/**
 * @title IParaSwapLiquiditySwapAdapter
 * @notice Defines the basic interface for ParaSwapLiquiditySwapAdapter
 * @dev Implement this interface to provide functionality of swapping one collateral asset to another collateral asset
 * @author Aave Labs
 **/
interface IParaSwapLiquiditySwapAdapter is IBaseParaSwapAdapter {
  struct LiquiditySwapParams {
    address collateralAsset; // the asset to swap collateral from
    uint256 collateralAmountToSwap; // the amount of asset to swap from
    address newCollateralAsset; // the asset to swap collateral to
    uint256 newCollateralAmount; // the minimum amount of new collateral asset to receive
    uint256 offset; // offset in sell calldata in case of swapping all collateral, otherwise 0
    address user; // the address of user
    bool withFlashLoan; // true if flashloan is needed to swap collateral, otherwise false
    bytes paraswapData; // encoded paraswap data
  }

  /**
   * @notice Swaps liquidity(collateral) from one asset to another
   * @param liquiditySwapParams struct describing the liquidity swap
   * @param collateralATokenPermit optional permit for collateral aToken
   */
  function swapLiquidity(
    LiquiditySwapParams memory liquiditySwapParams,
    PermitInput memory collateralATokenPermit
  ) external;
}
