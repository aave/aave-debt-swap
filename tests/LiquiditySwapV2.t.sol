// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {Errors} from 'aave-address-book/AaveV2.sol';
import {AaveV2Ethereum, AaveV2EthereumAssets, ILendingPool} from 'aave-address-book/AaveV2Ethereum.sol';
import {BaseTest} from './utils/BaseTest.sol';
import {ParaSwapLiquiditySwapAdapterV2} from '../src/contracts/ParaSwapLiquiditySwapAdapterV2.sol';
import {AugustusRegistry} from '../src/lib/AugustusRegistry.sol';
import {BaseParaSwapAdapter} from '../src/contracts/BaseParaSwapAdapter.sol';
import '../src/interfaces/IParaSwapLiquiditySwapAdapter.sol';
import {IBaseParaSwapAdapter} from '../src/interfaces/IBaseParaSwapAdapter.sol';
import {stdMath} from 'forge-std/stdMath.sol';

contract LiquiditySwapAdapterV2 is BaseTest {
  ParaSwapLiquiditySwapAdapterV2 internal liquiditySwapAdapter;

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'), 17706839);

    liquiditySwapAdapter = new ParaSwapLiquiditySwapAdapterV2(
      IPoolAddressesProvider(address(AaveV2Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV2Ethereum.POOL),
      AugustusRegistry.ETHEREUM,
      AaveGovernanceV2.SHORT_EXECUTOR
    );
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

    //  address collateralAsset;
    // uint256 collateralAmountToSwap;
    // address newCollateralAsset;
    // uint256 minNewCollateralAmount;
    // uint256 offset;
    // bytes paraswapData;

    uint256 supplyAmount = 120e18;
    uint256 borrowAmount = 80e18;

    // We want to end with LT > utilisation > LTV, so we pump up the utilisation to 75% by withdrawing (80 > 75 > 67).
    uint256 withdrawAmount = supplyAmount - (borrowAmount * 100) / 75;

    vm.startPrank(user);

    _supply(AaveV2Ethereum.POOL, supplyAmount, collateralAsset);
    _borrow(AaveV2Ethereum.POOL, borrowAmount, collateralAsset);

    _withdraw(AaveV2Ethereum.POOL, withdrawAmount, collateralAsset);

    vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
    _borrow(AaveV2Ethereum.POOL, 1, collateralAsset);

    // Swap liquidity(collateral)
    uint256 collateralAmountToSwap = 5e18;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newCollateralAsset,
      collateralAmountToSwap,
      user,
      true,
      true
    );

    skip(1 hours);

    IParaSwapLiquiditySwapAdapter.LiquiditySwapParams
      memory liquiditySwapParams = IParaSwapLiquiditySwapAdapter.LiquiditySwapParams({
        collateralAsset: collateralAsset,
        collateralAmountToSwap: collateralAmountToSwap,
        newCollateralAsset: newCollateralAsset,
        minNewCollateralAmount: 1,
        offset: psp.offset,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IParaSwapLiquiditySwapAdapter.FlashParams memory flashParams;
    IParaSwapLiquiditySwapAdapter.PermitInput memory collateralATokenPermit;

    // vm.expectRevert(bytes(Errors.VL_COLLATERAL_CANNOT_COVER_NEW_BORROW));
    liquiditySwapAdapter.swapLiquidity(liquiditySwapParams, flashParams, collateralATokenPermit);
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
