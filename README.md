# Aave ParaSwap Adapters

This repository contains adapter contracts for ParaSwap:

- [ParaSwapDebtSwapAdapter](./src/contracts/ParaSwapDebtSwapAdapter.sol)
- [ParaSwapLiquidityAdapter](./src/contracts/ParaSwapLiquidityAdapter.sol)
- [ParaSwapRepayAdapter](./src/contracts/ParaSwapRepayAdapter.sol)
- [ParaSwapWithdrawAdapter](./src/contracts/ParaSwapWithdrawAdapter.sol)

## ParaSwapDebtSwapAdapter

ParaSwapDebtSwapAdapter aims to allow users to arbitrage borrow APY and exit illiquid debt positions.
Therefore, this contract is able to swap one debt position to another debt position - either partially or completely.

You could for example swap your `1000 BUSD` debt to `max(1010 USDC)` debt.
In order to perform this task, `swapDebt`:

1. Creates a flashLoan with variable debt mode with the **target debt**(`1010 USDC`) on behalf of the user
   - On Aave V2 you need to approve the debtSwapAdapter for credit delegation
   - On Aave V3 you can also pass a credit delegation permit
2. It then swaps the flashed assets to the underlying of the **current debt**(`1000 BUSD`) via exact out swap (meaning it will receive `1000 BUSD`, but might only need `1000.1 USDC` for the swap)
3. Repays the **current debt** (`1000 BUSD`)
4. Uses potential (`9.9 USDC`) to repay parts of the newly created **target debt**

The user has now payed off his `1000 BUSD` debt position, and created a new `1000.1 USDC` debt position.

In situations where a user's real loan-to-value (LTV) is higher than their maximum LTV but lower than their liquidation threshold (LT), extra collateral is needed to "wrap" around the flashloan-and-swap outlined above. The flow would then look like this:

1. Creates a standard, repayable flashloan with the specified extra collateral asset and amount
2. Supplies the flashed collateral on behalf of the user
3. Creates the variable debt flashloan with the **target debt**(`1010 USDC`) on behalf of the user
4. Swaps the flashloaned target debt asset to the underlying of the **current debt**(`1000 BUSD`), needing only `1000.1 USDC`
5. Repays the **current debt** (`1000 BUSD`)
6. Repays the flashloaned collateral asset and premium if needed (requires `aToken` approval)
7. Uses the remaining new debt asset (`9.9 USDC`) to repay parts of the newly created **target debt**

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

You could for example swap your `1000 BUSD` collateral to `min(995 USDC)` collateral. In order to perform this task, `swapLiquidity`:

1. Pulls the `1000 aBUSD` token from user and withdraws `1000 BUSD` from pool. (requires `aToken` approval)
2. It then swaps the collateral asset to the new collateral asset via exact in swap (meaning it will send `1000 BUSD` for the swap and receive at least `995 USDC`)
3. Supplies the received `995 USDC` to the pool on behalf of user and user receives `995 aUSDC`.

The user has now swapped off his `1000 BUSD` collateral position, and created a new `995 USDC` collateral position.

In situations where a user's real loan-to-value (LTV) is higher than their maximum LTV but lower than their liquidation threshold (LT), extra collateral is needed in the steps outlined above. The flow would then look like this(assuming flashloan premium as `0.09%`):

1. Creates a standard, repayable flashloan with the collateral asset(`BUSD`) and amount equals to the collateral to swap(`1000`).
2. Swaps the collateral asset via exact in with amount excluding the flashloan premium(`1000 BUSD` - flashloan premium = `999.1 BUSD`) to the new collateral asset(`USDC`). Flashloan premium stays in the contract so repayment is guaranteed.
3. Supplies the `USDC` received in step 2 as a collateral in the pool on behalf of user.
4. Pulls the `1000 aBUSD` from the user and withdraws `1000 BUSD` from the pool. (requires `aToken` approval)
5. Repays `1000 BUSD` flashloan and `0.9 BUSD` premium.

The `function swapLiquidity(LiquiditySwapParams memory liquiditySwapParams, PermitInput memory collateralATokenPermit)` expects three parameters.

The first one describes the swap:

```solidity
struct LiquiditySwapParams {
  address collateralAsset; // the asset to swap collateral from
  uint256 collateralAmountToSwap; // the amount of asset to swap from
  address newCollateralAsset; // the asset to swap collateral to
  uint256 newCollateralAmount; // the minimum amount of new collateral asset to receive
  uint256 offset; // offset in sell calldata in case of swapping all collateral, otherwise 0
  address user; // the address of user
  bool withFlashLoan; // true if flashloan is needed to swap collateral, otherwise false
  bytes paraswapData; // encoded paraswap data
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

## ParaSwapRepayAdapter

ParaSwapRepayAdapter aims to allow users to repay debt using collateral position.
Therefore, this contract is able to swap one collateral position to repay borrow position - either partially or completely.

You could for example repay `1000 USDC` borrow position by swapping your `max(1005 BUSD)` that are supplied as collateral. In order to perform this task, `repayWithCollateral`:

1. Pulls the `1005 aBUSD` token from user and withdraws `1005 BUSD` from pool. (requires `aToken` approval)
2. It then swaps the collateral asset to the borrow asset via exact out swap (meaning it will send `max(1005 BUSD)` for the swap but receive exact `1000 USDC`)
3. Repays the borrow position with received `1000 USDC` on behalf of user.

The user has now repaid a `1000 USDC` borrow position by swapping off his `1005 BUSD` collateral position.

In situations where a user's real loan-to-value (LTV) is higher than their maximum LTV but lower than their liquidation threshold (LT), extra collateral is needed in the steps outlined above. The flow would then look like this(assuming flashloan premium as `0.09%`):

1. Creates a standard, repayable flashloan with the collateral asset(`BUSD`) with value equivalent to the value of collateral asset to be used for the repayment.
2. Swaps the flashed assets to the borrow asset(`USDC`) via exact out.
3. Repays the borrow position with received `USDC` in step 2 on behalf of user.
4. Pull the `aBUSD` from the user equivalent to the value of (flashloan + premium - unutilized flashloan asset in step 2). (requires `aToken` approval)
5. Repays the flashloan along with premium.

The `function repayWithCollateral(RepayParams memory repayParams, FlashParams memory flashParams, PermitInput memory collateralATokenPermit)` expects three parameters.

The first one describes the repay params:

```solidity
struct RepayParams {
  address collateralAsset; // the asset you want to swap collateral from
  uint256 maxCollateralAmountToSwap; // the max amount you want to swap from
  address debtRepayAsset; // the asset you want to repay the debt
  uint256 debtRepayAmount; // the amount of debt to repay
  uint256 debtRepayMode; // debt interest rate mode (1 for stable, 2 for variable)
  uint256 offset; // offset in buy calldata in case of swapping all collateral, otherwise 0
  bool withFlashLoan; // true if flashloan is needed to repay the debt, otherwise false
  address user; // the address of user
  bytes paraswapData; // encoded paraswap data
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

## ParaSwapWithdrawSwapAdapter

ParaSwapRepayAdapter aims to allow users to withdraw their collateral and swap it to other asset.

You could for example withdraw your `1000 BUSD` collateral and convert the received collateral to `min(995 USDC)`. In order to perform this task, `withdrawAndSwap`:

1. Pulls the `1000 aBUSD` token from user and withdraws `1000 BUSD` from pool. (requires `aToken` approval)
2. It then swaps the BUSD to the USDC via exact in swap (meaning it will send `1000 BUSD` for the swap and receive at least `995 USDC`).
3. Transfers the new asset amount `995 USDC` to the user.

The user has now withdraw a 1000 BUSD collateral position and swapped it off to 995 USDC.

The `function withdrawAndSwap(WithdrawSwapParams memory withdrawSwapParams, PermitInput memory permitInput)` expects two parameters.

The first one describes the withdraw params:

```solidity
struct WithdrawSwapParams {
  address oldAsset; // the asset to withdraw and swap from
  uint256 oldAssetAmount; // the amount to withdraw
  address newAsset; // the asset to swap to
  uint256 minAmountToReceive; // the minimum amount of new asset to receive
  uint256 allBalanceOffset; // offset in sell calldata in case of swapping all collateral, otherwise 0
  address user; // the address of user
  bytes paraswapData; // encoded paraswap data
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

Security considerations around the ParaSwap adapter contracts:

- The adapter contracts are built on top of [BaseParaswapBuyAdapter](./src/contracts/BaseParaSwapBuyAdapter.sol) and [BaseParaswapSellAdapter](./src/contracts/BaseParaSwapSellAdapter.sol) which has been used in production for the previous version of these adapters ([Aave Protocol](https://github.com/Aave/Aave-V3-periphery/blob/master/contracts/adapters/paraswap)).

- The adapter contracts always act on behalf of the user. So instead of having approvals per transaction the adapter will approve `type(uint256).max` once to reduce gas consumption.

- The Aave `POOL` is considered a trustable entity for allowance purposes.

- Contracts only interact with 1 single user per action, ensuring isolation between users.

- Contracts are not upgradable.

- Contracts are ownable and will be owned by governance, so the governance will be the only entity able to call `tokenRescue`.

- The approach with credit delegation and borrow-mode flashLoans is very similar to what is done on [V2-V3 Migration helper](https://github.com/bgd-labs/V2-V3-migration-helpers)

- Contracts inherit the security and limitations of Aave V2/V3. Contracts themselves do not validate for frozen/inactive reserves and also do not consider isolation/eMode or borrowCaps. It is the responsibility of the interface integrating these contracts to correctly handle all user position compositions and pool configurations.

- Contracts implement an upper bound of 30% price impact, which would revert any swap. The slippage has to be properly configured in incorporated into:

  - `DebtSwapParams.maxNewDebt` parameter for `ParaSwapDebtSwapAdapter`
  - `LiquiditySwapParams.newCollateralAmount` parameter for `ParaSwapLiquiditySwapAdapter`
  - `RepayParams.maxCollateralAmountToSwap` parameter for `ParaSwapRepayAdapter`
  - `WithdrawSwapParams.minAmountToReceive` parameter for `ParaSwapWithdrawSwapAdapter`

- Contracts are using SELL and BUY operations of ParaSwap for swaps, which allows to designate exact input or output for swaps:

  - A SELL action of X means the adapter contract will spend X exactly for the swap. In case of receiving more than X, is considered dust and automatically donated to the contract.
  - A BUY action of Y means the adapter contract will receive Y exactly as a result of the swap. In case of receiving more than Y, is considered dust and automatically donated to the contract.

- Contracts support Aave V2 and V3. There are contracts specifically designed for each version, as well as for working with GHO.

- Using full balance of the user for actions supported by these adapter contracts require manipulating the ParaSwap calldata passed to the ParaSwap Augustus contract, and some of the swap routes do not support it. Therefore, in the case where full balance is used, the ParaSwap API call be made using a preferred set of methods.
  - Excluding the following routes when calculating a swap, using `excludeContractMethods` option:
    - BUY: `simpleBuy`, `directUniV3Buy` and `directBalancerV2GivenOutSwap`.
    - SELL: `simpleSwap`, `directUniV3Swap`, `directBalancerV2GivenInSwap`, `directBalancerV2GivenOutSwap`, `directCurveV1Swap` and `directCurveV2Swap`.
  - Including only these route when calculating a swap, using `includeContractMethods` option:
    - BUY: `buy`.
    - SELL: `multiSwap` and `megaSwap`. 

- ParaSwap extracts token surplus if ParaSwap positive slippage happens: the trade ends up with a positive result favoring the user (e.g. receiving more assets than expected in a BUY, receiving more assets than expected for same amount of assets in exchange in a SELL).
  - Positive slippage means the trade was more efficient than expected, so user is not impacted by the surplus extraction theoretically (e.g. they will get as much tokens as expected). However, a misconfiguration or bad integration with these contracts can lead to artificially create positive slippage.
  - Using full balance of users position for an action is a bit problematic and could lead to positive slippage if transaction swap amounts highly differ from amounts used for the ParaSwap API Call. Highly recommended to estimate properly the full balance the user will have at the transaction execution time.
    - When using full balance, the ParaSwap `offset` is set to non-zero value (depends on the action) the `amount` is set to a high value (higher than the current balance of the user) so contracts override the amount with the last updated value of the user position. This could artificially create positive slippage if the amount used for the ParaSwap API call highly differs from the amount that is finally used on the transaction execution (the actual one).
    - Example for `BUY`: API call of `buy(x,y)` and swap transaction of `buy(x',y')`. If `y'>y` then `x'>x`, so positive slippage happens as user is receiving more assets than expected.
    - Example for `SELL`: API call of `sell(x,y)` and swap transaction of `sell(x',y')`. If `x'>x` then `y'>y`, so positive slippage happens as user is receiving more assets than expected.
  - In `ParaSwapLiquditySwapAdapter`, fetching of ParaSwap route for swapping from collateral asset to another asset with flashloan enabled should take `flashloanFee` into consideration. As `ParaSwapLiquditySwapAdapter` swaps `(collateralAmountToSwap - flashloanFee)` to guarantee that `flashloanFee` is paid, generating routes with `(collateralAmountToSwap - flashloanFee) `is recommended.
    - Example: User wants to swap `1000 BUSD` collateral to `min(995 USDC)` collateral and with flashloan enabled. The ParaSwap route should be generated for selling (1000 BUSD - 0.9 BUSD) to buy USDC assuming (0.09% flashloan fee). Thus, ParaSwapLiquditySwapAdapter will flashloan (1000 BUSD) but will sell (1000 BUSD - 0.9 BUSD) to ensure that 0.9 BUSD stays in the contract to pay flashloan premium.

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

This code is a fork of [Aave Debt Swap Adapter](https://github.com/bgd-labs/Aave-debt-swap) contract by [BGD Labs](https://github.com/bgd-labs). Intention is to create a modern version of [the existing Aave paraswap adapters](https://github.com/Aave/Aave-V3-periphery/tree/master/contracts/adapters/paraswap) for V3, by extending the code of the Aave Debt Swap Adapter.

Furthermore, these contracts are heavily inspired by the [ParaSwap adapter contracts of Aave Protocol V2](https://github.com/Aave/protocol-V2/tree/master/contracts/adapters) written by ParaSwap team.
