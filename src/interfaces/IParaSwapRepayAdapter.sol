// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import {IERC20WithPermit} from 'solidity-utils/contracts/oz-common/interfaces/IERC20WithPermit.sol';
import {IBaseParaSwapAdapter} from './IBaseParaSwapAdapter.sol';

interface IParaSwapRepayAdapter is IBaseParaSwapAdapter {
  struct FlashParams {
    address v3Pool;
    address flashLoanAsset;
    uint256 flashLoanAmount;
    address user;
    PermitInput flashLoanAssetPermit;
  }

  struct RepayParams {
    address collateralAsset;
    uint256 maxCollateralAmountToSwap;
    address debtRepayAsset;
    uint256 debtRepayAmount;
    uint256 debtRepayMode;
    uint256 offset;
    bytes paraswapData;
  }

  /**
   * @dev swaps liquidity(collateral) from one asset to another asset. Repays the debt of received asset from swap.
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
