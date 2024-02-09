// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {DataTypes, ILendingPool} from 'aave-address-book/AaveV2.sol';
import {IParaSwapAugustusRegistry} from './dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {BaseParaSwapAdapter} from './base/BaseParaSwapAdapter.sol';
import {ParaSwapDebtSwapAdapter} from './base/ParaSwapDebtSwapAdapter.sol';

/**
 * @title ParaSwapDebtSwapAdapter
 * @notice ParaSwap Adapter to perform a swap of debt to another debt.
 * @author BGD labs
 **/
contract ParaSwapDebtSwapAdapterV2 is ParaSwapDebtSwapAdapter {
  constructor(
    IPoolAddressesProvider addressesProvider,
    address pool,
    IParaSwapAugustusRegistry augustusRegistry,
    address owner
  ) ParaSwapDebtSwapAdapter(addressesProvider, pool, augustusRegistry, owner) {
    // Intentionally left blank
  }

  /// @inheritdoc BaseParaSwapAdapter
  function _getReserveData(
    address asset
  ) internal view override returns (address, address, address) {
    DataTypes.ReserveData memory reserveData = ILendingPool(address(POOL)).getReserveData(asset);
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
    ILendingPool(address(POOL)).deposit(asset, amount, to, referralCode);
  }
}
