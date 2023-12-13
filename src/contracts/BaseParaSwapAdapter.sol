// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';
import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IERC20WithPermit} from 'solidity-utils/contracts/oz-common/interfaces/IERC20WithPermit.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {IPriceOracleGetter} from '@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol';
import {SafeERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/SafeERC20.sol';
import {Ownable} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/Ownable.sol';
import {IFlashLoanReceiverBase} from '../interfaces/IFlashLoanReceiverBase.sol';
import {IBaseParaSwapAdapter} from '../interfaces/IBaseParaSwapAdapter.sol';
import "forge-std/Test.sol";

/**
 * @title BaseParaSwapAdapter
 * @notice Utility functions for adapters using ParaSwap
 * @author Jason Raymond Bell
 */
abstract contract BaseParaSwapAdapter is Ownable, IFlashLoanReceiverBase, IBaseParaSwapAdapter {
  using SafeERC20 for IERC20;
  using SafeERC20 for IERC20Detailed;
  using SafeERC20 for IERC20WithPermit;

  // Max slippage percent allowed
  uint256 public constant MAX_SLIPPAGE_PERCENT = 3000; // 30%

  IPriceOracleGetter public immutable ORACLE;
  IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
  IPool public immutable POOL;

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

  constructor(IPoolAddressesProvider addressesProvider, address pool) {
    ORACLE = IPriceOracleGetter(addressesProvider.getPriceOracle());
    ADDRESSES_PROVIDER = addressesProvider;
    POOL = IPool(pool);
  }

  /**
   * @dev Get the price of the asset from the oracle denominated in eth
   * @param asset address
   * @return eth price for the asset
   */
  function _getPrice(address asset) internal view returns (uint256) {
    return ORACLE.getAssetPrice(asset);
  }

  /**
   * @dev Get the decimals of an asset
   * @return number of decimals of the asset
   */
  function _getDecimals(IERC20Detailed asset) internal view returns (uint8) {
    uint8 decimals = asset.decimals();
    // Ensure 10**decimals won't overflow a uint256
    require(decimals <= 77, 'TOO_MANY_DECIMALS_ON_TOKEN');
    return decimals;
  }

  /**
   * @dev Get the vToken, sToken associated to the asset
   * @return address of the vToken
   * @return address of the sToken
   * @return address of the aToken
   */
  function _getReserveData(address asset) internal view virtual returns (address, address, address);

  /**
   * @dev Supply "amount" of "asset" to Aave
   * @param asset Address of the asset to be supplied
   * @param amount Amount of the asset to be supplied
   * @param to Address receiving the aTokens
   * @param referralCode Referral code to pass to Aave
   */
  function _supply(address asset, uint256 amount, address to, uint16 referralCode) internal virtual;

  /**
   * @dev Pull the ATokens from the user and withdraws the underlying asset from the POOL
   * @param reserve address of the asset
   * @param user address
   * @param amount of tokens to be transferred to the contract
   * @param permitInput struct containing the permit signature
   */
  function _pullATokenAndWithdraw(
    address reserve,
    address user,
    uint256 amount,
    PermitInput memory permitInput
  ) internal returns (uint256) {
    // If deadline is set to zero, assume there is no signature for permit
    if (permitInput.deadline != 0) {
      permitInput.aToken.permit(
        user,
        address(this),
        permitInput.value,
        permitInput.deadline,
        permitInput.v,
        permitInput.r,
        permitInput.s
      );
    }

    (, , address reserveAToken) = _getReserveData(reserve);

    uint256 reserveATokenBalanceBefore = IERC20(reserveAToken).balanceOf(address(this));
    // transfer from user to adapter
    IERC20(reserveAToken).safeTransferFrom(user, address(this), amount);

    uint256 reserveATokenBalanceReceived = IERC20(reserveAToken).balanceOf(address(this)) -
      reserveATokenBalanceBefore;

    // withdraw reserve
    require(
      POOL.withdraw(reserve, reserveATokenBalanceReceived, address(this)) ==
        reserveATokenBalanceReceived,
      'UNEXPECTED_AMOUNT_WITHDRAWN'
    );
    return reserveATokenBalanceReceived;
  }

  /**
   * @dev Emergency rescue for token stucked on this contract, as failsafe mechanism
   * - Funds should never remain in this contract more time than during transactions
   * - Only callable by the owner
   */
  function rescueTokens(IERC20 token) external onlyOwner {
    token.safeTransfer(owner(), token.balanceOf(address(this)));
  }
}
