# Behodler3 Tokenlaunch

Bootstrap AMM using Virtual Pair architecture for token launches.

## Architecture

This project uses an external vault dependency via git submodules. The vault contracts are imported from the [reflax-yield-vault](https://github.com/Behodler/reflax-yield-vault) repository to avoid code duplication and maintain a clean separation of concerns.

## Code Quality and Development Setup

This project implements comprehensive code quality tooling to maintain security standards and consistent formatting across the codebase.

### Quick Start

For first-time setup, run:

```shell
make dev-setup
```

This will install all dependencies, set up pre-commit hooks, build contracts, and run tests.

### Development Dependencies

Required tools:

- **Node.js & npm**: For JavaScript tooling (solhint, prettier)
- **Foundry**: For Solidity compilation, testing, and formatting
- **Pre-commit**: For automated quality checks before commits
- **detect-secrets**: For preventing sensitive information from being committed

Check dependency status:

```shell
make deps
```

### Code Quality Tools

#### Solidity Linting (solhint)

- **Purpose**: Security-focused linting for Solidity files
- **Configuration**: `.solhint.json` with security rules enabled
- **Exclusions**: `.solhintignore` excludes `lib/`, `node_modules/`, `out/`, `cache/`
- **Usage**:
    ```shell
    make lint-solidity          # Check linting issues
    make lint-solidity-fix      # Auto-fix issues where possible
    npm run lint                # Alternative via npm
    ```

#### Code Formatting

- **Solidity**: Uses `forge fmt` with configuration in `foundry.toml`
- **Other files**: Uses `prettier` for JSON, Markdown, YAML files
- **Configuration**: `.prettierrc` and `.prettierignore`
- **Compatibility**: Settings aligned between forge fmt and prettier
- **Usage**:
    ```shell
    make format                 # Apply all formatting
    make format-check           # Check formatting without changes
    make format-solidity        # Format only Solidity files
    make format-other           # Format only JSON/MD/YAML files
    npm run format              # Alternative via npm
    ```

#### Pre-commit Hooks

Automatically run quality checks before each commit:

- **Prettier formatting** for non-Solidity files
- **Forge formatting** for Solidity files
- **Forge build check** to ensure contracts compile
- **Solhint linting** for security and code quality
- **Secret detection** to prevent credentials from being committed
- **General checks**: trailing whitespace, large files, etc.

**Setup**:

```shell
pre-commit install          # Enable hooks (done automatically by make dev-setup)
```

**Manual testing**:

```shell
make pre-commit-run         # Run all hooks on all files
pre-commit run prettier     # Run specific hook
```

#### Security Analysis

- **detect-secrets**: Scans for potential secrets and credentials
- **Baseline**: `.secrets.baseline` contains known/approved findings
- **Static Analysis Tools**: Comprehensive security analysis using multiple tools
    - **Slither**: Vulnerability detection and code analysis
    - **Mythril**: Security analysis with import callback support (see `MYTHRIL-IMPORT-FIX.md`)
    - **Manticore**: Symbolic execution analysis
- **Usage**:
    ```shell
    make security-scan              # Run basic security analysis (secrets detection)
    make security-update-baseline   # Update secrets baseline
    make static-analysis            # Run all static analysis tools (Slither, Mythril, Manticore)
    make mythril-analysis           # Run Mythril with import callback fix
    ```

#### Formal Verification with Scribble

This project includes comprehensive [Scribble](https://docs.scribble.codes/) specifications for formal verification of contract behavior:

- **Purpose**: Formal verification of contract invariants, preconditions, and postconditions
- **Coverage**: Complete specifications for all public functions and critical invariants
- **Documentation**: See `docs/scribble-patterns.md` for detailed patterns and guidelines
- **Specifications**: See `docs/SCRIBBLE_FUNCTION_SPECIFICATIONS.md` for complete specification reference

**Scribble Targets**:

```shell
make scribble                   # Run complete Scribble validation suite
make scribble-check            # Verify Scribble installation
make scribble-instrument       # Instrument contracts with annotations
make scribble-test             # Test instrumented contracts
make scribble-validation-test  # Run comprehensive specification tests
make scribble-clean            # Clean instrumented files
```

**Key Features**:

- **Invariants**: Mathematical properties that must always hold (e.g., virtual K consistency)
- **Preconditions**: Input validation and state requirements for all functions
- **Postconditions**: Verification of expected outcomes and state changes
- **Access Control**: Formal verification of permission requirements
- **Edge Case Testing**: Comprehensive testing of boundary conditions and error states

The Scribble specifications provide formal guarantees about contract behavior and serve as executable documentation of the system's properties.

### Make Targets Reference

#### Development Setup

```shell
make help                   # Show all available targets
make install-dev            # Install all development dependencies
make dev-setup              # Complete development environment setup
make deps                   # Show dependency status
```

#### Building and Testing

```shell
make clean                  # Clean build artifacts
make build                  # Build contracts
make test                   # Run all tests
make test-verbose           # Run tests with verbose output
make test-gas               # Run tests with gas reporting
make test-coverage          # Run test coverage analysis
```

#### Code Quality

```shell
make quality                # Run complete quality check suite
make quality-fix            # Fix all auto-fixable issues
make lint                   # Run all linting checks
make format                 # Apply all formatting
make format-check           # Check all formatting
```

#### Comprehensive Checks

```shell
make check-all              # Run full verification suite (build, test, quality, security)
make git-pre-push           # Pre-push validation
```

### NPM Scripts

The project also provides npm scripts for common tasks:

```shell
npm run lint                # Run solhint on Solidity files
npm run lint:fix            # Auto-fix linting issues
npm run format              # Format all files (prettier + forge fmt)
npm run format:check        # Check formatting
npm run quality             # Run lint + format check
npm run quality:fix         # Run lint fix + format
npm run install-dev         # Install npm + forge dependencies
```

### Development Workflow

1. **Initial Setup**:

    ```shell
    git clone <repository>
    cd behodler3-tokenlaunch
    git submodule update --init --recursive
    make dev-setup
    ```

2. **Daily Development**:
    - Write code following Test-Driven Development (TDD)
    - Pre-commit hooks automatically run quality checks
    - Use `make quality` to manually check code quality
    - Use `make test` to run tests

3. **Before Pushing**:
    ```shell
    make check-all              # Comprehensive verification
    # or
    make git-pre-push           # Focused pre-push checks
    ```

### Quality Standards

The project enforces:

- **Security-focused Solidity linting** with rules for reentrancy, overflow, timing dependencies
- **Consistent formatting** using forge fmt for Solidity and prettier for other files
- **Automated testing** with comprehensive test coverage
- **Secret detection** to prevent credential leaks
- **Pre-commit validation** to catch issues early

### Troubleshooting

#### Common Issues

**Pre-commit hooks failing**:

```shell
pre-commit clean            # Clear hook cache
pre-commit install          # Reinstall hooks
```

**Solhint configuration errors**:

- Check `.solhint.json` syntax (JSON does not support comments)
- Verify `.solhintignore` excludes problematic directories

**Format conflicts between forge fmt and prettier**:

- Run `make format` to apply both formatters
- Settings in `.prettierrc` and `foundry.toml` are aligned for compatibility

**Node.js dependency issues**:

```shell
rm -rf node_modules package-lock.json
npm install
```

### Integration with IDEs

For optimal development experience:

- **VS Code**: Install Solidity and Prettier extensions
- **Configuration**: Project includes `.vscode/` settings (if present)
- **Formatting**: Configure editor to run prettier on save

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
