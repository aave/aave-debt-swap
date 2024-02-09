// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';
import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {ReentrancyGuard} from 'aave-v3-periphery/contracts/dependencies/openzeppelin/ReentrancyGuard.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {IParaSwapAugustusRegistry} from '../dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {IParaSwapAugustus} from '../dependencies/paraswap/IParaSwapAugustus.sol';
import {IAaveFlashLoanReceiver} from '../interfaces/IAaveFlashLoanReceiver.sol';
import {IParaSwapRepayAdapter} from '../interfaces/IParaSwapRepayAdapter.sol';
import {BaseParaSwapBuyAdapter} from './BaseParaSwapBuyAdapter.sol';

/**
 * @title ParaSwapRepayAdapter
 * @notice ParaSwap Adapter to repay debt with collateral.
 * @dev Swaps the existing collateral asset to debt asset in order to repay the debt. It flash-borrows assets from the Aave Pool in case the
 * user position does not remain collateralized during the operation.
 * @author Aave Labs
 **/
abstract contract ParaSwapRepayAdapter is
  BaseParaSwapBuyAdapter,
  ReentrancyGuard,
  IAaveFlashLoanReceiver,
  IParaSwapRepayAdapter
{
  using SafeERC20 for IERC20;

  // unique identifier to track usage via flashloan events
  uint16 public constant REFERRER = 13410; // uint16(uint256(keccak256(abi.encode('repay-swap-adapter'))) / type(uint16).max)

  /**
   * @dev Constructor
   * @param addressesProvider The address of the Aave PoolAddressesProvider contract
   * @param pool The address of the Aave Pool contract
   * @param augustusRegistry The address of the Paraswap AugustusRegistry contract
   * @param owner The address of the owner
   */
  constructor(
    IPoolAddressesProvider addressesProvider,
    address pool,
    IParaSwapAugustusRegistry augustusRegistry,
    address owner
  ) BaseParaSwapBuyAdapter(addressesProvider, pool, augustusRegistry) {
    transferOwnership(owner);
    // set initial approval for all reserves
    address[] memory reserves = POOL.getReservesList();
    for (uint256 i = 0; i < reserves.length; i++) {
      IERC20(reserves[i]).safeApprove(address(POOL), type(uint256).max);
    }
  }

  /**
   * @notice Renews the asset allowance to the Aave Pool
   * @param reserve The address of the asset
   */
  function renewAllowance(address reserve) public {
    IERC20(reserve).safeApprove(address(POOL), 0);
    IERC20(reserve).safeApprove(address(POOL), type(uint256).max);
  }

  /// @inheritdoc IParaSwapRepayAdapter
  function repayWithCollateral(
    RepayParams memory repayParams,
    PermitInput memory collateralATokenPermit
  ) external nonReentrant {
    // Refresh the debt amount to repay
    repayParams.debtRepayAmount = _getDebtRepayAmount(
      IERC20(repayParams.debtRepayAsset),
      repayParams.debtRepayMode,
      repayParams.offset,
      repayParams.debtRepayAmount,
      repayParams.user
    );

    // true if flashloan is needed to repay the debt
    if (!repayParams.withFlashLoan) {
      uint256 collateralBalanceBefore = IERC20(repayParams.collateralAsset).balanceOf(
        address(this)
      );
      _swapAndRepay(repayParams, collateralATokenPermit);

      // Supply on behalf of the user in case of excess of collateral asset after the swap
      uint256 collateralBalanceAfter = IERC20(repayParams.collateralAsset).balanceOf(address(this));
      uint256 collateralExcess = collateralBalanceAfter > collateralBalanceBefore
        ? collateralBalanceAfter - collateralBalanceBefore
        : 0;
      if (collateralExcess > 0) {
        _conditionalRenewAllowance(repayParams.collateralAsset, collateralExcess);
        _supply(repayParams.collateralAsset, collateralExcess, repayParams.user, REFERRER);
      }
    } else {
      // flashloan of the current collateral asset to use for repayment
      _flash(repayParams, collateralATokenPermit);
    }
  }

  /**
   * @dev Executes the repay with collateral after receiving the flash-borrowed assets
   * @dev Workflow:
   * 1. Buy debt asset by providing the flash-borrowed assets in exchange
   * 2. Repay debt
   * 3. Pull aToken collateral from user and withdraw from Pool
   * 4. Repay flashloan
   * @param assets The addresses of the flash-borrowed assets
   * @param amounts The amounts of the flash-borrowed assets
   * @param premiums The premiums of the flash-borrowed assets
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
  ) external returns (bool) {
    require(msg.sender == address(POOL), 'CALLER_MUST_BE_POOL');
    require(initiator == address(this), 'INITIATOR_MUST_BE_THIS');

    (RepayParams memory repayParams, PermitInput memory collateralATokenPermit) = abi.decode(
      params,
      (RepayParams, PermitInput)
    );

    address flashLoanAsset = assets[0];
    uint256 flashLoanAmount = amounts[0];
    uint256 flashLoanPremium = premiums[0];

    // buys the debt asset by providing the flashloanAsset
    uint256 amountSold = _buyOnParaSwap(
      repayParams.offset,
      repayParams.paraswapData,
      IERC20Detailed(flashLoanAsset),
      IERC20Detailed(repayParams.debtRepayAsset),
      flashLoanAmount,
      repayParams.debtRepayAmount
    );

    // repays debt
    _conditionalRenewAllowance(repayParams.debtRepayAsset, repayParams.debtRepayAmount);
    POOL.repay(
      repayParams.debtRepayAsset,
      repayParams.debtRepayAmount,
      repayParams.debtRepayMode,
      repayParams.user
    );

    // pulls only the amount needed from the user for the flashloan repayment
    // flashLoanAmount - amountSold = excess in the contract from swap
    // flashLoanAmount + flashLoanPremium = flashloan repayment
    // the amount needed is:
    // flashLoanAmount + flashLoanPremium - (flashLoanAmount - amountSold)
    // equivalent to
    // flashLoanPremium + amountSold
    _pullATokenAndWithdraw(
      flashLoanAsset,
      repayParams.user,
      flashLoanPremium + amountSold,
      collateralATokenPermit
    );

    // flashloan repayment
    _conditionalRenewAllowance(flashLoanAsset, flashLoanAmount + flashLoanPremium);
    return true;
  }

  /**
   * @dev Swaps the collateral asset and repays the debt of received asset from swap
   * @dev Workflow:
   * 1. Pull aToken collateral from user and withdraw from Pool
   * 2. Buy debt asset by providing the withdrawn collateral in exchange
   * 3. Repay debt
   * @param repayParams struct describing the debt swap
   * @param collateralATokenPermit Permit for withdrawing collateral token from the pool
   * @return The amount of withdrawn collateral sold in the swap
   */
  function _swapAndRepay(
    RepayParams memory repayParams,
    PermitInput memory collateralATokenPermit
  ) internal returns (uint256) {
    uint256 collateralAmountReceived = _pullATokenAndWithdraw(
      repayParams.collateralAsset,
      repayParams.user,
      repayParams.maxCollateralAmountToSwap,
      collateralATokenPermit
    );

    // buy(exact out) of debt asset by providing the withdrawn collateral in exchange
    uint256 amountSold = _buyOnParaSwap(
      repayParams.offset,
      repayParams.paraswapData,
      IERC20Detailed(repayParams.collateralAsset),
      IERC20Detailed(repayParams.debtRepayAsset),
      collateralAmountReceived,
      repayParams.debtRepayAmount
    );

    // repay the debt with the bought asset (debtRepayAsset) from the swap
    _conditionalRenewAllowance(repayParams.debtRepayAsset, repayParams.debtRepayAmount);
    POOL.repay(
      repayParams.debtRepayAsset,
      repayParams.debtRepayAmount,
      repayParams.debtRepayMode,
      repayParams.user
    );

    return amountSold;
  }

  /**
   * @dev Triggers the flashloan passing encoded params for the repay with collateral
   * @param repayParams struct describing the repay swap
   * @param collateralATokenPermit optional permit for old collateral's aToken
   */
  function _flash(
    RepayParams memory repayParams,
    PermitInput memory collateralATokenPermit
  ) internal virtual {
    bytes memory params = abi.encode(repayParams, collateralATokenPermit);
    address[] memory assets = new address[](1);
    assets[0] = repayParams.collateralAsset;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = repayParams.maxCollateralAmountToSwap;
    uint256[] memory interestRateModes = new uint256[](1);
    interestRateModes[0] = 0;

    POOL.flashLoan(
      address(this),
      assets,
      amounts,
      interestRateModes,
      address(this),
      params,
      REFERRER
    );
  }

  /**
   * @dev Renews the asset allowance in case the current allowance is below a given threshold
   * @param asset The address of the asset
   * @param minAmount The minimum required allowance to the Aave Pool
   */
  function _conditionalRenewAllowance(address asset, uint256 minAmount) internal {
    uint256 allowance = IERC20(asset).allowance(address(this), address(POOL));
    if (allowance < minAmount) {
      renewAllowance(asset);
    }
  }

  /**
   * @dev Returns the amount of debt to repay for the user
   * @param debtAsset The address of the asset to repay the debt
   * @param rateMode The interest rate mode of the debt (e.g. STABLE or VARIABLE)
   * @param buyAllBalanceOffset offset in calldata in case all debt is repaid, otherwise 0
   * @param debtRepayAmount The amount of debt to repay
   * @param user The address user for whom the debt is repaid
   * @return The amount of debt to be repaid
   */
  function _getDebtRepayAmount(
    IERC20 debtAsset,
    uint256 rateMode,
    uint256 buyAllBalanceOffset,
    uint256 debtRepayAmount,
    address user
  ) internal view returns (uint256) {
    (address vDebtToken, address sDebtToken, ) = _getReserveData(address(debtAsset));

    address debtToken = DataTypes.InterestRateMode(rateMode) == DataTypes.InterestRateMode.STABLE
      ? sDebtToken
      : vDebtToken;
    uint256 currentDebt = IERC20(debtToken).balanceOf(user);

    if (buyAllBalanceOffset != 0) {
      // Sanity check to ensure the passed value `debtRepayAmount` is higher than the current debt
      // when repaying all debt.
      require(currentDebt <= debtRepayAmount, 'INSUFFICIENT_AMOUNT_TO_REPAY');
      debtRepayAmount = currentDebt;
    } else {
      // Sanity check to ensure the passed value `debtRepayAmount` is less than the current debt
      // when repaying the exact amount
      require(debtRepayAmount <= currentDebt, 'INVALID_DEBT_REPAY_AMOUNT');
    }

    return debtRepayAmount;
  }
}
