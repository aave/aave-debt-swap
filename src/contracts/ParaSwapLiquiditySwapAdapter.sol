// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {DataTypes} from '@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol';
import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {IERC20WithPermit} from 'solidity-utils/contracts/oz-common/interfaces/IERC20WithPermit.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {ReentrancyGuard} from 'aave-v3-periphery/contracts/dependencies/openzeppelin/ReentrancyGuard.sol';
import {BaseParaSwapSellAdapter} from './BaseParaSwapSellAdapter.sol';
import {IParaSwapAugustusRegistry} from '../interfaces/IParaSwapAugustusRegistry.sol';
import {IParaSwapAugustus} from '../interfaces/IParaSwapAugustus.sol';
import {IFlashLoanReceiver} from '../interfaces/IFlashLoanReceiver.sol';
import {ICreditDelegationToken} from '../interfaces/ICreditDelegationToken.sol';
import {SafeERC20} from 'solidity-utils/contracts/oz-common/SafeERC20.sol';
import {IParaSwapLiquiditySwapAdapter} from '../interfaces/IParaSwapLiquiditySwapAdapter.sol';
import {AaveV3Ethereum} from 'aave-address-book/AaveV3Ethereum.sol';

/**
 * @title ParaSwapLiquiditySwapAdapter
 * @notice ParaSwap Adapter to perform a swap of debt to another debt.
 * @author BGD labs
 **/
abstract contract ParaSwapLiquiditySwapAdapter is
  BaseParaSwapSellAdapter,
  ReentrancyGuard,
  IFlashLoanReceiver,
  IParaSwapLiquiditySwapAdapter
{
  using SafeERC20 for IERC20WithPermit;

  // unique identifier to track usage via flashloan events
  uint16 public constant REFERRER = 43980; // uint16(uint256(keccak256(abi.encode('liquidity-swap-adapter'))) / type(uint16).max)

  /**
   * @dev Constructor
   * @param addressesProvider The address for a Pool Addresses Provider.
   * @param pool The address of the Aave Pool
   * @param augustusRegistry address of ParaSwap Augustus Registry
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
      IERC20WithPermit(reserves[i]).safeApprove(address(POOL), type(uint256).max);
    }
  }

  function renewAllowance(address reserve) public {
    IERC20WithPermit(reserve).safeApprove(address(POOL), 0);
    IERC20WithPermit(reserve).safeApprove(address(POOL), type(uint256).max);
  }

  ///@inheritdoc IParaSwapLiquiditySwapAdapter
  function swapLiquidity(
    LiquiditySwapParams memory liquiditySwapParams,
    CreditDelegationInput memory creditDelegationPermit,
    PermitInput memory collateralATokenPermit,
    PermitInput memory extraCollateralATokenPermit
  ) external nonReentrant {
    // delegate credit
    if (creditDelegationPermit.deadline != 0) {
      ICreditDelegationToken(creditDelegationPermit.debtToken).delegationWithSig(
        msg.sender,
        address(this),
        creditDelegationPermit.value,
        creditDelegationPermit.deadline,
        creditDelegationPermit.v,
        creditDelegationPermit.r,
        creditDelegationPermit.s
      );
    }

    if (liquiditySwapParams.offset != 0) {
      (, , address aToken) = _getReserveData(liquiditySwapParams.collateralAsset);
      uint256 balance = IERC20WithPermit(aToken).balanceOf(msg.sender);
      // require(balance <= liquiditySwapParams.collateralAmountToSwap, 'INSUFFICIENT_AMOUNT_TO_SWAP');
      liquiditySwapParams.collateralAmountToSwap = balance;
    }
    if (liquiditySwapParams.extraCollateralAsset == address(0)) {
      _swapAndDeposit(liquiditySwapParams, collateralATokenPermit, msg.sender);
    } else {
      _flash(liquiditySwapParams, collateralATokenPermit, extraCollateralATokenPermit);
    }
  }

  function _flash(
    LiquiditySwapParams memory liquiditySwapParams,
    PermitInput memory collateralATokenPermit,
    PermitInput memory extraCollateralATokenPermit
  ) internal virtual {
    bytes memory params = abi.encode(liquiditySwapParams, collateralATokenPermit, extraCollateralATokenPermit, msg.sender);
    address[] memory assets = new address[](1);
    assets[0] = liquiditySwapParams.extraCollateralAsset;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = liquiditySwapParams.extraCollateralAmount;
    uint256[] memory interestRateModes = new uint256[](1);
    interestRateModes[0] = 2;

    IPool(POOL).flashLoan(address(this), assets, amounts, interestRateModes, msg.sender, params, REFERRER);
  }

  /**
   * @notice Executes an operation after receiving the flash-borrowed assets
   * @dev Ensure that the contract can return the debt + premium, e.g., has
   *      enough funds to repay and has approved the Pool to pull the total amount
   * @param assets The addresses of the flash-borrowed assets
   * @param amounts The amounts of the flash-borrowed assets
   * @param initiator The address of the flashloan initiator
   * @param params The byte-encoded params passed when initiating the flashloan
   * @return True if the execution of the operation succeeds, false otherwise
   */
  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata,
    address initiator,
    bytes calldata params
  ) external returns (bool) {
    require(msg.sender == address(AaveV3Ethereum.POOL), 'CALLER_MUST_BE_POOL');
    require(initiator == address(this), 'INITIATOR_MUST_BE_THIS');

    (
      LiquiditySwapParams memory liquiditySwapParams,
      PermitInput memory collateralATokenPermit,
      PermitInput memory extraCollateralATokenPermit,
      address user
    ) = abi.decode(params, (LiquiditySwapParams, PermitInput, PermitInput, address));

    address flashLoanAsset = assets[0];
    uint256 flashLoanAmount = amounts[0];

    // Supply to the pool
    _supply(flashLoanAsset, flashLoanAmount, user, REFERRER);

    _swapAndDeposit(liquiditySwapParams, collateralATokenPermit, user);

    uint256 amountWithdrawn = _pullATokenAndWithdraw(
      flashLoanAsset,
      user,
      IERC20WithPermit(flashLoanAsset).balanceOf(msg.sender),
      extraCollateralATokenPermit
    );

    _conditionalRenewAllowance(flashLoanAsset, amountWithdrawn);

    //repay the flashloan taken on behalf of user
    POOL.repay(
      flashLoanAsset,
      amountWithdrawn,
      2,
      user
    );
    

    return true;
  }

  /**
   * @dev Swaps the collateral asset and deposit the received asset to the pool as collateral
   * @param liquiditySwapParams Decoded swap parameters
   * @param collateralATokenPermit Permit for withdrawing collateral token from the pool
   * @param user address of user
   */
  function _swapAndDeposit(
    LiquiditySwapParams memory liquiditySwapParams,
    PermitInput memory collateralATokenPermit,
    address user
  ) internal returns (uint256) {
    uint256 collateralAmountReceived = _pullATokenAndWithdraw(
      liquiditySwapParams.collateralAsset,
      user,
      liquiditySwapParams.collateralAmountToSwap,
      collateralATokenPermit
    );
    uint256 amountReceived = _sellOnParaSwap(
      liquiditySwapParams.offset,
      liquiditySwapParams.paraswapData,
      IERC20Detailed(liquiditySwapParams.collateralAsset),
      IERC20Detailed(liquiditySwapParams.newCollateralAsset),
      collateralAmountReceived,
      liquiditySwapParams.minNewCollateralAmount
    );

    _conditionalRenewAllowance(liquiditySwapParams.newCollateralAsset, amountReceived);

    _supply(liquiditySwapParams.newCollateralAsset, amountReceived, user, 0);
    return amountReceived;
  }

  function _conditionalRenewAllowance(address asset, uint256 minAmount) internal {
    uint256 allowance = IERC20(asset).allowance(address(this), address(POOL));
    if (allowance < minAmount) {
      renewAllowance(asset);
    }
  }
}
