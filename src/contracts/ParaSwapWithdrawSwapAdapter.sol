// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {ReentrancyGuard} from 'aave-v3-periphery/contracts/dependencies/openzeppelin/ReentrancyGuard.sol';
import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {GPv2SafeERC20} from '@aave/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol';
import {IParaSwapWithdrawSwapAdapter} from '../interfaces/IParaSwapWithdrawSwapAdapter.sol';
import {IParaSwapAugustusRegistry} from '../interfaces/IParaSwapAugustusRegistry.sol';
import {BaseParaSwapAdapter} from './BaseParaSwapAdapter.sol';
import {BaseParaSwapSellAdapter} from './BaseParaSwapSellAdapter.sol';

/**
 * @title ParaSwapWithdrawSwapAdapter
 * @notice ParaSwap Adapter to perform a withdrawal of asset and swapping it to another asset.
 **/
abstract contract ParaSwapWithdrawSwapAdapter is
  BaseParaSwapSellAdapter,
  ReentrancyGuard,
  IParaSwapWithdrawSwapAdapter
{
  using GPv2SafeERC20 for IERC20;

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
  ) BaseParaSwapSellAdapter(addressesProvider, pool, augustusRegistry) {
    transferOwnership(owner);
  }

  /// @inheritdoc IParaSwapWithdrawSwapAdapter
  function withdrawAndSwap(
    WithdrawSwapParams memory withdrawSwapParams,
    PermitInput memory permitInput
  ) external nonReentrant {
    (, , address aToken) = _getReserveData(withdrawSwapParams.oldAsset);

    if (withdrawSwapParams.allBalanceOffset != 0) {
      uint256 balance = IERC20(aToken).balanceOf(msg.sender);
      require(balance <= withdrawSwapParams.oldAssetAmount, 'INSUFFICIENT_AMOUNT_TO_SWAP');
      withdrawSwapParams.oldAssetAmount = balance;
    }

    _pullATokenAndWithdraw(
      withdrawSwapParams.oldAsset,
      msg.sender,
      withdrawSwapParams.oldAssetAmount,
      permitInput
    );

    uint256 amountReceived = _sellOnParaSwap(
      withdrawSwapParams.allBalanceOffset,
      withdrawSwapParams.paraswapData,
      IERC20Detailed(withdrawSwapParams.oldAsset),
      IERC20Detailed(withdrawSwapParams.newAsset),
      withdrawSwapParams.oldAssetAmount,
      withdrawSwapParams.minAmountToReceive
    );

    IERC20(withdrawSwapParams.newAsset).safeTransfer(msg.sender, amountReceived);
  }
}
