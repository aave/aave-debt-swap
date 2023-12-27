// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IACLManager} from '@aave/core-v3/contracts/interfaces/IACLManager.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {Errors} from 'aave-address-book/AaveV2.sol';
import {AaveV2Ethereum, AaveV2EthereumAssets, ILendingPool} from 'aave-address-book/AaveV2Ethereum.sol';
import {AaveV3Ethereum} from 'aave-address-book/AaveV3Ethereum.sol';
import {BaseTest} from './utils/BaseTest.sol';
import {ParaSwapRepayAdapterV2} from '../src/contracts/ParaSwapRepayAdapterV2.sol';
import {AugustusRegistry} from '../src/lib/AugustusRegistry.sol';
import {BaseParaSwapAdapter} from '../src/contracts/BaseParaSwapAdapter.sol';
import {IParaSwapRepayAdapter} from '../src/interfaces/IParaSwapRepayAdapter.sol';
import {IBaseParaSwapAdapter} from '../src/interfaces/IBaseParaSwapAdapter.sol';
import {stdMath} from 'forge-std/StdMath.sol';
import "forge-std/Test.sol";

contract RepayAdapterV2 is BaseTest {
  ParaSwapRepayAdapterV2 internal repayAdapter;

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'), 18683100);

    repayAdapter = new ParaSwapRepayAdapterV2(
      IPoolAddressesProvider(address(AaveV2Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV2Ethereum.POOL),
      AugustusRegistry.ETHEREUM,
      AaveGovernanceV2.SHORT_EXECUTOR
    );
    vm.startPrank(0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A); //ACL admin
    IACLManager(address(AaveV3Ethereum.ACL_MANAGER)).addFlashBorrower(address(repayAdapter));
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
    vm.prank(address(AaveV3Ethereum.POOL));
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

  function test_repay_without_extra_collateral() public {
    uint256 supplyAmount = 120e18;
    uint256 borrowAmount = 80e18;
    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address debtAssetVToken = AaveV2EthereumAssets.LUSD_V_TOKEN;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV2Ethereum.POOL, 25e18, debtAsset);

    uint256 maxCollateralAmountToSwap = 25e18;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      debtAsset,
      maxCollateralAmountToSwap,
      user,
      true,
      false
    );

    skip(1 hours);

    IERC20Detailed(collateralAssetAToken).approve(
      address(repayAdapter),
      maxCollateralAmountToSwap
    );
    uint256 debtRepayAmount = 22e18;
    IParaSwapRepayAdapter.RepayParams
      memory repayParams = IParaSwapRepayAdapter.RepayParams({
        collateralAsset: collateralAsset,
        maxCollateralAmountToSwap: maxCollateralAmountToSwap,
        debtRepayAsset: debtAsset,
        debtRepayAmount: debtRepayAmount,
        debtRepayMode: 2,
        offset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapRepayAdapter.FlashParams memory flashParams;
    IParaSwapRepayAdapter.PermitInput memory collateralATokenPermit;

    uint256 debtTokenBalanceBefore = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    repayAdapter.repayWithCollateral(repayParams, flashParams, collateralATokenPermit);
    uint256 debtTokenBalanceAfter = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    assertTrue(
      _withinRange(
        debtTokenBalanceBefore - debtTokenBalanceAfter,
        debtRepayAmount,
        2
      )
    );
    assertLt(collateralAssetATokenBalanceAfter, collateralAssetATokenBalanceBefore);
    _invariant(address(repayAdapter), collateralAsset, debtAsset);
    _invariant(address(repayAdapter), collateralAssetAToken, debtAssetVToken);
  }

  function test_repay_permit_without_extra_collateral() public {
    uint256 supplyAmount = 120e18;
    uint256 borrowAmount = 80e18;
    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address debtAssetVToken = AaveV2EthereumAssets.LUSD_V_TOKEN;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV2Ethereum.POOL, 25e18, debtAsset);

    uint256 maxCollateralAmountToSwap = 25e18;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      debtAsset,
      maxCollateralAmountToSwap,
      user,
      true,
      false
    );

    skip(1 hours);

    uint256 debtRepayAmount = 22e18;
    IParaSwapRepayAdapter.RepayParams
      memory repayParams = IParaSwapRepayAdapter.RepayParams({
        collateralAsset: collateralAsset,
        maxCollateralAmountToSwap: maxCollateralAmountToSwap,
        debtRepayAsset: debtAsset,
        debtRepayAmount: debtRepayAmount,
        debtRepayMode: 2,
        offset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapRepayAdapter.FlashParams memory flashParams;
    IParaSwapRepayAdapter.PermitInput memory collateralATokenPermit =  _getPermit(
      collateralAssetAToken,
      address(repayAdapter),
      maxCollateralAmountToSwap
    );

    uint256 debtTokenBalanceBefore = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    repayAdapter.repayWithCollateral(repayParams, flashParams, collateralATokenPermit);
    uint256 debtTokenBalanceAfter = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    assertTrue(
      _withinRange(
        debtTokenBalanceBefore - debtTokenBalanceAfter,
        debtRepayAmount,
        2
      )
    );
    assertLt(collateralAssetATokenBalanceAfter, collateralAssetATokenBalanceBefore);
    _invariant(address(repayAdapter), collateralAsset, debtAsset);
    _invariant(address(repayAdapter), collateralAssetAToken, debtAssetVToken);
  }

  function test_repay_full_without_extra_token() public {
    uint256 daiSupplyAmount = 12000e18;
    uint256 usdcBorrowAmount = 1000e6;
    
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.USDC_UNDERLYING;
    address debtAssetVToken = AaveV2EthereumAssets.USDC_V_TOKEN;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, daiSupplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, usdcBorrowAmount, debtAsset);

    uint256 maxCollateralAmountToSwap = 1050e18;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      debtAsset,
      maxCollateralAmountToSwap,
      user,
      true,
      false //todo true not working here
    );

    IERC20Detailed(collateralAssetAToken).approve(
      address(repayAdapter),
      maxCollateralAmountToSwap
    );
    console.log(psp.offset);
    uint256 debtRepayAmount = usdcBorrowAmount;
    IParaSwapRepayAdapter.RepayParams
      memory repayParams = IParaSwapRepayAdapter.RepayParams({
        collateralAsset: collateralAsset,
        maxCollateralAmountToSwap: maxCollateralAmountToSwap,
        debtRepayAsset: debtAsset,
        debtRepayAmount: debtRepayAmount,
        debtRepayMode: 2,
        offset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapRepayAdapter.FlashParams memory flashParams;
    IParaSwapRepayAdapter.PermitInput memory collateralATokenPermit;

    uint256 debtTokenBalanceBefore = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    repayAdapter.repayWithCollateral(repayParams, flashParams, collateralATokenPermit);
    uint256 debtTokenBalanceAfter = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    assertTrue(
      _withinRange(
        debtTokenBalanceBefore - debtTokenBalanceAfter,
        debtRepayAmount,
        2
      )
    );
    assertTrue(debtTokenBalanceAfter == 0);
    assertLt(collateralAssetATokenBalanceAfter, collateralAssetATokenBalanceBefore);
    _invariant(address(repayAdapter), collateralAsset, debtAsset);
    _invariant(address(repayAdapter), collateralAssetAToken, debtAssetVToken);
  }

  function test_repay_with_extra_collateral() public {
    uint256 daiSupplyAmount = 1500e18;
    uint256 usdcBorrowAmount = 1000e6;
    uint256 maxCollateralAmountToSwap = 1050e18;
    
    address collateralAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.USDC_UNDERLYING;
    address debtAssetVToken = AaveV2EthereumAssets.USDC_V_TOKEN;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, daiSupplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, usdcBorrowAmount, debtAsset);

    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      debtAsset,
      maxCollateralAmountToSwap,
      user,
      true,
      false
    );

    IERC20Detailed(collateralAssetAToken).approve(
      address(repayAdapter),
      maxCollateralAmountToSwap
    );
    uint256 debtRepayAmount = usdcBorrowAmount;
    IParaSwapRepayAdapter.RepayParams
      memory repayParams = IParaSwapRepayAdapter.RepayParams({
        collateralAsset: collateralAsset,
        maxCollateralAmountToSwap: maxCollateralAmountToSwap,
        debtRepayAsset: debtAsset,
        debtRepayAmount: debtRepayAmount,
        debtRepayMode: 2,
        offset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });
    address flashLoanAsset = AaveV2EthereumAssets.USDC_UNDERLYING;
    address flashLoanAssetAToken = AaveV2EthereumAssets.USDC_A_TOKEN;
    uint256 flashLoanAmount = 5000e6;
    IERC20Detailed(flashLoanAssetAToken).approve(
      address(repayAdapter),
      flashLoanAmount
    );
    IParaSwapRepayAdapter.PermitInput memory collateralATokenPermit;
    IParaSwapRepayAdapter.FlashParams memory flashParams = IParaSwapRepayAdapter.FlashParams({
      v3Pool: address(AaveV3Ethereum.POOL),
      flashLoanAsset: flashLoanAsset,
      flashLoanAmount: flashLoanAmount,
      user: user,
      flashLoanAssetPermit: collateralATokenPermit
    });

    uint256 debtTokenBalanceBefore = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    repayAdapter.repayWithCollateral(repayParams, flashParams, collateralATokenPermit);
    uint256 debtTokenBalanceAfter = IERC20Detailed(debtAssetVToken).balanceOf(user);
    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    assertTrue(
      _withinRange(
        debtTokenBalanceBefore - debtTokenBalanceAfter,
        debtRepayAmount,
        2
      )
    );
    assertTrue(debtTokenBalanceAfter == 0);
    assertLt(collateralAssetATokenBalanceAfter, collateralAssetATokenBalanceBefore);
    // _invariant(address(repayAdapter), collateralAsset, debtAsset);
    // _invariant(address(repayAdapter), collateralAssetAToken, debtAssetVToken);
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

  function _withinRange(uint256 a, uint256 b, uint256 diff) internal returns (bool) {
    return stdMath.delta(a, b) <= diff;
  }

}