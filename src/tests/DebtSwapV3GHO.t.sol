// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {Errors} from '@aave/core-v3/contracts/protocol/libraries/helpers/Errors.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {ICreditDelegationToken} from '@aave/core-v3/contracts/interfaces/ICreditDelegationToken.sol';
import {IERC20WithPermit} from 'solidity-utils/contracts/oz-common/interfaces/IERC20WithPermit.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets, IPool} from 'aave-address-book/AaveV3Ethereum.sol';
import {IParaSwapDebtSwapAdapter} from 'src/contracts/interfaces/IParaSwapDebtSwapAdapter.sol';
import {ParaSwapDebtSwapAdapter} from 'src/contracts/base/ParaSwapDebtSwapAdapter.sol';
import {ParaSwapDebtSwapAdapterV3GHO} from 'src/contracts/ParaSwapDebtSwapAdapterV3GHO.sol';
import {IParaSwapAugustusRegistry} from 'src/contracts/dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {AugustusRegistry} from 'src/contracts/dependencies/paraswap/AugustusRegistry.sol';
import {BaseTest} from './utils/BaseTest.sol';
import {SigUtils} from './utils/SigUtils.sol';

contract DebtSwapV3GHOTest is BaseTest {
  ParaSwapDebtSwapAdapterV3GHO internal debtSwapAdapter;

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'), 17786869);

    debtSwapAdapter = new ParaSwapDebtSwapAdapterV3GHO(
      IPoolAddressesProvider(address(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Ethereum.POOL),
      IParaSwapAugustusRegistry(AugustusRegistry.ETHEREUM),
      AaveGovernanceV2.SHORT_EXECUTOR
    );
  }

  function test_revert_Gho_debtSwap_without_extra_collateral() public {
    address aToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newDebtAsset = debtSwapAdapter.GHO();
    address newDebtToken = 0x786dBff3f1292ae8F92ea68Cf93c30b34B1ed04B; // vDebtGHO

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

  function test_revert_Gho_onFlashloan_not_minter() public {
    vm.expectRevert(bytes('SENDER_MUST_BE_MINTER'));
    debtSwapAdapter.onFlashLoan(address(0), address(0), 0, 0, '');
  }

  function test_revert_Gho_onFlashloan_not_initiator() public {
    vm.prank(0xb639D208Bcf0589D54FaC24E655C79EC529762B8);

    vm.expectRevert(bytes('INITIATOR_MUST_BE_THIS'));
    debtSwapAdapter.onFlashLoan(address(0), address(0), 0, 0, '');
  }

  function test_revert_Gho_onFlashloan_token_not_Gho() public {
    vm.prank(0xb639D208Bcf0589D54FaC24E655C79EC529762B8);

    vm.expectRevert(bytes('MUST_BE_GHO'));
    debtSwapAdapter.onFlashLoan(address(debtSwapAdapter), address(0), 0, 0, '');
  }

  /**
   * 1. supply 200000 DAI
   * 2. borrow 1000 GHO
   * 3. swap whole DAI debt to LUSD debt
   */
  function test_debtSwap_swapHalf() public {
    vm.startPrank(user);
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address debtToken = AaveV3EthereumAssets.DAI_V_TOKEN;
    address newDebtAsset = debtSwapAdapter.GHO();
    address newDebtToken = 0x786dBff3f1292ae8F92ea68Cf93c30b34B1ed04B;

    uint256 supplyAmount = 200000 ether;
    uint256 borrowAmount = 2000 ether;

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

  function testDebtSwapGho() public {
    vm.startPrank(user);
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address debtToken = AaveV3EthereumAssets.DAI_V_TOKEN;
    address newDebtAsset = debtSwapAdapter.GHO();
    address newDebtToken = 0x786dBff3f1292ae8F92ea68Cf93c30b34B1ed04B;

    uint256 supplyAmount = 200000 ether;
    uint256 borrowAmount = 2000 ether;

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

  function test_Gho_debtSwap_extra_collateral() public {
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newDebtAsset = debtSwapAdapter.GHO();
    address newDebtToken = 0x786dBff3f1292ae8F92ea68Cf93c30b34B1ed04B;
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
    IERC20Detailed(extraCollateralAToken).approve(address(debtSwapAdapter), extraCollateralAmount);

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

  function test_Gho_debtSwap_extra_collateral_permit() public {
    address debtAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newDebtAsset = debtSwapAdapter.GHO();
    address newDebtToken = 0x786dBff3f1292ae8F92ea68Cf93c30b34B1ed04B;
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
