// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';
import {IParaSwapAugustusRegistry} from './dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {BaseParaSwapAdapter} from './base/BaseParaSwapAdapter.sol';
import {ParaSwapWithdrawSwapAdapter} from './base/ParaSwapWithdrawSwapAdapter.sol';

/**
 * @title ParaSwapWithdrawSwapAdapterV3
 * @notice ParaSwap Adapter to withdraw and swap.
 * @dev It is specifically designed for Aave V3
 * @author Aave Labs
 **/
contract ParaSwapWithdrawSwapAdapterV3 is ParaSwapWithdrawSwapAdapter {
  /**
   * @dev Constructor
   * @param addressesProvider The address of the Aave PoolAddressesProvider contract
   * @param pool The address of the Aave Pool contract
   * @param augustusRegistry The address of the Paraswap AugustusRegistry contract
   * @param owner The address of the owner
   */
  constructor(
    IPoolAddressesProvider addressesProvider,
    address pool,
    IParaSwapAugustusRegistry augustusRegistry,
    address owner
  ) ParaSwapWithdrawSwapAdapter(addressesProvider, pool, augustusRegistry, owner) {}

  /// @inheritdoc BaseParaSwapAdapter
  function _getReserveData(
    address asset
  ) internal view override returns (address, address, address) {
    DataTypes.ReserveData memory reserveData = POOL.getReserveData(asset);
    return (
      reserveData.variableDebtTokenAddress,
      reserveData.stableDebtTokenAddress,
      reserveData.aTokenAddress
    );
  }

  /// @inheritdoc BaseParaSwapAdapter
  function _supply(
    address asset,
    uint256 amount,
    address to,
    uint16 referralCode
  ) internal override {
    POOL.supply(asset, amount, to, referralCode);
  }
}
