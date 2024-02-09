// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {AaveV2Ethereum, AaveV2EthereumAssets, ILendingPool} from 'aave-address-book/AaveV2Ethereum.sol';
import {ParaSwapWithdrawSwapAdapterV2} from 'src/contracts/ParaSwapWithdrawSwapAdapterV2.sol';
import {IParaSwapAugustusRegistry} from 'src/contracts/dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {AugustusRegistry} from 'src/contracts/dependencies/paraswap/AugustusRegistry.sol';
import {IParaSwapWithdrawSwapAdapter} from 'src/contracts/interfaces/IParaSwapWithdrawSwapAdapter.sol';
import {IBaseParaSwapAdapter} from 'src/contracts/interfaces/IBaseParaSwapAdapter.sol';
import {BaseTest} from './utils/BaseTest.sol';

contract WithdrawSwapAdapterV2Test is BaseTest {
  ParaSwapWithdrawSwapAdapterV2 internal withdrawSwapAdapter;

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'), 19125717);

    withdrawSwapAdapter = new ParaSwapWithdrawSwapAdapterV2(
      IPoolAddressesProvider(address(AaveV2Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV2Ethereum.POOL),
      IParaSwapAugustusRegistry(AugustusRegistry.ETHEREUM),
      AaveGovernanceV2.SHORT_EXECUTOR
    );
  }

  function test_revert_due_to_slippage_withdrawSwap() public {
    address daiAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    uint256 supplyAmount = 120 ether;
    uint256 withdrawAmount = 120 ether;
    uint256 expectedAmount = 10 ether;

    vm.startPrank(user);
    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);

    skip(1 hours);

    IERC20Detailed(daiAToken).approve(address(withdrawSwapAdapter), withdrawAmount);

    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newAsset,
      withdrawAmount,
      user,
      true,
      false
    );
    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: withdrawAmount,
        newAsset: newAsset,
        minAmountToReceive: expectedAmount,
        allBalanceOffset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IBaseParaSwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes('minAmountToReceive exceeds max slippage'));
    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, collateralATokenPermit);
  }

  function test_revert_wrong_paraswap_route() public {
    address daiAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    uint256 supplyAmount = 120 ether;
    uint256 withdrawAmount = 120 ether;
    uint256 expectedAmount = 100 ether;

    vm.startPrank(user);
    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);

    skip(1 hours);

    IERC20Detailed(daiAToken).approve(address(withdrawSwapAdapter), withdrawAmount);
    // generating the paraswap route for half of withdrawAmount and executing swap with withdrawAmount
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newAsset,
      withdrawAmount / 2,
      user,
      true,
      false
    );
    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: withdrawAmount,
        newAsset: newAsset,
        minAmountToReceive: expectedAmount,
        allBalanceOffset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IBaseParaSwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert();
    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, collateralATokenPermit);
  }

  function test_revert_withdrawSwap_max_collateral() public {
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    uint256 supplyAmount = 120 ether;
    uint256 withdrawAmount = 120 ether;
    uint256 expectedAmount = 115 ether;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);

    skip(1 hours);

    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newAsset,
      withdrawAmount,
      user,
      true,
      true
    );
    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: withdrawAmount,
        newAsset: newAsset,
        minAmountToReceive: expectedAmount,
        allBalanceOffset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IBaseParaSwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes('INSUFFICIENT_AMOUNT_TO_SWAP'));
    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, collateralATokenPermit);
  }

  function test_withdrawSwap_swapHalf() public {
    vm.startPrank(user);
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    uint256 supplyAmount = 10_000 ether;

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);

    uint256 swapAmount = 5_000 ether; // supplyAmount/2
    uint256 expectedAmount = 4500 ether;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newAsset,
      swapAmount,
      user,
      true,
      false
    );
    IERC20Detailed(collateralAssetAToken).approve(address(withdrawSwapAdapter), swapAmount);

    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: swapAmount,
        newAsset: newAsset,
        minAmountToReceive: expectedAmount,
        allBalanceOffset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });
    IBaseParaSwapAdapter.PermitInput memory tokenPermit;

    uint256 collateratAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newAssetBalanceBefore = IERC20Detailed(newAsset).balanceOf(user);

    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, tokenPermit);

    uint256 collateratAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newAssetBalanceAfter = IERC20Detailed(newAsset).balanceOf(user);
    assertEq(
      _withinRange(
        collateratAssetATokenBalanceAfter,
        collateratAssetATokenBalanceBefore,
        swapAmount + 1
      ),
      true,
      'INVALID_ATOKEN_AMOUNT_AFTER_WITHDRAW_SWAP'
    );
    assertGt(
      newAssetBalanceAfter - newAssetBalanceBefore,
      expectedAmount,
      'invalid amount received'
    );
    _invariant(address(withdrawSwapAdapter), collateralAsset, newAsset);
  }

  function test_withdrawSwap_swapHalf_with_permit() public {
    vm.startPrank(user);
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address newAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    uint256 supplyAmount = 10_000 ether;

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);

    uint256 swapAmount = 5_000 ether; // supplyAmount/2
    uint256 expectedAmount = 4500 ether;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newAsset,
      swapAmount,
      user,
      true,
      false
    );

    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: swapAmount,
        newAsset: newAsset,
        minAmountToReceive: expectedAmount,
        allBalanceOffset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IBaseParaSwapAdapter.PermitInput memory tokenPermit = _getPermit(
      collateralAssetAToken,
      address(withdrawSwapAdapter),
      swapAmount
    );

    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newAssetBalanceBefore = IERC20Detailed(newAsset).balanceOf(user);

    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, tokenPermit);

    uint256 collateratAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newAssetBalanceAfter = IERC20Detailed(newAsset).balanceOf(user);

    assertEq(
      _withinRange(
        collateratAssetATokenBalanceAfter,
        collateralAssetATokenBalanceBefore,
        swapAmount + 1
      ),
      true,
      'INVALID_ATOKEN_AMOUNT_AFTER_WITHDRAW_SWAP'
    );
    assertGt(
      newAssetBalanceAfter - newAssetBalanceBefore,
      expectedAmount,
      'invalid amount received'
    );
    _invariant(address(withdrawSwapAdapter), collateralAsset, newAsset);
  }

  function test_withdrawSwap_swapFull() public {
    vm.startPrank(user);
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address newAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    uint256 supplyAmount = 10_000 ether;

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);

    skip(1 hours);

    uint256 swapAmount = 10_100 ether;
    uint256 expectedAmount = 9500 ether;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newAsset,
      swapAmount,
      user,
      true,
      true
    );

    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: swapAmount,
        newAsset: newAsset,
        minAmountToReceive: expectedAmount,
        allBalanceOffset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });
    IBaseParaSwapAdapter.PermitInput memory tokenPermit;

    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newAssetBalanceBefore = IERC20Detailed(newAsset).balanceOf(user);

    IERC20Detailed(collateralAssetAToken).approve(
      address(withdrawSwapAdapter),
      collateralAssetATokenBalanceBefore
    );

    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, tokenPermit);

    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newAssetBalanceAfter = IERC20Detailed(newAsset).balanceOf(user);
    assertEq(collateralAssetATokenBalanceAfter, 0, 'NON_ZERO_ATOKEN_BALANCE_AFTER_WITHDRAW_SWAP');
    assertGt(
      newAssetBalanceAfter - newAssetBalanceBefore,
      expectedAmount,
      'invalid amount received'
    );
    _invariant(address(withdrawSwapAdapter), collateralAsset, newAsset);
  }

  function _supply(ILendingPool pool, uint256 amount, address asset) internal {
    deal(asset, user, amount);
    IERC20Detailed(asset).approve(address(pool), amount);
    pool.deposit(asset, amount, user, 0);
  }

  function _borrow(ILendingPool pool, uint256 amount, address asset) internal {
    pool.borrow(asset, amount, 2, 0, user);
  }

  function _withdraw(ILendingPool pool, uint256 amount, address asset) internal {
    pool.withdraw(asset, amount, user);
  }
}
