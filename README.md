# BGD labs <> Aave Debt Swap Adapter

This repository contains the [ParaSwapDebtSwapAdapter](./src/contracts/ParaSwapDebtSwapAdapter.sol), [ParaSwapLiquidityAdapter](./s, rc/contracts/ParaSwapLiquidityAdapter.sol), [ParaSwapRepayAdapter](./src/contracts/ParaSwapRepayAdapter.sol) and [ParaSwapWithdrawAdapter](./src/contracts/ParaSwapWithdrawAdapter.sol)

## ParaSwapDebtSwapAdapter

ParaSwapDebtSwapAdapter aims to allow users to arbitrage borrow APY and exit illiquid debt positions.
Therefore, this contract is able to swap one debt position to another debt position - either partially or completely.

You could for example swap your `1000 BUSD` debt to `max(1010 USDC)` debt.
In order to perform this task, `swapDebt`:

1. Creates a flashLoan with variable debt mode with the **target debt**(`1010 USDC`) on behalf of the user
   - On aave v2 you need to approve the debtSwapAdapter for credit delegation
   - On aave v3 you can also pass a credit delegation permit
2. It then swaps the flashed assets to the underlying of the **current debt**(`1000 BUSD`) via exact out swap (meaning it will receive `1000 BUSD`, but might only need `1000.1 USDC` for the swap)
3. Repays the **current debt** (`1000 BUSD`)
4. Uses potential (`9.9 USDC`) to repay parts of the newly created **target debt**

The user has now payed off his `1000 BUSD` debt position, and created a new `1000.1 USDC` debt position.

In situations where a user's real loan-to-value (LTV) is higher than their maximum LTV but lower than their liquidation threshold (LT), extra collateral is needed to "wrap" around the flashloan-and-swap outlined above. The flow would then look like this:

1. Create a standard, repayable flashloan with the specified extra collateral asset and amount
2. Supply the flashed collateral on behalf of the user
3. Create the variable debt flashloan with the **target debt**(`1010 USDC`) on behalf of the user
4. Swap the flashloaned target debt asset to the underlying of the **current debt**(`1000 BUSD`), needing only `1000.1 USDC`
5. Repay the **current debt** (`1000 BUSD`)
6. Repay the flashloaned collateral asset and premium if needed (requires `aToken` approval)
7. Use the remaining new debt asset (`9.9 USDC`) to repay parts of the newly created **target debt**

Notice how steps 3, 4, 5, and 7 are the same four steps from the collateral-less flow.

The guidelines for selecting a proper extra collateral asset are as follows:

For Aave V3:
1. Ensure that the potential asset's LTV is nonzero.
2. Ensure that the potential asset's LT is nonzero.
3. Ensure that the potential asset's Supply Cap has sufficient capacity.
4. If the user is in isolation mode, ensure the asset is the same as the isolated collateral asset. 

For Aave V2:
1. Ensure that the potential asset's LTV is nonzero.
2. Ensure that the potential asset's LT is nonzero.
3. Ensure that the extra collateral asset is the same as the new debt asset.
4. Ensure that the collateral flashloan premium is added to the `newDebtAmount`.

When possible, for both V2 and V3 deployments, use the from/to debt asset in order to reduce cold storage access costs and save gas.

The recommended formula to determine the minimum amount of extra collateral is derived below:

```
USER_TOTAL_BORROW / (USER_OLD_COLLATERAL * OLD_COLLATERAL_LTV + EXTRA_COLLATERAL * EXTRA_COLLATERAL_ltv) = 1

USER_OLD_COLLATERAL * OLD_COLLATERAL_LTV + EXTRA_COLLATERAL * EXTRA_COLLATERAL_LTV = USER_TOTAL_BORROW

Therefore:

EXTRA_COLLATERAL = USER_TOTAL_BORROW * EXTRA_COLLATERAL_LTV / (USER_OLD_COLLATERAL * OLD_COLLATERAL_LTV)
```

We recommend a margin to account for interest accrual and health factor fluctuation until execution.

The `function swapDebt(DebtSwapParams memory debtSwapParams, CreditDelegationInput memory creditDelegationPermit, PermitInput memory collateralATokenPermit)` expects three parameters.

The first one describes the swap:

```solidity
struct DebtSwapParams {
  address debtAsset; // the asset you want to swap away from
  uint256 debtRepayAmount; // the amount of debt you want to eliminate
  uint256 debtRateMode; // the type of debt (1 for stable, 2 for variable)
  address newDebtAsset; // the asset you want to swap to
  uint256 maxNewDebtAmount; // the max amount of debt your're willing to receive in excahnge for repaying debtRepayAmount
  address extraCollateralAsset; // The asset to flash and add as collateral if needed
  uint256 extraCollateralAmount; // The amount of `extraCollateralAsset` to flash and supply momentarily
  bytes paraswapData; // encoded exactOut swap
}

```

The second one describes the (optional) creditDelegation permit:

```solidity
struct CreditDelegationInput {
  ICreditDelegationToken debtToken;
  uint256 value;
  uint256 deadline;
  uint8 v;
  bytes32 r;
  bytes32 s;
}

```

The third one describes the (optional) collateral aToken permit:

```solidity
struct PermitInput {
  IERC20WithPermit aToken;
  uint256 value;
  uint256 deadline;
  uint8 v;
  bytes32 r;
  bytes32 s;
}
```

## ParaSwapLiquidityAdapter

ParaSwapLiquidityAdapter aims to allow users to arbitrage supply APY.
Therefore, this contract is able to swap one collateral position to another collateral position - either partially or completely.

You could for example swap your `1000 BUSD` collateral to `min(995 USDC)` collateral.
In order to perform this task, `swapLiquidity`:

1. Pulls the `1000 aBUSD` token from user and withdraws `1000 BUSD` from pool. (requires `aToken` approval)
2. It then swaps the collateral asset to the new collateral asset via exact in swap (meaning it will send `1000 BUSD` for the swap but may receive `995 USDC`)
3. Supplies the received `995 USDC`` to the pool on behalf of user and user receives `995 aUSDC`.

The user has now swapped off his `1000 BUSD` collateral position, and created a new `995 USDC` collateral position.

In situations where a user's real loan-to-value (LTV) is higher than their maximum LTV but lower than their liquidation threshold (LT), extra collateral is needed in the steps outlined above. The flow would then look like this(assuming flashloan premium as `0.09%`):

1. Create a standard, repayable flashloan with the collateral asset(`BUSD`) and amount equals to the collateral to swap(`1000`).
2. Swap the collateral asset with amount excluding the flashloan premium(`1000 BUSD` - flashloan premium = `999.1 BUSD`) to the new collateral asset(`USDC`). 
3. Deposit the `USDC` received in step 2 as a collateral in the pool on behalf of user.
4. Pull the `1000 aBUSD` from the user and withdraws `1000 BUSD` from the pool.  (requires `aToken` approval)
5. Repay `1000 BUSD` flashloan and `0.9 BUSD` premium.

The `function swapLiquidity(LiquiditySwapParams memory liquiditySwapParams, FlashParams memory flashParams, PermitInput memory collateralATokenPermit)` expects three parameters.

The first one describes the swap:

```solidity
struct LiquiditySwapParams {
    address collateralAsset;  // the asset you want to swap collateral from
    uint256 collateralAmountToSwap; // the amount you want to swap from
    address newCollateralAsset; // the asset you want to swap collateral to
    uint256 newCollateralAmount; // the minimum amount of new collateral asset to be received
    uint256 offset; // offset in calldata in case of all collateral is to be swapped
    bytes paraswapData; // encoded exactIn swap
  }
```

The second one describes the (optional) flashParams:

```solidity
struct FlashParams {
    address flashLoanAsset; // the asset to flashloan(collateralAsset)
    uint256 flashLoanAmount; // the amount to flashloan(collateralAmountToSwap)
  }
```

The third one describes the (optional) collateral aToken permit:

```solidity
struct PermitInput {
  IERC20WithPermit aToken;
  uint256 value;
  uint256 deadline;
  uint8 v;
  bytes32 r;
  bytes32 s;
}
```

## ParaSwapRepayAdapter

ParaSwapRepayAdapter aims to allow users to repay the borrow position using collateral position.
Therefore, this contract is able to swap one collateral position to repay borrow position - either partially or completely.

You could for example swap your `max(1000 BUSD)` collateral to repay `(995 USDC)` borrow position.
In order to perform this task, `repayWithCollateral`:

1. Pulls the `1000 aBUSD` token from user and withdraws `1000 BUSD` from pool. (requires `aToken` approval)
2. It then swaps the collateral asset to the borrow asset via exact out swap (meaning it will send `max(1000 BUSD)` for the swap but receive exact `995 USDC`)
3. Repays the received `995 USDC` to the pool on behalf of user.

The user has now swapped off his `1000 BUSD` collateral position, and repayed a `995 USDC` borrow position.

In situations where a user's real loan-to-value (LTV) is higher than their maximum LTV but lower than their liquidation threshold (LT), extra collateral is needed in the steps outlined above. The flow would then look like this(assuming flashloan premium as `0.09%`):

1. Create a standard, repayable flashloan with the collateral asset(`BUSD`) with value equivalent to the value to be repaid of borrowed asset.
2. Swap the collateral asset with amount received to the borrowed asset(`USDC`) using exactOut. 
3. Repays the exact `USDC` received in step 2 in the pool on behalf of user.
4. Pull the `aBUSD` from the user equivalent to the value of (flashloan + premium - unutilized flashloan asset in step 2).  (requires `aToken` approval)
5. Repays the flashloan alongwith premium.

The `function repayWithCollateral(RepayParams memory repayParams, FlashParams memory flashParams, PermitInput memory collateralATokenPermit)` expects three parameters.

The first one describes the repay params:

```solidity
struct RepayParams {
    address collateralAsset; // the asset you want to swap collateral from
    uint256 maxCollateralAmountToSwap; // the max amount you want to swap from
    address debtRepayAsset; // the asset you want to repay the debt
    uint256 debtRepayAmount; // the amount of debt to be paid
    uint256 debtRepayMode; // the type of debt (1 for stable, 2 for variable)
    uint256 offset; // offset in calldata in case of all collateral is to be swapped
    bytes paraswapData; // encoded exactOut swap
  }
```

The second one describes the (optional) flashParams:

```solidity
struct FlashParams {
    address flashLoanAsset; // the asset to flashloan(collateralAsset)
    uint256 flashLoanAmount; // the amount to flashloan equivalent to the debt to be repaid
  }
```

The third one describes the (optional) collateral aToken permit:

```solidity
struct PermitInput {
  IERC20WithPermit aToken;
  uint256 value;
  uint256 deadline;
  uint8 v;
  bytes32 r;
  bytes32 s;
}
```

## ParaSwapWithdrawSwapAdapter

ParaSwapRepayAdapter aims to allow users to withdraw their collateral and swap the received collateral asset to other asset.

You could for example withdraw your `(1000 BUSD)` collateral and convert the received collateral to `min(995 USDC)`.
In order to perform this task, `withdrawAndSwap`:

1. Pulls the `1000 aBUSD` token from user and withdraws `1000 BUSD` from pool. (requires `aToken` approval)
2. It then swaps the BUSD to the USDC via exact in swap (meaning it will send `(1000 BUSD)` for the swap but receive `min(995 USDC)`)

The `function withdrawAndSwap(WithdrawSwapParams memory withdrawSwapParams, PermitInput memory permitInput)` expects two parameters.

The first one describes the withdraw params:

```solidity
struct WithdrawSwapParams {
    address oldAsset; // the asset you want withdraw and swap from
    uint256 oldAssetAmount; // the amount you want to withdraw
    address newAsset; // the asset you want to swap to
    uint256 minAmountToReceive; // the minimum amount you expect to receive
    uint256 allBalanceOffset; // offset in calldata in case of all the asset to withdraw
    bytes paraswapData; // encoded exactIn swap
  }
```

The second one describes the (optional) collateral aToken permit:

```solidity
struct PermitInput {
  IERC20WithPermit aToken;
  uint256 value;
  uint256 deadline;
  uint8 v;
  bytes32 r;
  bytes32 s;
}
```

For usage examples please check the [tests](./tests/).

## Security

- This contract is a extra layer on top of [BaseParaswapBuyAdapter](./src/contracts/BaseParaSwapBuyAdapter.sol) which is used in production for [ParaSwapRepayAdapter](https://github.com/aave/aave-v3-periphery/blob/master/contracts/adapters/paraswap/ParaSwapRepayAdapter.sol). It uses the exact same mechanism for exact out swap.

- In contrast to ParaSwapRepayAdapter the ParaSwapDebtSwapAdapter will always repay on the pool on behalf of the user. So instead of having approvals per transaction the adapter will approve `type(uint256).max` once to reduce gas consumption.

- The Aave `POOL` is considered a trustable entity for allowance purposes.

- The contract only interact with `msg.sender` and therefore ensures isolation between users.

- The contract is not upgradable.

- The contract is ownable and will be owned by governance, so the governance will be the only entity able to call `tokenRescue`.

- The approach with credit delegation and borrow-mode flashLoans is very similar to what is done on [V2-V3 Migration helper](https://github.com/bgd-labs/V2-V3-migration-helpers)

- The contract inherits the security and limitations of Aave v2/v3. The contract itself does not validate for frozen/inactive reserves and also does not consider isolation/eMode or borrowCaps. It is the responsibility of the interface integrating this contract to correctly handle all user position compositions and pool configurations.

- The contract implements an upper bound of 30% price impact, which would revert any swap. The slippage has to be properly configured in incorporated into the `DebtSwapParams.maxNewDebt` parameter.

## Install

This repo has forge and npm dependencies, so you will need to install foundry then run:

```sh
forge install
```

and also run:

```sh
yarn
```

## Tests

To run the tests just run:

```sh
forge test
```

## References

This code is based on [the existing aave paraswap adapters](https://github.com/aave/aave-v3-periphery/tree/master/contracts/adapters/paraswap) for v3.

The [BaseParaSwapAdapter.sol](./src/contracts/BaseParaSwapAdapter.sol) was slightly adjusted to receive the POOL via constructor instead of fetching it.

This makes the code agnostic for v2 and v3, as the only methods used are unchanged between the two versions.
