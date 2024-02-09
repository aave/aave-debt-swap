// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IERC20WithPermit} from 'solidity-utils/contracts/oz-common/interfaces/IERC20WithPermit.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {Errors} from '@aave/core-v3/contracts/protocol/libraries/helpers/Errors.sol';
import {ICreditDelegationToken} from '@aave/core-v3/contracts/interfaces/ICreditDelegationToken.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets, IPool} from 'aave-address-book/AaveV3Ethereum.sol';
import {IParaSwapDebtSwapAdapter} from 'src/contracts/interfaces/IParaSwapDebtSwapAdapter.sol';
import {ParaSwapDebtSwapAdapter} from 'src/contracts/base/ParaSwapDebtSwapAdapter.sol';
import {ParaSwapDebtSwapAdapterV3} from 'src/contracts/ParaSwapDebtSwapAdapterV3.sol';
import {IParaSwapAugustusRegistry} from 'src/contracts/dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {AugustusRegistry} from 'src/contracts/dependencies/paraswap/AugustusRegistry.sol';
import {BaseTest} from './utils/BaseTest.sol';
import {SigUtils} from './utils/SigUtils.sol';

contract DebtSwapV3Test is BaseTest {
  ParaSwapDebtSwapAdapterV3 internal debtSwapAdapter;

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'), 17786869);

    debtSwapAdapter = new ParaSwapDebtSwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Ethereum.POOL),
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
    vm.prank(address(AaveV3Ethereum.POOL));
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
    address aToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newDebtAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newDebtToken = AaveV3EthereumAssets.LUSD_V_TOKEN;

    uint256 supplyAmount = 120e18;
    uint256 borrowAmount = 80e18;

    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;

    // Deal some debtAsset to cover the premium and any 1 wei rounding errors on withdrawal.
    deal(debtAsset, address(debtSwapAdapter), 1e18);

    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, debtAsset);

    _withdraw(AaveV3Ethereum.POOL, withdrawAmount, debtAsset);

    vm.expectRevert(bytes(Errors.COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV3Ethereum.POOL, 1, debtAsset);

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

    vm.expectRevert(bytes(Errors.COLLATERAL_CANNOT_COVER_NEW_BORROW));
    debtSwapAdapter.swapDebt(debtSwapParams, cd, collateralATokenPermit);
  }

  /**
   * 1. supply 200000 DAI
   * 2. borrow 100 DAI
   * 3. swap whole DAI debt to LUSD debt
   */
  function test_debtSwap_swapHalf() public {
    vm.startPrank(user);
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address debtToken = AaveV3EthereumAssets.DAI_V_TOKEN;
    address newDebtAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newDebtToken = AaveV3EthereumAssets.LUSD_V_TOKEN;

    uint256 supplyAmount = 200000 ether;
    uint256 borrowAmount = 1000 ether;

    _supply(AaveV3Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, debtAsset);

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
    assertApproxEqAbs(vDEBT_TOKENBalanceAfter, vDEBT_TOKENBalanceBefore - repayAmount, 1);
    assertLe(vNEWDEBT_TOKENBalanceAfter, psp.srcAmount);
    _invariant(address(debtSwapAdapter), debtAsset, newDebtAsset);
  }

  function test_debtSwap_swapAll() public {
    vm.startPrank(user);
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address debtToken = AaveV3EthereumAssets.DAI_V_TOKEN;
    address newDebtAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newDebtToken = AaveV3EthereumAssets.LUSD_V_TOKEN;

    uint256 supplyAmount = 200000 ether;
    uint256 borrowAmount = 1000 ether;

    _supply(AaveV3Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, debtAsset);

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

  function test_debtSwap_swapAll_lacking_allowance() public {
    vm.startPrank(user);
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address debtToken = AaveV3EthereumAssets.DAI_V_TOKEN;
    address newDebtAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newDebtToken = AaveV3EthereumAssets.LUSD_V_TOKEN;

    uint256 supplyAmount = 200000 ether;
    uint256 borrowAmount = 1000 ether;

    {
      // Pre
      assertEq(
        IERC20WithPermit(debtAsset).allowance(
          address(debtSwapAdapter),
          address(AaveV3Ethereum.POOL)
        ),
        type(uint256).max
      );

      vm.record();
      IERC20WithPermit(debtAsset).allowance(address(debtSwapAdapter), address(AaveV3Ethereum.POOL));
      (bytes32[] memory reads, ) = vm.accesses(AaveV3EthereumAssets.DAI_UNDERLYING);
      vm.store(address(debtAsset), reads[0], 0);

      // Post
      assertEq(
        IERC20WithPermit(debtAsset).allowance(
          address(debtSwapAdapter),
          address(AaveV3Ethereum.POOL)
        ),
        0
      );
    }

    _supply(AaveV3Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, debtAsset);

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

  function test_debtSwap_swapAll_permit() public {
    vm.startPrank(user);
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address debtToken = AaveV3EthereumAssets.DAI_V_TOKEN;
    address newDebtAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newDebtToken = AaveV3EthereumAssets.LUSD_V_TOKEN;

    uint256 supplyAmount = 200000 ether;
    uint256 borrowAmount = 1000 ether;

    _supply(AaveV3Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, debtAsset);

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

    IParaSwapDebtSwapAdapter.CreditDelegationInput memory cd = _getCDPermit(
      psp.srcAmount,
      newDebtToken
    );
    IParaSwapDebtSwapAdapter.PermitInput memory collateralATokenPermit;

    debtSwapAdapter.swapDebt(debtSwapParams, cd, collateralATokenPermit);

    uint256 vDEBT_TOKENBalanceAfter = IERC20Detailed(debtToken).balanceOf(user);
    uint256 vNEWDEBT_TOKENBalanceAfter = IERC20Detailed(newDebtToken).balanceOf(user);
    assertEq(vDEBT_TOKENBalanceAfter, 0);
    assertLe(vNEWDEBT_TOKENBalanceAfter, psp.srcAmount);
    _invariant(address(debtSwapAdapter), debtAsset, newDebtAsset);
  }

  function test_debtSwap_extra_Collateral() public {
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newDebtAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newDebtToken = AaveV3EthereumAssets.LUSD_V_TOKEN;
    address extraCollateralAsset = debtAsset;
    address extraCollateralAToken = AaveV3EthereumAssets.DAI_A_TOKEN;

    uint256 supplyAmount = 120e18;
    uint256 borrowAmount = 80e18;
    uint256 extraCollateralAmount = 1000e18;

    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;

    // Deal some debtAsset to cover the premium and any 1 wei rounding errors on withdrawal.
    deal(debtAsset, address(debtSwapAdapter), 1e18);

    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, debtAsset);

    _withdraw(AaveV3Ethereum.POOL, withdrawAmount, debtAsset);

    vm.expectRevert(bytes(Errors.COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV3Ethereum.POOL, 1, debtAsset);

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
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newDebtAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newDebtToken = AaveV3EthereumAssets.LUSD_V_TOKEN;
    address extraCollateralAsset = debtAsset;
    address extraCollateralAToken = AaveV3EthereumAssets.DAI_A_TOKEN;

    uint256 supplyAmount = 120e18;
    uint256 borrowAmount = 80e18;
    uint256 extraCollateralAmount = 1000e18;

    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;

    // Deal some debtAsset to cover the premium and any 1 wei rounding errors on withdrawal.
    deal(debtAsset, address(debtSwapAdapter), 1e18);

    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, debtAsset);

    _withdraw(AaveV3Ethereum.POOL, withdrawAmount, debtAsset);

    vm.expectRevert(bytes(Errors.COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV3Ethereum.POOL, 1, debtAsset);

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
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newDebtAsset = AaveV3EthereumAssets.USDC_UNDERLYING;
    address newDebtToken = AaveV3EthereumAssets.USDC_V_TOKEN;
    address extraCollateralAsset = newDebtAsset;
    address extraCollateralAToken = AaveV3EthereumAssets.USDC_A_TOKEN;

    uint256 supplyAmount = 120e18;
    uint256 borrowAmount = 80e18;
    uint256 extraCollateralAmount = 1000e6;

    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;

    // Deal some debtAsset to cover the premium and any 1 wei rounding errors on withdrawal.
    deal(debtAsset, address(debtSwapAdapter), 1e18);

    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, supplyAmount, debtAsset);
    _borrow(AaveV3Ethereum.POOL, borrowAmount, debtAsset);

    _withdraw(AaveV3Ethereum.POOL, withdrawAmount, debtAsset);

    vm.expectRevert(bytes(Errors.COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV3Ethereum.POOL, 1, debtAsset);

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

  function _getCDPermit(
    uint256 amount,
    address debtToken
  ) internal view returns (IParaSwapDebtSwapAdapter.CreditDelegationInput memory) {
    IERC20WithPermit token = IERC20WithPermit(debtToken);
    SigUtils.CreditDelegation memory creditDelegation = SigUtils.CreditDelegation({
      delegatee: address(debtSwapAdapter),
      value: amount,
      nonce: token.nonces(user),
      deadline: type(uint256).max
    });

    bytes32 digest = SigUtils.getCreditDelegationTypedDataHash(
      creditDelegation,
      token.DOMAIN_SEPARATOR()
    );

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

    return
      IParaSwapDebtSwapAdapter.CreditDelegationInput({
        debtToken: ICreditDelegationToken(address(token)),
        value: amount,
        deadline: type(uint256).max,
        v: v,
        r: r,
        s: s
      });
  }

  function _supply(IPool pool, uint256 amount, address asset) internal {
    deal(asset, user, amount);
    IERC20Detailed(asset).approve(address(pool), amount);
    pool.supply(asset, amount, user, 0);
  }

  function _borrow(IPool pool, uint256 amount, address asset) internal {
    pool.borrow(asset, amount, 2, 0, user);
  }

  function _withdraw(IPool pool, uint256 amount, address asset) internal {
    pool.withdraw(asset, amount, user);
  }
}
