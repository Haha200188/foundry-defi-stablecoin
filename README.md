# Foundry Defi Stablecoin Project

## 1. Relative Stability: Anchored or Pegged -> $1.00

- **Chainlink Price feed**:
  - Using Chainlink's decentralized oracle network to get accurate and reliable market data for pricing assets such as ETH and BTC.
- **Function for exchange**:
  - A function is set up to allow users to exchange ETH and BTC for the stablecoin (represented as $$$ in the contract).

## 2. Stability Mechanism (Minting): Algorithmic (Decentralized)

- Users can only mint the stablecoin by providing enough collateral. This rule is enforced through code to ensure the value of the minted stablecoin is always backed by sufficient assets.

## 3. Collateral: Exogenous (Crypto)

- **wETH** (Wrapped Ethereum):
  - Wrapped Ethereum (wETH) is an ERC-20 token pegged 1:1 to Ethereum (ETH), and is used as collateral.
- **wBTC** (Wrapped Bitcoin):
  - Wrapped Bitcoin (wBTC) is an ERC-20 token pegged 1:1 to Bitcoin (BTC), and is used as collateral.

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
