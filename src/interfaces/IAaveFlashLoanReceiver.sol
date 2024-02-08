// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAaveFlashLoanReceiver
 * @author Aave Labs
 * @notice Defines the basic interface of an Aave flashloan-receiver contract.
 * @dev Altered version of the official Aave Interface IFlashLoanReceiver, keeping the minimal functionality to receive the flashloan execution
 **/
interface IAaveFlashLoanReceiver {
  /**
   * @notice Executes an operation after receiving the flash-borrowed assets
   * @dev Ensure that the contract can return the debt + premium, e.g., has
   *      enough funds to repay and has approved the Pool to pull the total amount
   * @param assets The addresses of the flash-borrowed assets
   * @param amounts The amounts of the flash-borrowed assets
   * @param premiums The fee of each flash-borrowed asset
   * @param initiator The address of the flashloan initiator
   * @param params The byte-encoded params passed when initiating the flashloan
   * @return True if the execution of the operation succeeds, false otherwise
   */
  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external returns (bool);
}
