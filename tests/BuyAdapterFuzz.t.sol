// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {AugustusRegistry} from 'src/lib/AugustusRegistry.sol';
import {MockParaSwapBuyAdapter} from './mocks/MockParaSwapBuyAdapter.sol';
import {BaseTest} from './utils/BaseTest.sol';

contract BuyAdapterFuzzTest is BaseTest {
  MockParaSwapBuyAdapter internal buyAdapter;
  address[] internal aaveV3EthereumAssets;

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'));

    buyAdapter = new MockParaSwapBuyAdapter(
      IPoolAddressesProvider(address(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Ethereum.POOL),
      AugustusRegistry.ETHEREUM
    );
    aaveV3EthereumAssets = [
      AaveV3EthereumAssets.DAI_UNDERLYING,
      AaveV3EthereumAssets.LINK_UNDERLYING,
      AaveV3EthereumAssets.LUSD_UNDERLYING
    ];
  }

  function test_fuzz_buy_on_paraswap(
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
    amountToBuy = bound(amountToBuy, 1e9, 1000 ether);
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
      uint256 amountAtOffset;
      bytes memory swapCalldata = psp.swapCalldata;
      uint256 offset = psp.offset;

      // Ensure 256 bit (32 bytes) toAmountOffset value is within bounds of the
      // calldata, not overlapping with the first 4 bytes (function selector).
      assertTrue(offset >= 4 && offset <= swapCalldata.length - 32, 'offset out of range');
      // In memory, swapCalldata consists of a 256 bit length field, followed by
      // the actual bytes data, that is why 32 is added to the byte offset.
      assembly {
        amountAtOffset := mload(add(swapCalldata, add(offset, 32)))
      }
      assertEq(amountAtOffset, amountToBuy, 'wrong offset');
    }
    deal(assetToSwapFrom, address(buyAdapter), psp.srcAmount);

    buyAdapter.buyOnParaSwap(
      psp.offset,
      abi.encode(psp.swapCalldata, psp.augustus),
      IERC20Detailed(assetToSwapFrom),
      IERC20Detailed(assetToSwapTo),
      psp.srcAmount,
      amountToBuy
    );

    assertGt(psp.destAmount, 0, 'route quoted zero destAmount');
    assertGe(
      IERC20Detailed(assetToSwapTo).balanceOf(address(buyAdapter)),
      amountToBuy,
      'received less amount than quoted'
    );
  }
}
