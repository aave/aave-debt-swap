// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {IERC20WithPermit} from 'solidity-utils/contracts/oz-common/interfaces/IERC20WithPermit.sol';
import {IPriceOracleGetter} from '@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol';

/**
 * @title IBaseParaSwapAdapter
 * @notice Defines the basic interface of ParaSwap adapter
 * @dev Implement this interface to provide functionality of swapping one asset to another asset
 **/
interface IBaseParaSwapAdapter {
  struct PermitInput {
    IERC20WithPermit aToken; // the asset to give allowance for
    uint256 value; // the amount of asset for the allowance
    uint256 deadline; // expiration unix timestamp
    uint8 v; // sig v
    bytes32 r; // sig r
    bytes32 s; // sig s
  }

  /**
   * @dev Emitted after a sell of an asset is made
   * @param fromAsset The address of the asset sold
   * @param toAsset The address of the asset received in exchange
   * @param fromAmount The amount of asset sold
   * @param receivedAmount The amount received from the sell
   */
  event Swapped(
    address indexed fromAsset,
    address indexed toAsset,
    uint256 fromAmount,
    uint256 receivedAmount
  );

  /**
   * @dev Emitted after a buy of an asset is made
   * @param fromAsset The address of the asset provided in exchange
   * @param toAsset The address of the asset bought
   * @param amountSold The amount of asset provided for the buy
   * @param receivedAmount The amount of asset bought
   */
  event Bought(
    address indexed fromAsset,
    address indexed toAsset,
    uint256 amountSold,
    uint256 receivedAmount
  );

  /**
   * @notice Emergency rescue for token stucked on this contract, as failsafe mechanism
   * @dev Funds should never remain in this contract more time than during transactions
   * @dev Only callable by the owner
   * @param token The address of the stucked token to rescue
   */
  function rescueTokens(IERC20 token) external;

  /**
   * @notice Returns the maximum slippage percent allowed for swapping one asset to another
   * @return The maximum allowed slippage percent, in bps
   */
  function MAX_SLIPPAGE_PERCENT() external view returns (uint256);

  /**
   * @notice Returns the Aave Price Oracle contract
   * @return The address of the AaveOracle
   */
  function ORACLE() external view returns (IPriceOracleGetter);
}
