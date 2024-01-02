// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IParaSwapAugustusRegistry} from '../interfaces/IParaSwapAugustusRegistry.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';
import {ParaSwapRepayAdapter} from './ParaSwapRepayAdapter.sol';
import {BaseParaSwapAdapter} from './BaseParaSwapAdapter.sol';

/**
 * @title ParaSwapRepayAdapterV3
 * @notice ParaSwap Adapter to repay a debt of asset with collateral asset.
 **/
contract ParaSwapRepayAdapterV3 is ParaSwapRepayAdapter {
  /**
   * @dev Constructor
   * @param addressesProvider The address for a Pool Addresses Provider.
   * @param pool The address of the Aave Pool
   * @param augustusRegistry address of ParaSwap Augustus Registry
   * @param owner The address to transfer ownership to
   */
  constructor(
    IPoolAddressesProvider addressesProvider,
    address pool,
    IParaSwapAugustusRegistry augustusRegistry,
    address owner
  ) ParaSwapRepayAdapter(addressesProvider, pool, augustusRegistry, owner) {}

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
