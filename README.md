# Behodler3 Tokenlaunch

Bootstrap AMM using Virtual Pair architecture for token launches.

## Architecture

This project uses an external vault dependency via git submodules. The vault contracts are imported from the [reflax-yield-vault](https://github.com/Behodler/reflax-yield-vault) repository to avoid code duplication and maintain a clean separation of concerns.

## Dependencies

### Vault Submodule

The vault functionality is provided by an external git submodule located at `lib/vault/`. This submodule points to the reflax-yield-vault repository.

#### Submodule Setup

When cloning this repository, initialize the submodules:

```shell
git submodule update --init --recursive
```

#### Import Paths

Vault contracts are imported using the `@vault/` remapping:
- `@vault/interfaces/IVault.sol` - Vault interface
- `@vault/mocks/MockVault.sol` - Mock vault for testing
- `@vault/Vault.sol` - Base vault contract

### Remappings

The project uses the following import remappings in `remappings.txt`:
```
@openzeppelin=lib/openzeppelin-contracts
@vault/=lib/vault/src/
vault-contracts/=lib/vault/src/contracts/
vault-interfaces/=lib/vault/src/interfaces/
```

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

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

## Submodule Management

### Update Vault Dependency

To update the vault submodule to the latest version:

```shell
cd lib/vault
git pull origin master
cd ../..
git add lib/vault
git commit -m "Update vault submodule to latest version"
```

### Check Submodule Status

```shell
git submodule status
```

### Initialize Submodules (for new clones)

```shell
git submodule update --init --recursive
```

## Development Workflow

### Working with Vault Contracts

1. Vault contracts are imported using `@vault/` prefix
2. Mock vault is available at `@vault/mocks/MockVault.sol` for testing
3. Interface definitions are at `@vault/interfaces/IVault.sol`
4. Never modify files in `lib/vault/` - make changes in the vault repository instead

### Adding New Vault Features

1. Make changes in the vault repository: https://github.com/Behodler/reflax-yield-vault
2. Update the submodule reference in this project (see "Update Vault Dependency" above)
3. Update import statements if interfaces change
4. Run tests to ensure compatibility

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
