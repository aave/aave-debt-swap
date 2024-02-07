// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {ArbitrumScript, EthereumScript, PolygonScript, AvalancheScript, OptimismScript, BaseScript} from 'aave-helpers/ScriptUtils.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {AaveV2Ethereum} from 'aave-address-book/AaveV2Ethereum.sol';
import {AaveV3Ethereum} from 'aave-address-book/AaveV3Ethereum.sol';
import {AaveV2Polygon} from 'aave-address-book/AaveV2Polygon.sol';
import {AaveV3Polygon} from 'aave-address-book/AaveV3Polygon.sol';
import {AaveV2Avalanche} from 'aave-address-book/AaveV2Avalanche.sol';
import {AaveV3Avalanche} from 'aave-address-book/AaveV3Avalanche.sol';
import {AaveV3Optimism} from 'aave-address-book/AaveV3Optimism.sol';
import {AaveV3Arbitrum} from 'aave-address-book/AaveV3Arbitrum.sol';
import {AaveV3Base} from 'aave-address-book/AaveV3Base.sol';
import {ParaSwapLiquiditySwapAdapterV2} from '../src/contracts/ParaSwapLiquiditySwapAdapterV2.sol';
import {ParaSwapLiquiditySwapAdapterV3} from '../src/contracts/ParaSwapLiquiditySwapAdapterV3.sol';
import {AugustusRegistry} from '../src/lib/AugustusRegistry.sol';

contract EthereumV2 is EthereumScript {
  function run() external broadcast {
    new ParaSwapLiquiditySwapAdapterV2(
      IPoolAddressesProvider(address(AaveV2Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV2Ethereum.POOL),
      AugustusRegistry.ETHEREUM,
      AaveGovernanceV2.SHORT_EXECUTOR
    );
  }
}

contract EthereumV3 is EthereumScript {
  function run() external broadcast {
    new ParaSwapLiquiditySwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Ethereum.POOL),
      AugustusRegistry.ETHEREUM,
      AaveGovernanceV2.SHORT_EXECUTOR
    );
  }
}

contract PolygonV2 is PolygonScript {
  function run() external broadcast {
    new ParaSwapLiquiditySwapAdapterV2(
      IPoolAddressesProvider(address(AaveV2Polygon.POOL_ADDRESSES_PROVIDER)),
      address(AaveV2Polygon.POOL),
      AugustusRegistry.POLYGON,
      AaveGovernanceV2.POLYGON_BRIDGE_EXECUTOR
    );
  }
}

contract PolygonV3 is PolygonScript {
  function run() external broadcast {
    new ParaSwapLiquiditySwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Polygon.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Polygon.POOL),
      AugustusRegistry.POLYGON,
      AaveGovernanceV2.POLYGON_BRIDGE_EXECUTOR
    );
  }
}

contract AvalancheV2 is AvalancheScript {
  function run() external broadcast {
    new ParaSwapLiquiditySwapAdapterV2(
      IPoolAddressesProvider(address(AaveV2Avalanche.POOL_ADDRESSES_PROVIDER)),
      address(AaveV2Avalanche.POOL),
      AugustusRegistry.AVALANCHE,
      0xa35b76E4935449E33C56aB24b23fcd3246f13470 // guardian
    );
  }
}

contract AvalancheV3 is AvalancheScript {
  function run() external broadcast {
    new ParaSwapLiquiditySwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Avalanche.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Avalanche.POOL),
      AugustusRegistry.AVALANCHE,
      0xa35b76E4935449E33C56aB24b23fcd3246f13470 // guardian
    );
  }
}

contract ArbitrumV3 is ArbitrumScript {
  function run() external broadcast {
    new ParaSwapLiquiditySwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Arbitrum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Arbitrum.POOL),
      AugustusRegistry.ARBITRUM,
      AaveGovernanceV2.ARBITRUM_BRIDGE_EXECUTOR
    );
  }
}

contract OptimismV3 is OptimismScript {
  function run() external broadcast {
    new ParaSwapLiquiditySwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Optimism.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Optimism.POOL),
      AugustusRegistry.OPTIMISM,
      AaveGovernanceV2.OPTIMISM_BRIDGE_EXECUTOR
    );
  }
}

contract BaseV3 is BaseScript {
  function run() external broadcast {
    new ParaSwapLiquiditySwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Base.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Base.POOL),
      AugustusRegistry.BASE,
      AaveGovernanceV2.BASE_BRIDGE_EXECUTOR
    );
  }
}
