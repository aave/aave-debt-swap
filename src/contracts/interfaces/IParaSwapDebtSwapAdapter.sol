// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ICreditDelegationToken} from '@aave/core-v3/contracts/interfaces/ICreditDelegationToken.sol';
import {IBaseParaSwapAdapter} from './IBaseParaSwapAdapter.sol';

/**
 * @title IParaSwapDebtSwapAdapter
 * @notice Defines the basic interface for ParaSwapDebtSwapAdapter
 * @dev Implement this interface to provide functionality of swapping one debt asset to another debt asset
 * @author BGD labs
 **/
interface IParaSwapDebtSwapAdapter is IBaseParaSwapAdapter {
  struct FlashParams {
    address debtAsset; // the asset to swap debt from
    uint256 debtRepayAmount; // the amount of asset to swap from
    uint256 debtRateMode; // debt interest rate mode (1 for stable, 2 for variable)
    address nestedFlashloanDebtAsset;  // 0 if no need of extra collateral. Otherwise internally used for new debt asset
    uint256 nestedFlashloanDebtAmount; // internally used for the amount of new debt asset in case extra collateral
    bytes paraswapData; // encoded paraswap data
    uint256 offset; // offset in buy calldata in case of swapping all debt, otherwise 0
    address user; // the address of user
  }

  struct DebtSwapParams {
    address debtAsset; // the asset to repay the debt
    uint256 debtRepayAmount; // the amount of debt to repay
    uint256 debtRateMode; // debt interest rate mode (1 for stable, 2 for variable)
    address newDebtAsset; // the asset of the new debt
    uint256 maxNewDebtAmount; // the maximum amount of asset to swap from
    address extraCollateralAsset; // the asset of extra collateral to use (if needed)
    uint256 extraCollateralAmount; // the amount of extra collateral to use (if needed)
    uint256 offset; // offset in buy calldata in case of swapping all debt, otherwise 0
    bytes paraswapData; // encoded paraswap data
  }

  struct CreditDelegationInput {
    ICreditDelegationToken debtToken; // the debt asset to delegate credit for
    uint256 value; // the amount of credit to delegate
    uint256 deadline; // expiration unix timestamp
    uint8 v; // sig v
    bytes32 r; // sig r
    bytes32 s; // sig s
  }

  /**
   * @notice Swaps debt from one asset to another
   * @param debtSwapParams struct describing the debt swap
   * @param creditDelegationPermit optional permit for credit delegation
   * @param collateralATokenPermit optional permit for collateral aToken
   */
  function swapDebt(
    DebtSwapParams memory debtSwapParams,
    CreditDelegationInput memory creditDelegationPermit,
    PermitInput memory collateralATokenPermit
  ) external;
}
