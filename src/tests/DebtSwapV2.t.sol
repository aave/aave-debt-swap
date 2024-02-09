// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {ICreditDelegationToken} from '@aave/core-v3/contracts/interfaces/ICreditDelegationToken.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {Errors} from 'aave-address-book/AaveV2.sol';
import {AaveV2Ethereum, AaveV2EthereumAssets, ILendingPool} from 'aave-address-book/AaveV2Ethereum.sol';
import {IParaSwapDebtSwapAdapter} from 'src/contracts/interfaces/IParaSwapDebtSwapAdapter.sol';
import {ParaSwapDebtSwapAdapter} from 'src/contracts/base/ParaSwapDebtSwapAdapter.sol';
import {ParaSwapDebtSwapAdapterV2} from 'src/contracts/ParaSwapDebtSwapAdapterV2.sol';
import {IParaSwapAugustusRegistry} from 'src/contracts/dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {AugustusRegistry} from 'src/contracts/dependencies/paraswap/AugustusRegistry.sol';
import {BaseTest} from './utils/BaseTest.sol';

contract DebtSwapV2Test is BaseTest {
  ParaSwapDebtSwapAdapterV2 internal debtSwapAdapter;

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'), 17706839);

    debtSwapAdapter = new ParaSwapDebtSwapAdapterV2(
      IPoolAddressesProvider(address(AaveV2Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV2Ethereum.POOL),
      IParaSwapAugustusRegistry(AugustusRegistry.ETHEREUM),
      AaveGovernanceV2.SHORT_EXECUTOR
    );
  }

  function test_revert_executeOperation_not_pool() public {
    address[] memory mockAddresses = new address[](0);
    uint256[] memory mockAmounts = new uint256[](0);

    vm.expectRevert(bytes('CALLER_MUST_BE_POOL'));
    debtSwapAdapter.executeOperation(
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
    debtSwapAdapter.executeOperation(
      mockAddresses,
      mockAmounts,
      mockAmounts,
      address(0),
      abi.encode('')
    );
  }

  function test_revert_debtSwap_without_extra_collateral() public {
    address aToken = AaveV2EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newDebtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address newDebtToken = AaveV2EthereumAssets.LUSD_V_TOKEN;

    uint256 supplyAmount = 120e18;
    uint256 borrowAmount = 80e18;

    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;

    // Deal some debtAsset to cover the premium and any 1 wei rounding errors on withdrawal.
    deal(debtAsset, address(debtSwapAdapter), 1e18);

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    _withdraw(AaveV2Ethereum.POOL, withdrawAmount, debtAsset);

    vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV2Ethereum.POOL, 1, debtAsset);

    // Swap debt
    // add some margin to account for accumulated debt
    uint256 repayAmount = (borrowAmount * 101) / 100;
    PsPResponse memory psp = _fetchPSPRoute(
      newDebtAsset,
      debtAsset,
      repayAmount,
      user,
      false,
      true
    );

    skip(1 hours);

    ICreditDelegationToken(newDebtToken).approveDelegation(address(debtSwapAdapter), psp.srcAmount);
    IERC20Detailed(aToken).approve(address(debtSwapAdapter), supplyAmount);

    IParaSwapDebtSwapAdapter.DebtSwapParams memory debtSwapParams = IParaSwapDebtSwapAdapter
      .DebtSwapParams({
        debtAsset: debtAsset,
        debtRepayAmount: type(uint256).max,
        debtRateMode: 2,
        newDebtAsset: newDebtAsset,
        maxNewDebtAmount: psp.srcAmount,
        extraCollateralAsset: address(0),
        extraCollateralAmount: 0,
        offset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapDebtSwapAdapter.CreditDelegationInput memory cd;
    IParaSwapDebtSwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
    debtSwapAdapter.swapDebt(debtSwapParams, cd, collateralATokenPermit);
  }

  /**
   * 1. supply 200000 DAI
   * 2. borrow 1000 DAI
   * 3. swap whole DAI debt to LUSD debt
   */
  function test_debtSwap_swapHalf() public {
    vm.startPrank(user);
    address debtAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address debtToken = AaveV2EthereumAssets.DAI_V_TOKEN;
    address newDebtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address newDebtToken = AaveV2EthereumAssets.LUSD_V_TOKEN;

    uint256 supplyAmount = 200000 ether;
    uint256 borrowAmount = 1000 ether;

    _supply(AaveV2Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    uint256 repayAmount = borrowAmount / 2;
    PsPResponse memory psp = _fetchPSPRoute(
      newDebtAsset,
      debtAsset,
      repayAmount,
      user,
      false,
      false
    );

    ICreditDelegationToken(newDebtToken).approveDelegation(address(debtSwapAdapter), psp.srcAmount);

    IParaSwapDebtSwapAdapter.DebtSwapParams memory debtSwapParams = IParaSwapDebtSwapAdapter
      .DebtSwapParams({
        debtAsset: debtAsset,
        debtRepayAmount: repayAmount,
        debtRateMode: 2,
        newDebtAsset: newDebtAsset,
        maxNewDebtAmount: psp.srcAmount,
        extraCollateralAsset: address(0),
        extraCollateralAmount: 0,
        offset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    uint256 vDEBT_TOKENBalanceBefore = IERC20Detailed(debtToken).balanceOf(user);

    IParaSwapDebtSwapAdapter.CreditDelegationInput memory cd;
    IParaSwapDebtSwapAdapter.PermitInput memory collateralATokenPermit;

    debtSwapAdapter.swapDebt(debtSwapParams, cd, collateralATokenPermit);

    uint256 vDEBT_TOKENBalanceAfter = IERC20Detailed(debtToken).balanceOf(user);
    uint256 vNEWDEBT_TOKENBalanceAfter = IERC20Detailed(newDebtToken).balanceOf(user);
    assertEq(vDEBT_TOKENBalanceAfter, vDEBT_TOKENBalanceBefore - repayAmount);
    assertLe(vNEWDEBT_TOKENBalanceAfter, psp.srcAmount);
    _invariant(address(debtSwapAdapter), debtAsset, newDebtAsset);
  }

  function test_debtSwap_swapAll() public {
    vm.startPrank(user);
    address debtAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address debtToken = AaveV2EthereumAssets.DAI_V_TOKEN;
    address newDebtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address newDebtToken = AaveV2EthereumAssets.LUSD_V_TOKEN;

    uint256 supplyAmount = 200000 ether;
    uint256 borrowAmount = 1000 ether;

    _supply(AaveV2Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    // add some margin to account for accumulated debt
    uint256 repayAmount = (borrowAmount * 101) / 100;
    PsPResponse memory psp = _fetchPSPRoute(
      newDebtAsset,
      debtAsset,
      repayAmount,
      user,
      false,
      true
    );

    skip(1 hours);

    ICreditDelegationToken(newDebtToken).approveDelegation(address(debtSwapAdapter), psp.srcAmount);

    IParaSwapDebtSwapAdapter.DebtSwapParams memory debtSwapParams = IParaSwapDebtSwapAdapter
      .DebtSwapParams({
        debtAsset: debtAsset,
        debtRepayAmount: type(uint256).max,
        debtRateMode: 2,
        newDebtAsset: newDebtAsset,
        maxNewDebtAmount: psp.srcAmount,
        extraCollateralAsset: address(0),
        extraCollateralAmount: 0,
        offset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapDebtSwapAdapter.CreditDelegationInput memory cd;
    IParaSwapDebtSwapAdapter.PermitInput memory collateralATokenPermit;

    debtSwapAdapter.swapDebt(debtSwapParams, cd, collateralATokenPermit);

    uint256 vDEBT_TOKENBalanceAfter = IERC20Detailed(debtToken).balanceOf(user);
    uint256 vNEWDEBT_TOKENBalanceAfter = IERC20Detailed(newDebtToken).balanceOf(user);
    assertEq(vDEBT_TOKENBalanceAfter, 0);
    assertLe(vNEWDEBT_TOKENBalanceAfter, psp.srcAmount);
    _invariant(address(debtSwapAdapter), debtAsset, newDebtAsset);
  }

  function test_debtSwap_swapAll_BUSD() public {
    address vBUSD_WHALE = 0x154AF3A2071363D3fFcDB43744C2a906d8EB856a;
    vm.startPrank(vBUSD_WHALE); // vBUSD Whale
    address debtAsset = AaveV2EthereumAssets.BUSD_UNDERLYING;
    address debtToken = AaveV2EthereumAssets.BUSD_V_TOKEN;
    address newDebtAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newDebtToken = AaveV2EthereumAssets.DAI_V_TOKEN;

    uint256 borrowAmount = IERC20Detailed(debtToken).balanceOf(vBUSD_WHALE);

    // add some margin to account for accumulated debt
    uint256 repayAmount = (borrowAmount * 101) / 100;
    PsPResponse memory psp = _fetchPSPRoute(
      newDebtAsset,
      debtAsset,
      repayAmount,
      vBUSD_WHALE,
      false,
      true
    );

    skip(1 minutes);

    ICreditDelegationToken(newDebtToken).approveDelegation(address(debtSwapAdapter), psp.srcAmount);

    IParaSwapDebtSwapAdapter.DebtSwapParams memory debtSwapParams = IParaSwapDebtSwapAdapter
      .DebtSwapParams({
        debtAsset: debtAsset,
        debtRepayAmount: type(uint256).max,
        debtRateMode: 2,
        newDebtAsset: newDebtAsset,
        maxNewDebtAmount: psp.srcAmount,
        extraCollateralAsset: address(0),
        extraCollateralAmount: 0,
        offset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapDebtSwapAdapter.CreditDelegationInput memory cd;
    IParaSwapDebtSwapAdapter.PermitInput memory collateralATokenPermit;

    debtSwapAdapter.swapDebt(debtSwapParams, cd, collateralATokenPermit);

    uint256 vDEBT_TOKENBalanceAfter = IERC20Detailed(debtToken).balanceOf(vBUSD_WHALE);
    uint256 vNEWDEBT_TOKENBalanceAfter = IERC20Detailed(newDebtToken).balanceOf(vBUSD_WHALE);
    assertEq(vDEBT_TOKENBalanceAfter, 0);
    assertLe(vNEWDEBT_TOKENBalanceAfter, psp.srcAmount);
    _invariant(address(debtSwapAdapter), debtAsset, newDebtAsset);
  }

  function test_debtSwap_extra_Collateral() public {
    address debtAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newDebtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address newDebtToken = AaveV2EthereumAssets.LUSD_V_TOKEN;
    address extraCollateralAsset = debtAsset;
    address extraCollateralAToken = AaveV2EthereumAssets.DAI_A_TOKEN;

    uint256 supplyAmount = 120e18;
    uint256 borrowAmount = 80e18;
    uint256 extraCollateralAmount = 1000e18;

    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;

    // Deal some debtAsset to cover the premium and any 1 wei rounding errors on withdrawal.
    deal(debtAsset, address(debtSwapAdapter), 1e18);

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    _withdraw(AaveV2Ethereum.POOL, withdrawAmount, debtAsset);

    vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV2Ethereum.POOL, 1, debtAsset);

    // Swap debt
    // add some margin to account for accumulated debt
    uint256 repayAmount = (borrowAmount * 101) / 100;
    PsPResponse memory psp = _fetchPSPRoute(
      newDebtAsset,
      debtAsset,
      repayAmount,
      user,
      false,
      true
    );

    skip(1 hours);

    ICreditDelegationToken(newDebtToken).approveDelegation(address(debtSwapAdapter), psp.srcAmount);
    IERC20Detailed(extraCollateralAToken).approve(
      address(debtSwapAdapter),
      extraCollateralAmount + 1
    );

    IParaSwapDebtSwapAdapter.DebtSwapParams memory debtSwapParams = IParaSwapDebtSwapAdapter
      .DebtSwapParams({
        debtAsset: debtAsset,
        debtRepayAmount: type(uint256).max,
        debtRateMode: 2,
        newDebtAsset: newDebtAsset,
        maxNewDebtAmount: psp.srcAmount,
        extraCollateralAsset: extraCollateralAsset,
        extraCollateralAmount: extraCollateralAmount,
        offset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapDebtSwapAdapter.CreditDelegationInput memory cd;
    IParaSwapDebtSwapAdapter.PermitInput memory collateralATokenPermit;

    debtSwapAdapter.swapDebt(debtSwapParams, cd, collateralATokenPermit);
  }

  function test_debtSwap_extra_Collateral_permit() public {
    address debtAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newDebtAsset = AaveV2EthereumAssets.LUSD_UNDERLYING;
    address newDebtToken = AaveV2EthereumAssets.LUSD_V_TOKEN;
    address extraCollateralAsset = debtAsset;
    address extraCollateralAToken = AaveV2EthereumAssets.DAI_A_TOKEN;

    uint256 supplyAmount = 120e18;
    uint256 borrowAmount = 80e18;
    uint256 extraCollateralAmount = 1000e18;

    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;

    // Deal some debtAsset to cover the premium and any 1 wei rounding errors on withdrawal.
    deal(debtAsset, address(debtSwapAdapter), 1e18);

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    _withdraw(AaveV2Ethereum.POOL, withdrawAmount, debtAsset);

    vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV2Ethereum.POOL, 1, debtAsset);

    // Swap debt
    // add some margin to account for accumulated debt
    uint256 repayAmount = (borrowAmount * 101) / 100;
    PsPResponse memory psp = _fetchPSPRoute(
      newDebtAsset,
      debtAsset,
      repayAmount,
      user,
      false,
      true
    );

    skip(1 hours);

    ICreditDelegationToken(newDebtToken).approveDelegation(address(debtSwapAdapter), psp.srcAmount);

    IParaSwapDebtSwapAdapter.DebtSwapParams memory debtSwapParams = IParaSwapDebtSwapAdapter
      .DebtSwapParams({
        debtAsset: debtAsset,
        debtRepayAmount: type(uint256).max,
        debtRateMode: 2,
        newDebtAsset: newDebtAsset,
        maxNewDebtAmount: psp.srcAmount,
        extraCollateralAsset: extraCollateralAsset,
        extraCollateralAmount: extraCollateralAmount,
        offset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapDebtSwapAdapter.CreditDelegationInput memory cd;
    IParaSwapDebtSwapAdapter.PermitInput memory collateralATokenPermit = _getPermit(
      extraCollateralAToken,
      address(debtSwapAdapter),
      extraCollateralAmount + 1
    );

    debtSwapAdapter.swapDebt(debtSwapParams, cd, collateralATokenPermit);
  }

  function test_debtSwap_extra_Collateral_same_as_new_debt() public {
    // We'll use the debtAsset & supplyAmount as extra collateral too.
    address debtAsset = AaveV2EthereumAssets.DAI_UNDERLYING;
    address newDebtAsset = AaveV2EthereumAssets.USDC_UNDERLYING;
    address newDebtToken = AaveV2EthereumAssets.USDC_V_TOKEN;
    address extraCollateralAsset = newDebtAsset;
    address extraCollateralAToken = AaveV2EthereumAssets.USDC_A_TOKEN;

    uint256 supplyAmount = 120e18;
    uint256 borrowAmount = 80e18;
    uint256 extraCollateralAmount = 1000e6;

    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;

    // Deal some debtAsset to cover the premium and any 1 wei rounding errors on withdrawal.
    deal(debtAsset, address(debtSwapAdapter), 1e18);

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, debtAsset);

    _withdraw(AaveV2Ethereum.POOL, withdrawAmount, debtAsset);

    vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV2Ethereum.POOL, 1, debtAsset);

    // Swap debt
    // add some margin to account for accumulated debt
    uint256 repayAmount = (borrowAmount * 101) / 100;
    PsPResponse memory psp = _fetchPSPRoute(
      newDebtAsset,
      debtAsset,
      repayAmount,
      user,
      false,
      true
    );

    skip(1 hours);

    ICreditDelegationToken(newDebtToken).approveDelegation(address(debtSwapAdapter), psp.srcAmount);
    IERC20Detailed(extraCollateralAToken).approve(
      address(debtSwapAdapter),
      extraCollateralAmount + 1
    );

    IParaSwapDebtSwapAdapter.DebtSwapParams memory debtSwapParams = IParaSwapDebtSwapAdapter
      .DebtSwapParams({
        debtAsset: debtAsset,
        debtRepayAmount: type(uint256).max,
        debtRateMode: 2,
        newDebtAsset: newDebtAsset,
        maxNewDebtAmount: psp.srcAmount,
        extraCollateralAsset: extraCollateralAsset,
        extraCollateralAmount: extraCollateralAmount,
        offset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapDebtSwapAdapter.CreditDelegationInput memory cd;
    IParaSwapDebtSwapAdapter.PermitInput memory collateralATokenPermit;

    debtSwapAdapter.swapDebt(debtSwapParams, cd, collateralATokenPermit);
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
