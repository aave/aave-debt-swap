// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {Errors} from 'aave-address-book/AaveV2.sol';
import {AaveV2Ethereum, AaveV2EthereumAssets, ILendingPool} from 'aave-address-book/AaveV2Ethereum.sol';
import {ParaSwapLiquiditySwapAdapterV2} from 'src/contracts/ParaSwapLiquiditySwapAdapterV2.sol';
import {IParaSwapAugustusRegistry} from 'src/contracts/dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {IParaSwapLiquiditySwapAdapter} from 'src/contracts/interfaces/IParaSwapLiquiditySwapAdapter.sol';
import {AugustusRegistry} from 'src/contracts/dependencies/paraswap/AugustusRegistry.sol';
import {BaseTest} from './utils/BaseTest.sol';

contract LiquiditySwapAdapterV2Test is BaseTest {
  ParaSwapLiquiditySwapAdapterV2 internal liquiditySwapAdapter;

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'), 19125717);

    liquiditySwapAdapter = new ParaSwapLiquiditySwapAdapterV2(
      IPoolAddressesProvider(address(AaveV2Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV2Ethereum.POOL),
      IParaSwapAugustusRegistry(AugustusRegistry.ETHEREUM),
      AaveGovernanceV2.SHORT_EXECUTOR
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
    vm.prank(address(AaveV2Ethereum.POOL));
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
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    uint256 supplyAmount = 120 ether;
    uint256 borrowAmount = 80 ether;

    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, collateralAsset);

    _withdraw(AaveV2Ethereum.POOL, withdrawAmount, collateralAsset);

    vm.expectRevert(bytes(Errors.VL_TRANSFER_NOT_ALLOWED));
    _withdraw(AaveV2Ethereum.POOL, 25 ether, collateralAsset);

    // Swap liquidity(collateral)
    uint256 collateralAmountToSwap = 25 ether;
    uint256 expectedAmount = 20 ether;
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
        newCollateralAmount: expectedAmount,
        offset: psp.offset,
        user: user,
        withFlashLoan: false,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes(Errors.VL_TRANSFER_NOT_ALLOWED));
    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, collateralATokenPermit);
  }

  function test_revert_due_to_insufficient_amount() public {
    uint256 supplyAmount = 12_000 ether;
    uint256 borrowAmount = 1_000 ether;

    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address newCollateralAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    vm.startPrank(user);
    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, collateralAsset);

    skip(1 hours);

    uint256 collateralAmountToSwap = 11_999 ether;
    uint256 expectedAmount = 11_800 ether;
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
        newCollateralAmount: expectedAmount,
        offset: psp.offset,
        user: user,
        withFlashLoan: false,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes('INSUFFICIENT_AMOUNT_TO_SWAP'));
    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, collateralATokenPermit);
  }

  function test_revert_wrong_paraswap_route() public {
    uint256 supplyAmount = 12_000 ether;
    uint256 borrowAmount = 9_000 ether;

    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address newCollateralAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    vm.startPrank(user);
    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, collateralAsset);

    skip(1 hours);

    uint256 collateralAmountToSwap = 250 ether;
    uint256 expectedAmount = 220 ether;
    // generating the paraswap route for half of collateralAmountToSwap and executing swap with collateralAmountToSwap
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newCollateralAsset,
      collateralAmountToSwap / 2,
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
        newCollateralAmount: expectedAmount,
        offset: psp.offset,
        user: user,
        withFlashLoan: false,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes('WRONG_BALANCE_AFTER_SWAP'));
    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, collateralATokenPermit);
  }

  function test_liquiditySwap_without_extra_collateral() public {
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address newCollateralAssetAToken = AaveV2EthereumAssets.LUSD_A_TOKEN;

    uint256 supplyAmount = 12000 ether;
    uint256 borrowAmount = 1000 ether;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, collateralAsset);

    uint256 oldCollateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newCollateralAssetATokenBalanceBefore = IERC20Detailed(newCollateralAssetAToken)
      .balanceOf(user);

    uint256 collateralAmountToSwap = 3000 ether;
    uint256 expectedAmount = 2800 ether;
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
        newCollateralAmount: expectedAmount,
        offset: psp.offset,
        user: user,
        withFlashLoan: false,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit;

    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, collateralATokenPermit);

    _invariant(address(liquiditySwapAdapter), collateralAsset, newCollateralAsset);
    uint256 oldCollateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newCollateralAssetATokenBalanceAfter = IERC20Detailed(newCollateralAssetAToken)
      .balanceOf(user);
    assertGt(
      newCollateralAssetATokenBalanceAfter - newCollateralAssetATokenBalanceBefore,
      expectedAmount,
      'invalid amount received'
    );
    assertTrue(
      _withinRange(
        oldCollateralAssetATokenBalanceBefore - oldCollateralAssetATokenBalanceAfter,
        collateralAmountToSwap,
        2
      )
    );
  }

  function test_liquiditySwap_permit_without_extra_collateral() public {
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address newCollateralAssetAToken = AaveV2EthereumAssets.LUSD_A_TOKEN;

    uint256 supplyAmount = 10_000 ether;
    uint256 borrowAmount = 1000 ether;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, collateralAsset);

    uint256 oldCollateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newCollateralAssetATokenBalanceBefore = IERC20Detailed(newCollateralAssetAToken)
      .balanceOf(user);

    uint256 collateralAmountToSwap = 5000 ether;
    uint256 expectedAmount = 4800 ether;
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
        newCollateralAmount: expectedAmount,
        offset: psp.offset,
        user: user,
        withFlashLoan: false,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit = _getPermit(
      collateralAssetAToken,
      address(liquiditySwapAdapter),
      collateralAmountToSwap
    );

    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, collateralATokenPermit);

    _invariant(address(liquiditySwapAdapter), collateralAsset, newCollateralAsset);
    uint256 oldCollateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newCollateralAssetATokenBalanceAfter = IERC20Detailed(newCollateralAssetAToken)
      .balanceOf(user);
    assertTrue(
      _withinRange(
        oldCollateralAssetATokenBalanceBefore - oldCollateralAssetATokenBalanceAfter,
        collateralAmountToSwap,
        2
      )
    );
    assertGt(
      newCollateralAssetATokenBalanceAfter - newCollateralAssetATokenBalanceBefore,
      expectedAmount,
      'invalid amount received'
    );
  }

  function test_revert_liquiditySwap_wrong_permit() public {
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    uint256 supplyAmount = 10_000 ether;
    uint256 borrowAmount = 1000 ether;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, collateralAsset);

    uint256 collateralAmountToSwap = 5000 ether;
    uint256 expectedAmount = 4800 ether;
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
        newCollateralAmount: expectedAmount,
        offset: psp.offset,
        user: user,
        withFlashLoan: false,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit = _getPermit(
      collateralAssetAToken,
      address(liquiditySwapAdapter),
      collateralAmountToSwap - 1
    );

    vm.expectRevert(bytes('ERC20: transfer amount exceeds allowance'));
    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, collateralATokenPermit);
  }

  function test_liquiditySwapFull_without_extra_collateral() public {
    uint256 supplyAmount = 15_000 ether;
    uint256 borrowAmount = 1000 ether;

    address anotherCollateralAsset = AaveV2EthereumAssets.USDC_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address newCollateralAssetAToken = AaveV2EthereumAssets.LUSD_A_TOKEN;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    //supplying extra collateral so that all dai collateral can be swapped without flashloan
    _supply(AaveV2Ethereum.POOL, 15000e6, anotherCollateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, collateralAsset);

    uint256 newCollateralAssetATokenBalanceBefore = IERC20Detailed(newCollateralAssetAToken)
      .balanceOf(user);

    uint256 collateralAmountToSwap = 15_000 ether; // equals to supplyAmount
    uint256 expectedAmount = 14_800 ether;
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
        newCollateralAmount: expectedAmount,
        offset: psp.offset,
        user: user,
        withFlashLoan: false,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit;

    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, collateralATokenPermit);

    uint256 oldCollateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newCollateralAssetATokenBalanceAfter = IERC20Detailed(newCollateralAssetAToken)
      .balanceOf(user);
    assertEq(oldCollateralAssetATokenBalanceAfter, 0);
    _invariant(address(liquiditySwapAdapter), newCollateralAsset, collateralAsset);
    assertGt(
      newCollateralAssetATokenBalanceAfter - newCollateralAssetATokenBalanceBefore,
      expectedAmount,
      'invalid amount received'
    );
  }

  function test_liquiditySwap_half_with_flashloan() public {
    uint256 supplyAmount = 18_000 ether;
    uint256 borrowAmount = 12_000 ether;

    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV2EthereumAssets.USDC_UNDERLYING;
    address newCollateralAssetAToken = AaveV2EthereumAssets.USDC_A_TOKEN;
    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, collateralAsset);

    uint256 oldCollateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newCollateralAssetATokenBalanceBefore = IERC20Detailed(newCollateralAssetAToken)
      .balanceOf(user);

    uint256 collateralAmountToSwap = 5000 ether;
    uint256 expectedAmount = 4800e6;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newCollateralAsset,
      (collateralAmountToSwap * 9991) / 10_000, //taking flashloan premium(0.09%) into account
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
        newCollateralAmount: expectedAmount,
        offset: psp.offset,
        user: user,
        withFlashLoan: true,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit;

    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, collateralATokenPermit);
    uint256 oldCollateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newCollateralAssetATokenBalanceAfter = IERC20Detailed(newCollateralAssetAToken)
      .balanceOf(user);
    assertTrue(
      _withinRange(
        oldCollateralAssetATokenBalanceBefore - oldCollateralAssetATokenBalanceAfter,
        collateralAmountToSwap,
        1e15 //flashloan premium is added to the pool and indexes are updated. So, relaxed this condition
      )
    );
    assertGt(
      newCollateralAssetATokenBalanceAfter - newCollateralAssetATokenBalanceBefore,
      expectedAmount,
      'invalid amount received'
    );
    _invariant(address(liquiditySwapAdapter), collateralAsset, newCollateralAsset);
  }

  function test_revert_liquiditySwap_half_without_flashloan() public {
    uint256 supplyAmount = 18_000 ether;
    uint256 borrowAmount = 12_000 ether;

    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV2EthereumAssets.USDC_UNDERLYING;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, collateralAsset);

    uint256 collateralAmountToSwap = 4500 ether;
    uint256 expectedAmount = 4000e6;
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
        newCollateralAmount: expectedAmount,
        offset: psp.offset,
        user: user,
        withFlashLoan: false,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes(Errors.VL_TRANSFER_NOT_ALLOWED));
    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, collateralATokenPermit);

    _invariant(address(liquiditySwapAdapter), collateralAsset, newCollateralAsset);
  }

  function test_liquiditySwap_full_with_flashloan_and_permit() public {
    uint256 supplyAmount = 18_000 ether;
    uint256 borrowAmount = 10_000 ether;

    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newCollateralAsset = AaveV2EthereumAssets.USDC_UNDERLYING;
    address newCollateralAssetAToken = AaveV2EthereumAssets.USDC_A_TOKEN;
    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, collateralAsset);

    uint256 newCollateralAssetATokenBalanceBefore = IERC20Detailed(newCollateralAssetAToken)
      .balanceOf(user);

    uint256 collateralAmountToSwap = 18_000 ether; // supplyAmount
    uint256 expectedAmount = 17_500e6;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newCollateralAsset,
      (collateralAmountToSwap * 9991) / 10_000, //taking flashloan premium(0.09%) into account
      user,
      true,
      true
    );

    IParaSwapLiquiditySwapAdapter.LiquiditySwapParams
      memory liquiditySwapParams = IParaSwapLiquiditySwapAdapter.LiquiditySwapParams({
        collateralAsset: collateralAsset,
        collateralAmountToSwap: collateralAmountToSwap,
        newCollateralAsset: newCollateralAsset,
        newCollateralAmount: expectedAmount,
        offset: psp.offset,
        user: user,
        withFlashLoan: true,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });
    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit = _getPermit(
      collateralAssetAToken,
      address(liquiditySwapAdapter),
      collateralAmountToSwap
    );

    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, collateralATokenPermit);
    uint256 oldCollateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newCollateralAssetATokenBalanceAfter = IERC20Detailed(newCollateralAssetAToken)
      .balanceOf(user);
    assertEq(oldCollateralAssetATokenBalanceAfter, 0, 'swap with all collateral failed');
    assertGt(
      newCollateralAssetATokenBalanceAfter - newCollateralAssetATokenBalanceBefore,
      expectedAmount,
      'invalid amount received'
    );
    _invariant(address(liquiditySwapAdapter), collateralAsset, newCollateralAsset);
    _invariant(address(liquiditySwapAdapter), collateralAssetAToken, newCollateralAssetAToken);
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
