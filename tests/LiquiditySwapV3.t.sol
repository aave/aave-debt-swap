// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IACLManager} from '@aave/core-v3/contracts/interfaces/IACLManager.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {Errors} from 'aave-address-book/AaveV3.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets, IPool} from 'aave-address-book/AaveV3Ethereum.sol';
import {BaseTest} from './utils/BaseTest.sol';
import {ParaSwapLiquiditySwapAdapterV3} from '../src/contracts/ParaSwapLiquiditySwapAdapterV3.sol';
import {AugustusRegistry} from '../src/lib/AugustusRegistry.sol';
import {BaseParaSwapAdapter} from '../src/contracts/BaseParaSwapAdapter.sol';
import {IParaSwapLiquiditySwapAdapter} from '../src/interfaces/IParaSwapLiquiditySwapAdapter.sol';
import {IBaseParaSwapAdapter} from '../src/interfaces/IBaseParaSwapAdapter.sol';
import {stdMath} from 'forge-std/StdMath.sol';

contract LiquiditySwapAdapterV3 is BaseTest {
  ParaSwapLiquiditySwapAdapterV3 internal liquiditySwapAdapter;

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'), 18683100);

    liquiditySwapAdapter = new ParaSwapLiquiditySwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Ethereum.POOL),
      AugustusRegistry.ETHEREUM,
      AaveGovernanceV2.SHORT_EXECUTOR
    );
    vm.startPrank(0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A); //ACL admin
    IACLManager(address(AaveV3Ethereum.ACL_MANAGER)).addFlashBorrower(
      address(liquiditySwapAdapter)
    );
    vm.stopPrank();
  }

  function test_revert_executeOperation_not_pool() public {
    address[] memory mockAddresses = new address[](0);
    uint256[] memory mockAmounts = new uint256[](0);

    vm.expectRevert(bytes('CALLER_MUST_BE_POOL'));
    liquiditySwapAdapter.executeOperation(
      mockAddresses,
      mockAmounts,
      mockAmounts,
      address(0),
      abi.encode('')
    );
  }

  function test_revert_executeOperation_wrong_initiator() public {
    vm.prank(address(AaveV3Ethereum.POOL));
    address[] memory mockAddresses = new address[](0);
    uint256[] memory mockAmounts = new uint256[](0);

    vm.expectRevert(bytes('INITIATOR_MUST_BE_THIS'));
    liquiditySwapAdapter.executeOperation(
      mockAddresses,
      mockAmounts,
      mockAmounts,
      address(0),
      abi.encode('')
    );
  }

  function test_revert_liquiditySwap_without_extra_collateral() public {
    address collateralAssetAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;

    uint256 supplyAmount = 120e18;
    uint256 borrowAmount = 80e18;

    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;

    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, collateralAsset);

    _withdraw(AaveV3Ethereum.POOL, withdrawAmount, collateralAsset);

    vm.expectRevert(bytes(Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD));
    _withdraw(AaveV3Ethereum.POOL, 25e18, collateralAsset);

    // Swap liquidity(collateral)
    uint256 collateralAmountToSwap = 25e18;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newCollateralAsset,
      collateralAmountToSwap,
      user,
      true,
      false
    );

    skip(1 hours);

    IERC20Detailed(collateralAssetAToken).approve(
      address(liquiditySwapAdapter),
      collateralAmountToSwap
    );

    IParaSwapLiquiditySwapAdapter.LiquiditySwapParams
      memory liquiditySwapParams = IParaSwapLiquiditySwapAdapter.LiquiditySwapParams({
        collateralAsset: collateralAsset,
        collateralAmountToSwap: collateralAmountToSwap,
        newCollateralAsset: newCollateralAsset,
        newCollateralAmount: 25e18,
        offset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.FlashParams memory flashParams;
    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes(Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD));
    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, flashParams, collateralATokenPermit);
  }

  function test_liquiditySwap_without_extra_collateral() public {
    address collateralAssetAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newCollateralAssetAToken = AaveV3EthereumAssets.LUSD_A_TOKEN;

    uint256 supplyAmount = 12000e18;
    uint256 borrowAmount = 80e18;

    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, collateralAsset);

    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );

    // Swap liquidity(collateral)
    uint256 collateralAmountToSwap = 1000e18;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newCollateralAsset,
      collateralAmountToSwap,
      user,
      true,
      false
    );

    IERC20Detailed(collateralAssetAToken).approve(
      address(liquiditySwapAdapter),
      collateralAmountToSwap
    );

    IParaSwapLiquiditySwapAdapter.LiquiditySwapParams
      memory liquiditySwapParams = IParaSwapLiquiditySwapAdapter.LiquiditySwapParams({
        collateralAsset: collateralAsset,
        collateralAmountToSwap: collateralAmountToSwap,
        newCollateralAsset: newCollateralAsset,
        newCollateralAmount: 900e18,
        offset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.FlashParams memory flashParams;
    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit;

    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, flashParams, collateralATokenPermit);

    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    assertTrue(
      _withinRange(
        collateralAssetATokenBalanceBefore - collateralAssetATokenBalanceAfter,
        collateralAmountToSwap,
        2
      )
    );
    _invariant(address(liquiditySwapAdapter), collateralAsset, newCollateralAsset);
    _invariant(address(liquiditySwapAdapter), collateralAssetAToken, newCollateralAssetAToken);
  }

  function test_liquiditySwap_permit_without_extra_collateral() public {
    address collateralAssetAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newCollateralAssetAToken = AaveV3EthereumAssets.LUSD_A_TOKEN;

    uint256 supplyAmount = 12000e18;
    uint256 borrowAmount = 80e18;

    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, collateralAsset);

    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );

    // Swap liquidity(collateral)
    uint256 collateralAmountToSwap = 1000e18;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newCollateralAsset,
      collateralAmountToSwap,
      user,
      true,
      false
    );

    IParaSwapLiquiditySwapAdapter.LiquiditySwapParams
      memory liquiditySwapParams = IParaSwapLiquiditySwapAdapter.LiquiditySwapParams({
        collateralAsset: collateralAsset,
        collateralAmountToSwap: collateralAmountToSwap,
        newCollateralAsset: newCollateralAsset,
        newCollateralAmount: 900e18,
        offset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.FlashParams memory flashParams;
    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit = _getPermit(
      collateralAssetAToken,
      address(liquiditySwapAdapter),
      collateralAmountToSwap
    );

    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, flashParams, collateralATokenPermit);

    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    assertTrue(
      _withinRange(
        collateralAssetATokenBalanceBefore - collateralAssetATokenBalanceAfter,
        collateralAmountToSwap,
        2
      )
    );
    _invariant(address(liquiditySwapAdapter), collateralAsset, newCollateralAsset);
    _invariant(address(liquiditySwapAdapter), collateralAssetAToken, newCollateralAssetAToken);
  }

  function test_liquiditySwapFull_without_extra_collateral() public {
    uint256 daiSupplyAmount = 12000e18;
    uint256 usdcSupplyAmount = 12000e6;
    uint256 borrowAmount = 80e18;

    address anotherCollateralAsset = AaveV3EthereumAssets.USDC_UNDERLYING;
    address collateralAssetAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newCollateralAssetAToken = AaveV3EthereumAssets.LUSD_A_TOKEN;

    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, daiSupplyAmount, collateralAsset);
    _supply(AaveV3Ethereum.POOL, usdcSupplyAmount, anotherCollateralAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, collateralAsset);

    uint256 daiCollateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );

    // Swap liquidity(collateral)
    uint256 collateralAmountToSwap = daiSupplyAmount;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newCollateralAsset,
      collateralAmountToSwap,
      user,
      true,
      true
    );

    IERC20Detailed(collateralAssetAToken).approve(
      address(liquiditySwapAdapter),
      collateralAmountToSwap
    );

    IParaSwapLiquiditySwapAdapter.LiquiditySwapParams
      memory liquiditySwapParams = IParaSwapLiquiditySwapAdapter.LiquiditySwapParams({
        collateralAsset: collateralAsset,
        collateralAmountToSwap: collateralAmountToSwap,
        newCollateralAsset: newCollateralAsset,
        newCollateralAmount: daiSupplyAmount,
        offset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.FlashParams memory flashParams;
    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit;

    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, flashParams, collateralATokenPermit);

    uint256 daiCollateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    assertTrue(
      _withinRange(
        daiCollateralAssetATokenBalanceBefore - daiCollateralAssetATokenBalanceAfter,
        collateralAmountToSwap,
        2
      )
    );
    assertEq(daiCollateralAssetATokenBalanceAfter, 0);
    _invariant(address(liquiditySwapAdapter), newCollateralAsset, newCollateralAssetAToken);
    _invariant(address(liquiditySwapAdapter), collateralAsset, collateralAssetAToken);
  }

  function test_liquiditySwap_with_extra_collateral() public {
    uint256 supplyAmount = 12000e18;
    uint256 borrowAmount = 5000e18;
    uint256 flashLoanAmount = 2000e18;
    address collateralAssetAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newCollateralAssetAToken = AaveV3EthereumAssets.LUSD_A_TOKEN;
    address flashLoanAsset = collateralAsset;
    address flashLoanAssetAToken = collateralAssetAToken;
    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, collateralAsset);

    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );

    // Swap liquidity(collateral)
    uint256 collateralAmountToSwap = 2000e18;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newCollateralAsset,
      collateralAmountToSwap,
      user,
      true,
      false
    );

    IERC20Detailed(collateralAssetAToken).approve(
      address(liquiditySwapAdapter),
      collateralAmountToSwap
    );

    IParaSwapLiquiditySwapAdapter.LiquiditySwapParams
      memory liquiditySwapParams = IParaSwapLiquiditySwapAdapter.LiquiditySwapParams({
        collateralAsset: collateralAsset,
        collateralAmountToSwap: collateralAmountToSwap,
        newCollateralAsset: newCollateralAsset,
        newCollateralAmount: 2000e18,
        offset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit;
    IParaSwapLiquiditySwapAdapter.PermitInput memory flashLoanATokenPermit;
    IParaSwapLiquiditySwapAdapter.FlashParams memory flashParams = IParaSwapLiquiditySwapAdapter
      .FlashParams({flashLoanAsset: flashLoanAsset, flashLoanAmount: flashLoanAmount});

    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, flashParams, collateralATokenPermit);
    {
      uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
        user
      );
      assertTrue(
        _withinRange(
          collateralAssetATokenBalanceBefore - collateralAssetATokenBalanceAfter,
          collateralAmountToSwap,
          2
        )
      );
    }
    _invariant(address(liquiditySwapAdapter), collateralAsset, newCollateralAsset);
    _invariant(address(liquiditySwapAdapter), collateralAssetAToken, newCollateralAssetAToken);
    _invariant(address(liquiditySwapAdapter), flashLoanAsset, flashLoanAssetAToken);
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

  function _withinRange(uint256 a, uint256 b, uint256 diff) internal returns (bool) {
    return stdMath.delta(a, b) <= diff;
  }
}
