// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import {IERC20WithPermit} from 'solidity-utils/contracts/oz-common/interfaces/IERC20WithPermit.sol';
import {IBaseParaSwapAdapter} from './IBaseParaSwapAdapter.sol';

interface IParaSwapLiquiditySwapAdapter is IBaseParaSwapAdapter {
  struct FlashParams {
    address v3Pool;
    address flashLoanAsset;
    uint256 flashLoanAmount;
    address user;
    PermitInput flashLoanAssetPermit;
  }

  struct LiquiditySwapParams {
    address collateralAsset;
    uint256 collateralAmountToSwap;
    address newCollateralAsset;
    uint256 minNewCollateralAmount;
    uint256 offset;
    bytes paraswapData;
  }

  /**
   * @dev swaps liquidity(collateral) from one asset to another
   * @param liquiditySwapParams struct describing the liqudity swap
   * @param flashParams optional struct describing flashloan params if needed
   * @param collateralATokenPermit optional permit for collateral aToken
   */
  function swapLiquidity(
    LiquiditySwapParams memory liquiditySwapParams,
    FlashParams memory flashParams,
    PermitInput memory collateralATokenPermit
  ) external;
}
