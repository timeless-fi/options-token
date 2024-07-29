# **Table of content**
- [Description](#description)
  - [OptionsToken](#optionstoken)
  - [OptionsCompounder](#optionscompounder)
- [Installation](#installation)
  - [Local Development](#local-development)
- [Testing](#testing)
  - [Dynamic](#dynamic)
  - [Static](#static)
- [Deployment](#deployment)
- [Checklist](#checklist)
- [Frontend integration](#frontend-integration)



# Description 
## OptionsToken

An options token representing the right to exercise any one of the whitelisted exercise contracts, allowing the user to receive different forms of discounted assets in return for the appropriate payment. The option does not expire. The options token receives user input and a specified exercise contract address, passing through to the exercise contract to execute the option. We fork https://github.com/timeless-fi/options-token, which is a simple implementation of an option for discounted tokens at an adjusted oracle rate. Here, we divorce the exercise functionality from the token contract, and allow an admin to whitelist and fund exercise contracts as the desired. We also implement more potential oracle types, and make several other minor changes.

We want to ensure there are no attacks on pricing in DiscountExercise, atomically or otherwise, in each oracle implementation.  We want to ensure users will never pay more than maxPaymentAmount. When properly specified, this should ensure users experience no more deviation in price than they specify.

Given the nature of this token, it is fine for the admin to have some centralized permissions (admin can mint tokens, admin is the one who funds exercise contracts, etc).  The team is responsible for refilling the exercise contracts. We limit the amount of funds we leave in an exercise contract at any given time to limit risk.  

### Flow of an Option Token Exercise (Ex. Discount Exercise)

The user will always interact with the OptionsToken itself, and never with any exercise contract directly.

#### ZAP
1. User calls exercise on the OptionsToken, specifying their desired exercise contract and encoding exercise parameters
2. OptionsToken validates the exercise contract.
3. DiscountExercise decodes the parameters for the exercise function on the chosen exercise contract, and calls the specified function. In the case of zapping in DiscountExercise, the parameters are maxPaymentAmount, deadline, and isInstantExit set to true.
4. OptionsTokens are burnt.
5. A penalty fee in the form of underlying tokens (available in the contract) is calculated, then conditionally swapped to the desired token and distributed to the fee recipients.
    - Swapping and distribution occur only when the fee amount exceeds a specified trigger to avoid swapping small amounts.
    - The transaction reverts if the minimal desired amount of desired tokens is not obtained.
6. The underlying tokens available in the DiscountExercise contract are sent to the user. The amount of underlying tokens is discounted by the multiplier and reduced by the penalty fee.

#### REDEEM
1. The user approves OptionsToken the amount of Payment Token they wish to spend
2. User calls exercise on the OptionsToken, specifying their desired exercise contract and encoding exercise parameters
3. OptionsToken validates the exercise contract, decodes the parameters for the exercise function on the exercise contract of choice, and calls said function. In the case of DiscountExercise, the params are maxPaymentAmount, deadline and isInstantExit set to false.
4. oTokens are burnt, WETH is sent to the treasury, and underlyingTokens, discounted by the multiplier, are sent to the user exercising
    - Can be priced using balancer, thena, univ3 twap oracles
    - Reverts above maxPaymentAmount or past deadline

## OptionsCompounder

The Compounder platform facilitates the utilization of flash loans to exercise the option, enabling the acquisition of the underlying token at a discounted rate via payment token.

### Flow of an Options Compounder (Ex. Discount Exercise) - strategy usage

1. Admin configures swap paths, oracles, initializer args, etc
2. Strategy has an oToken balance
3. Keeper calls harvestOTokens
4. Calculate Payment Amount from Discount Exercise given oToken balance
5. Flashloan the necessary amount of funds to exercise in paymentToken
6. Callback from flashloan is called
    - oTokens are exercised using paymentToken that was flash loaned
    - Underlying token is received by the strategy
    - Calculate minAmountOut by directly querying the same oracle consumed by the DiscountExercise we interact with
    - Swap entire amount into payment token to repay flashloan
    - Assess profitability in units of paymentToken, swap profits to want of the strategy if not same token as paymentToken
    - Emit event that reflects the oTokens compounded

# Installation

To install with [DappTools](https://github.com/dapphub/dapptools):

```
dapp install timeless-fi/options-token
```

To install with [Foundry](https://github.com/gakonst/foundry):

```
forge install timeless-fi/options-token
```

## Local development

This project uses [Foundry](https://github.com/gakonst/foundry) as the development framework.

### Dependencies

```
forge install
```

### Compilation

```
forge build
```

# Testing

## Dynamic

```
forge test
```

`--report lcov` - coverage which can be turned on in code using "Coverage Gutters"

## Static 

`slither . --include-path src/<targetFile>`

`--checklist` - report in md

`--print inheritance-graph` - generate inheritance graph in xdot

`xdot inheritance-graph.dot` - open inheritance graph

# Deployment

Inside `./scripts` there is "config.json" where can be defined deployment configurations.
You can choose which contract to deploy by adding/removing string in CONTRACTS_TO_DEPLOY. If some contracts are removed from CONTRACTS_TO_DEPLOY, there must be defined the address for already existing contract on the chain (example: SWAPPER, OPTIONS_COMPOUNDER).
There are 2 deployment scripts. One is for swapper and paths updates and second for all optionsToken infra (swapper address must be passed here).

## Examples of config.json
### All contracts to deploy
```
{
  "VERSION": "1.1.0",
  "OWNER": <OWNER ADDRESS>,
  "ORACLE_SOURCE": <PRICE TWAP ORACLE>,
  "ORACLE_SECS": 1800,
  "ORACLE_MIN_PRICE": 10000000,
  "OT_NAME": "ICL Call Option Token",
  "OT_SYMBOL": "oICL",
  "OT_PAYMENT_TOKEN": "0xDfc7C877a950e49D2610114102175A06C2e3167a",
  "OT_UNDERLYING_TOKEN": "0x95177295a394f2b9b04545fff58f4af0673e839d",
  "OT_TOKEN_ADMIN": "0xF29dA3595351dBFd0D647857C46F8D63Fc2e68C5",
  "VELO_ROUTER": "0x3a63171DD9BebF4D07BC782FECC7eb0b890C2A45",
  "ADDRESS_PROVIDER": "0xEDc83309549e36f3c7FD8c2C5C54B4c8e5FA00FC",
  "MULTIPLIER": 5000,
  "FEE_RECIPIENTS": [
    <TREASURY>
  ],
  "FEE_BPS": [
    10000
  ],
  "STRATS": [
    <STRATEGY ADDRESS>
  ],
  "INSTANT_EXIT_FEE": 1000,
  "MIN_AMOUNT_TO_TRIGGER_SWAP": 1e15,
  "CONTRACTS_TO_DEPLOY": [],
  "SWAPPER": "0x63D170618A8Ed1987F3CA6391b5e2F6a4554Cf53",
  "DISCOUNT_EXERCISE": "0xcb727532e24dFe22E74D3892b998f5e915676Da8",
  "OPTIONS_TOKEN": "0x3B6eA0fA8A487c90007ce120a83920fd52b06f6D",
  "OPTIONS_COMPOUNDER": "0xf6cf2065C35595c12B532e54ACDe5A4597e32e6e",
  "ORACLE": "0xDaA2c821428f62e1B08009a69CE824253CCEE5f9"
}
```
### Only configure options compounder (no deployments)
```
{
  "VERSION": "1.1.0",
  "OWNER": <OWNER ADDRESS>,
  "ORACLE_SOURCE": <PRICE TWAP ORACLE>,
  "ORACLE_SECS": 1800,
  "ORACLE_MIN_PRICE": 10000000,
  "OT_NAME": "ICL Call Option Token",
  "OT_SYMBOL": "oICL",
  "OT_PAYMENT_TOKEN": "0xDfc7C877a950e49D2610114102175A06C2e3167a",
  "OT_UNDERLYING_TOKEN": "0x95177295a394f2b9b04545fff58f4af0673e839d",
  "OT_TOKEN_ADMIN": "0xF29dA3595351dBFd0D647857C46F8D63Fc2e68C5",
  "VELO_ROUTER": "0x3a63171DD9BebF4D07BC782FECC7eb0b890C2A45",
  "ADDRESS_PROVIDER": "0xEDc83309549e36f3c7FD8c2C5C54B4c8e5FA00FC",
  "MULTIPLIER": 5000,
  "FEE_RECIPIENTS": [
    <TREASURY>
  ],
  "FEE_BPS": [
    10000
  ],
  "STRATS": [
    <STRATEGY ADDRESS>
  ],
  "INSTANT_EXIT_FEE": 1000,
  "MIN_AMOUNT_TO_TRIGGER_SWAP": 1e15,
  "CONTRACTS_TO_DEPLOY": [
    "OptionsToken",
    "DiscountExercise",
    "ThenaOracle"
  ],
  "SWAPPER": "0x63D170618A8Ed1987F3CA6391b5e2F6a4554Cf53",
  "DISCOUNT_EXERCISE": "undefined",
  "OPTIONS_TOKEN": "undefined",
  "OPTIONS_COMPOUNDER": "undefined",
  "ORACLE": "undefined"
}
```

# Checklist

## Internal Audit Checklist

- [x]  All functionality that touches funds can be paused
- [ ]  Pause function called by 2/7 Guardian
- [ ]  Guardian has 7 members globally dispersed
- [x]  Arithmetic errors
- [x]  Re-entrancy
- [x]  Flashloans
- [x]  Access Control

- [x]  (N/A) Unchecked External Calls
- [x]  (N/A) Account abstraction/multicall issues 
- [x]  Static analysis -> Slither
  - [x]  [Discount-Exercise](#discount-exercise-slither)
  - [x]  [Options-Compounder](#options-compounder-slither)
  - [x]  [Options-Token](#options-token-slither)
  - [x]  [Thena-Oracle](#thena-oracle-slither)
  - [x]  [Base-Exercise](#base-exercise-slither)

## Pre-deployment Checklist

- [x]  Contracts pass all tests
- [x]  Contracts deployed to testnet
  - [x]  [DiscountExercise](https://explorer.mode.network/address/0xcb727532e24dFe22E74D3892b998f5e915676Da8?tab=contract)
  - [x]  [ReaperSwapper](https://explorer.mode.network/address/0x63D170618A8Ed1987F3CA6391b5e2F6a4554Cf53?tab=contract)
  - [x]  [VeloOracle](https://explorer.mode.network/address/0xDaA2c821428f62e1B08009a69CE824253CCEE5f9?tab=contract)
  - [x]  [OptionsToken](https://explorer.mode.network/address/0x3B6eA0fA8A487c90007ce120a83920fd52b06f6D?tab=contract)
  - [ ]  [OptionsCompounder](https://explorer.mode.network/address/0xf6cf2065C35595c12B532e54ACDe5A4597e32e6e?tab=contract)
- [x]  Unchecked External Calls
- [ ]  Account abstraction/multicall issues
- [x]  USE SLITHER

- [x]  Does this deployment have access to funds, either directly or indirectly (zappers, leveragers, etc.)?

Minimum security if Yes:

- [x]  Internal Audit (not the author, minimum 1x Junior review + minimum 1x Senior review)
- [x]  External Audit (impact scope)
  - [x]  [OptionsToken zapping feature scope](https://docs.google.com/document/d/1HrmXSEKuBK5U9Ix8ZSkAYf2VEYwxZ17piOjhjY4XPzs/edit?usp=drive_link)
  - [x]  [OptionsToken zapping feature audit](https://drive.google.com/file/d/1kbYnVN1HJrpllkMXXb4mmwLeU361YASG/view?usp=drive_link)
  - [x]  [OptionsCompounder integration scope](https://docs.google.com/document/d/1eKcyiVvmux2wv2P92qLQLSYIgbD-qETurHObyhOLh8Y/edit?usp=drive_link)
  - [x]  [OptionsCompounder integration audit](https://drive.google.com/file/d/1GR0Jnxo9Txa6sJ8aM_mP4xBfaBJ9UNG2/view)

Action items in support of deployment:

- [ ]  Minimum two people present for deployment
- [x]  All developers who worked on and reviewed the contract should be included in the readme
  - Developers involved: xRave110 (change owner), Eidolon (reviewer), Zokunei (reviewer), Goober (reviewer), Beirao (reviewer)
- [ ]  Documentation of deployment procedure if non-standard (i.e. if multiple scripts are necessary)  

## Discount Exercise Slither

Summary
 - [reentrancy-no-eth](#reentrancy-no-eth) (1 results) (Medium)
 - [unused-return](#unused-return) (2 results) (Medium)
 - [reentrancy-benign](#reentrancy-benign) (1 results) (Low)
 - [reentrancy-events](#reentrancy-events) (4 results) (Low)
 - [timestamp](#timestamp) (2 results) (Low)
 - [pragma](#pragma) (1 results) (Informational)
 - [solc-version](#solc-version) (1 results) (Informational)
 - [naming-convention](#naming-convention) (3 results) (Informational)
 - [unused-import](#unused-import) (2 results) (Informational)
## reentrancy-no-eth
Impact: Medium
Confidence: Medium
 - [ ] ID-0
Reentrancy in [DiscountExercise._zap(address,uint256,address,DiscountExerciseParams)](src/exercise/DiscountExercise.sol#L211-L249):
        External calls:
        - [underlyingToken.approve(swapProps.swapper,feeAmount)](src/exercise/DiscountExercise.sol#L228)
        - [amountOut = _generalSwap(swapProps.exchangeTypes,address(underlyingToken),address(paymentToken),feeAmount,minAmountOut,swapProps.exchangeAddress)](src/exercise/DiscountExercise.sol#L230-L232)
                - [_swapper.swapUniV2(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L72)
                - [_swapper.swapBal(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L74)
                - [_swapper.swapVelo(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L76)
                - [_swapper.swapUniV3(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L78)
        State variables written after the call(s):
        - [feeAmount = 0](src/exercise/DiscountExercise.sol#L238)
        [DiscountExercise.feeAmount](src/exercise/DiscountExercise.sol#L74) can be used in cross function reentrancies:
        - [DiscountExercise._zap(address,uint256,address,DiscountExerciseParams)](src/exercise/DiscountExercise.sol#L211-L249)

src/exercise/DiscountExercise.sol#L211-L249

Justification: External call is happening to well known dexes which are verified against any reentrancy attacks but fix may be implemented using additional temporary variable.

## unused-return
Impact: Medium
Confidence: Medium
 - [ ] ID-1
[DiscountExercise._zap(address,uint256,address,DiscountExerciseParams)](src/exercise/DiscountExercise.sol#L211-L249) ignores return value by [underlyingToken.approve(swapProps.swapper,feeAmount)](src/exercise/DiscountExercise.sol#L228)

src/exercise/DiscountExercise.sol#L211-L249


 - [ ] ID-2
[DiscountExercise._zap(address,uint256,address,DiscountExerciseParams)](src/exercise/DiscountExercise.sol#L211-L249) ignores return value by [underlyingToken.approve(swapProps.swapper,0)](src/exercise/DiscountExercise.sol#L239)

src/exercise/DiscountExercise.sol#L211-L249

Justification: It is just potential DOS which is very unlikely.

## reentrancy-benign
Impact: Low
Confidence: Medium
 - [ ] ID-3
Reentrancy in [DiscountExercise._pay(address,uint256)](src/exercise/DiscountExercise.sol#L269-L278):
        External calls:
        - [underlyingToken.safeTransfer(to,balance)](src/exercise/DiscountExercise.sol#L272)
        - [underlyingToken.safeTransfer(to,amount)](src/exercise/DiscountExercise.sol#L275)
        State variables written after the call(s):
        - [credit[to] += remainingAmount](src/exercise/DiscountExercise.sol#L277)

src/exercise/DiscountExercise.sol#L269-L278

Justification: Tokens are set by the addresses with special access role who knows that onReceiveErc20 hook might lead to the potential reentrancy attack.

## reentrancy-events
Impact: Low
Confidence: Medium
 - [ ] ID-4
Reentrancy in [DiscountExercise._zap(address,uint256,address,DiscountExerciseParams)](src/exercise/DiscountExercise.sol#L211-L249):
        External calls:
        - [underlyingToken.approve(swapProps.swapper,feeAmount)](src/exercise/DiscountExercise.sol#L228)
        - [amountOut = _generalSwap(swapProps.exchangeTypes,address(underlyingToken),address(paymentToken),feeAmount,minAmountOut,swapProps.exchangeAddress)](src/exercise/DiscountExercise.sol#L230-L232)
                - [_swapper.swapUniV2(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L72)
                - [_swapper.swapBal(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L74)
                - [_swapper.swapVelo(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L76)
                - [_swapper.swapUniV3(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L78)
        - [underlyingToken.approve(swapProps.swapper,0)](src/exercise/DiscountExercise.sol#L239)
        - [distributeFees(paymentToken.balanceOf(address(this)),paymentToken)](src/exercise/DiscountExercise.sol#L242)
                - [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L110)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
                - [token.safeTransfer(feeRecipients[i],feeAmount)](src/exercise/BaseExercise.sol#L90)
                - [token.safeTransfer(feeRecipients[feeRecipients.length - 1],remaining)](src/exercise/BaseExercise.sol#L93)
        - [_pay(recipient,underlyingAmount)](src/exercise/DiscountExercise.sol#L246)
                - [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L110)
                - [underlyingToken.safeTransfer(to,balance)](src/exercise/DiscountExercise.sol#L272)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
                - [underlyingToken.safeTransfer(to,amount)](src/exercise/DiscountExercise.sol#L275)
        External calls sending eth:
        - [distributeFees(paymentToken.balanceOf(address(this)),paymentToken)](src/exercise/DiscountExercise.sol#L242)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
        - [_pay(recipient,underlyingAmount)](src/exercise/DiscountExercise.sol#L246)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
        Event emitted after the call(s):
        - [Exercised(from,recipient,underlyingAmount,paymentAmount)](src/exercise/DiscountExercise.sol#L248)

src/exercise/DiscountExercise.sol#L211-L249


 - [ ] ID-5
Reentrancy in [DiscountExercise.claim(address)](src/exercise/DiscountExercise.sol#L134-L140):
        External calls:
        - [underlyingToken.safeTransfer(to,amount)](src/exercise/DiscountExercise.sol#L138)
        Event emitted after the call(s):
        - [Claimed(amount)](src/exercise/DiscountExercise.sol#L139)

src/exercise/DiscountExercise.sol#L134-L140


 - [ ] ID-6
Reentrancy in [DiscountExercise._zap(address,uint256,address,DiscountExerciseParams)](src/exercise/DiscountExercise.sol#L211-L249):
        External calls:
        - [underlyingToken.approve(swapProps.swapper,feeAmount)](src/exercise/DiscountExercise.sol#L228)
        - [amountOut = _generalSwap(swapProps.exchangeTypes,address(underlyingToken),address(paymentToken),feeAmount,minAmountOut,swapProps.exchangeAddress)](src/exercise/DiscountExercise.sol#L230-L232)
                - [_swapper.swapUniV2(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L72)
                - [_swapper.swapBal(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L74)
                - [_swapper.swapVelo(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L76)
                - [_swapper.swapUniV3(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L78)
        - [underlyingToken.approve(swapProps.swapper,0)](src/exercise/DiscountExercise.sol#L239)
        - [distributeFees(paymentToken.balanceOf(address(this)),paymentToken)](src/exercise/DiscountExercise.sol#L242)
                - [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L110)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
                - [token.safeTransfer(feeRecipients[i],feeAmount)](src/exercise/BaseExercise.sol#L90)
                - [token.safeTransfer(feeRecipients[feeRecipients.length - 1],remaining)](src/exercise/BaseExercise.sol#L93)
        External calls sending eth:
        - [distributeFees(paymentToken.balanceOf(address(this)),paymentToken)](src/exercise/DiscountExercise.sol#L242)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
        Event emitted after the call(s):
        - [DistributeFees(feeRecipients,feeBPS,totalAmount)](src/exercise/BaseExercise.sol#L94)
                - [distributeFees(paymentToken.balanceOf(address(this)),paymentToken)](src/exercise/DiscountExercise.sol#L242)

src/exercise/DiscountExercise.sol#L211-L249


 - [ ] ID-7
Reentrancy in [DiscountExercise._redeem(address,uint256,address,DiscountExerciseParams)](src/exercise/DiscountExercise.sol#L252-L267):
        External calls:
        - [distributeFeesFrom(paymentAmount,paymentToken,from)](src/exercise/DiscountExercise.sol#L262)
                - [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L110)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
                - [token.safeTransferFrom(from,feeRecipients[i],feeAmount)](src/exercise/BaseExercise.sol#L77)
                - [token.safeTransferFrom(from,feeRecipients[feeRecipients.length - 1],remaining)](src/exercise/BaseExercise.sol#L80)
        - [_pay(recipient,amount)](src/exercise/DiscountExercise.sol#L264)
                - [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L110)
                - [underlyingToken.safeTransfer(to,balance)](src/exercise/DiscountExercise.sol#L272)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
                - [underlyingToken.safeTransfer(to,amount)](src/exercise/DiscountExercise.sol#L275)
        External calls sending eth:
        - [distributeFeesFrom(paymentAmount,paymentToken,from)](src/exercise/DiscountExercise.sol#L262)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
        - [_pay(recipient,amount)](src/exercise/DiscountExercise.sol#L264)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
        Event emitted after the call(s):
        - [Exercised(from,recipient,amount,paymentAmount)](src/exercise/DiscountExercise.sol#L266)

src/exercise/DiscountExercise.sol#L252-L267


## timestamp
Impact: Low
Confidence: Medium
 - [ ] ID-8
[DiscountExercise._redeem(address,uint256,address,DiscountExerciseParams)](src/exercise/DiscountExercise.sol#L252-L267) uses timestamp for comparisons
        Dangerous comparisons:
        - [block.timestamp > params.deadline](src/exercise/DiscountExercise.sol#L257)

src/exercise/DiscountExercise.sol#L252-L267


 - [ ] ID-9
[DiscountExercise._zap(address,uint256,address,DiscountExerciseParams)](src/exercise/DiscountExercise.sol#L211-L249) uses timestamp for comparisons
        Dangerous comparisons:
        - [block.timestamp > params.deadline](src/exercise/DiscountExercise.sol#L215)

src/exercise/DiscountExercise.sol#L211-L249


## pragma
Impact: Informational
Confidence: High
 - [ ] ID-10
11 different versions of Solidity are used:
        - Version constraint ^0.8.0 is used by:
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlEnumerableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC1967Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/interfaces/draft-IERC1822Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/proxy/beacon/IBeaconUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/StorageSlotUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/StringsUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/ERC165Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/IERC165Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol#L5)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/security/Pausable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/draft-IERC20Permit.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/utils/Context.sol#L4)
                -[^0.8.0](lib/v3-core/contracts/libraries/FullMath.sol#L2)
                -[^0.8.0](lib/v3-core/contracts/libraries/TickMath.sol#L2)
                -[^0.8.0](lib/vault-v2/src/ReaperSwapper.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/AggregatorV3Interface.sol#L4)
                -[^0.8.0](lib/vault-v2/src/interfaces/IAsset.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IAuthorizer.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBasePool.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBaseWeightedPool.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBeetVault.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IPoolSwapStructs.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISignaturesValidator.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapErrors.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapper.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapperSwaps.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ITemporarilyPausable.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IUniswapV2Router01.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloPair.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloRouter.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloV1AndV2Factory.sol#L2)
                -[^0.8.0](lib/vault-v2/src/libraries/Babylonian.sol#L3)
                -[^0.8.0](lib/vault-v2/src/libraries/ReaperMathUtils.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/BalMixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/ReaperAccessControl.sol#L5)
                -[^0.8.0](lib/vault-v2/src/mixins/UniV2Mixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/UniV3Mixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/VeloSolidMixin.sol#L3)
                -[^0.8.0](src/OptionsCompounder.sol#L3)
                -[^0.8.0](src/interfaces/IBalancerTwapOracle.sol#L15)
                -[^0.8.0](src/interfaces/IFlashLoanReceiver.sol#L2)
                -[^0.8.0](src/interfaces/ILendingPool.sol#L2)
                -[^0.8.0](src/interfaces/ILendingPoolAddressesProvider.sol#L2)
                -[^0.8.0](src/interfaces/IOptionsCompounder.sol#L3)
                -[^0.8.0](src/interfaces/ISwapperSwaps.sol#L3)
                -[^0.8.0](src/libraries/DataTypes.sol#L2)
        - Version constraint ^0.8.2 is used by:
                -[^0.8.2](lib/openzeppelin-contracts-upgradeable/contracts/proxy/ERC1967/ERC1967UpgradeUpgradeable.sol#L4)
                -[^0.8.2](lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol#L4)
        - Version constraint ^0.8.1 is used by:
                -[^0.8.1](lib/openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol#L4)
                -[^0.8.1](lib/openzeppelin-contracts/contracts/utils/Address.sol#L4)
        - Version constraint >=0.8.0 is used by:
                -[>=0.8.0](lib/solmate/src/auth/Owned.sol#L2)
                -[>=0.8.0](lib/solmate/src/tokens/ERC20.sol#L2)
                -[>=0.8.0](lib/solmate/src/utils/FixedPointMathLib.sol#L2)
        - Version constraint >=0.5.0 is used by:
                -[>=0.5.0](lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolErrors.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IPeripheryImmutableState.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IUniswapV3Factory.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IUniswapV3SwapCallback.sol#L2)
                -[>=0.5.0](src/interfaces/IAlgebraPool.sol#L2)
        - Version constraint >=0.7.5 is used by:
                -[>=0.7.5](lib/vault-v2/src/interfaces/ISwapRouter.sol#L2)
        - Version constraint >=0.6.2 is used by:
                -[>=0.6.2](lib/vault-v2/src/interfaces/IUniswapV2Router02.sol#L2)
        - Version constraint >=0.6.0 is used by:
                -[>=0.6.0](lib/vault-v2/src/libraries/TransferHelper.sol#L2)
        - Version constraint ^0.8.13 is used by:
                -[^0.8.13](src/OptionsToken.sol#L2)
                -[^0.8.13](src/exercise/BaseExercise.sol#L2)
                -[^0.8.13](src/exercise/DiscountExercise.sol#L2)
                -[^0.8.13](src/helpers/SwapHelper.sol#L3)
                -[^0.8.13](src/interfaces/IBalancer2TokensPool.sol#L2)
                -[^0.8.13](src/interfaces/IExercise.sol#L2)
                -[^0.8.13](src/interfaces/IOptionsToken.sol#L2)
                -[^0.8.13](src/oracles/AlgebraOracle.sol#L2)
                -[^0.8.13](src/oracles/BalancerOracle.sol#L2)
                -[^0.8.13](src/oracles/ThenaOracle.sol#L2)
                -[^0.8.13](src/oracles/UniswapV3Oracle.sol#L2)
        - Version constraint >=0.7.0<0.9.0 is used by:
                -[>=0.7.0<0.9.0](src/interfaces/IBalancerVault.sol#L17)
                -[>=0.7.0<0.9.0](src/interfaces/IERC20Mintable.sol#L3)
                -[>=0.7.0<0.9.0](src/interfaces/IOracle.sol#L3)
        - Version constraint >=0.5 is used by:
                -[>=0.5](src/interfaces/IThenaPair.sol#L1)

lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol#L4


## solc-version
Impact: Informational
Confidence: High
 - [ ] ID-11
Version constraint ^0.8.13 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
        - VerbatimInvalidDeduplication
        - FullInlinerNonExpressionSplitArgumentEvaluationOrder
        - MissingSideEffectsOnSelectorAccess
        - StorageWriteRemovalBeforeConditionalTermination
        - AbiReencodingHeadOverflowWithStaticArrayCleanup
        - DirtyBytesArrayToStorage
        - InlineAssemblyMemorySideEffects
        - DataLocationChangeInInternalOverride
        - NestedCalldataArrayAbiReencodingSizeValidation.
It is used by:
        - [^0.8.13](src/OptionsToken.sol#L2)
        - [^0.8.13](src/exercise/BaseExercise.sol#L2)
        - [^0.8.13](src/exercise/DiscountExercise.sol#L2)
        - [^0.8.13](src/helpers/SwapHelper.sol#L3)
        - [^0.8.13](src/interfaces/IBalancer2TokensPool.sol#L2)
        - [^0.8.13](src/interfaces/IExercise.sol#L2)
        - [^0.8.13](src/interfaces/IOptionsToken.sol#L2)
        - [^0.8.13](src/oracles/AlgebraOracle.sol#L2)
        - [^0.8.13](src/oracles/BalancerOracle.sol#L2)
        - [^0.8.13](src/oracles/ThenaOracle.sol#L2)
        - [^0.8.13](src/oracles/UniswapV3Oracle.sol#L2)

src/OptionsToken.sol#L2


## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-12
Parameter [DiscountExercise.setSwapProps(SwapProps)._swapProps](src/exercise/DiscountExercise.sol#L143) is not in mixedCase

src/exercise/DiscountExercise.sol#L143


 - [ ] ID-13
Parameter [DiscountExercise.setMinAmountToTriggerSwap(uint256)._minAmountToTriggerSwap](src/exercise/DiscountExercise.sol#L193) is not in mixedCase

src/exercise/DiscountExercise.sol#L193


 - [ ] ID-14
Parameter [DiscountExercise.setInstantExitFee(uint256)._instantExitFee](src/exercise/DiscountExercise.sol#L179) is not in mixedCase

src/exercise/DiscountExercise.sol#L179


## unused-import
Impact: Informational
Confidence: High
 - [ ] ID-15
The following unused import(s) in src/interfaces/IOptionsCompounder.sol should be removed:
        -import {IOptionsToken} from "./IOptionsToken.sol"; (src/interfaces/IOptionsCompounder.sol#5)

 - [ ] ID-16
The following unused import(s) in src/OptionsCompounder.sol should be removed:
        -import {ReaperAccessControl} from "vault-v2/mixins/ReaperAccessControl.sol"; (src/OptionsCompounder.sol#11)

INFO:Slither:. analyzed (100 contracts with 94 detectors), 17 result(s) found

## Options Compounder Slither

Summary
 - [arbitrary-send-erc20](#arbitrary-send-erc20) (1 results) (High)
 - [reentrancy-eth](#reentrancy-eth) (1 results) (High)
 - [incorrect-equality](#incorrect-equality) (1 results) (Medium)
 - [unused-return](#unused-return) (6 results) (Medium)
 - [missing-zero-check](#missing-zero-check) (1 results) (Low)
 - [reentrancy-benign](#reentrancy-benign) (1 results) (Low)
 - [reentrancy-events](#reentrancy-events) (1 results) (Low)
 - [timestamp](#timestamp) (1 results) (Low)
 - [boolean-equal](#boolean-equal) (3 results) (Informational)
 - [pragma](#pragma) (1 results) (Informational)
 - [solc-version](#solc-version) (1 results) (Informational)
 - [missing-inheritance](#missing-inheritance) (1 results) (Informational)
 - [naming-convention](#naming-convention) (13 results) (Informational)
## arbitrary-send-erc20
Impact: High
Confidence: High
 - [ ] ID-0
[OptionsCompounder._exerciseOptionAndReturnDebt(address,uint256,uint256,bytes)](src/OptionsCompounder.sol#L241-L320) uses arbitrary from in transferFrom: [IERC20(address(optionsToken)).safeTransferFrom(flashloanParams.sender,address(this),flashloanParams.optionsAmount)](src/OptionsCompounder.sol#L258)

src/OptionsCompounder.sol#L241-L320


## reentrancy-eth
Impact: High
Confidence: Medium
 - [ ] ID-1
Reentrancy in [OptionsCompounder.executeOperation(address[],uint256[],uint256[],address,bytes)](src/OptionsCompounder.sol#L214-L230):
        External calls:
        - [_exerciseOptionAndReturnDebt(assets[0],amounts[0],premiums[0],params)](src/OptionsCompounder.sol#L227)
                - [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L110)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
                - [_swapper.swapUniV2(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L72)
                - [_swapper.swapBal(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L74)
                - [_swapper.swapVelo(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L76)
                - [IERC20(address(optionsToken)).safeTransferFrom(flashloanParams.sender,address(this),flashloanParams.optionsAmount)](src/OptionsCompounder.sol#L258)
                - [_swapper.swapUniV3(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L78)
                - [IERC20(asset).approve(flashloanParams.exerciserContract,amount)](src/OptionsCompounder.sol#L265)
                - [optionsToken.exercise(flashloanParams.optionsAmount,address(this),flashloanParams.exerciserContract,exerciseParams)](src/OptionsCompounder.sol#L267)
                - [IERC20(asset).approve(flashloanParams.exerciserContract,0)](src/OptionsCompounder.sol#L270)
                - [underlyingToken.approve(swapper,balanceOfUnderlyingToken)](src/OptionsCompounder.sol#L280)
                - [underlyingToken.approve(swapper,0)](src/OptionsCompounder.sol#L292)
                - [IERC20(asset).approve(address(lendingPool),totalAmountToPay)](src/OptionsCompounder.sol#L315)
                - [IERC20(asset).safeTransfer(flashloanParams.sender,gainInPaymentToken)](src/OptionsCompounder.sol#L316)
        External calls sending eth:
        - [_exerciseOptionAndReturnDebt(assets[0],amounts[0],premiums[0],params)](src/OptionsCompounder.sol#L227)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
        State variables written after the call(s):
        - [flashloanFinished = true](src/OptionsCompounder.sol#L228)
        [OptionsCompounder.flashloanFinished](src/OptionsCompounder.sol#L48) can be used in cross function reentrancies:
        - [OptionsCompounder._harvestOTokens(uint256,address,uint256)](src/OptionsCompounder.sol#L164-L202)
        - [OptionsCompounder.executeOperation(address[],uint256[],uint256[],address,bytes)](src/OptionsCompounder.sol#L214-L230)
        - [OptionsCompounder.initialize(address,address,address,SwapProps,IOracle)](src/OptionsCompounder.sol#L74-L87)

src/OptionsCompounder.sol#L214-L230


## incorrect-equality
Impact: Medium
Confidence: High
 - [ ] ID-2
[OptionsCompounder._exerciseOptionAndReturnDebt(address,uint256,uint256,bytes)](src/OptionsCompounder.sol#L241-L320) uses a dangerous strict equality:
        - [swapAmountOut == 0](src/OptionsCompounder.sol#L287)

src/OptionsCompounder.sol#L241-L320


## unused-return
Impact: Medium
Confidence: Medium
 - [ ] ID-3
[OptionsCompounder._exerciseOptionAndReturnDebt(address,uint256,uint256,bytes)](src/OptionsCompounder.sol#L241-L320) ignores return value by [IERC20(asset).approve(flashloanParams.exerciserContract,0)](src/OptionsCompounder.sol#L270)

src/OptionsCompounder.sol#L241-L320


 - [ ] ID-4
[OptionsCompounder._exerciseOptionAndReturnDebt(address,uint256,uint256,bytes)](src/OptionsCompounder.sol#L241-L320) ignores return value by [IERC20(asset).approve(address(lendingPool),totalAmountToPay)](src/OptionsCompounder.sol#L315)

src/OptionsCompounder.sol#L241-L320


 - [ ] ID-5
[OptionsCompounder._exerciseOptionAndReturnDebt(address,uint256,uint256,bytes)](src/OptionsCompounder.sol#L241-L320) ignores return value by [underlyingToken.approve(swapper,balanceOfUnderlyingToken)](src/OptionsCompounder.sol#L280)

src/OptionsCompounder.sol#L241-L320


 - [ ] ID-6
[OptionsCompounder._exerciseOptionAndReturnDebt(address,uint256,uint256,bytes)](src/OptionsCompounder.sol#L241-L320) ignores return value by [underlyingToken.approve(swapper,0)](src/OptionsCompounder.sol#L292)

src/OptionsCompounder.sol#L241-L320


 - [ ] ID-7
[OptionsCompounder._exerciseOptionAndReturnDebt(address,uint256,uint256,bytes)](src/OptionsCompounder.sol#L241-L320) ignores return value by [IERC20(asset).approve(flashloanParams.exerciserContract,amount)](src/OptionsCompounder.sol#L265)

src/OptionsCompounder.sol#L241-L320


 - [ ] ID-8
[OptionsCompounder._exerciseOptionAndReturnDebt(address,uint256,uint256,bytes)](src/OptionsCompounder.sol#L241-L320) ignores return value by [optionsToken.exercise(flashloanParams.optionsAmount,address(this),flashloanParams.exerciserContract,exerciseParams)](src/OptionsCompounder.sol#L267)

src/OptionsCompounder.sol#L241-L320


## missing-zero-check
Impact: Low
Confidence: Medium
 - [ ] ID-9
[OptionsCompounder.initiateUpgradeCooldown(address)._nextImplementation](src/OptionsCompounder.sol#L326) lacks a zero-check on :
                - [nextImplementation = _nextImplementation](src/OptionsCompounder.sol#L328)

src/OptionsCompounder.sol#L326


## reentrancy-benign
Impact: Low
Confidence: Medium
 - [ ] ID-10
Reentrancy in [OptionsCompounder._harvestOTokens(uint256,address,uint256)](src/OptionsCompounder.sol#L164-L202):
        External calls:
        - [optionsToken.isExerciseContract(exerciseContract) == false](src/OptionsCompounder.sol#L166)
        State variables written after the call(s):
        - [flashloanFinished = false](src/OptionsCompounder.sol#L192)

src/OptionsCompounder.sol#L164-L202


## reentrancy-events
Impact: Low
Confidence: Medium
 - [ ] ID-11
Reentrancy in [OptionsCompounder._exerciseOptionAndReturnDebt(address,uint256,uint256,bytes)](src/OptionsCompounder.sol#L241-L320):
        External calls:
        - [IERC20(address(optionsToken)).safeTransferFrom(flashloanParams.sender,address(this),flashloanParams.optionsAmount)](src/OptionsCompounder.sol#L258)
        - [IERC20(asset).approve(flashloanParams.exerciserContract,amount)](src/OptionsCompounder.sol#L265)
        - [optionsToken.exercise(flashloanParams.optionsAmount,address(this),flashloanParams.exerciserContract,exerciseParams)](src/OptionsCompounder.sol#L267)
        - [IERC20(asset).approve(flashloanParams.exerciserContract,0)](src/OptionsCompounder.sol#L270)
        - [underlyingToken.approve(swapper,balanceOfUnderlyingToken)](src/OptionsCompounder.sol#L280)
        - [swapAmountOut = _generalSwap(swapProps.exchangeTypes,address(underlyingToken),asset,balanceOfUnderlyingToken,minAmountOut,swapProps.exchangeAddress)](src/OptionsCompounder.sol#L283-L285)
                - [_swapper.swapUniV2(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L72)
                - [_swapper.swapBal(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L74)
                - [_swapper.swapVelo(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L76)
                - [_swapper.swapUniV3(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L78)
        - [underlyingToken.approve(swapper,0)](src/OptionsCompounder.sol#L292)
        - [IERC20(asset).approve(address(lendingPool),totalAmountToPay)](src/OptionsCompounder.sol#L315)
        - [IERC20(asset).safeTransfer(flashloanParams.sender,gainInPaymentToken)](src/OptionsCompounder.sol#L316)
        Event emitted after the call(s):
        - [OTokenCompounded(gainInPaymentToken,totalAmountToPay)](src/OptionsCompounder.sol#L318)

src/OptionsCompounder.sol#L241-L320


## timestamp
Impact: Low
Confidence: Medium
 - [ ] ID-12
[OptionsCompounder._authorizeUpgrade(address)](src/OptionsCompounder.sol#L350-L354) uses timestamp for comparisons
        Dangerous comparisons:
        - [require(bool,string)(upgradeProposalTime + UPGRADE_TIMELOCK < block.timestamp,Upgrade cooldown not initiated or still ongoing)](src/OptionsCompounder.sol#L351)

src/OptionsCompounder.sol#L350-L354


## boolean-equal
Impact: Informational
Confidence: High
 - [ ] ID-13
[OptionsCompounder._harvestOTokens(uint256,address,uint256)](src/OptionsCompounder.sol#L164-L202) compares to a boolean constant:
        -[optionsToken.isExerciseContract(exerciseContract) == false](src/OptionsCompounder.sol#L166)

src/OptionsCompounder.sol#L164-L202


 - [ ] ID-14
[OptionsCompounder._harvestOTokens(uint256,address,uint256)](src/OptionsCompounder.sol#L164-L202) compares to a boolean constant:
        -[flashloanFinished == false](src/OptionsCompounder.sol#L170)

src/OptionsCompounder.sol#L164-L202


 - [ ] ID-15
[OptionsCompounder.executeOperation(address[],uint256[],uint256[],address,bytes)](src/OptionsCompounder.sol#L214-L230) compares to a boolean constant:
        -[flashloanFinished != false || msg.sender != address(lendingPool)](src/OptionsCompounder.sol#L219)

src/OptionsCompounder.sol#L214-L230


## pragma
Impact: Informational
Confidence: High
 - [ ] ID-16
11 different versions of Solidity are used:
        - Version constraint ^0.8.0 is used by:
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlEnumerableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC1967Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/interfaces/draft-IERC1822Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/proxy/beacon/IBeaconUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/StorageSlotUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/StringsUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/ERC165Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/IERC165Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol#L5)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/security/Pausable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/draft-IERC20Permit.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/utils/Context.sol#L4)
                -[^0.8.0](lib/v3-core/contracts/libraries/FullMath.sol#L2)
                -[^0.8.0](lib/v3-core/contracts/libraries/TickMath.sol#L2)
                -[^0.8.0](lib/vault-v2/src/ReaperSwapper.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/AggregatorV3Interface.sol#L4)
                -[^0.8.0](lib/vault-v2/src/interfaces/IAsset.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IAuthorizer.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBasePool.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBaseWeightedPool.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBeetVault.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IPoolSwapStructs.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISignaturesValidator.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapErrors.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapper.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapperSwaps.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ITemporarilyPausable.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IUniswapV2Router01.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloPair.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloRouter.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloV1AndV2Factory.sol#L2)
                -[^0.8.0](lib/vault-v2/src/libraries/Babylonian.sol#L3)
                -[^0.8.0](lib/vault-v2/src/libraries/ReaperMathUtils.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/BalMixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/ReaperAccessControl.sol#L5)
                -[^0.8.0](lib/vault-v2/src/mixins/UniV2Mixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/UniV3Mixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/VeloSolidMixin.sol#L3)
                -[^0.8.0](src/OptionsCompounder.sol#L3)
                -[^0.8.0](src/interfaces/IBalancerTwapOracle.sol#L15)
                -[^0.8.0](src/interfaces/IFlashLoanReceiver.sol#L2)
                -[^0.8.0](src/interfaces/ILendingPool.sol#L2)
                -[^0.8.0](src/interfaces/ILendingPoolAddressesProvider.sol#L2)
                -[^0.8.0](src/interfaces/IOptionsCompounder.sol#L3)
                -[^0.8.0](src/interfaces/ISwapperSwaps.sol#L3)
                -[^0.8.0](src/libraries/DataTypes.sol#L2)
        - Version constraint ^0.8.2 is used by:
                -[^0.8.2](lib/openzeppelin-contracts-upgradeable/contracts/proxy/ERC1967/ERC1967UpgradeUpgradeable.sol#L4)
                -[^0.8.2](lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol#L4)
        - Version constraint ^0.8.1 is used by:
                -[^0.8.1](lib/openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol#L4)
                -[^0.8.1](lib/openzeppelin-contracts/contracts/utils/Address.sol#L4)
        - Version constraint >=0.8.0 is used by:
                -[>=0.8.0](lib/solmate/src/auth/Owned.sol#L2)
                -[>=0.8.0](lib/solmate/src/tokens/ERC20.sol#L2)
                -[>=0.8.0](lib/solmate/src/utils/FixedPointMathLib.sol#L2)
        - Version constraint >=0.5.0 is used by:
                -[>=0.5.0](lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolErrors.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IPeripheryImmutableState.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IUniswapV3Factory.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IUniswapV3SwapCallback.sol#L2)
                -[>=0.5.0](src/interfaces/IAlgebraPool.sol#L2)
        - Version constraint >=0.7.5 is used by:
                -[>=0.7.5](lib/vault-v2/src/interfaces/ISwapRouter.sol#L2)
        - Version constraint >=0.6.2 is used by:
                -[>=0.6.2](lib/vault-v2/src/interfaces/IUniswapV2Router02.sol#L2)
        - Version constraint >=0.6.0 is used by:
                -[>=0.6.0](lib/vault-v2/src/libraries/TransferHelper.sol#L2)
        - Version constraint ^0.8.13 is used by:
                -[^0.8.13](src/OptionsToken.sol#L2)
                -[^0.8.13](src/exercise/BaseExercise.sol#L2)
                -[^0.8.13](src/exercise/DiscountExercise.sol#L2)
                -[^0.8.13](src/helpers/SwapHelper.sol#L3)
                -[^0.8.13](src/interfaces/IBalancer2TokensPool.sol#L2)
                -[^0.8.13](src/interfaces/IExercise.sol#L2)
                -[^0.8.13](src/interfaces/IOptionsToken.sol#L2)
                -[^0.8.13](src/oracles/AlgebraOracle.sol#L2)
                -[^0.8.13](src/oracles/BalancerOracle.sol#L2)
                -[^0.8.13](src/oracles/ThenaOracle.sol#L2)
                -[^0.8.13](src/oracles/UniswapV3Oracle.sol#L2)
        - Version constraint >=0.7.0<0.9.0 is used by:
                -[>=0.7.0<0.9.0](src/interfaces/IBalancerVault.sol#L17)
                -[>=0.7.0<0.9.0](src/interfaces/IERC20Mintable.sol#L3)
                -[>=0.7.0<0.9.0](src/interfaces/IOracle.sol#L3)
        - Version constraint >=0.5 is used by:
                -[>=0.5](src/interfaces/IThenaPair.sol#L1)

lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol#L4


## solc-version
Impact: Informational
Confidence: High
 - [ ] ID-17
Version constraint ^0.8.0 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
        - FullInlinerNonExpressionSplitArgumentEvaluationOrder
        - MissingSideEffectsOnSelectorAccess
        - AbiReencodingHeadOverflowWithStaticArrayCleanup
        - DirtyBytesArrayToStorage
        - DataLocationChangeInInternalOverride
        - NestedCalldataArrayAbiReencodingSizeValidation
        - SignedImmutables
        - ABIDecodeTwoDimensionalArrayMemory
        - KeccakCaching.
It is used by:
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlEnumerableUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC1967Upgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/interfaces/draft-IERC1822Upgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/proxy/beacon/IBeaconUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/StorageSlotUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/StringsUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/ERC165Upgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/IERC165Upgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol#L5)
        - [^0.8.0](lib/openzeppelin-contracts/contracts/security/Pausable.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/draft-IERC20Permit.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L4)
        - [^0.8.0](lib/openzeppelin-contracts/contracts/utils/Context.sol#L4)
        - [^0.8.0](lib/v3-core/contracts/libraries/FullMath.sol#L2)
        - [^0.8.0](lib/v3-core/contracts/libraries/TickMath.sol#L2)
        - [^0.8.0](lib/vault-v2/src/ReaperSwapper.sol#L3)
        - [^0.8.0](lib/vault-v2/src/interfaces/AggregatorV3Interface.sol#L4)
        - [^0.8.0](lib/vault-v2/src/interfaces/IAsset.sol#L3)
        - [^0.8.0](lib/vault-v2/src/interfaces/IAuthorizer.sol#L3)
        - [^0.8.0](lib/vault-v2/src/interfaces/IBasePool.sol#L3)
        - [^0.8.0](lib/vault-v2/src/interfaces/IBaseWeightedPool.sol#L3)
        - [^0.8.0](lib/vault-v2/src/interfaces/IBeetVault.sol#L3)
        - [^0.8.0](lib/vault-v2/src/interfaces/IPoolSwapStructs.sol#L3)
        - [^0.8.0](lib/vault-v2/src/interfaces/ISignaturesValidator.sol#L3)
        - [^0.8.0](lib/vault-v2/src/interfaces/ISwapErrors.sol#L3)
        - [^0.8.0](lib/vault-v2/src/interfaces/ISwapper.sol#L3)
        - [^0.8.0](lib/vault-v2/src/interfaces/ISwapperSwaps.sol#L3)
        - [^0.8.0](lib/vault-v2/src/interfaces/ITemporarilyPausable.sol#L3)
        - [^0.8.0](lib/vault-v2/src/interfaces/IUniswapV2Router01.sol#L2)
        - [^0.8.0](lib/vault-v2/src/interfaces/IVeloPair.sol#L2)
        - [^0.8.0](lib/vault-v2/src/interfaces/IVeloRouter.sol#L2)
        - [^0.8.0](lib/vault-v2/src/interfaces/IVeloV1AndV2Factory.sol#L2)
        - [^0.8.0](lib/vault-v2/src/libraries/Babylonian.sol#L3)
        - [^0.8.0](lib/vault-v2/src/libraries/ReaperMathUtils.sol#L3)
        - [^0.8.0](lib/vault-v2/src/mixins/BalMixin.sol#L3)
        - [^0.8.0](lib/vault-v2/src/mixins/ReaperAccessControl.sol#L5)
        - [^0.8.0](lib/vault-v2/src/mixins/UniV2Mixin.sol#L3)
        - [^0.8.0](lib/vault-v2/src/mixins/UniV3Mixin.sol#L3)
        - [^0.8.0](lib/vault-v2/src/mixins/VeloSolidMixin.sol#L3)
        - [^0.8.0](src/OptionsCompounder.sol#L3)
        - [^0.8.0](src/interfaces/IBalancerTwapOracle.sol#L15)
        - [^0.8.0](src/interfaces/IFlashLoanReceiver.sol#L2)
        - [^0.8.0](src/interfaces/ILendingPool.sol#L2)
        - [^0.8.0](src/interfaces/ILendingPoolAddressesProvider.sol#L2)
        - [^0.8.0](src/interfaces/IOptionsCompounder.sol#L3)
        - [^0.8.0](src/interfaces/ISwapperSwaps.sol#L3)
        - [^0.8.0](src/libraries/DataTypes.sol#L2)

lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol#L4


## missing-inheritance
Impact: Informational
Confidence: High
 - [ ] ID-18
[OptionsCompounder](src/OptionsCompounder.sol#L25-L370) should inherit from [IOptionsCompounder](src/interfaces/IOptionsCompounder.sol#L20-L24)

src/OptionsCompounder.sol#L25-L370


## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-19
Parameter [OptionsCompounder.initialize(address,address,address,SwapProps,IOracle)._optionsToken](src/OptionsCompounder.sol#L74) is not in mixedCase

src/OptionsCompounder.sol#L74


 - [ ] ID-20
Parameter [OptionsCompounder.initialize(address,address,address,SwapProps,IOracle)._swapper](src/OptionsCompounder.sol#L74) is not in mixedCase

src/OptionsCompounder.sol#L74


 - [ ] ID-21
Parameter [OptionsCompounder.initialize(address,address,address,SwapProps,IOracle)._oracle](src/OptionsCompounder.sol#L74) is not in mixedCase

src/OptionsCompounder.sol#L74


 - [ ] ID-22
Parameter [OptionsCompounder.initialize(address,address,address,SwapProps,IOracle)._swapProps](src/OptionsCompounder.sol#L74) is not in mixedCase

src/OptionsCompounder.sol#L74


 - [ ] ID-23
Parameter [OptionsCompounder.setSwapProps(SwapProps)._swapProps](src/OptionsCompounder.sol#L108) is not in mixedCase

src/OptionsCompounder.sol#L108


 - [ ] ID-24
Parameter [OptionsCompounder.setOracle(IOracle)._oracle](src/OptionsCompounder.sol#L112) is not in mixedCase

src/OptionsCompounder.sol#L112


 - [ ] ID-25
Function [OptionsCompounder.ADDRESSES_PROVIDER()](src/OptionsCompounder.sol#L363-L365) is not in mixedCase

src/OptionsCompounder.sol#L363-L365


 - [ ] ID-26
Parameter [OptionsCompounder.initialize(address,address,address,SwapProps,IOracle)._addressProvider](src/OptionsCompounder.sol#L74) is not in mixedCase

src/OptionsCompounder.sol#L74


 - [ ] ID-27
Parameter [OptionsCompounder.initiateUpgradeCooldown(address)._nextImplementation](src/OptionsCompounder.sol#L326) is not in mixedCase

src/OptionsCompounder.sol#L326


 - [ ] ID-28
Parameter [OptionsCompounder.setOptionsToken(address)._optionsToken](src/OptionsCompounder.sol#L97) is not in mixedCase

src/OptionsCompounder.sol#L97


 - [ ] ID-29
Parameter [OptionsCompounder.setSwapper(address)._swapper](src/OptionsCompounder.sol#L123) is not in mixedCase

src/OptionsCompounder.sol#L123


 - [ ] ID-30
Function [OptionsCompounder.LENDING_POOL()](src/OptionsCompounder.sol#L367-L369) is not in mixedCase

src/OptionsCompounder.sol#L367-L369


 - [ ] ID-31
Parameter [OptionsCompounder.setAddressProvider(address)._addressProvider](src/OptionsCompounder.sol#L134) is not in mixedCase

src/OptionsCompounder.sol#L134

## Options Token Slither

Summary
 - [missing-zero-check](#missing-zero-check) (2 results) (Low)
 - [reentrancy-events](#reentrancy-events) (1 results) (Low)
 - [timestamp](#timestamp) (1 results) (Low)
 - [pragma](#pragma) (1 results) (Informational)
 - [solc-version](#solc-version) (1 results) (Informational)
 - [naming-convention](#naming-convention) (3 results) (Informational)
## missing-zero-check
Impact: Low
Confidence: Medium
 - [ ] ID-0
[OptionsToken.initialize(string,string,address).tokenAdmin_](src/OptionsToken.sol#L60) lacks a zero-check on :
                - [tokenAdmin = tokenAdmin_](src/OptionsToken.sol#L65)

src/OptionsToken.sol#L60


 - [ ] ID-1
[OptionsToken.initiateUpgradeCooldown(address)._nextImplementation](src/OptionsToken.sol#L178) lacks a zero-check on :
                - [nextImplementation = _nextImplementation](src/OptionsToken.sol#L180)

src/OptionsToken.sol#L178


## reentrancy-events
Impact: Low
Confidence: Medium
 - [ ] ID-2
Reentrancy in [OptionsToken._exercise(uint256,address,address,bytes)](src/OptionsToken.sol#L144-L168):
        External calls:
        - [(paymentAmount,data0,data1,data2) = IExercise(option).exercise(msg.sender,amount,recipient,params)](src/OptionsToken.sol#L164)
        Event emitted after the call(s):
        - [Exercise(msg.sender,recipient,amount,data0,data1,data2)](src/OptionsToken.sol#L167)

src/OptionsToken.sol#L144-L168


## timestamp
Impact: Low
Confidence: Medium
 - [ ] ID-3
[OptionsToken._authorizeUpgrade(address)](src/OptionsToken.sol#L202-L206) uses timestamp for comparisons
        Dangerous comparisons:
        - [require(bool,string)(upgradeProposalTime + UPGRADE_TIMELOCK < block.timestamp,Upgrade cooldown not initiated or still ongoing)](src/OptionsToken.sol#L203)

src/OptionsToken.sol#L202-L206


## pragma
Impact: Informational
Confidence: High
 - [ ] ID-4
11 different versions of Solidity are used:
        - Version constraint ^0.8.0 is used by:
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlEnumerableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC1967Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/interfaces/draft-IERC1822Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/proxy/beacon/IBeaconUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/StorageSlotUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/StringsUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/ERC165Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/IERC165Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol#L5)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/security/Pausable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/draft-IERC20Permit.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/utils/Context.sol#L4)
                -[^0.8.0](lib/v3-core/contracts/libraries/FullMath.sol#L2)
                -[^0.8.0](lib/v3-core/contracts/libraries/TickMath.sol#L2)
                -[^0.8.0](lib/vault-v2/src/ReaperSwapper.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/AggregatorV3Interface.sol#L4)
                -[^0.8.0](lib/vault-v2/src/interfaces/IAsset.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IAuthorizer.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBasePool.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBaseWeightedPool.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBeetVault.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IPoolSwapStructs.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISignaturesValidator.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapErrors.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapper.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapperSwaps.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ITemporarilyPausable.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IUniswapV2Router01.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloPair.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloRouter.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloV1AndV2Factory.sol#L2)
                -[^0.8.0](lib/vault-v2/src/libraries/Babylonian.sol#L3)
                -[^0.8.0](lib/vault-v2/src/libraries/ReaperMathUtils.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/BalMixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/ReaperAccessControl.sol#L5)
                -[^0.8.0](lib/vault-v2/src/mixins/UniV2Mixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/UniV3Mixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/VeloSolidMixin.sol#L3)
                -[^0.8.0](src/OptionsCompounder.sol#L3)
                -[^0.8.0](src/interfaces/IBalancerTwapOracle.sol#L15)
                -[^0.8.0](src/interfaces/IFlashLoanReceiver.sol#L2)
                -[^0.8.0](src/interfaces/ILendingPool.sol#L2)
                -[^0.8.0](src/interfaces/ILendingPoolAddressesProvider.sol#L2)
                -[^0.8.0](src/interfaces/IOptionsCompounder.sol#L3)
                -[^0.8.0](src/interfaces/ISwapperSwaps.sol#L3)
                -[^0.8.0](src/libraries/DataTypes.sol#L2)
        - Version constraint ^0.8.2 is used by:
                -[^0.8.2](lib/openzeppelin-contracts-upgradeable/contracts/proxy/ERC1967/ERC1967UpgradeUpgradeable.sol#L4)
                -[^0.8.2](lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol#L4)
        - Version constraint ^0.8.1 is used by:
                -[^0.8.1](lib/openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol#L4)
                -[^0.8.1](lib/openzeppelin-contracts/contracts/utils/Address.sol#L4)
        - Version constraint >=0.8.0 is used by:
                -[>=0.8.0](lib/solmate/src/auth/Owned.sol#L2)
                -[>=0.8.0](lib/solmate/src/tokens/ERC20.sol#L2)
                -[>=0.8.0](lib/solmate/src/utils/FixedPointMathLib.sol#L2)
        - Version constraint >=0.5.0 is used by:
                -[>=0.5.0](lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolErrors.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IPeripheryImmutableState.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IUniswapV3Factory.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IUniswapV3SwapCallback.sol#L2)
                -[>=0.5.0](src/interfaces/IAlgebraPool.sol#L2)
        - Version constraint >=0.7.5 is used by:
                -[>=0.7.5](lib/vault-v2/src/interfaces/ISwapRouter.sol#L2)
        - Version constraint >=0.6.2 is used by:
                -[>=0.6.2](lib/vault-v2/src/interfaces/IUniswapV2Router02.sol#L2)
        - Version constraint >=0.6.0 is used by:
                -[>=0.6.0](lib/vault-v2/src/libraries/TransferHelper.sol#L2)
        - Version constraint ^0.8.13 is used by:
                -[^0.8.13](src/OptionsToken.sol#L2)
                -[^0.8.13](src/exercise/BaseExercise.sol#L2)
                -[^0.8.13](src/exercise/DiscountExercise.sol#L2)
                -[^0.8.13](src/helpers/SwapHelper.sol#L3)
                -[^0.8.13](src/interfaces/IBalancer2TokensPool.sol#L2)
                -[^0.8.13](src/interfaces/IExercise.sol#L2)
                -[^0.8.13](src/interfaces/IOptionsToken.sol#L2)
                -[^0.8.13](src/oracles/AlgebraOracle.sol#L2)
                -[^0.8.13](src/oracles/BalancerOracle.sol#L2)
                -[^0.8.13](src/oracles/ThenaOracle.sol#L2)
                -[^0.8.13](src/oracles/UniswapV3Oracle.sol#L2)
        - Version constraint >=0.7.0<0.9.0 is used by:
                -[>=0.7.0<0.9.0](src/interfaces/IBalancerVault.sol#L17)
                -[>=0.7.0<0.9.0](src/interfaces/IERC20Mintable.sol#L3)
                -[>=0.7.0<0.9.0](src/interfaces/IOracle.sol#L3)
        - Version constraint >=0.5 is used by:
                -[>=0.5](src/interfaces/IThenaPair.sol#L1)

lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol#L4


## solc-version
Impact: Informational
Confidence: High
 - [ ] ID-5
Version constraint ^0.8.13 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
        - VerbatimInvalidDeduplication
        - FullInlinerNonExpressionSplitArgumentEvaluationOrder
        - MissingSideEffectsOnSelectorAccess
        - StorageWriteRemovalBeforeConditionalTermination
        - AbiReencodingHeadOverflowWithStaticArrayCleanup
        - DirtyBytesArrayToStorage
        - InlineAssemblyMemorySideEffects
        - DataLocationChangeInInternalOverride
        - NestedCalldataArrayAbiReencodingSizeValidation.
It is used by:
        - [^0.8.13](src/OptionsToken.sol#L2)
        - [^0.8.13](src/exercise/BaseExercise.sol#L2)
        - [^0.8.13](src/exercise/DiscountExercise.sol#L2)
        - [^0.8.13](src/helpers/SwapHelper.sol#L3)
        - [^0.8.13](src/interfaces/IBalancer2TokensPool.sol#L2)
        - [^0.8.13](src/interfaces/IExercise.sol#L2)
        - [^0.8.13](src/interfaces/IOptionsToken.sol#L2)
        - [^0.8.13](src/oracles/AlgebraOracle.sol#L2)
        - [^0.8.13](src/oracles/BalancerOracle.sol#L2)
        - [^0.8.13](src/oracles/ThenaOracle.sol#L2)
        - [^0.8.13](src/oracles/UniswapV3Oracle.sol#L2)

src/OptionsToken.sol#L2


## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-6
Parameter [OptionsToken.initiateUpgradeCooldown(address)._nextImplementation](src/OptionsToken.sol#L178) is not in mixedCase

src/OptionsToken.sol#L178


 - [ ] ID-7
Parameter [OptionsToken.setExerciseContract(address,bool)._isExercise](src/OptionsToken.sol#L125) is not in mixedCase

src/OptionsToken.sol#L125


 - [ ] ID-8
Parameter [OptionsToken.setExerciseContract(address,bool)._address](src/OptionsToken.sol#L125) is not in mixedCase

src/OptionsToken.sol#L125

## Thena Oracle Slither

Summary
 - [pragma](#pragma) (1 results) (Informational)
 - [solc-version](#solc-version) (1 results) (Informational)
 - [immutable-states](#immutable-states) (1 results) (Optimization)
## pragma
Impact: Informational
Confidence: High
 - [ ] ID-0
11 different versions of Solidity are used:
        - Version constraint ^0.8.0 is used by:
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlEnumerableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC1967Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/interfaces/draft-IERC1822Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/proxy/beacon/IBeaconUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/StorageSlotUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/StringsUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/ERC165Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/IERC165Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol#L5)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/security/Pausable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/draft-IERC20Permit.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/utils/Context.sol#L4)
                -[^0.8.0](lib/v3-core/contracts/libraries/FullMath.sol#L2)
                -[^0.8.0](lib/v3-core/contracts/libraries/TickMath.sol#L2)
                -[^0.8.0](lib/vault-v2/src/ReaperSwapper.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/AggregatorV3Interface.sol#L4)
                -[^0.8.0](lib/vault-v2/src/interfaces/IAsset.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IAuthorizer.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBasePool.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBaseWeightedPool.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBeetVault.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IPoolSwapStructs.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISignaturesValidator.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapErrors.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapper.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapperSwaps.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ITemporarilyPausable.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IUniswapV2Router01.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloPair.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloRouter.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloV1AndV2Factory.sol#L2)
                -[^0.8.0](lib/vault-v2/src/libraries/Babylonian.sol#L3)
                -[^0.8.0](lib/vault-v2/src/libraries/ReaperMathUtils.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/BalMixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/ReaperAccessControl.sol#L5)
                -[^0.8.0](lib/vault-v2/src/mixins/UniV2Mixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/UniV3Mixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/VeloSolidMixin.sol#L3)
                -[^0.8.0](src/OptionsCompounder.sol#L3)
                -[^0.8.0](src/interfaces/IBalancerTwapOracle.sol#L15)
                -[^0.8.0](src/interfaces/IFlashLoanReceiver.sol#L2)
                -[^0.8.0](src/interfaces/ILendingPool.sol#L2)
                -[^0.8.0](src/interfaces/ILendingPoolAddressesProvider.sol#L2)
                -[^0.8.0](src/interfaces/IOptionsCompounder.sol#L3)
                -[^0.8.0](src/interfaces/ISwapperSwaps.sol#L3)
                -[^0.8.0](src/libraries/DataTypes.sol#L2)
        - Version constraint ^0.8.2 is used by:
                -[^0.8.2](lib/openzeppelin-contracts-upgradeable/contracts/proxy/ERC1967/ERC1967UpgradeUpgradeable.sol#L4)
                -[^0.8.2](lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol#L4)
        - Version constraint ^0.8.1 is used by:
                -[^0.8.1](lib/openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol#L4)
                -[^0.8.1](lib/openzeppelin-contracts/contracts/utils/Address.sol#L4)
        - Version constraint >=0.8.0 is used by:
                -[>=0.8.0](lib/solmate/src/auth/Owned.sol#L2)
                -[>=0.8.0](lib/solmate/src/tokens/ERC20.sol#L2)
                -[>=0.8.0](lib/solmate/src/utils/FixedPointMathLib.sol#L2)
        - Version constraint >=0.5.0 is used by:
                -[>=0.5.0](lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolErrors.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IPeripheryImmutableState.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IUniswapV3Factory.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IUniswapV3SwapCallback.sol#L2)
                -[>=0.5.0](src/interfaces/IAlgebraPool.sol#L2)
        - Version constraint >=0.7.5 is used by:
                -[>=0.7.5](lib/vault-v2/src/interfaces/ISwapRouter.sol#L2)
        - Version constraint >=0.6.2 is used by:
                -[>=0.6.2](lib/vault-v2/src/interfaces/IUniswapV2Router02.sol#L2)
        - Version constraint >=0.6.0 is used by:
                -[>=0.6.0](lib/vault-v2/src/libraries/TransferHelper.sol#L2)
        - Version constraint ^0.8.13 is used by:
                -[^0.8.13](src/OptionsToken.sol#L2)
                -[^0.8.13](src/exercise/BaseExercise.sol#L2)
                -[^0.8.13](src/exercise/DiscountExercise.sol#L2)
                -[^0.8.13](src/helpers/SwapHelper.sol#L3)
                -[^0.8.13](src/interfaces/IBalancer2TokensPool.sol#L2)
                -[^0.8.13](src/interfaces/IExercise.sol#L2)
                -[^0.8.13](src/interfaces/IOptionsToken.sol#L2)
                -[^0.8.13](src/oracles/AlgebraOracle.sol#L2)
                -[^0.8.13](src/oracles/BalancerOracle.sol#L2)
                -[^0.8.13](src/oracles/ThenaOracle.sol#L2)
                -[^0.8.13](src/oracles/UniswapV3Oracle.sol#L2)
        - Version constraint >=0.7.0<0.9.0 is used by:
                -[>=0.7.0<0.9.0](src/interfaces/IBalancerVault.sol#L17)
                -[>=0.7.0<0.9.0](src/interfaces/IERC20Mintable.sol#L3)
                -[>=0.7.0<0.9.0](src/interfaces/IOracle.sol#L3)
        - Version constraint >=0.5 is used by:
                -[>=0.5](src/interfaces/IThenaPair.sol#L1)

lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol#L4


## solc-version
Impact: Informational
Confidence: High
 - [ ] ID-1
Version constraint ^0.8.13 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
        - VerbatimInvalidDeduplication
        - FullInlinerNonExpressionSplitArgumentEvaluationOrder
        - MissingSideEffectsOnSelectorAccess
        - StorageWriteRemovalBeforeConditionalTermination
        - AbiReencodingHeadOverflowWithStaticArrayCleanup
        - DirtyBytesArrayToStorage
        - InlineAssemblyMemorySideEffects
        - DataLocationChangeInInternalOverride
        - NestedCalldataArrayAbiReencodingSizeValidation.
It is used by:
        - [^0.8.13](src/OptionsToken.sol#L2)
        - [^0.8.13](src/exercise/BaseExercise.sol#L2)
        - [^0.8.13](src/exercise/DiscountExercise.sol#L2)
        - [^0.8.13](src/helpers/SwapHelper.sol#L3)
        - [^0.8.13](src/interfaces/IBalancer2TokensPool.sol#L2)
        - [^0.8.13](src/interfaces/IExercise.sol#L2)
        - [^0.8.13](src/interfaces/IOptionsToken.sol#L2)
        - [^0.8.13](src/oracles/AlgebraOracle.sol#L2)
        - [^0.8.13](src/oracles/BalancerOracle.sol#L2)
        - [^0.8.13](src/oracles/ThenaOracle.sol#L2)
        - [^0.8.13](src/oracles/UniswapV3Oracle.sol#L2)

src/OptionsToken.sol#L2


## immutable-states
Impact: Optimization
Confidence: High
 - [ ] ID-2
[ThenaOracle.isToken0](src/oracles/ThenaOracle.sol#L60) should be immutable 

src/oracles/ThenaOracle.sol#L60

## Base Exercise Slither

Summary
 - [arbitrary-send-erc20](#arbitrary-send-erc20) (2 results) (High)
 - [reentrancy-events](#reentrancy-events) (5 results) (Low)
 - [pragma](#pragma) (1 results) (Informational)
 - [solc-version](#solc-version) (1 results) (Informational)
 - [naming-convention](#naming-convention) (2 results) (Informational)
## arbitrary-send-erc20
Impact: High
Confidence: High
 - [ ] ID-0
[BaseExercise.distributeFeesFrom(uint256,IERC20,address)](src/exercise/BaseExercise.sol#L73-L82) uses arbitrary from in transferFrom: [token.safeTransferFrom(from,feeRecipients[i],feeAmount)](src/exercise/BaseExercise.sol#L77)

src/exercise/BaseExercise.sol#L73-L82


 - [ ] ID-1
[BaseExercise.distributeFeesFrom(uint256,IERC20,address)](src/exercise/BaseExercise.sol#L73-L82) uses arbitrary from in transferFrom: [token.safeTransferFrom(from,feeRecipients[feeRecipients.length - 1],remaining)](src/exercise/BaseExercise.sol#L80)

src/exercise/BaseExercise.sol#L73-L82


## reentrancy-events
Impact: Low
Confidence: Medium
 - [ ] ID-2
Reentrancy in [DiscountExercise._zap(address,uint256,address,DiscountExerciseParams)](src/exercise/DiscountExercise.sol#L211-L249):
        External calls:
        - [underlyingToken.approve(swapProps.swapper,feeAmount)](src/exercise/DiscountExercise.sol#L228)
        - [amountOut = _generalSwap(swapProps.exchangeTypes,address(underlyingToken),address(paymentToken),feeAmount,minAmountOut,swapProps.exchangeAddress)](src/exercise/DiscountExercise.sol#L230-L232)
                - [_swapper.swapUniV2(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L72)
                - [_swapper.swapBal(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L74)
                - [_swapper.swapVelo(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L76)
                - [_swapper.swapUniV3(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L78)
        - [underlyingToken.approve(swapProps.swapper,0)](src/exercise/DiscountExercise.sol#L239)
        - [distributeFees(paymentToken.balanceOf(address(this)),paymentToken)](src/exercise/DiscountExercise.sol#L242)
                - [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L110)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
                - [token.safeTransfer(feeRecipients[i],feeAmount)](src/exercise/BaseExercise.sol#L90)
                - [token.safeTransfer(feeRecipients[feeRecipients.length - 1],remaining)](src/exercise/BaseExercise.sol#L93)
        - [_pay(recipient,underlyingAmount)](src/exercise/DiscountExercise.sol#L246)
                - [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L110)
                - [underlyingToken.safeTransfer(to,balance)](src/exercise/DiscountExercise.sol#L272)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
                - [underlyingToken.safeTransfer(to,amount)](src/exercise/DiscountExercise.sol#L275)
        External calls sending eth:
        - [distributeFees(paymentToken.balanceOf(address(this)),paymentToken)](src/exercise/DiscountExercise.sol#L242)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
        - [_pay(recipient,underlyingAmount)](src/exercise/DiscountExercise.sol#L246)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
        Event emitted after the call(s):
        - [Exercised(from,recipient,underlyingAmount,paymentAmount)](src/exercise/DiscountExercise.sol#L248)

src/exercise/DiscountExercise.sol#L211-L249


 - [ ] ID-3
Reentrancy in [BaseExercise.distributeFees(uint256,IERC20)](src/exercise/BaseExercise.sol#L86-L95):
        External calls:
        - [token.safeTransfer(feeRecipients[i],feeAmount)](src/exercise/BaseExercise.sol#L90)
        - [token.safeTransfer(feeRecipients[feeRecipients.length - 1],remaining)](src/exercise/BaseExercise.sol#L93)
        Event emitted after the call(s):
        - [DistributeFees(feeRecipients,feeBPS,totalAmount)](src/exercise/BaseExercise.sol#L94)

src/exercise/BaseExercise.sol#L86-L95


 - [ ] ID-4
Reentrancy in [DiscountExercise._zap(address,uint256,address,DiscountExerciseParams)](src/exercise/DiscountExercise.sol#L211-L249):
        External calls:
        - [underlyingToken.approve(swapProps.swapper,feeAmount)](src/exercise/DiscountExercise.sol#L228)
        - [amountOut = _generalSwap(swapProps.exchangeTypes,address(underlyingToken),address(paymentToken),feeAmount,minAmountOut,swapProps.exchangeAddress)](src/exercise/DiscountExercise.sol#L230-L232)
                - [_swapper.swapUniV2(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L72)
                - [_swapper.swapBal(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L74)
                - [_swapper.swapVelo(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L76)
                - [_swapper.swapUniV3(tokenIn,tokenOut,amount,minAmountOutData,exchangeAddress)](src/helpers/SwapHelper.sol#L78)
        - [underlyingToken.approve(swapProps.swapper,0)](src/exercise/DiscountExercise.sol#L239)
        - [distributeFees(paymentToken.balanceOf(address(this)),paymentToken)](src/exercise/DiscountExercise.sol#L242)
                - [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L110)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
                - [token.safeTransfer(feeRecipients[i],feeAmount)](src/exercise/BaseExercise.sol#L90)
                - [token.safeTransfer(feeRecipients[feeRecipients.length - 1],remaining)](src/exercise/BaseExercise.sol#L93)
        External calls sending eth:
        - [distributeFees(paymentToken.balanceOf(address(this)),paymentToken)](src/exercise/DiscountExercise.sol#L242)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
        Event emitted after the call(s):
        - [DistributeFees(feeRecipients,feeBPS,totalAmount)](src/exercise/BaseExercise.sol#L94)
                - [distributeFees(paymentToken.balanceOf(address(this)),paymentToken)](src/exercise/DiscountExercise.sol#L242)

src/exercise/DiscountExercise.sol#L211-L249


 - [ ] ID-5
Reentrancy in [DiscountExercise._redeem(address,uint256,address,DiscountExerciseParams)](src/exercise/DiscountExercise.sol#L252-L267):
        External calls:
        - [distributeFeesFrom(paymentAmount,paymentToken,from)](src/exercise/DiscountExercise.sol#L262)
                - [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L110)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
                - [token.safeTransferFrom(from,feeRecipients[i],feeAmount)](src/exercise/BaseExercise.sol#L77)
                - [token.safeTransferFrom(from,feeRecipients[feeRecipients.length - 1],remaining)](src/exercise/BaseExercise.sol#L80)
        - [_pay(recipient,amount)](src/exercise/DiscountExercise.sol#L264)
                - [returndata = address(token).functionCall(data,SafeERC20: low-level call failed)](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L110)
                - [underlyingToken.safeTransfer(to,balance)](src/exercise/DiscountExercise.sol#L272)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
                - [underlyingToken.safeTransfer(to,amount)](src/exercise/DiscountExercise.sol#L275)
        External calls sending eth:
        - [distributeFeesFrom(paymentAmount,paymentToken,from)](src/exercise/DiscountExercise.sol#L262)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
        - [_pay(recipient,amount)](src/exercise/DiscountExercise.sol#L264)
                - [(success,returndata) = target.call{value: value}(data)](lib/openzeppelin-contracts/contracts/utils/Address.sol#L135)
        Event emitted after the call(s):
        - [Exercised(from,recipient,amount,paymentAmount)](src/exercise/DiscountExercise.sol#L266)

src/exercise/DiscountExercise.sol#L252-L267


 - [ ] ID-6
Reentrancy in [BaseExercise.distributeFeesFrom(uint256,IERC20,address)](src/exercise/BaseExercise.sol#L73-L82):
        External calls:
        - [token.safeTransferFrom(from,feeRecipients[i],feeAmount)](src/exercise/BaseExercise.sol#L77)
        - [token.safeTransferFrom(from,feeRecipients[feeRecipients.length - 1],remaining)](src/exercise/BaseExercise.sol#L80)
        Event emitted after the call(s):
        - [DistributeFees(feeRecipients,feeBPS,totalAmount)](src/exercise/BaseExercise.sol#L81)

src/exercise/BaseExercise.sol#L73-L82


## pragma
Impact: Informational
Confidence: High
 - [ ] ID-7
11 different versions of Solidity are used:
        - Version constraint ^0.8.0 is used by:
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlEnumerableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/IAccessControlUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC1967Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/interfaces/draft-IERC1822Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/proxy/beacon/IBeaconUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/StorageSlotUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/StringsUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/ERC165Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/IERC165Upgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol#L5)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/security/Pausable.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/draft-IERC20Permit.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol#L4)
                -[^0.8.0](lib/openzeppelin-contracts/contracts/utils/Context.sol#L4)
                -[^0.8.0](lib/v3-core/contracts/libraries/FullMath.sol#L2)
                -[^0.8.0](lib/v3-core/contracts/libraries/TickMath.sol#L2)
                -[^0.8.0](lib/vault-v2/src/ReaperSwapper.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/AggregatorV3Interface.sol#L4)
                -[^0.8.0](lib/vault-v2/src/interfaces/IAsset.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IAuthorizer.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBasePool.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBaseWeightedPool.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IBeetVault.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IPoolSwapStructs.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISignaturesValidator.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapErrors.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapper.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ISwapperSwaps.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/ITemporarilyPausable.sol#L3)
                -[^0.8.0](lib/vault-v2/src/interfaces/IUniswapV2Router01.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloPair.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloRouter.sol#L2)
                -[^0.8.0](lib/vault-v2/src/interfaces/IVeloV1AndV2Factory.sol#L2)
                -[^0.8.0](lib/vault-v2/src/libraries/Babylonian.sol#L3)
                -[^0.8.0](lib/vault-v2/src/libraries/ReaperMathUtils.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/BalMixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/ReaperAccessControl.sol#L5)
                -[^0.8.0](lib/vault-v2/src/mixins/UniV2Mixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/UniV3Mixin.sol#L3)
                -[^0.8.0](lib/vault-v2/src/mixins/VeloSolidMixin.sol#L3)
                -[^0.8.0](src/OptionsCompounder.sol#L3)
                -[^0.8.0](src/interfaces/IBalancerTwapOracle.sol#L15)
                -[^0.8.0](src/interfaces/IFlashLoanReceiver.sol#L2)
                -[^0.8.0](src/interfaces/ILendingPool.sol#L2)
                -[^0.8.0](src/interfaces/ILendingPoolAddressesProvider.sol#L2)
                -[^0.8.0](src/interfaces/IOptionsCompounder.sol#L3)
                -[^0.8.0](src/interfaces/ISwapperSwaps.sol#L3)
                -[^0.8.0](src/libraries/DataTypes.sol#L2)
        - Version constraint ^0.8.2 is used by:
                -[^0.8.2](lib/openzeppelin-contracts-upgradeable/contracts/proxy/ERC1967/ERC1967UpgradeUpgradeable.sol#L4)
                -[^0.8.2](lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol#L4)
        - Version constraint ^0.8.1 is used by:
                -[^0.8.1](lib/openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol#L4)
                -[^0.8.1](lib/openzeppelin-contracts/contracts/utils/Address.sol#L4)
        - Version constraint >=0.8.0 is used by:
                -[>=0.8.0](lib/solmate/src/auth/Owned.sol#L2)
                -[>=0.8.0](lib/solmate/src/tokens/ERC20.sol#L2)
                -[>=0.8.0](lib/solmate/src/utils/FixedPointMathLib.sol#L2)
        - Version constraint >=0.5.0 is used by:
                -[>=0.5.0](lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolErrors.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol#L2)
                -[>=0.5.0](lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IPeripheryImmutableState.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IUniswapV3Factory.sol#L2)
                -[>=0.5.0](lib/vault-v2/src/interfaces/IUniswapV3SwapCallback.sol#L2)
                -[>=0.5.0](src/interfaces/IAlgebraPool.sol#L2)
        - Version constraint >=0.7.5 is used by:
                -[>=0.7.5](lib/vault-v2/src/interfaces/ISwapRouter.sol#L2)
        - Version constraint >=0.6.2 is used by:
                -[>=0.6.2](lib/vault-v2/src/interfaces/IUniswapV2Router02.sol#L2)
        - Version constraint >=0.6.0 is used by:
                -[>=0.6.0](lib/vault-v2/src/libraries/TransferHelper.sol#L2)
        - Version constraint ^0.8.13 is used by:
                -[^0.8.13](src/OptionsToken.sol#L2)
                -[^0.8.13](src/exercise/BaseExercise.sol#L2)
                -[^0.8.13](src/exercise/DiscountExercise.sol#L2)
                -[^0.8.13](src/helpers/SwapHelper.sol#L3)
                -[^0.8.13](src/interfaces/IBalancer2TokensPool.sol#L2)
                -[^0.8.13](src/interfaces/IExercise.sol#L2)
                -[^0.8.13](src/interfaces/IOptionsToken.sol#L2)
                -[^0.8.13](src/oracles/AlgebraOracle.sol#L2)
                -[^0.8.13](src/oracles/BalancerOracle.sol#L2)
                -[^0.8.13](src/oracles/ThenaOracle.sol#L2)
                -[^0.8.13](src/oracles/UniswapV3Oracle.sol#L2)
        - Version constraint >=0.7.0<0.9.0 is used by:
                -[>=0.7.0<0.9.0](src/interfaces/IBalancerVault.sol#L17)
                -[>=0.7.0<0.9.0](src/interfaces/IERC20Mintable.sol#L3)
                -[>=0.7.0<0.9.0](src/interfaces/IOracle.sol#L3)
        - Version constraint >=0.5 is used by:
                -[>=0.5](src/interfaces/IThenaPair.sol#L1)

lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol#L4


## solc-version
Impact: Informational
Confidence: High
 - [ ] ID-8
Version constraint ^0.8.13 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
        - VerbatimInvalidDeduplication
        - FullInlinerNonExpressionSplitArgumentEvaluationOrder
        - MissingSideEffectsOnSelectorAccess
        - StorageWriteRemovalBeforeConditionalTermination
        - AbiReencodingHeadOverflowWithStaticArrayCleanup
        - DirtyBytesArrayToStorage
        - InlineAssemblyMemorySideEffects
        - DataLocationChangeInInternalOverride
        - NestedCalldataArrayAbiReencodingSizeValidation.
It is used by:
        - [^0.8.13](src/OptionsToken.sol#L2)
        - [^0.8.13](src/exercise/BaseExercise.sol#L2)
        - [^0.8.13](src/exercise/DiscountExercise.sol#L2)
        - [^0.8.13](src/helpers/SwapHelper.sol#L3)
        - [^0.8.13](src/interfaces/IBalancer2TokensPool.sol#L2)
        - [^0.8.13](src/interfaces/IExercise.sol#L2)
        - [^0.8.13](src/interfaces/IOptionsToken.sol#L2)
        - [^0.8.13](src/oracles/AlgebraOracle.sol#L2)
        - [^0.8.13](src/oracles/BalancerOracle.sol#L2)
        - [^0.8.13](src/oracles/ThenaOracle.sol#L2)
        - [^0.8.13](src/oracles/UniswapV3Oracle.sol#L2)

src/OptionsToken.sol#L2


## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-9
Parameter [BaseExercise.setFees(address[],uint256[])._feeRecipients](src/exercise/BaseExercise.sol#L55) is not in mixedCase

src/exercise/BaseExercise.sol#L55


 - [ ] ID-10
Parameter [BaseExercise.setFees(address[],uint256[])._feeBPS](src/exercise/BaseExercise.sol#L55) is not in mixedCase

src/exercise/BaseExercise.sol#L55

# Frontend Integration

Frontend shall allow to go through 3 different scenarios:
- Pay [PaymentTokens](#paymenttoken) to [**redeem**](#redeem-flow) [UnderlyingTokens](#underlyingtoken) from OptionsTokens
- [**Zap**](#zap-flow) OptionsTokens into the [UnderlyingTokens](#underlyingtoken)
- [**Claim**](#claim-flow---optional) not exercised [UnderlyingTokens](#underlyingtoken) (due to lack of funds in exercise contract) -> this is probably optional frontend feature

## Redeem flow
 - Standard ERC20 approve action on [PaymentToken](#paymenttoken) 
   - Note: `getPaymentAmount(uint256 amount)` interface may be usefull to get correct amount of PaymentToken needed.
 - Exercise optionsToken with following parameters:
   - amount of options tokens to spend (defined by user)
   - recipient of the [UnderlyingTokens](#underlyingtoken) transferred during exercise (user address)
   - option of the exercise -> it is DiscountExercise contract address
   - encoded params:
     - maxPaymentAmount - calculated maximal payment amount (amount * price * multiplier). Price can be get from oracle contract using interface `getPrice()`. Multiplier can be get from DiscountExercise contract using interface `multiplier()`
     - deadline - current block timestamp
     - isInstantExit - determines whether it is redeem (false) or zap (true) action. **Shall be hardcoded to false.**
 - Events emitted:
   - `Exercise(address indexed sender, address indexed recipient, uint256 amount, address data0, uint256 data1, uint256 data2)` - from OptionsToken contract. data0, data1, data2 - are not used in this case.
   - `Exercised(from, recipient, underlyingAmount, paymentAmount)` from DiscountExercise contract
 - Note: Amount of [UnderlyingTokens](#underlyingtoken) to receive from redeeming is the same amount that is specified for optionsTokens.

## Zap flow
 - Call `exercise(uint256 amount, address recipient, address option, bytes calldata params)` from  optionsToken contract with following parameters:
   - amount of options tokens to spend (defined by user)
   - recipient of the [UnderlyingTokens](#underlyingtoken) transferred during exercise (user address)
   - option of the exercise -> it is DiscountExercise contract address
   - encoded params:
     - maxPaymentAmount - calculated maximal payment amount (amount * price * multiplier). Price can be get from oracle contract using interface `getPrice()`. Multiplier can be get from DiscountExercise contract using interface `multiplier()`
     - deadline - current block timestamp
     - isInstantExit - determines whether it is redeem (false) or zap (true) action. **Shall be hardcoded to true.**
 - Events emitted:
   - `Exercise(address indexed sender, address indexed recipient, uint256 amount, address data0, uint256 data1, uint256 data2)` - from OptionsToken contract. data0, data1, data2 - are not used in this case.
   - `Exercised(from, recipient, underlyingAmount, paymentAmount)` from DiscountExercise contract
 - Note: Amount of [UnderlyingTokens](#underlyingtoken) to receive from zapping is: amountOfOTokens * (1 - multiplier) * (1 - instantExitFee). Everything is denominated in BPS (10 000). InstantExitFee can be get by calling `instantExitFee()`.
 - Note: `getPaymentAmount(uint256 amount)` interface may be usefull to get correct amount of PaymentToken needed.
 - Note: Usually swap action happens here so standard events for swapping are here, but contract handles all actions like approvals etc

## Claim flow - optional
- Call `claim(address to)` with address of recipient of the [UnderlyingTokens](#underlyingtoken) transferred during claiming process
- `Claimed(amount)` event is emitted

## Changelog
Main change between version 1.0.0 deployed on Harbor is the zap feature which requires additional variable in `params` argument (`isInstantExit`) of the `exercise(uint256 amount, address recipient, address option, bytes calldata params)` interface. 
Now frontend shall allow to obtain [UnderlyingTokens](#underlyingtoken) in two ways (redeem and zap).

## Legend
### PaymentToken
Token used to pay for exercising options token. Ironclad -> MODE, Harbor -> WBNB
### UnderlyingToken
Token which can be obtained from exercising. Ironclad -> ICL, Harbor -> HBR

