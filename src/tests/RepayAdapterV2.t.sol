// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {Errors} from 'aave-address-book/AaveV2.sol';
import {AaveV2Ethereum, AaveV2EthereumAssets, ILendingPool} from 'aave-address-book/AaveV2Ethereum.sol';
import {ParaSwapRepayAdapterV2} from 'src/contracts/ParaSwapRepayAdapterV2.sol';
import {IParaSwapAugustusRegistry} from 'src/contracts/dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {AugustusRegistry} from 'src/contracts/dependencies/paraswap/AugustusRegistry.sol';
import {IParaSwapRepayAdapter} from 'src/contracts/interfaces/IParaSwapRepayAdapter.sol';
import {BaseTest} from './utils/BaseTest.sol';

contract RepayAdapterV2Test is BaseTest {
  ParaSwapRepayAdapterV2 internal repayAdapter;

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'), 18883410);

    repayAdapter = new ParaSwapRepayAdapterV2(
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
    repayAdapter.executeOperation(
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
    repayAdapter.executeOperation(
      mockAddresses,
      mockAmounts,
      mockAmounts,
      address(0),
      abi.encode('')
    );
  }

  function test_repay_partial() public {
    uint256 supplyAmount = 12_000 ether;
    uint256 borrowAmount = 6_000 ether;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address debtAssetVToken = AaveV2EthereumAssets.LUSD_V_TOKEN;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV2Ethereum.POOL, 5_000 ether, debtAsset);

    uint256 maxCollateralAmountToSwap = 3300 ether;
    uint256 debtRepayAmount = 3_000 ether;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      debtAsset,
      debtRepayAmount,
      user,
      false,
      false
    );

    skip(1 hours);

    IERC20Detailed(collateralAssetAToken).approve(address(repayAdapter), maxCollateralAmountToSwap);
    IParaSwapRepayAdapter.RepayParams memory repayParams = IParaSwapRepayAdapter.RepayParams({
      collateralAsset: collateralAsset,
      maxCollateralAmountToSwap: maxCollateralAmountToSwap,
      debtRepayAsset: debtAsset,
      debtRepayAmount: debtRepayAmount,
      debtRepayMode: 2,
      offset: psp.offset,
      withFlashLoan: false,
      user: user,
      paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
    });

    IParaSwapRepayAdapter.PermitInput memory collateralATokenPermit;

    uint256 debtTokenBalanceBefore = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );

    repayAdapter.repayWithCollateral(repayParams, collateralATokenPermit);

    uint256 debtTokenBalanceAfter = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    assertTrue(_withinRange(debtTokenBalanceBefore - debtTokenBalanceAfter, debtRepayAmount, 2));
    assertTrue(
      _withinRange(
        collateralAssetATokenBalanceBefore - collateralAssetATokenBalanceAfter,
        maxCollateralAmountToSwap,
        300 ether
      )
    );
    assertGt(collateralAssetATokenBalanceBefore, collateralAssetATokenBalanceAfter);
    _invariant(address(repayAdapter), collateralAsset, debtAsset);
  }

  function test_repay_partial_with_permit() public {
    uint256 supplyAmount = 20_000 ether;
    uint256 borrowAmount = 8_000 ether;

    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address debtAssetVToken = AaveV2EthereumAssets.LUSD_V_TOKEN;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV2Ethereum.POOL, 10_000 ether, debtAsset);

    uint256 maxCollateralAmountToSwap = 2200 ether;
    uint256 debtRepayAmount = 2_000 ether;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      debtAsset,
      debtRepayAmount,
      user,
      false,
      false
    );

    skip(1 hours);

    IParaSwapRepayAdapter.RepayParams memory repayParams = IParaSwapRepayAdapter.RepayParams({
      collateralAsset: collateralAsset,
      maxCollateralAmountToSwap: maxCollateralAmountToSwap,
      debtRepayAsset: debtAsset,
      debtRepayAmount: debtRepayAmount,
      debtRepayMode: 2,
      offset: psp.offset,
      withFlashLoan: false,
      user: user,
      paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
    });

    IParaSwapRepayAdapter.PermitInput memory collateralATokenPermit = _getPermit(
      collateralAssetAToken,
      address(repayAdapter),
      maxCollateralAmountToSwap
    );

    uint256 debtTokenBalanceBefore = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );

    repayAdapter.repayWithCollateral(repayParams, collateralATokenPermit);

    uint256 debtTokenBalanceAfter = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    assertTrue(_withinRange(debtTokenBalanceBefore - debtTokenBalanceAfter, debtRepayAmount, 2));
    assertTrue(
      _withinRange(
        collateralAssetATokenBalanceBefore - collateralAssetATokenBalanceAfter,
        maxCollateralAmountToSwap,
        300 ether
      )
    );
    assertGt(collateralAssetATokenBalanceBefore, collateralAssetATokenBalanceAfter);
    _invariant(address(repayAdapter), collateralAsset, debtAsset);
  }

  function test_repay_full_without_flashLoan() public {
    uint256 supplyAmount = 20_000 ether;
    uint256 borrowAmount = 7_900 ether;

    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address debtAssetVToken = AaveV2EthereumAssets.LUSD_V_TOKEN;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    skip(1 hours);

    uint256 maxCollateralAssetToSwap = 8500 ether;
    uint256 debtRepayAmount = 8000 ether;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      debtAsset,
      debtRepayAmount,
      user,
      false,
      true
    );

    IERC20Detailed(collateralAssetAToken).approve(address(repayAdapter), maxCollateralAssetToSwap);
    IParaSwapRepayAdapter.RepayParams memory repayParams = IParaSwapRepayAdapter.RepayParams({
      collateralAsset: collateralAsset,
      maxCollateralAmountToSwap: maxCollateralAssetToSwap,
      debtRepayAsset: debtAsset,
      debtRepayAmount: debtRepayAmount,
      debtRepayMode: 2,
      offset: psp.offset,
      withFlashLoan: false,
      user: user,
      paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
    });

    IParaSwapRepayAdapter.PermitInput memory collateralATokenPermit;

    uint256 debtTokenBalanceBefore = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );

    repayAdapter.repayWithCollateral(repayParams, collateralATokenPermit);

    uint256 debtTokenBalanceAfter = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    assertTrue(debtTokenBalanceAfter == 0, 'FULL_DEBT_NOT_REPAID');
    assertTrue(
      _withinRange(debtTokenBalanceBefore - debtTokenBalanceAfter, debtRepayAmount, 100 ether)
    );
    assertGt(collateralAssetATokenBalanceBefore, collateralAssetATokenBalanceAfter);
    _invariant(address(repayAdapter), collateralAsset, debtAsset);
  }

  function test_repay_full_with_flashloan() public {
    uint256 supplyAmount = 12_000 ether;
    uint256 borrowAmount = 9_000 ether;

    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address debtAssetVToken = AaveV2EthereumAssets.LUSD_V_TOKEN;

    vm.startPrank(user);
    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    skip(1 hours);

    uint256 debtRepayAmount = 9100 ether;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      debtAsset,
      debtRepayAmount,
      user,
      false,
      true
    );

    IERC20Detailed(collateralAssetAToken).approve(address(repayAdapter), psp.srcAmount);
    IParaSwapRepayAdapter.RepayParams memory repayParams = IParaSwapRepayAdapter.RepayParams({
      collateralAsset: collateralAsset,
      maxCollateralAmountToSwap: psp.srcAmount,
      debtRepayAsset: debtAsset,
      debtRepayAmount: debtRepayAmount,
      debtRepayMode: 2,
      offset: psp.offset,
      withFlashLoan: true,
      user: user,
      paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
    });
    IParaSwapRepayAdapter.PermitInput memory collateralATokenPermit;

    uint256 debtTokenBalanceBefore = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );

    repayAdapter.repayWithCollateral(repayParams, collateralATokenPermit);

    uint256 debtTokenBalanceAfter = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    assertTrue(
      _withinRange(debtTokenBalanceBefore - debtTokenBalanceAfter, debtRepayAmount, 100 ether)
    );
    assertTrue(debtTokenBalanceAfter == 0);
    assertGt(collateralAssetATokenBalanceBefore, collateralAssetATokenBalanceAfter);
    _invariant(address(repayAdapter), collateralAsset, debtAsset);
  }

  function test_revert_with_invalid_flashloan_input() public {
    uint256 supplyAmount = 12_000 ether;
    uint256 borrowAmount = 9_000 ether;

    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    vm.startPrank(user);
    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    skip(1 hours);

    uint256 debtRepayAmount = 9100 ether;
    uint256 maxCollateralAmountToSwap = 9500 ether;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      debtAsset,
      debtRepayAmount,
      user,
      false,
      true
    );

    IERC20Detailed(collateralAssetAToken).approve(address(repayAdapter), maxCollateralAmountToSwap);
    IParaSwapRepayAdapter.RepayParams memory repayParams = IParaSwapRepayAdapter.RepayParams({
      collateralAsset: collateralAsset,
      maxCollateralAmountToSwap: psp.srcAmount - 1, // not passing enough amount for flashloan
      debtRepayAsset: debtAsset,
      debtRepayAmount: debtRepayAmount,
      debtRepayMode: 2,
      offset: psp.offset,
      withFlashLoan: false,
      user: user,
      paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
    });
    IParaSwapRepayAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert();
    repayAdapter.repayWithCollateral(repayParams, collateralATokenPermit);
  }

  function test_revert_wrong_paraswap_route() public {
    uint256 supplyAmount = 12_000 ether;
    uint256 borrowAmount = 9_000 ether;

    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    vm.startPrank(user);
    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    skip(1 hours);

    uint256 debtRepayAmount = 9100 ether;
    uint256 maxCollateralAmountToSwap = 9500 ether;
    // generating the paraswap route for half of debtRepayAmount and calling repayAdapter with debtRepayAmount
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      debtAsset,
      debtRepayAmount / 2,
      user,
      false,
      true
    );

    IERC20Detailed(collateralAssetAToken).approve(address(repayAdapter), maxCollateralAmountToSwap);
    IParaSwapRepayAdapter.RepayParams memory repayParams = IParaSwapRepayAdapter.RepayParams({
      collateralAsset: collateralAsset,
      maxCollateralAmountToSwap: psp.srcAmount,
      debtRepayAsset: debtAsset,
      debtRepayAmount: debtRepayAmount, // debtRepayAmount will be more than route generated
      debtRepayMode: 2,
      offset: psp.offset,
      withFlashLoan: false,
      user: user,
      paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
    });
    IParaSwapRepayAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert();
    repayAdapter.repayWithCollateral(repayParams, collateralATokenPermit);
  }

  function test_revert_due_to_insufficient_amount() public {
    uint256 supplyAmount = 12_000 ether;
    uint256 borrowAmount = 9_000 ether;

    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;

    vm.startPrank(user);
    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    skip(1 hours);

    uint256 debtRepayAmount = 9000 ether;
    uint256 maxCollateralAmountToSwap = 9500 ether;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      debtAsset,
      debtRepayAmount,
      user,
      false,
      true
    );

    IERC20Detailed(collateralAssetAToken).approve(address(repayAdapter), maxCollateralAmountToSwap);
    IParaSwapRepayAdapter.RepayParams memory repayParams = IParaSwapRepayAdapter.RepayParams({
      collateralAsset: collateralAsset,
      maxCollateralAmountToSwap: psp.srcAmount,
      debtRepayAsset: debtAsset,
      debtRepayAmount: debtRepayAmount,
      debtRepayMode: 2,
      offset: psp.offset,
      withFlashLoan: false,
      user: user,
      paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
    });
    IParaSwapRepayAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes('INSUFFICIENT_AMOUNT_TO_REPAY'));
    repayAdapter.repayWithCollateral(repayParams, collateralATokenPermit);
  }

  function test_repay_full_with_flashloan_with_permit() public {
    uint256 supplyAmount = 12_000 ether;
    uint256 borrowAmount = 9_000 ether;

    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address debtAssetVToken = AaveV2EthereumAssets.LUSD_V_TOKEN;

    vm.startPrank(user);
    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    skip(1 hours);

    uint256 debtRepayAmount = 9100 ether;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      debtAsset,
      debtRepayAmount,
      user,
      false,
      true
    );

    IParaSwapRepayAdapter.RepayParams memory repayParams = IParaSwapRepayAdapter.RepayParams({
      collateralAsset: collateralAsset,
      maxCollateralAmountToSwap: psp.srcAmount + 1000, // passing extra to check whether there is no dust of collateral asset
      debtRepayAsset: debtAsset,
      debtRepayAmount: debtRepayAmount,
      debtRepayMode: 2,
      offset: psp.offset,
      withFlashLoan: true,
      user: user,
      paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
    });
    IParaSwapRepayAdapter.PermitInput memory collateralATokenPermit = _getPermit(
      collateralAssetAToken,
      address(repayAdapter),
      psp.srcAmount + 1000
    );

    uint256 debtTokenBalanceBefore = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );

    repayAdapter.repayWithCollateral(repayParams, collateralATokenPermit);

    uint256 debtTokenBalanceAfter = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    assertTrue(
      _withinRange(debtTokenBalanceBefore - debtTokenBalanceAfter, debtRepayAmount, 100 ether)
    );
    assertTrue(debtTokenBalanceAfter == 0);
    assertGt(collateralAssetATokenBalanceBefore, collateralAssetATokenBalanceAfter);
    _invariant(address(repayAdapter), collateralAsset, debtAsset);
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
