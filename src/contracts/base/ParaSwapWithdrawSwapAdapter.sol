// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {ReentrancyGuard} from 'aave-v3-periphery/contracts/dependencies/openzeppelin/ReentrancyGuard.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {IParaSwapAugustusRegistry} from '../dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {IParaSwapWithdrawSwapAdapter} from '../interfaces/IParaSwapWithdrawSwapAdapter.sol';
import {BaseParaSwapSellAdapter} from './BaseParaSwapSellAdapter.sol';

/**
 * @title ParaSwapWithdrawSwapAdapter
 * @notice ParaSwap Adapter to withdraw and swap.
 * @dev Withdraws the asset from the Aave Pool and swaps(exact in) it to another asset
 * @author Aave Labs
 **/
abstract contract ParaSwapWithdrawSwapAdapter is
  BaseParaSwapSellAdapter,
  ReentrancyGuard,
  IParaSwapWithdrawSwapAdapter
{
  using SafeERC20 for IERC20;

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
  ) BaseParaSwapSellAdapter(addressesProvider, pool, augustusRegistry) {
    transferOwnership(owner);
  }

  /// @inheritdoc IParaSwapWithdrawSwapAdapter
  function withdrawAndSwap(
    WithdrawSwapParams memory withdrawSwapParams,
    PermitInput memory permitInput
  ) external nonReentrant {
    (, , address aToken) = _getReserveData(withdrawSwapParams.oldAsset);

    // Offset in August calldata if wanting to swap all balance, otherwise 0
    if (withdrawSwapParams.allBalanceOffset != 0) {
      uint256 balance = IERC20(aToken).balanceOf(withdrawSwapParams.user);
      require(balance <= withdrawSwapParams.oldAssetAmount, 'INSUFFICIENT_AMOUNT_TO_SWAP');
      withdrawSwapParams.oldAssetAmount = balance;
    }

    // pulls liquidity asset from the user and withdraw
    _pullATokenAndWithdraw(
      withdrawSwapParams.oldAsset,
      withdrawSwapParams.user,
      withdrawSwapParams.oldAssetAmount,
      permitInput
    );

    // sell(exact in) withdrawn asset from Aave Pool to new asset
    uint256 amountReceived = _sellOnParaSwap(
      withdrawSwapParams.allBalanceOffset,
      withdrawSwapParams.paraswapData,
      IERC20Detailed(withdrawSwapParams.oldAsset),
      IERC20Detailed(withdrawSwapParams.newAsset),
      withdrawSwapParams.oldAssetAmount,
      withdrawSwapParams.minAmountToReceive
    );

    // transfer new asset to the user
    IERC20(withdrawSwapParams.newAsset).safeTransfer(withdrawSwapParams.user, amountReceived);
  }
}
