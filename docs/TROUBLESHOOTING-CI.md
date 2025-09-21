# CI/CD Troubleshooting Guide

## Overview

This guide provides comprehensive troubleshooting solutions for CI/CD pipeline failures in the Behodler3 TokenLaunch project. It covers common issues, diagnostic steps, and resolution strategies for the automated security testing pipeline.

## Quick Diagnosis Commands

### Check CI Status

```bash
# View recent workflow runs
gh run list --limit 10

# View specific run details
gh run view [RUN-ID]

# Download artifacts from failed run
gh run download [RUN-ID]
```

### Local CI Environment Simulation

```bash
# Run with CI profile locally
FOUNDRY_PROFILE=ci forge test

# Simulate CI environment
CI=true ./adaptive-test-runner.sh

# Run CI-optimized Echidna
echidna test/echidna/SimpleTest.sol --contract SimpleTest --config echidna-ci.yaml
```

## Common CI Failure Categories

## 1. Environment Setup Failures

### Node.js/npm Installation Issues

**Symptoms**:

- `npm ci` fails
- Node.js version conflicts
- Package dependency errors

**Diagnostic Steps**:

```bash
# Check Node.js version locally
node --version

# Verify package.json validity
npm install --dry-run

# Check for npm vulnerabilities
npm audit
```

**Solutions**:

1. **Update Node.js Version**:

    ```yaml
    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
          node-version: "20" # Update version
          cache: "npm"
    ```

2. **Fix Package Vulnerabilities**:

    ```bash
    # Local fix, then commit
    npm audit fix
    git add package*.json
    git commit -m "Fix npm security vulnerabilities"
    ```

3. **Clear npm Cache**:
    ```yaml
    - name: Clear npm cache
      run: npm cache clean --force
    ```

### Foundry Installation Problems

**Symptoms**:

- `forge` command not found
- Foundry compilation errors
- Version compatibility issues

**Diagnostic Steps**:

```bash
# Check Foundry version locally
forge --version

# Verify compilation locally
forge build

# Check foundry.toml syntax
forge config
```

**Solutions**:

1. **Update Foundry Version**:

    ```yaml
    - name: Install Foundry
      uses: foundry-rs/foundry-toolchain@v1
      with:
          version: nightly-latest # or specific version
    ```

2. **Fix foundry.toml Configuration**:
    ```toml
    [profile.ci]
    fuzz = { runs = 256 }
    invariant = { runs = 32, depth = 100 }
    optimizer = true
    optimizer_runs = 200
    ```

### Python/pip Setup Issues

**Symptoms**:

- Python module import errors
- pip install failures
- Scribble not available

**Solutions**:

1. **Update Python Version**:

    ```yaml
    - name: Install Python and pip
      uses: actions/setup-python@v4
      with:
          python-version: "3.10" # Update version
    ```

2. **Add pip Dependencies**:
    ```yaml
    - name: Install Python dependencies
      run: |
          pip install --upgrade pip
          pip install solc-select scribble-lang
    ```

### Echidna Installation Failures

**Symptoms**:

- `echidna` command not found
- Download failures
- Permission issues

**Diagnostic Steps**:

```bash
# Check if Echidna is accessible
which echidna

# Test Echidna installation
echidna --version

# Check PATH configuration
echo $PATH | grep -o '[^:]*local/bin[^:]*'
```

**Solutions**:

1. **Use Different Download Method**:

    ```yaml
    - name: Install Echidna via APT
      run: |
          sudo apt update
          sudo apt install -y echidna
    ```

2. **Fix Download URL**:
    ```yaml
    - name: Install Echidna
      run: |
          cd /tmp
          curl -L -o echidna.tar.gz https://github.com/crytic/echidna/releases/download/v2.2.7/echidna-2.2.7-x86_64-linux.tar.gz
          tar -xzf echidna.tar.gz
          sudo mv echidna /usr/local/bin/
          chmod +x /usr/local/bin/echidna
    ```

## 2. Compilation and Build Failures

### Solidity Compilation Errors

**Symptoms**:

- `forge build` fails
- Contract compilation errors
- Import resolution issues

**Diagnostic Steps**:

```bash
# Clean build locally
forge clean && forge build

# Check specific contract compilation
forge build --contracts src/SpecificContract.sol

# Verify import paths
find . -name "*.sol" -exec grep -l "import.*SomeContract" {} \;
```

**Solutions**:

1. **Fix Import Paths**:

    ```solidity
    // Use relative paths consistently
    import "../interfaces/ITokenLaunch.sol";
    import "./BaseContract.sol";
    ```

2. **Update Solidity Version**:

    ```toml
    [profile.default]
    solc = "0.8.25"
    ```

3. **Resolve Dependency Conflicts**:

    ```bash
    # Update forge dependencies
    forge update

    # Reinstall specific dependency
    forge install openzeppelin/openzeppelin-contracts@v4.9.0 --no-commit
    ```

### Gas Limit Exceeded

**Symptoms**:

- Tests fail with "out of gas"
- Contract deployment failures
- Stack too deep errors

**Solutions**:

1. **Increase Gas Limits**:

    ```toml
    [profile.ci]
    gas_limit = 30000000
    gas_price = 1000000000
    ```

2. **Enable IR Compilation**:
    ```toml
    [profile.ci]
    via_ir = true
    optimizer = true
    optimizer_runs = 200
    ```

## 3. Test Execution Failures

### Forge Test Failures

**Symptoms**:

- Specific tests fail in CI but pass locally
- Timeout errors
- Assertion failures

**Diagnostic Steps**:

```bash
# Run with CI profile locally
FOUNDRY_PROFILE=ci forge test -vvv

# Run specific failing test
forge test --match-test test_specific_function -vvvv

# Check gas usage
forge test --gas-report
```

**Solutions**:

1. **Fix Test Environment Dependencies**:

    ```solidity
    function setUp() public {
        // Ensure clean state for each test
        vm.deal(address(this), 100 ether);
        vm.warp(1000000); // Set consistent timestamp
    }
    ```

2. **Add Timeout Handling**:
    ```yaml
    - name: Run Forge tests
      run: timeout 300 forge test -vvv
      continue-on-error: false
    ```

### Echidna Property Test Failures

**Symptoms**:

- Echidna crashes or hangs
- Property violations detected
- Configuration errors

**Diagnostic Steps**:

```bash
# Test Echidna configuration
echidna test/echidna/SimpleTest.sol --contract SimpleTest --config echidna-ci.yaml --dry-run

# Run with verbose output
echidna test/echidna/SimpleTest.sol --contract SimpleTest --config echidna-ci.yaml --verbose

# Check configuration file syntax
yaml-lint echidna-ci.yaml
```

**Solutions**:

1. **Fix Echidna Configuration**:

    ```yaml
    # echidna-ci.yaml
    testLimit: 50
    seqLen: 8
    timeout: 30
    workers: 2
    corpusDir: null
    coverage: false
    cryticArgs: ["--ignore-compile-errors"]
    ```

2. **Handle Property Violations**:

    ```solidity
    // Add proper preconditions
    function echidna_invariant_check() public view returns (bool) {
        // Only check if contract is properly initialized
        if (address(tokenLaunch) == address(0)) return true;

        return tokenLaunch.invariantCheck();
    }
    ```

3. **Reduce Test Complexity for CI**:
    ```yaml
    # Use simpler test configuration in CI
    testLimit: 20
    seqLen: 5
    timeout: 15
    ```

### Fuzz Test Failures

**Symptoms**:

- Fuzz tests timeout
- Specific input combinations cause failures
- Memory issues

**Solutions**:

1. **Optimize Fuzz Test Configuration**:

    ```toml
    [profile.ci]
    fuzz = { runs = 256, max_test_rejects = 100000 }
    ```

2. **Add Input Bounds**:

    ```solidity
    function testFuzz_addLiquidity(uint256 amount) public {
        // Bound inputs to reasonable ranges
        amount = bound(amount, 1e6, 1e24);
        // Test implementation
    }
    ```

3. **Handle Edge Cases**:
    ```solidity
    function testFuzz_edge_case(uint256 input) public {
        vm.assume(input > 0 && input < type(uint128).max);
        // Continue with test
    }
    ```

## 4. Security Tool Integration Issues

### Scribble Validation Failures

**Symptoms**:

- Scribble instrumentation errors
- Annotation syntax errors
- Contract not found errors

**Solutions**:

1. **Fix Scribble Annotations**:

    ```solidity
    /// if_succeeds {:msg "Balance invariant"}
    ///     balanceOf(msg.sender) >= old(balanceOf(msg.sender));
    function transfer(address to, uint256 amount) public returns (bool) {
        // Implementation
    }
    ```

2. **Update Scribble Installation**:
    ```yaml
    - name: Install Scribble
      run: |
          npm install -g @consensys/scribble
          scribble --version
    ```

### Pre-commit Hook Integration Issues

**Symptoms**:

- Pre-commit hooks fail in CI
- Tool version mismatches
- Configuration conflicts

**Solutions**:

1. **Sync Tool Versions**:

    ```yaml
    # .pre-commit-config.yaml
    repos:
        - repo: https://github.com/pre-commit/mirrors-prettier
          rev: v4.0.0-alpha.8 # Match CI version
    ```

2. **CI Pre-commit Execution**:
    ```yaml
    - name: Run pre-commit checks
      run: |
          pre-commit install
          pre-commit run --all-files
    ```

## 5. Performance and Timeout Issues

### CI Pipeline Timeouts

**Symptoms**:

- Jobs exceed time limits
- Tests take too long
- Resource exhaustion

**Solutions**:

1. **Optimize Test Configuration**:

    ```toml
    [profile.ci]
    fuzz = { runs = 128 }      # Reduced from 256
    invariant = { runs = 16 }  # Reduced from 32
    ```

2. **Add Strategic Timeouts**:

    ```yaml
    - name: Run Echidna tests
      run: timeout 60 echidna test/echidna/SimpleTest.sol --contract SimpleTest --config echidna-ci.yaml
      continue-on-error: true
    ```

3. **Use Parallel Job Execution**:
    ```yaml
    strategy:
        matrix:
            test-type: [unit, fuzz, property, security]
    ```

### Memory Issues

**Symptoms**:

- Out of memory errors
- Large artifact sizes
- Slow artifact upload

**Solutions**:

1. **Limit Report Size**:

    ```bash
    # Limit log file sizes
    echo "Last 100 lines of output:" > limited-report.log
    tail -100 full-report.log >> limited-report.log
    ```

2. **Compress Artifacts**:
    ```yaml
    - name: Compress reports
      run: |
          cd docs/reports
          tar -czf ../reports-compressed.tar.gz *.log *.json
    ```

## 6. GitHub Actions Specific Issues

### Permission Errors

**Symptoms**:

- Cannot write PR comments
- Artifact upload failures
- Checkout issues

**Solutions**:

1. **Update Permissions**:

    ```yaml
    jobs:
        security-and-quality:
            permissions:
                contents: read
                pull-requests: write
                actions: read
    ```

2. **Use GitHub Token**:
    ```yaml
    - name: Comment PR
      env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      run: gh pr comment ${{ github.event.number }} --body "Test results..."
    ```

### Artifact Management Issues

**Symptoms**:

- Artifacts not uploaded
- Download failures
- Size limits exceeded

**Solutions**:

1. **Optimize Artifact Size**:

    ```yaml
    - name: Upload test reports
      uses: actions/upload-artifact@v3
      with:
          name: security-test-reports
          path: |
              docs/reports/*.json
              docs/reports/*.md
          retention-days: 7 # Reduced retention
    ```

2. **Conditional Artifact Upload**:
    ```yaml
    - name: Upload artifacts on failure
      if: failure()
      uses: actions/upload-artifact@v3
    ```

## 7. Integration and Workflow Issues

### PR Comment Failures

**Symptoms**:

- No PR comments generated
- Malformed comment content
- GitHub API errors

**Solutions**:

1. **Fix Output Format**:

    ```bash
    # Escape special characters in output
    echo "RESULTS<<EOF" >> $GITHUB_OUTPUT
    echo "$(cat report.log | sed 's/`/\\`/g')" >> $GITHUB_OUTPUT
    echo "EOF" >> $GITHUB_OUTPUT
    ```

2. **Add Error Handling**:
    ```yaml
    - name: Comment PR with results
      if: github.event_name == 'pull_request'
      continue-on-error: true
      uses: actions/github-script@v6
    ```

### Branch Protection Issues

**Symptoms**:

- Cannot merge despite passing tests
- Status checks not completing
- Required checks missing

**Solutions**:

1. **Verify Required Status Checks**:
    - Go to repository Settings → Branches
    - Ensure required checks match job names in workflow

2. **Update Job Names**:
    ```yaml
    jobs:
        security-and-quality: # Ensure this matches required checks
            name: Security and Quality Checks
    ```

## Emergency Recovery Procedures

### Complete CI Failure Recovery

If the CI pipeline is completely broken:

1. **Disable Failing Checks Temporarily**:

    ```yaml
    # Comment out problematic steps
    # - name: Run Echidna tests
    #   run: echidna test/echidna/SimpleTest.sol
    ```

2. **Create Minimal Working Pipeline**:

    ```yaml
    jobs:
        basic-checks:
            runs-on: ubuntu-latest
            steps:
                - uses: actions/checkout@v4
                - uses: foundry-rs/foundry-toolchain@v1
                - run: forge build
                - run: forge test
    ```

3. **Gradually Re-enable Features**:
    - Add one security tool at a time
    - Test each addition thoroughly
    - Monitor performance impact

### Rollback Strategy

```bash
# Identify last working commit
git log --oneline --grep="CI working"

# Create emergency fix branch
git checkout -b emergency-ci-fix [LAST-WORKING-COMMIT]

# Make minimal fixes
git add .github/workflows/
git commit -m "Emergency CI fix: restore basic functionality"

# Create PR for review
gh pr create --title "Emergency CI Fix" --body "Restores basic CI functionality"
```

## Monitoring and Prevention

### Proactive Monitoring

1. **Set Up Alerts**:
    - GitHub webhook notifications
    - Slack/Discord integration for failures
    - Email alerts for critical failures

2. **Regular Health Checks**:
    ```bash
    # Weekly CI health check script
    ./scripts/ci-health-check.sh
    ```

### Prevention Best Practices

1. **Test Locally First**:

    ```bash
    # Always test with CI profile before pushing
    FOUNDRY_PROFILE=ci forge test
    CI=true ./adaptive-test-runner.sh
    ```

2. **Gradual Changes**:
    - Make small, incremental changes to CI
    - Test each change in a feature branch
    - Monitor performance impact

3. **Documentation**:
    - Document all CI configuration changes
    - Keep troubleshooting guide updated
    - Maintain runbook for common issues

## Getting Help

### Information to Provide

When seeking help with CI issues:

1. **Workflow Run URL**: Direct link to failed GitHub Actions run
2. **Error Messages**: Complete error output from failed steps
3. **Local Reproduction**: Whether issue reproduces locally
4. **Recent Changes**: What was changed before the failure
5. **Environment Details**: Tool versions, configuration files

### Debugging Commands

```bash
# Workflow debugging
gh run list --limit 5
gh run view [RUN-ID] --log

# Local CI simulation
CI=true FOUNDRY_PROFILE=ci forge test -vvv

# Configuration validation
forge config
echidna --version
pre-commit --version
```

### Support Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Foundry Book](https://book.getfoundry.sh/)
- [Echidna Documentation](https://github.com/crytic/echidna)
- Project Slack/Discord channels for team support

This troubleshooting guide should resolve most CI/CD pipeline issues. For persistent problems, consider consulting with the development team or creating detailed issue reports with the information specified above.
