// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {Errors} from 'aave-address-book/AaveV3.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets, IPool} from 'aave-address-book/AaveV3Ethereum.sol';
import {BaseTest} from './utils/BaseTest.sol';
import {ParaSwapWithdrawSwapAdapterV3} from '../src/contracts/ParaSwapWithdrawSwapAdapterV3.sol';
import {AugustusRegistry} from '../src/lib/AugustusRegistry.sol';
import {IParaSwapWithdrawSwapAdapter} from '../src/interfaces/IParaSwapWithdrawSwapAdapter.sol';
import {BaseParaSwapAdapter} from '../src/contracts/BaseParaSwapAdapter.sol';
import {IBaseParaSwapAdapter} from '../src/interfaces/IBaseParaSwapAdapter.sol';
import {stdMath} from 'forge-std/StdMath.sol';

contract WithdrawSwapV3Test is BaseTest {
  ParaSwapWithdrawSwapAdapterV3 internal withdrawSwapAdapter;

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'), 18877385);

    withdrawSwapAdapter = new ParaSwapWithdrawSwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Ethereum.POOL),
      AugustusRegistry.ETHEREUM,
      AaveGovernanceV2.SHORT_EXECUTOR
    );
  }

  function test_revert_withdrawSwap_without_collateral() public {
    address aToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address otherAsset = AaveV3EthereumAssets.USDC_UNDERLYING;

    uint256 supplyAmount = 120e18;
    uint256 withdrawAmount = 120e6;

    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, supplyAmount, collateralAsset);

    skip(1 hours);

    PsPResponse memory psp = _fetchPSPRoute(otherAsset, newAsset, withdrawAmount, user, true, true);

    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: otherAsset,
        oldAssetAmount: withdrawAmount,
        newAsset: newAsset,
        minAmountToReceive: 0,
        allBalanceOffset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IBaseParaSwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes(Errors.INVALID_AMOUNT));
    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, collateralATokenPermit);
  }

  function test_revert_withdrawSwap_max_collateral() public {
    address aToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address otherAsset = AaveV3EthereumAssets.USDC_UNDERLYING;

    uint256 supplyAmount = 120e18;
    uint256 withdrawAmount = 120e6;

    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, supplyAmount, collateralAsset);

    skip(1 hours);

    PsPResponse memory psp = _fetchPSPRoute(otherAsset, newAsset, withdrawAmount, user, true, true);
    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: withdrawAmount / 2,
        newAsset: newAsset,
        minAmountToReceive: 0,
        allBalanceOffset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IBaseParaSwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes('INSUFFICIENT_AMOUNT_TO_SWAP'));
    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, collateralATokenPermit);
  }

  function test_withdrawSwap_swapHalf() public {
    vm.startPrank(user);
    address oldAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address oldAssetAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address newAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newAssetAToken = AaveV3EthereumAssets.LUSD_A_TOKEN;

    uint256 supplyAmount = 10_000 ether;

    _supply(AaveV3Ethereum.POOL, supplyAmount, oldAsset);

    uint256 swapAmount = supplyAmount / 2;
    PsPResponse memory psp = _fetchPSPRoute(oldAsset, newAsset, swapAmount, user, true, false);
    IERC20Detailed(oldAssetAToken).approve(address(withdrawSwapAdapter), swapAmount);
    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: oldAsset,
        oldAssetAmount: swapAmount,
        newAsset: newAsset,
        minAmountToReceive: swapAmount,
        allBalanceOffset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });
    IBaseParaSwapAdapter.PermitInput memory tokenPermit;

    uint256 oldAsset_ATokenBalanceBefore = IERC20Detailed(oldAssetAToken).balanceOf(user);

    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, tokenPermit);

    uint256 oldAsset_ATokenBalanceAfter = IERC20Detailed(oldAssetAToken).balanceOf(user);
    assertEq(
      _withinRange(oldAsset_ATokenBalanceAfter, oldAsset_ATokenBalanceBefore, swapAmount + 1),
      true,
      'INVALID_ATOKEN_AMOUNT_AFTER_WITHDRAW_SWAP'
    );
    _invariant(address(withdrawSwapAdapter), oldAsset, newAsset);
  }

  function test_withdrawSwap_swapHalf_with_permit() public {
    vm.startPrank(user);
    address oldAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address oldAssetAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address newAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newAssetAToken = AaveV3EthereumAssets.LUSD_A_TOKEN;

    uint256 supplyAmount = 10_000 ether;

    _supply(AaveV3Ethereum.POOL, supplyAmount, oldAsset);

    uint256 swapAmount = supplyAmount / 2;
    PsPResponse memory psp = _fetchPSPRoute(oldAsset, newAsset, swapAmount, user, true, false);
    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: oldAsset,
        oldAssetAmount: swapAmount,
        newAsset: newAsset,
        minAmountToReceive: swapAmount,
        allBalanceOffset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IBaseParaSwapAdapter.PermitInput memory tokenPermit = _getPermit(
      oldAssetAToken,
      address(withdrawSwapAdapter),
      swapAmount
    );

    uint256 oldAsset_ATokenBalanceBefore = IERC20Detailed(oldAssetAToken).balanceOf(user);

    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, tokenPermit);

    uint256 oldAsset_ATokenBalanceAfter = IERC20Detailed(oldAssetAToken).balanceOf(user);
    assertEq(
      _withinRange(oldAsset_ATokenBalanceAfter, oldAsset_ATokenBalanceBefore, swapAmount + 1),
      true,
      'INVALID_ATOKEN_AMOUNT_AFTER_WITHDRAW_SWAP'
    );
    _invariant(address(withdrawSwapAdapter), oldAsset, newAsset);
  }

  function test_withdrawSwap_swapFull() public {
    vm.startPrank(user);
    address oldAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address oldAssetAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address newAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newAssetAToken = AaveV3EthereumAssets.LUSD_A_TOKEN;

    uint256 supplyAmount = 10_000 ether;

    _supply(AaveV3Ethereum.POOL, supplyAmount, oldAsset);

    uint256 swapAmount = supplyAmount;
    PsPResponse memory psp = _fetchPSPRoute(oldAsset, newAsset, swapAmount, user, true, false);
    IERC20Detailed(oldAssetAToken).approve(address(withdrawSwapAdapter), swapAmount);
    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: oldAsset,
        oldAssetAmount: swapAmount,
        newAsset: newAsset,
        minAmountToReceive: swapAmount,
        allBalanceOffset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });
    IBaseParaSwapAdapter.PermitInput memory tokenPermit;

    uint256 oldAsset_ATokenBalanceBefore = IERC20Detailed(oldAssetAToken).balanceOf(user);

    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, tokenPermit);

    uint256 oldAsset_ATokenBalanceAfter = IERC20Detailed(oldAssetAToken).balanceOf(user);
    assertEq(
      _withinRange(oldAsset_ATokenBalanceAfter, oldAsset_ATokenBalanceBefore, swapAmount + 1),
      true,
      'INVALID_ATOKEN_AMOUNT_AFTER_WITHDRAW_SWAP'
    );
    assertEq(oldAsset_ATokenBalanceAfter, 0, 'NON_ZERO_ATOKEN_BALANCE_AFTER_WITHDRAW_SWAP');
    _invariant(address(withdrawSwapAdapter), oldAsset, newAsset);
  }

  function _withinRange(uint256 a, uint256 b, uint256 diff) internal returns (bool) {
    return stdMath.delta(a, b) <= diff;
  }

  function _supply(IPool pool, uint256 amount, address asset) internal {
    deal(asset, user, amount);
    IERC20Detailed(asset).approve(address(pool), amount);
    pool.deposit(asset, amount, user, 0);
  }

  function _borrow(IPool pool, uint256 amount, address asset) internal {
    pool.borrow(asset, amount, 2, 0, user);
  }

  function _withdraw(IPool pool, uint256 amount, address asset) internal {
    pool.withdraw(asset, amount, user);
  }
}
