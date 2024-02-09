// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IParaSwapAugustusRegistry} from 'src/contracts/dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {BaseParaSwapAdapter} from 'src/contracts/base/BaseParaSwapAdapter.sol';
import {BaseParaSwapBuyAdapter} from 'src/contracts/base/BaseParaSwapBuyAdapter.sol';

/**
 * @title ParaSwapBuyAdapterHarness
 * @notice Harness contract for BaseParaSwapBuyAdapter
 */
contract ParaSwapBuyAdapterHarness is BaseParaSwapBuyAdapter {
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
  ) BaseParaSwapBuyAdapter(addressesProvider, pool, augustusRegistry) {
    // intentionally left blank
  }

  /**
   * @dev Swaps a token for another using ParaSwap (exact out)
   * @dev In case the swap output is higher than the designated amount to buy, the excess remains in the contract
   * @param toAmountOffset Offset of toAmount in Augustus calldata if it should be overwritten, otherwise 0
   * @param paraswapData Data for Paraswap Adapter
   * @param assetToSwapFrom The address of the asset to swap from
   * @param assetToSwapTo The address of the asset to swap to
   * @param maxAmountToSwap The maximum amount of asset to swap from
   * @param amountToReceive The amount of asset to receive
   * @return amountSold The amount of asset sold
   */
  function buyOnParaSwap(
    uint256 toAmountOffset,
    bytes memory paraswapData,
    IERC20Detailed assetToSwapFrom,
    IERC20Detailed assetToSwapTo,
    uint256 maxAmountToSwap,
    uint256 amountToReceive
  ) external returns (uint256 amountSold) {
    return
      _buyOnParaSwap(
        toAmountOffset,
        paraswapData,
        assetToSwapFrom,
        assetToSwapTo,
        maxAmountToSwap,
        amountToReceive
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
