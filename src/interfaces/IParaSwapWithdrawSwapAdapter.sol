// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {BaseParaSwapAdapter} from '../contracts/BaseParaSwapAdapter.sol';
import {IBaseParaSwapAdapter} from './IBaseParaSwapAdapter.sol';

/**
 * @title IParaSwapWithdrawSwapAdapter
 * @notice Defines the basic interface for ParaSwapWithdrawSwapAdapter
 * @dev Implement this interface to provide functionality of withdrawing the asset from Aave pool and swapping it to another asset
 **/
interface IParaSwapWithdrawSwapAdapter is IBaseParaSwapAdapter {
  struct WithdrawSwapParams {
    address oldAsset; // the asset you want withdraw and swap from
    uint256 oldAssetAmount;  // the amount you want to withdraw
    address newAsset;  // the asset you want to swap to
    uint256 minAmountToReceive; // the minimum amount you expect to receive
    uint256 allBalanceOffset; // offset in calldata in case of all the asset to withdraw
    bytes paraswapData; // encoded exactIn swap
  }

  /**
   * @dev Swaps an amount of an asset to another after a withdraw and transfers the new asset to the user.
   * @param withdrawSwapParams struct describing the withdraw swap parameters
   * @param permitInput optional permit for collateral aToken
   */
  function withdrawAndSwap(
    WithdrawSwapParams memory withdrawSwapParams,
    PermitInput memory permitInput
  ) external;
}
