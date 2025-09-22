# Echidna Property Testing Setup

This document describes the Echidna property-based testing infrastructure setup for the Behodler3 TokenLaunch project.

## Overview

Echidna is a property-based fuzzing tool for Ethereum smart contracts that helps discover edge cases and invariant violations. This setup establishes the foundation for comprehensive property testing of the TokenLaunch contract.

## Installation

### Automated Installation

Use the provided Makefile target for easy installation:

```bash
make install-echidna
```

This will:

- Download Echidna v2.2.7 for x86_64 Linux
- Install it to `~/.local/bin/echidna`
- Set appropriate permissions

### Manual Installation

1. Download the latest release from [Echidna Releases](https://github.com/crytic/echidna/releases)
2. Extract the binary and place it in your PATH
3. Install the Python dependency: `pipx install crytic-compile`

### Dependencies

- **crytic-compile**: Required for Solidity compilation
    ```bash
    pipx install crytic-compile
    ```

## Configuration

### echidna.yaml

Basic configuration file with the following key settings:

```yaml
# Test execution parameters
testLimit: 100 # Number of test sequences to run
seqLen: 10 # Maximum sequence length per test

# Use Foundry for compilation
cryticArgs: ["--compile-force-framework", "foundry"]

# Test discovery
sender: ["0x10000", "0x20000", "0x30000"] # Test sender addresses
```

### foundry.toml

Updated to ensure compatibility:

```toml
[profile.default]
evm_version = "london"  # Compatible with available Solidity version
```

## Usage

### Running Tests

Use the integrated Makefile target:

```bash
make echidna
```

This runs basic functionality tests and verifies the setup.

### Direct Execution

For manual testing:

```bash
echidna test/echidna/SimpleTest.sol --contract SimpleTest --test-limit 100
```

## Property Test Patterns

### Basic Property Test Structure

```solidity
contract TestContract {
    // State variables to test
    uint256 public value;

    // Function to modify state
    function setValue(uint256 _value) public {
        value = _value;
    }

    // Property function (must start with "echidna_")
    function echidna_property_name() public view returns (bool) {
        return value < 1000;  // Property invariant
    }
}
```

### Core Property Types

1. **State Invariants**: Properties that should always hold

    ```solidity
    function echidna_balance_non_negative() public view returns (bool) {
        return balance >= 0;
    }
    ```

2. **Conservation Properties**: Total values should be conserved

    ```solidity
    function echidna_token_conservation() public view returns (bool) {
        return totalSupply == totalDeposits;
    }
    ```

3. **Monotonicity Properties**: Values should increase/decrease appropriately
    ```solidity
    function echidna_price_monotonic() public view returns (bool) {
        return currentPrice >= previousPrice;
    }
    ```

## Current Implementation

### Working Components

1. **Echidna Installation**: ✅ Version 2.2.7 installed and functional
2. **Basic Configuration**: ✅ echidna.yaml with essential settings
3. **Foundry Integration**: ✅ Uses Foundry for compilation
4. **Make Target**: ✅ `make echidna` command available
5. **Simple Test**: ✅ Basic property test validates setup

### Implemented Files

- `echidna.yaml`: Configuration file
- `test/echidna/SimpleTest.sol`: Basic functionality test
- `test/echidna/properties/TokenLaunchProperties.sol`: Advanced property tests (requires dependency resolution)
- Makefile targets: `echidna`, `echidna-coverage`, `install-echidna`

### Known Limitations

1. **Complex Contract Dependencies**: The TokenLaunchProperties contract requires dependency resolution due to OpenZeppelin version conflicts
2. **Solidity Version**: System Solidity (0.8.13) vs OpenZeppelin requirements (0.8.20+)
3. **Coverage Reporting**: Disabled in basic configuration to avoid compilation issues

## Troubleshooting

### Common Issues

1. **"echidna: command not found"**
    - Ensure `~/.local/bin` is in your PATH
    - Run `export PATH="/home/justin/.local/bin:$PATH"`

2. **"crytic-compile not found"**
    - Install with `pipx install crytic-compile`

3. **Compilation Errors**
    - Check Solidity version compatibility
    - Verify foundry.toml EVM version settings
    - Use simpler test contracts for validation

### Verification Steps

1. **Check Echidna Installation**:

    ```bash
    echidna --version
    ```

2. **Test Basic Functionality**:

    ```bash
    make echidna
    ```

3. **Verify Dependencies**:
    ```bash
    crytic-compile --version
    ```

## K Invariant Testing

### Overview

The K invariant is critical for the Behodler3 TokenLaunch contract as it validates the mathematical correctness of the offset bonding curve formula: `(x + α)(y + β) = k`, where:

- `x` = virtualInputTokens (current input token balance in virtual pair)
- `y` = virtualL (current bonding token balance in virtual pair)
- `α` = alpha offset parameter
- `β` = beta offset parameter
- `k` = virtualK (constant product for the bonding curve)

### Implementation

The K invariant testing is implemented in `test/echidna/properties/TokenLaunchProperties.sol` and validated through Foundry tests in `test/PropertyTestBridge.sol`.

#### Core K Invariant Function

```solidity
function echidna_virtual_k_invariant() public view returns (bool) {
    uint256 virtualInput = tokenLaunch.virtualInputTokens();
    uint256 virtualL = tokenLaunch.virtualL();
    uint256 alpha = tokenLaunch.alpha();
    uint256 beta = tokenLaunch.beta();

    // Use correct offset bonding curve formula: (x + α)(y + β) = k
    uint256 currentK = (virtualInput + alpha) * (virtualL + beta);
    uint256 expectedK = tokenLaunch.virtualK();

    // K should match expected virtual K (allowing for precision tolerance)
    // Use 0.01% tolerance for large numbers (similar to other tests in codebase)
    uint256 tolerance = expectedK / 1e4; // 0.01% tolerance for precision
    return currentK >= expectedK - tolerance && currentK <= expectedK + tolerance;
}
```

#### Key Design Decisions

1. **Offset Bonding Curve Formula**: The function correctly implements `(x + α)(y + β) = k` instead of the simpler `x * y = k`. This offset formula is essential for proper bonding curve behavior.

2. **Precision Tolerance**: Uses 0.01% tolerance (`expectedK / 1e4`) to handle:
    - Integer division precision loss in Solidity
    - Large number arithmetic (values around 1e47)
    - Consistency with other tolerance patterns in the codebase

3. **Automatic Validation**: The invariant is automatically checked:
    - After every `addLiquidity` operation via `test_addLiquidity_integration()`
    - After every `removeLiquidity` operation via `test_removeLiquidity_integration()`
    - As a standalone property test via `test_virtual_k_invariant()`

#### Test Integration

The K invariant is integrated into three test functions:

1. **`test_virtual_k_invariant()`**: Direct validation of the K invariant
2. **`test_addLiquidity_integration()`**: Validates K invariant after liquidity addition
3. **`test_removeLiquidity_integration()`**: Validates K invariant after liquidity removal

### Historical Context

**Previous Issue**: The original implementation incorrectly used `virtualInputTokens * virtualL` which failed because it didn't account for the offset parameters (α and β) that are fundamental to the contract's bonding curve design.

**Resolution**: Updated to use the correct offset bonding curve formula `(virtualInputTokens + alpha) * (virtualL + beta)` with appropriate precision tolerance.

### Tolerance Calibration

The 0.01% tolerance was chosen based on:

- Analysis of similar tests in the codebase (B3AddLiquidityTest.sol, VirtualLiquidityTest.sol)
- The scale of numbers involved (~1e47 for virtualK)
- Observed precision differences (~1e23) which represent a tiny relative error

### Running K Invariant Tests

```bash
# Run all three K invariant tests
forge test --match-test "test_virtual_k_invariant|test_addLiquidity_integration|test_removeLiquidity_integration"

# Run just the direct K invariant test
forge test --match-test "test_virtual_k_invariant"

# Run with verbose output for debugging
forge test --match-test "test_virtual_k_invariant" -vvv
```

### Expected Results

All three tests should pass, confirming:

- ✅ The K invariant holds immediately after contract initialization
- ✅ The K invariant is preserved after adding liquidity
- ✅ The K invariant is preserved after removing liquidity
- ✅ Mathematical correctness of the offset bonding curve implementation

## Future Enhancements

### Phase 1 (Current)

- ✅ Basic Echidna setup and configuration
- ✅ Simple property test validation
- ✅ Make target integration

### Phase 2 (Next Steps)

- Resolve OpenZeppelin dependency conflicts
- Implement comprehensive TokenLaunch property tests
- Add coverage reporting
- ✅ Create property test patterns for bonding curve invariants

### Phase 3 (Advanced)

- Integration with CI/CD pipeline
- Automated property discovery
- Custom assertion libraries
- Performance optimization

## Example Output

When running `make echidna`, you should see:

```
🔍 Running Echidna property-based tests...
Running basic Echidna functionality test...
[timestamp] Compiling `test/echidna/SimpleTest.sol`... Done!
echidna_value_under_1000: failed!💥
  Call sequence:
    SimpleTest.setValue(1001)

💡 Echidna core setup is functional!
📝 Note: Complex TokenLaunch property tests require dependency resolution
```

This output confirms that:

- Echidna can compile Solidity contracts
- Property-based testing is working correctly
- The infrastructure is ready for more complex tests

## References

- [Echidna Documentation](https://github.com/crytic/echidna)
- [Property-Based Testing Guide](https://blog.trailofbits.com/2018/03/09/echidna-a-smart-fuzzer-for-ethereum/)
- [Foundry Integration](https://book.getfoundry.sh/)
