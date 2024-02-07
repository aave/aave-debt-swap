// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AaveV3EthereumAssets} from 'aave-address-book/AaveV3Ethereum.sol';
import {BaseTest} from './utils/BaseTest.sol';

contract PSRouteFuzzTest is BaseTest {
  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'), 17706839);
  }
  
  // limiting fuzz runs due to ParaSwap API rate limit
  /// forge-config: default.fuzz.runs = 50
  function test_fuzz_correct_offset(uint256 amount, bool sell) public {
    amount = bound(amount, 1e9, 1_000_000 ether);
    address fromAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address toAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;

    PsPResponse memory psp = _fetchPSPRouteWithoutPspCacheUpdate(
      fromAsset,
      toAsset,
      amount,
      user,
      sell,
      true
    );
    _checkAmountInParaSwapCalldata(psp.offset, amount, psp.swapCalldata);
  }
}
