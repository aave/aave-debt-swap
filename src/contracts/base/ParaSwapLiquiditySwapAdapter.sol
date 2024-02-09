// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {ReentrancyGuard} from 'aave-v3-periphery/contracts/dependencies/openzeppelin/ReentrancyGuard.sol';
import {IERC20} from 'solidity-utils/contracts/oz-common/interfaces/IERC20.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {IParaSwapAugustusRegistry} from '../dependencies/paraswap/IParaSwapAugustusRegistry.sol';
import {IAaveFlashLoanReceiver} from '../interfaces/IAaveFlashLoanReceiver.sol';
import {IParaSwapLiquiditySwapAdapter} from '../interfaces/IParaSwapLiquiditySwapAdapter.sol';
import {BaseParaSwapSellAdapter} from './BaseParaSwapSellAdapter.sol';

/**
 * @title ParaSwapLiquiditySwapAdapter
 * @notice ParaSwap Adapter to perform a swap of collateral from one asset to another.
 * @dev Swaps the existing collateral asset to another asset. It flash-borrows assets from the Aave Pool in case the
 * user position does not remain collateralized during the operation.
 * @author Aave Labs
 **/
abstract contract ParaSwapLiquiditySwapAdapter is
  BaseParaSwapSellAdapter,
  ReentrancyGuard,
  IAaveFlashLoanReceiver,
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
   * @param owner The address of the owner
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
   * @notice Renews the asset allowance to the Aave Pool
   * @param reserve The address of the asset
   */
  function renewAllowance(address reserve) public {
    IERC20(reserve).safeApprove(address(POOL), 0);
    IERC20(reserve).safeApprove(address(POOL), type(uint256).max);
  }

  /// @inheritdoc IParaSwapLiquiditySwapAdapter
  function swapLiquidity(
    LiquiditySwapParams memory liquiditySwapParams,
    PermitInput memory collateralATokenPermit
  ) external nonReentrant {
    // Offset in August calldata if wanting to swap all balance, otherwise 0
    if (liquiditySwapParams.offset != 0) {
      (, , address aToken) = _getReserveData(liquiditySwapParams.collateralAsset);
      uint256 balance = IERC20(aToken).balanceOf(liquiditySwapParams.user);
      require(balance <= liquiditySwapParams.collateralAmountToSwap, 'INSUFFICIENT_AMOUNT_TO_SWAP');
      liquiditySwapParams.collateralAmountToSwap = balance;
    }

    // true if flashloan is needed to swap liquidity
    if (!liquiditySwapParams.withFlashLoan) {
      _swapAndDeposit(liquiditySwapParams, collateralATokenPermit);
    } else {
      // flashloan of the current collateral asset
      _flash(liquiditySwapParams, collateralATokenPermit);
    }
  }

  /**
   * @dev Executes the collateral swap after receiving the flash-borrowed assets
   * @dev Workflow:
   * 1. Sell flash-borrowed asset for new collateral asset
   * 2. Supply new collateral asset
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

    (
      LiquiditySwapParams memory liquiditySwapParams,
      PermitInput memory collateralATokenPermit
    ) = abi.decode(params, (LiquiditySwapParams, PermitInput));

    address flashLoanAsset = assets[0];
    uint256 flashLoanAmount = amounts[0];
    uint256 flashLoanPremium = premiums[0];

    // sell the flashLoanAmount minus the premium, so flashloan repayment is guaranteed
    // flashLoan premium stays in the contract
    uint256 amountReceived = _sellOnParaSwap(
      liquiditySwapParams.offset,
      liquiditySwapParams.paraswapData,
      IERC20Detailed(flashLoanAsset),
      IERC20Detailed(liquiditySwapParams.newCollateralAsset),
      flashLoanAmount - flashLoanPremium,
      liquiditySwapParams.newCollateralAmount
    );

    // supplies the received asset(newCollateralAsset) from swap to Aave Pool
    _conditionalRenewAllowance(liquiditySwapParams.newCollateralAsset, amountReceived);
    _supply(
      liquiditySwapParams.newCollateralAsset,
      amountReceived,
      liquiditySwapParams.user,
      REFERRER
    );

    // pulls flashLoanAmount amount of flash-borrowed asset from the user
    _pullATokenAndWithdraw(
      flashLoanAsset,
      liquiditySwapParams.user,
      flashLoanAmount,
      collateralATokenPermit
    );

    // flashloan repayment
    _conditionalRenewAllowance(flashLoanAsset, flashLoanAmount + flashLoanPremium);
    return true;
  }

  /**
   * @dev Swaps the collateral asset and supplies the received asset to the Aave Pool
   * @dev Workflow:
   * 1. Pull aToken collateral from user and withdraw from Pool
   * 2. Sell asset for new collateral asset
   * 3. Supply new collateral asset
   * @param liquiditySwapParams struct describing the liquidity swap
   * @param collateralATokenPermit Permit for aToken corresponding to old collateral asset from the user
   * @return The amount received from the swap of new collateral asset, that is now supplied to the Aave Pool
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

    // supply the received asset(newCollateralAsset) from swap to the Aave Pool
    _conditionalRenewAllowance(liquiditySwapParams.newCollateralAsset, amountReceived);
    _supply(
      liquiditySwapParams.newCollateralAsset,
      amountReceived,
      liquiditySwapParams.user,
      REFERRER
    );

    return amountReceived;
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
   * @dev Triggers the flashloan passing encoded params for the collateral swap
   * @param liquiditySwapParams struct describing the liquidity swap
   * @param collateralATokenPermit optional permit for old collateral's aToken
   */
  function _flash(
    LiquiditySwapParams memory liquiditySwapParams,
    PermitInput memory collateralATokenPermit
  ) internal virtual {
    bytes memory params = abi.encode(liquiditySwapParams, collateralATokenPermit);
    address[] memory assets = new address[](1);
    assets[0] = liquiditySwapParams.collateralAsset;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = liquiditySwapParams.collateralAmountToSwap;
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
}
