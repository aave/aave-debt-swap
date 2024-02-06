// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {ArbitrumScript, EthereumScript, PolygonScript, AvalancheScript, OptimismScript, BaseScript} from 'aave-helpers/ScriptUtils.sol';
import {GovernanceV3Ethereum} from 'aave-address-book/GovernanceV3Ethereum.sol';
import {GovernanceV3Polygon} from 'aave-address-book/GovernanceV3Polygon.sol';
import {GovernanceV3Avalanche} from 'aave-address-book/GovernanceV3Avalanche.sol';
import {GovernanceV3Arbitrum} from 'aave-address-book/GovernanceV3Arbitrum.sol';
import {GovernanceV3Optimism} from 'aave-address-book/GovernanceV3Optimism.sol';
import {GovernanceV3Base} from 'aave-address-book/GovernanceV3Base.sol';
import {AaveV2Ethereum} from 'aave-address-book/AaveV2Ethereum.sol';
import {AaveV3Ethereum} from 'aave-address-book/AaveV3Ethereum.sol';
import {AaveV2Polygon} from 'aave-address-book/AaveV2Polygon.sol';
import {AaveV3Polygon} from 'aave-address-book/AaveV3Polygon.sol';
import {AaveV2Avalanche} from 'aave-address-book/AaveV2Avalanche.sol';
import {AaveV3Avalanche} from 'aave-address-book/AaveV3Avalanche.sol';
import {AaveV3Optimism} from 'aave-address-book/AaveV3Optimism.sol';
import {AaveV3Arbitrum} from 'aave-address-book/AaveV3Arbitrum.sol';
import {AaveV3Base} from 'aave-address-book/AaveV3Base.sol';
import {ParaSwapWithdrawSwapAdapterV2} from 'src/contracts/ParaSwapWithdrawSwapAdapterV2.sol';
import {ParaSwapWithdrawSwapAdapterV3} from 'src/contracts/ParaSwapWithdrawSwapAdapterV3.sol';
import {AugustusRegistry} from 'src/lib/AugustusRegistry.sol';

contract EthereumV2 is EthereumScript {
  function run() external broadcast {
    new ParaSwapWithdrawSwapAdapterV2(
      IPoolAddressesProvider(address(AaveV2Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV2Ethereum.POOL),
      AugustusRegistry.ETHEREUM,
      GovernanceV3Ethereum.EXECUTOR_LVL_1
    );
  }
}

contract EthereumV3 is EthereumScript {
  function run() external broadcast {
    new ParaSwapWithdrawSwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Ethereum.POOL),
      AugustusRegistry.ETHEREUM,
      GovernanceV3Ethereum.EXECUTOR_LVL_1
    );
  }
}

contract PolygonV2 is PolygonScript {
  function run() external broadcast {
    new ParaSwapWithdrawSwapAdapterV2(
      IPoolAddressesProvider(address(AaveV2Polygon.POOL_ADDRESSES_PROVIDER)),
      address(AaveV2Polygon.POOL),
      AugustusRegistry.POLYGON,
      GovernanceV3Polygon.EXECUTOR_LVL_1
    );
  }
}

contract PolygonV3 is PolygonScript {
  function run() external broadcast {
    new ParaSwapWithdrawSwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Polygon.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Polygon.POOL),
      AugustusRegistry.POLYGON,
      GovernanceV3Polygon.EXECUTOR_LVL_1
    );
  }
}

contract AvalancheV2 is AvalancheScript {
  function run() external broadcast {
    new ParaSwapWithdrawSwapAdapterV2(
      IPoolAddressesProvider(address(AaveV2Avalanche.POOL_ADDRESSES_PROVIDER)),
      address(AaveV2Avalanche.POOL),
      AugustusRegistry.AVALANCHE,
      GovernanceV3Avalanche.EXECUTOR_LVL_1
    );
  }
}

contract AvalancheV3 is AvalancheScript {
  function run() external broadcast {
    new ParaSwapWithdrawSwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Avalanche.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Avalanche.POOL),
      AugustusRegistry.AVALANCHE,
      GovernanceV3Avalanche.EXECUTOR_LVL_1
    );
  }
}

contract ArbitrumV3 is ArbitrumScript {
  function run() external broadcast {
    new ParaSwapWithdrawSwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Arbitrum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Arbitrum.POOL),
      AugustusRegistry.ARBITRUM,
      GovernanceV3Arbitrum.EXECUTOR_LVL_1
    );
  }
}

contract OptimismV3 is OptimismScript {
  function run() external broadcast {
    new ParaSwapWithdrawSwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Optimism.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Optimism.POOL),
      AugustusRegistry.OPTIMISM,
      GovernanceV3Optimism.EXECUTOR_LVL_1
    );
  }
}

contract BaseV3 is BaseScript {
  function run() external broadcast {
    new ParaSwapWithdrawSwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Base.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Base.POOL),
      AugustusRegistry.BASE,
      GovernanceV3Base.EXECUTOR_LVL_1
    );
  }
}
