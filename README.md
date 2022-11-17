# OptionsToken

An options token representing the right to purchase the underlying token at an oracle-specified rate. It's similar to a call option but with a variable strike price that's always at a certain discount to the market price.
It also has no expiry date.

## Installation

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

### Testing

```
forge test
```