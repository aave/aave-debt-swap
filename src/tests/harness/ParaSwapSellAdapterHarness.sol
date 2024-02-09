// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IParaSwapAugustusRegistry} from 'src/contracts/dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {BaseParaSwapAdapter} from 'src/contracts/base/BaseParaSwapAdapter.sol';
import {BaseParaSwapSellAdapter} from 'src/contracts/base/BaseParaSwapSellAdapter.sol';

/**
 * @title ParaSwapSellAdapterHarness
 * @notice Harness contract for BaseParaSwapSellAdapter
 */
contract ParaSwapSellAdapterHarness is BaseParaSwapSellAdapter {
  /**
   * @dev Constructor
   * @param addressesProvider The address of the Aave PoolAddressesProvider contract
   * @param pool The address of the Aave Pool contract
   * @param augustusRegistry The address of the Paraswap AugustusRegistry contract
   */
  constructor(
    IPoolAddressesProvider addressesProvider,
    address pool,
    IParaSwapAugustusRegistry augustusRegistry
  ) BaseParaSwapSellAdapter(addressesProvider, pool, augustusRegistry) {
    // intentionally left blank
  }

  /**
   * @dev Swaps a token for another using ParaSwap (exact in)
   * @dev In case the swap input is less than the designated amount to sell, the excess remains in the contract
   * @param fromAmountOffset Offset of fromAmount in Augustus calldata if it should be overwritten, otherwise 0
   * @param paraswapData Data for Paraswap Adapter
   * @param assetToSwapFrom The address of the asset to swap from
   * @param assetToSwapTo The address of the asset to swap to
   * @param amountToSwap The amount of asset to swap from
   * @param minAmountToReceive The minimum amount to receive
   * @return amountReceived The amount of asset bought
   */
  function sellOnParaSwap(
    uint256 fromAmountOffset,
    bytes memory paraswapData,
    IERC20Detailed assetToSwapFrom,
    IERC20Detailed assetToSwapTo,
    uint256 amountToSwap,
    uint256 minAmountToReceive
  ) external returns (uint256 amountReceived) {
    return
      _sellOnParaSwap(
        fromAmountOffset,
        paraswapData,
        assetToSwapFrom,
        assetToSwapTo,
        amountToSwap,
        minAmountToReceive
      );
  }

  /// @inheritdoc BaseParaSwapAdapter
  function _getReserveData(
    address asset
  ) internal view virtual override returns (address, address, address) {}

  /// @inheritdoc BaseParaSwapAdapter
  function _supply(
    address asset,
    uint256 amount,
    address to,
    uint16 referralCode
  ) internal virtual override {}
}
