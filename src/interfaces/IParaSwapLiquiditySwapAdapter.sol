// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import {IERC20WithPermit} from 'solidity-utils/contracts/oz-common/interfaces/IERC20WithPermit.sol';
import {IBaseParaSwapAdapter} from './IBaseParaSwapAdapter.sol';
import {ICreditDelegationToken} from './ICreditDelegationToken.sol';

interface IParaSwapLiquiditySwapAdapter is IBaseParaSwapAdapter {

  struct LiquiditySwapParams {
    address collateralAsset;
    uint256 collateralAmountToSwap;
    address newCollateralAsset;
    uint256 minNewCollateralAmount;
    address extraCollateralAsset;
    uint256 extraCollateralAmount;
    uint256 offset;
    bytes paraswapData;
  }

  struct CreditDelegationInput {
    ICreditDelegationToken debtToken;
    uint256 value;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  /**
   * @dev swaps liquidity(collateral) from one asset to another
   * @param liquiditySwapParams struct describing the liqudity swap
   * @param creditDelegationPermit optional permit for credit delegation
   * @param collateralATokenPermit optional permit for collateral aToken
   * @param extraCollateralATokenPermit optional permit for extra collateral aToken
   */
  function swapLiquidity(
    LiquiditySwapParams memory liquiditySwapParams,
    CreditDelegationInput memory creditDelegationPermit,
    PermitInput memory collateralATokenPermit,
    PermitInput memory extraCollateralATokenPermit
  ) external;
}
