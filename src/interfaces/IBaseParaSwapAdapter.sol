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
    IERC20WithPermit aToken;
    uint256 value;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  /**
   * @dev max slippage percentage allowed for swapping one asset to another asset
   * @return maximum allowed slippage percentage
   */
  function MAX_SLIPPAGE_PERCENT() external view returns(uint256);

  /**
   * @dev Aave price oracle
   * @return address of Aave price oracle
   */
  function ORACLE() external view returns(IPriceOracleGetter);

  /**
   * @dev Emergency rescue for token stucked on this contract, as failsafe mechanism
   * - Funds should never remain in this contract more time than during transactions
   * - Only callable by the owner
   * @param token The address of the stucked token to rescue
   */
  function rescueTokens(IERC20 token) external;

  event Swapped(
    address indexed fromAsset,
    address indexed toAsset,
    uint256 fromAmount,
    uint256 receivedAmount
  );
  event Bought(
    address indexed fromAsset,
    address indexed toAsset,
    uint256 amountSold,
    uint256 receivedAmount
  );
}
