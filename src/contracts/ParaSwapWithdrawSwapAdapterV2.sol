// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ParaSwapWithdrawSwapAdapter} from './ParaSwapWithdrawSwapAdapter.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IParaSwapAugustusRegistry} from '../interfaces/IParaSwapAugustusRegistry.sol';
import {DataTypes, ILendingPool} from 'aave-address-book/AaveV2.sol';
import {BaseParaSwapAdapter} from './BaseParaSwapAdapter.sol';

/**
 * @title ParaSwapWithdrawSwapAdapterV2
 * @notice ParaSwap Adapter to perform a withdrawal of asset and swapping it to another asset.
 **/
contract ParaSwapWithdrawSwapAdapterV2 is ParaSwapWithdrawSwapAdapter {
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
  ) ParaSwapWithdrawSwapAdapter(addressesProvider, pool, augustusRegistry, owner) {}

  ///@inheritdoc BaseParaSwapAdapter
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

  ///@inheritdoc BaseParaSwapAdapter
  function _supply(
    address asset,
    uint256 amount,
    address to,
    uint16 referralCode
  ) internal override {
    ILendingPool(address(POOL)).deposit(asset, amount, to, referralCode);
  }
}
