// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {IParaSwapAugustusRegistry} from 'src/contracts/dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {IBaseParaSwapAdapter} from 'src/contracts/interfaces/IBaseParaSwapAdapter.sol';
import {IParaSwapAugustusRegistry} from 'src/contracts/dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {AugustusRegistry} from 'src/contracts/dependencies/paraswap/AugustusRegistry.sol';
import {ParaSwapBuyAdapterHarness} from './harness/ParaSwapBuyAdapterHarness.sol';
import {BaseTest} from './utils/BaseTest.sol';

contract BuyAdapterFuzzTest is BaseTest {
  ParaSwapBuyAdapterHarness internal buyAdapter;
  address[] internal aaveV3EthereumAssets;

  event Bought(
    address indexed fromAsset,
    address indexed toAsset,
    uint256 amountSold,
    uint256 receivedAmount
  );

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'));

    buyAdapter = new ParaSwapBuyAdapterHarness(
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
  function test_fuzz_buyOnParaSwap(
    uint256 fromAssetIndex,
    uint256 toAssetIndex,
    uint256 amountToBuy,
    bool swapAll
  ) public {
    uint256 totalAssets = aaveV3EthereumAssets.length;
    fromAssetIndex = bound(fromAssetIndex, 0, totalAssets - 1);
    toAssetIndex = bound(toAssetIndex, 0, totalAssets - 1);
    if (fromAssetIndex == toAssetIndex) {
      toAssetIndex = (toAssetIndex + 1) % totalAssets;
    }
    amountToBuy = bound(amountToBuy, 1e15, 4_000 ether);
    address assetToSwapFrom = aaveV3EthereumAssets[fromAssetIndex];
    address assetToSwapTo = aaveV3EthereumAssets[toAssetIndex];
    PsPResponse memory psp = _fetchPSPRouteWithoutPspCacheUpdate(
      assetToSwapFrom,
      assetToSwapTo,
      amountToBuy,
      user,
      false,
      swapAll
    );
    if (swapAll) {
      _checkAmountInParaSwapCalldata(psp.offset, amountToBuy, psp.swapCalldata);
    }
    deal(assetToSwapFrom, address(buyAdapter), psp.srcAmount);
    uint256 buyAdapterAssetFromBalanceBefore = IERC20Detailed(assetToSwapFrom).balanceOf(
      address(buyAdapter)
    );

    vm.expectEmit(true, true, false, false, address(buyAdapter));
    emit Bought(assetToSwapFrom, assetToSwapTo, psp.srcAmount, psp.destAmount);
    buyAdapter.buyOnParaSwap(
      psp.offset,
      abi.encode(psp.swapCalldata, psp.augustus),
      IERC20Detailed(assetToSwapFrom),
      IERC20Detailed(assetToSwapTo),
      psp.srcAmount,
      amountToBuy
    );

    uint256 buyAdapterAssetFromBalanceAfter = IERC20Detailed(assetToSwapFrom).balanceOf(
      address(buyAdapter)
    );
    assertGe(
      psp.srcAmount,
      buyAdapterAssetFromBalanceBefore - buyAdapterAssetFromBalanceAfter,
      'consumed more balance than expected'
    );
    assertGt(psp.destAmount, 0, 'route quoted zero destAmount');
    assertGe(
      IERC20Detailed(assetToSwapTo).balanceOf(address(buyAdapter)),
      amountToBuy,
      'received less amount than quoted'
    );
  }
}
