// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {IPriceOracleGetter} from '@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol';
import {SafeERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/SafeERC20.sol';
import {Ownable} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/Ownable.sol';
import {IBaseParaSwapAdapter} from '../interfaces/IBaseParaSwapAdapter.sol';

/**
 * @title BaseParaSwapAdapter
 * @notice Utility functions for adapters using ParaSwap
 * @author Jason Raymond Bell
 */
abstract contract BaseParaSwapAdapter is Ownable, IBaseParaSwapAdapter {
  using SafeERC20 for IERC20;

  // @inheritdoc IBaseParaSwapAdapter
  uint256 public constant MAX_SLIPPAGE_PERCENT = 0.3e4; // 30.00%

  // @inheritdoc IBaseParaSwapAdapter
  IPriceOracleGetter public immutable ORACLE;

  /// The address of the Aave PoolAddressesProvider contract
  IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

  /// The address of the Aave Pool contract
  IPool public immutable POOL;

  /**
   * @dev Constructor
   * @param addressesProvider The address of the Aave PoolAddressesProvider contract
   * @param pool The address of the Aave Pool contract
   */
  constructor(IPoolAddressesProvider addressesProvider, address pool) {
    ORACLE = IPriceOracleGetter(addressesProvider.getPriceOracle());
    ADDRESSES_PROVIDER = addressesProvider;
    POOL = IPool(pool);
  }

  /// @inheritdoc IBaseParaSwapAdapter
  function rescueTokens(IERC20 token) external onlyOwner {
    token.safeTransfer(owner(), token.balanceOf(address(this)));
  }

  /**
   * @dev Get the price of the asset from the oracle
   * @param asset The address of the asset
   * @return The price of the asset, based on the oracle denomination units
   */
  function _getPrice(address asset) internal view returns (uint256) {
    return ORACLE.getAssetPrice(asset);
  }

  /**
   * @dev Get the decimals of an asset
   * @param asset The address of the asset
   * @return number of decimals of the asset
   */
  function _getDecimals(IERC20Detailed asset) internal view returns (uint8) {
    uint8 decimals = asset.decimals();
    // Ensure 10**decimals won't overflow a uint256
    require(decimals <= 77, 'TOO_MANY_DECIMALS_ON_TOKEN');
    return decimals;
  }

  /**
   * @dev Get the vToken, sToken and aToken associated to the asset
   * @param asset The address of the asset
   * @return address The address of the VariableDebtToken, vToken
   * @return address The address of the StableDebtToken, sToken
   * @return address The address of the aToken
   */
  function _getReserveData(address asset) internal view virtual returns (address, address, address);

  /**
   * @dev Supply an amount of asset to the Aave Pool
   * @param asset The address of the asset to be supplied
   * @param amount The amount of the asset to be supplied
   * @param to The address receiving the aTokens
   * @param referralCode The referral code to pass to Aave
   */
  function _supply(address asset, uint256 amount, address to, uint16 referralCode) internal virtual;

  /**
   * @dev Pull the ATokens from the user and withdraws the underlying asset from the Aave Pool
   * @param reserve The address of the asset
   * @param user The address of the user to pull aTokens from
   * @param amount The amount of tokens to be pulled and withdrawn
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

    (, , address aToken) = _getReserveData(reserve);

    uint256 aTokenBalanceBefore = IERC20(aToken).balanceOf(address(this));
    IERC20(aToken).safeTransferFrom(user, address(this), amount);
    uint256 aTokenBalanceDiff = IERC20(aToken).balanceOf(address(this)) - aTokenBalanceBefore;

    POOL.withdraw(reserve, aTokenBalanceDiff, address(this));
    return aTokenBalanceDiff;
  }

  /**
   * @dev Renews the asset allowance in case the current allowance is below a given threshold
   * @param asset The address of the asset
   * @param minAmount The minimum required allowance to the Aave Pool
   */
  function _conditionalRenewAllowance(address asset, uint256 minAmount) internal {
    uint256 allowance = IERC20(asset).allowance(address(this), address(POOL));
    if (allowance < minAmount) {
      IERC20(asset).safeApprove(address(POOL), 0);
      IERC20(asset).safeApprove(address(POOL), type(uint256).max);
    }
  }
}
