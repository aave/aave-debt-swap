// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import {IERC20WithPermit} from 'solidity-utils/contracts/oz-common/interfaces/IERC20WithPermit.sol';
import {IBaseParaSwapAdapter} from './IBaseParaSwapAdapter.sol';
import {ICreditDelegationToken} from './ICreditDelegationToken.sol';

interface IParaSwapRepayAdapter is IBaseParaSwapAdapter {

  struct RepayParams {
    address collateralAsset;
    uint256 maxCollateralAmountToSwap;
    address debtRepayAsset;
    uint256 debtRepayAmount;
    uint256 debtRepayMode;
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
   * @dev swaps liquidity(collateral) from one asset to another asset. Repays the debt of received asset from swap.
   * @param repayParams struct describing the repay with collateral swap
   * @param creditDelegationPermit optional permit for credit delegation
   * @param collateralATokenPermit optional permit for collateral aToken
   * @param extraCollateralATokenPermit optional permit for extra collateral aToken
   */
  function repayWithCollateral(
    RepayParams memory repayParams,
    CreditDelegationInput memory creditDelegationPermit,
    PermitInput memory collateralATokenPermit,
    PermitInput memory extraCollateralATokenPermit
  ) external;
}
