// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {IParaSwapAugustusRegistry} from 'src/contracts/dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {AugustusRegistry} from 'src/contracts/dependencies/paraswap/AugustusRegistry.sol';
import {ParaSwapSellAdapterHarness} from './harness/ParaSwapSellAdapterHarness.sol';
import {BaseTest} from './utils/BaseTest.sol';

contract SellAdapterFuzzTest is BaseTest {
  ParaSwapSellAdapterHarness internal sellAdapter;
  address[] internal aaveV3EthereumAssets;

  event Swapped(
    address indexed fromAsset,
    address indexed toAsset,
    uint256 fromAmount,
    uint256 receivedAmount
  );

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'));

    sellAdapter = new ParaSwapSellAdapterHarness(
      IPoolAddressesProvider(address(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Ethereum.POOL),
      IParaSwapAugustusRegistry(AugustusRegistry.ETHEREUM)
    );
    aaveV3EthereumAssets = [
      AaveV3EthereumAssets.DAI_UNDERLYING,
      AaveV3EthereumAssets.LINK_UNDERLYING,
      AaveV3EthereumAssets.LUSD_UNDERLYING
    ];
  }

  // limiting fuzz runs due to ParaSwap API rate limit
  /// forge-config: default.fuzz.runs = 50
  function test_fuzz_sell_on_paraswap(
    uint256 fromAssetIndex,
    uint256 toAssetIndex,
    uint256 amountToSwap,
    bool swapAll
  ) public {
    uint256 totalAssets = aaveV3EthereumAssets.length;
    fromAssetIndex = bound(fromAssetIndex, 0, totalAssets - 1);
    toAssetIndex = bound(toAssetIndex, 0, totalAssets - 1);
    if (fromAssetIndex == toAssetIndex) {
      toAssetIndex = (toAssetIndex + 1) % totalAssets;
    }
    amountToSwap = bound(amountToSwap, 1e15, 10_000 ether);
    address assetToSwapFrom = aaveV3EthereumAssets[fromAssetIndex];
    address assetToSwapTo = aaveV3EthereumAssets[toAssetIndex];
    PsPResponse memory psp = _fetchPSPRouteWithoutPspCacheUpdate(
      assetToSwapFrom,
      assetToSwapTo,
      amountToSwap,
      user,
      true,
      swapAll
    );
    if (swapAll) {
      _checkAmountInParaSwapCalldata(psp.offset, amountToSwap, psp.swapCalldata);
    }
    deal(assetToSwapFrom, address(sellAdapter), amountToSwap);

    vm.expectEmit(true, true, false, false, address(sellAdapter));
    emit Swapped(assetToSwapFrom, assetToSwapTo, psp.srcAmount, psp.destAmount);
    sellAdapter.sellOnParaSwap(
      psp.offset,
      abi.encode(psp.swapCalldata, psp.augustus),
      IERC20Detailed(assetToSwapFrom),
      IERC20Detailed(assetToSwapTo),
      amountToSwap,
      psp.destAmount
    );

    assertEq(
      IERC20Detailed(assetToSwapFrom).balanceOf(address(sellAdapter)),
      0,
      'sell adapter not performing exact-in swap'
    );
    assertGt(psp.destAmount, 0, 'received zero srcAmount');
    assertGe(
      IERC20Detailed(assetToSwapTo).balanceOf(address(sellAdapter)),
      psp.destAmount,
      'received less amount than quoted'
    );
  }
}
