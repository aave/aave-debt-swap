// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {BaseParaSwapAdapter} from '../contracts/BaseParaSwapAdapter.sol';
import {IBaseParaSwapAdapter} from './IBaseParaSwapAdapter.sol';

/**
 * @title ParaSwapWithdrawSwapAdapter
 * @notice ParaSwap Adapter to perform a withdrawal of asset and swapping it to another asset.
 **/
interface IParaSwapWithdrawSwapAdapter is IBaseParaSwapAdapter {
  struct WithdrawSwapParams {
    address oldAsset;
    uint256 oldAssetAmount;
    address newAsset;
    uint256 minAmountToReceive;
    uint256 allBalanceOffset;
    bytes paraswapData;
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
