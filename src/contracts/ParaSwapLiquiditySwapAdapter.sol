// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {ReentrancyGuard} from 'aave-v3-periphery/contracts/dependencies/openzeppelin/ReentrancyGuard.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {IParaSwapAugustusRegistry} from '../interfaces/IParaSwapAugustusRegistry.sol';
import {IParaSwapAugustus} from '../interfaces/IParaSwapAugustus.sol';
import {IFlashLoanReceiver} from '../interfaces/IFlashLoanReceiver.sol';
import {IParaSwapLiquiditySwapAdapter} from '../interfaces/IParaSwapLiquiditySwapAdapter.sol';
import {BaseParaSwapSellAdapter} from './BaseParaSwapSellAdapter.sol';

/**
 * @title ParaSwapLiquiditySwapAdapter
 * @notice Implements the logic of swapping collateral asset to another collateral asset
 * @dev Swaps the existing collateral asset to another asset. The asset received from swap will be provided as a collateral on behalf of user
 *      Uses the BaseParaSwapSellAdapter(exact in) for swapping the asset 
 * @author Aave Labs
 **/
abstract contract ParaSwapLiquiditySwapAdapter is
  BaseParaSwapSellAdapter,
  ReentrancyGuard,
  IFlashLoanReceiver,
  IParaSwapLiquiditySwapAdapter
{
  using SafeERC20 for IERC20;

  // unique identifier to track usage via flashloan events
  uint16 public constant REFERRER = 43980; // uint16(uint256(keccak256(abi.encode('liquidity-swap-adapter'))) / type(uint16).max)

  /**
   * @dev Constructor
   * @param addressesProvider The address of the Aave PoolAddressesProvider contract
   * @param pool The address of the Aave Pool contract
   * @param augustusRegistry The address of the Paraswap AugustusRegistry contract
   * @param owner The address to transfer ownership to
   */
  constructor(
    IPoolAddressesProvider addressesProvider,
    address pool,
    IParaSwapAugustusRegistry augustusRegistry,
    address owner
  ) BaseParaSwapSellAdapter(addressesProvider, pool, augustusRegistry) {
    transferOwnership(owner);
    // set initial approval for all reserves
    address[] memory reserves = POOL.getReservesList();
    for (uint256 i = 0; i < reserves.length; i++) {
      IERC20(reserves[i]).safeApprove(address(POOL), type(uint256).max);
    }
  }

  /**
   * @notice Renews the reserve's allowance(of this contract) to infinite for the Aave pool
   * @param reserve the address of reserve
   */
  function renewAllowance(address reserve) public {
    IERC20(reserve).safeApprove(address(POOL), 0);
    IERC20(reserve).safeApprove(address(POOL), type(uint256).max);
  }

  /// @inheritdoc IParaSwapLiquiditySwapAdapter
  function swapLiquidity(
    LiquiditySwapParams memory liquiditySwapParams,
    FlashParams memory flashParams,
    PermitInput memory collateralATokenPermit
  ) external nonReentrant {
    // Offset in August calldata if wanting to swap all balance, otherwise 0
    if (liquiditySwapParams.offset != 0) {
      (, , address aToken) = _getReserveData(liquiditySwapParams.collateralAsset);
      uint256 balance = IERC20(aToken).balanceOf(liquiditySwapParams.user);
      require(balance <= liquiditySwapParams.collateralAmountToSwap, 'INSUFFICIENT_AMOUNT_TO_SWAP');
      liquiditySwapParams.collateralAmountToSwap = balance;
    }
    // Non-zero amount if wanting to flashloan, otherwise 0
    if (flashParams.flashLoanAmount == 0) {
      _swapAndDeposit(liquiditySwapParams, collateralATokenPermit);
    } else {
      _flash(liquiditySwapParams, flashParams, collateralATokenPermit);
    }
  }

  /**
   * @notice Executes an operation after receiving the flash-borrowed assets
   * @dev Ensure that the contract can return the debt + premium, e.g., has
   *      enough funds to repay the loan and has approved the Pool to pull the total amount.
   *      only callable by Aave pool. Swaps the received flash-borrowed asset minus premium to newCollateralAsset
   *      Supplies the received newCollateralAsset to Aave pool
   *      flash-borrowed assets should be same as old collateral asset
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

    (
      LiquiditySwapParams memory liquiditySwapParams,
      FlashParams memory flashParams,
      PermitInput memory collateralATokenPermit
    ) = abi.decode(params, (LiquiditySwapParams, FlashParams, PermitInput));

    address flashLoanAsset = assets[0];
    uint256 flashLoanAmount = amounts[0];
    uint256 flashLoanPremium = premiums[0];

    // sell(exact in) the (flashLoanAmount - flashLoanPremium) amount of old collateral asset(flash-borrowed asset) to new collateral asset
    // flashLoanPremium amount of flash-borrowed asset stays in the contract
    uint256 amountReceived = _sellOnParaSwap(
      liquiditySwapParams.offset,
      liquiditySwapParams.paraswapData,
      IERC20Detailed(flashLoanAsset),
      IERC20Detailed(liquiditySwapParams.newCollateralAsset),
      flashLoanAmount - flashLoanPremium,
      liquiditySwapParams.newCollateralAmount
    );
    // supplies the received asset(newCollateralAsset) from swap to Aave pool
    _supply(liquiditySwapParams.newCollateralAsset, amountReceived, liquiditySwapParams.user, REFERRER);
    // pulls flashLoanAmount amount of flash-borrowed asset from the user
    _pullATokenAndWithdraw(
      flashLoanAsset,
      liquiditySwapParams.user,
      flashLoanAmount,
      collateralATokenPermit
    );
    _conditionalRenewAllowance(flashLoanAsset, flashLoanAmount + flashLoanPremium);
    return true;
  }

  /**
   * @dev Swaps the collateral asset and supplies the received asset to the Aave pool
   * @param liquiditySwapParams Decoded swap parameters
   * @param collateralATokenPermit Permit for aToken corresponding to old collateral asset from the user
   * @return The amount received from the swap of new collateral asset, that is now supplied to the Aave pool
   */
  function _swapAndDeposit(
    LiquiditySwapParams memory liquiditySwapParams,
    PermitInput memory collateralATokenPermit
  ) internal returns (uint256) {
    uint256 collateralAmountReceived = _pullATokenAndWithdraw(
      liquiditySwapParams.collateralAsset,
      liquiditySwapParams.user,
      liquiditySwapParams.collateralAmountToSwap,
      collateralATokenPermit
    );
    // sell(exact in) old collateral asset to new collateral asset
    uint256 amountReceived = _sellOnParaSwap(
      liquiditySwapParams.offset,
      liquiditySwapParams.paraswapData,
      IERC20Detailed(liquiditySwapParams.collateralAsset),
      IERC20Detailed(liquiditySwapParams.newCollateralAsset),
      collateralAmountReceived,
      liquiditySwapParams.newCollateralAmount
    );

    _conditionalRenewAllowance(liquiditySwapParams.newCollateralAsset, amountReceived);

    // supplies the received asset(newCollateralAsset) from swap to Aave pool
    _supply(liquiditySwapParams.newCollateralAsset, amountReceived, liquiditySwapParams.user, REFERRER);

    return amountReceived;
  }

  /**
   * @dev Checks if the asset's allowance to Aave pool is greater than or equal to minAmount, 
   *      else renews the asset's allowance to infinite for the Aave pool
   * @param asset address of asset 
   * @param minAmount minimum required allowance to Aave pool
   */
  function _conditionalRenewAllowance(address asset, uint256 minAmount) internal {
    uint256 allowance = IERC20(asset).allowance(address(this), address(POOL));
    if (allowance < minAmount) {
      renewAllowance(asset);
    }
  }

  /** 
   * @dev encodes the parameter required by executeOperation function of this contract for performing liquidity swap
   *      Flash-borrows the old collateral asset from the Aave pool 
   * @param liquiditySwapParams struct describing the liquidity swap 
   * @param flashParams struct describing flashloan params
   * @param collateralATokenPermit optional permit for old collateral's aToken
   */
  function _flash(
    LiquiditySwapParams memory liquiditySwapParams,
    FlashParams memory flashParams,
    PermitInput memory collateralATokenPermit
  ) internal virtual {
    bytes memory params = abi.encode(liquiditySwapParams, flashParams, collateralATokenPermit);
    address[] memory assets = new address[](1);
    assets[0] = flashParams.flashLoanAsset;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = flashParams.flashLoanAmount;
    uint256[] memory interestRateModes = new uint256[](1);
    interestRateModes[0] = 0;

    POOL.flashLoan(address(this), assets, amounts, interestRateModes, address(this), params, REFERRER);
  }
}
