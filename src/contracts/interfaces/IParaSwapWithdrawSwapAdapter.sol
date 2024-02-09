// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IBaseParaSwapAdapter} from './IBaseParaSwapAdapter.sol';

/**
 * @title IParaSwapWithdrawSwapAdapter
 * @notice Defines the basic interface for ParaSwapWithdrawSwapAdapter
 * @dev Implement this interface to provide functionality of withdrawing from the Aave Pool and swapping to another asset
 * @author Aave Labs
 **/
interface IParaSwapWithdrawSwapAdapter is IBaseParaSwapAdapter {
  struct WithdrawSwapParams {
    address oldAsset; // the asset to withdraw and swap from
    uint256 oldAssetAmount; // the amount to withdraw
    address newAsset; // the asset to swap to
    uint256 minAmountToReceive; // the minimum amount of new asset to receive
    uint256 allBalanceOffset; // offset in sell calldata in case of swapping all collateral, otherwise 0
    address user; // the address of user
    bytes paraswapData; // encoded paraswap data
  }

  /**
   * @notice Withdraws and swaps an asset that is supplied to the Aave Pool
   * @param withdrawSwapParams struct describing the withdraw swap
   * @param permitInput optional permit for collateral aToken
   */
  function withdrawAndSwap(
    WithdrawSwapParams memory withdrawSwapParams,
    PermitInput memory permitInput
  ) external;
}
