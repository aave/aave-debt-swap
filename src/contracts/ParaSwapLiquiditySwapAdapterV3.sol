// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';
import {IParaSwapAugustusRegistry} from './dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {BaseParaSwapAdapter} from './base/BaseParaSwapAdapter.sol';
import {ParaSwapLiquiditySwapAdapter} from './base/ParaSwapLiquiditySwapAdapter.sol';

/**
 * @title ParaSwapLiquiditySwapAdapterV3
 * @notice ParaSwap Adapter to perform a swap of collateral from one asset to another.
 * @dev It is specifically designed for Aave V3
 * @author Aave Labs
 **/
contract ParaSwapLiquiditySwapAdapterV3 is ParaSwapLiquiditySwapAdapter {
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
  ) ParaSwapLiquiditySwapAdapter(addressesProvider, pool, augustusRegistry, owner) {
    // Intentionally left blank
  }

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
