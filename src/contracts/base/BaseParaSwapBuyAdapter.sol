// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {PercentageMath} from '@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {SafeERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/SafeERC20.sol';
import {IParaSwapAugustus} from '../dependencies/paraswap/IParaSwapAugustus.sol';
import {IParaSwapAugustusRegistry} from '../dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {BaseParaSwapAdapter} from './BaseParaSwapAdapter.sol';

/**
 * @title BaseParaSwapBuyAdapter
 * @notice Implements logic for buying an asset using ParaSwap (exact-out swap)
 */
abstract contract BaseParaSwapBuyAdapter is BaseParaSwapAdapter {
  using SafeERC20 for IERC20Detailed;
  using PercentageMath for uint256;

  /// @notice The address of the Paraswap Augustus Registry
  IParaSwapAugustusRegistry public immutable AUGUSTUS_REGISTRY;

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
  ) BaseParaSwapAdapter(addressesProvider, pool) {
    // Do something on Augustus registry to check the right contract was passed
    require(!augustusRegistry.isValidAugustus(address(0)), 'Not a valid Augustus address');
    AUGUSTUS_REGISTRY = augustusRegistry;
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
  function _buyOnParaSwap(
    uint256 toAmountOffset,
    bytes memory paraswapData,
    IERC20Detailed assetToSwapFrom,
    IERC20Detailed assetToSwapTo,
    uint256 maxAmountToSwap,
    uint256 amountToReceive
  ) internal returns (uint256 amountSold) {
    (bytes memory buyCalldata, IParaSwapAugustus augustus) = abi.decode(
      paraswapData,
      (bytes, IParaSwapAugustus)
    );
    require(AUGUSTUS_REGISTRY.isValidAugustus(address(augustus)), 'INVALID_AUGUSTUS');

    {
      uint256 fromAssetDecimals = _getDecimals(assetToSwapFrom);
      uint256 toAssetDecimals = _getDecimals(assetToSwapTo);

      uint256 fromAssetPrice = _getPrice(address(assetToSwapFrom));
      uint256 toAssetPrice = _getPrice(address(assetToSwapTo));

      uint256 expectedMaxAmountToSwap = ((amountToReceive *
        (toAssetPrice * (10 ** fromAssetDecimals))) / (fromAssetPrice * (10 ** toAssetDecimals)))
        .percentMul(PercentageMath.PERCENTAGE_FACTOR + MAX_SLIPPAGE_PERCENT);

      // Sanity check for `maxAmountToSwap` to ensure it is within slippage bounds
      require(maxAmountToSwap <= expectedMaxAmountToSwap, 'maxAmountToSwap exceeds max slippage');
    }

    uint256 balanceBeforeAssetFrom = assetToSwapFrom.balanceOf(address(this));
    require(balanceBeforeAssetFrom >= maxAmountToSwap, 'INSUFFICIENT_BALANCE_BEFORE_SWAP');

    uint256 balanceBeforeAssetTo = assetToSwapTo.balanceOf(address(this));

    address tokenTransferProxy = augustus.getTokenTransferProxy();
    assetToSwapFrom.safeApprove(tokenTransferProxy, 0);
    assetToSwapFrom.safeApprove(tokenTransferProxy, maxAmountToSwap);

    if (toAmountOffset != 0) {
      // Ensure 256 bit (32 bytes) toAmountOffset value is within bounds of the
      // calldata, not overlapping with the first 4 bytes (function selector).
      require(
        toAmountOffset >= 4 && toAmountOffset <= buyCalldata.length - 32,
        'TO_AMOUNT_OFFSET_OUT_OF_RANGE'
      );
      // Overwrite the toAmount with the correct amount for the buy.
      // In memory, buyCalldata consists of a 256 bit length field, followed by
      // the actual bytes data, that is why 32 is added to the byte offset.
      assembly {
        mstore(add(buyCalldata, add(toAmountOffset, 32)), amountToReceive)
      }
    }
    (bool success, ) = address(augustus).call(buyCalldata);
    if (!success) {
      // Copy revert reason from call
      assembly {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }

    // Amount provided should be less or equal than `maxAmountToSwap`
    uint256 balanceAfterAssetFrom = assetToSwapFrom.balanceOf(address(this));
    amountSold = balanceBeforeAssetFrom - balanceAfterAssetFrom;
    require(amountSold <= maxAmountToSwap, 'WRONG_BALANCE_AFTER_SWAP');

    // Amount received should be equal (or even higher) than `amountToReceive`
    uint256 amountReceived = assetToSwapTo.balanceOf(address(this)) - balanceBeforeAssetTo;
    require(amountReceived >= amountToReceive, 'INSUFFICIENT_AMOUNT_RECEIVED');

    emit Bought(address(assetToSwapFrom), address(assetToSwapTo), amountSold, amountReceived);
  }
}
