// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {BaseTest} from './utils/BaseTest.sol';
import {stdMath} from 'forge-std/StdMath.sol';

contract PSRouteFuzzTest is BaseTest {
  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'));
  }

  function test_fuzz_correct_offset(uint256 fromAmount, bool sell) public {
    fromAmount = bound(fromAmount, 1e9, 1_000_000 ether);
    address fromAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address toAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;

    PsPResponse memory psp = _fetchPSPRouteWithoutPspCacheUpdate(
      fromAsset,
      toAsset,
      fromAmount,
      user,
      sell,
      true
    );

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

    assertEq(amountAtOffset, fromAmount, 'wrong offset');
  }
}
