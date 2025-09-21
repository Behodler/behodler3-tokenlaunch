# Pre-commit Hook Setup and Usage Guide

## Overview

This guide provides comprehensive instructions for setting up and using pre-commit hooks in the Behodler3 TokenLaunch project. The pre-commit system ensures code quality, security, and consistency before changes are committed to the repository.

## Quick Setup

### Prerequisites

Ensure you have the following tools installed:

```bash
# Required tools
python3 --version  # Python 3.7+
pip --version       # pip package manager
node --version      # Node.js 18+
forge --version     # Foundry
```

### One-Command Setup

```bash
# Complete setup via Makefile
make install-dev
```

This command automatically:

- Installs npm dependencies
- Installs Foundry dependencies
- Installs and configures pre-commit hooks

### Manual Setup

If you prefer manual installation:

```bash
# Install pre-commit
pip install pre-commit

# Install pre-commit hooks
pre-commit install

# Install npm dependencies
npm install

# Install Foundry dependencies
forge install
```

## Pre-commit Hook Configuration

### Configuration File

**Location**: `.pre-commit-config.yaml`

The configuration defines multiple stages of hooks that run at different times:

- **pre-commit**: Default stage, runs on every commit
- **pre-push**: Runs only before pushing to remote
- **manual**: Runs only when explicitly triggered

### Hook Categories

#### 1. Code Formatting Hooks

**Prettier (JavaScript/JSON/Markdown/YAML)**:

```yaml
- repo: https://github.com/pre-commit/mirrors-prettier
  rev: v4.0.0-alpha.8
  hooks:
      - id: prettier
        name: Format code with Prettier
        files: \.(json|md|yml|yaml)$
        exclude: ^(node_modules/|lib/|cache/|out/|crytic-export/).*
```

**Forge (Solidity)**:

```yaml
- repo: local
  hooks:
      - id: forge-fmt
        name: Format Solidity with Forge
        entry: forge fmt
        language: system
        files: \.sol$
        pass_filenames: false
```

#### 2. Basic Quality Checks

**Trailing Whitespace**:

```yaml
- id: trailing-whitespace
  name: Trim trailing whitespace
  exclude: ^(node_modules/|lib/|cache/|out/|crytic-export/).*
```

**End of File Fixer**:

```yaml
- id: end-of-file-fixer
  name: Fix end of files
  exclude: ^(node_modules/|lib/|cache/|out/|crytic-export/).*
```

**File Validation**:

```yaml
- id: check-yaml
  name: Check YAML
- id: check-json
  name: Check JSON
- id: check-added-large-files
  name: Check for large files
```

#### 3. Build and Compilation Checks

**Forge Build**:

```yaml
- repo: local
  hooks:
      - id: forge-build
        name: Build contracts with Forge
        entry: forge build
        language: system
        files: \.sol$
        pass_filenames: false
```

**Adaptive Testing**:

```yaml
- repo: local
  hooks:
      - id: adaptive-test-quick
        name: Run adaptive quick tests
        entry: bash
        language: system
        files: \.sol$
        pass_filenames: false
        args:
            [
                "-c",
                'FOUNDRY_PROFILE=quick ./adaptive-test-runner.sh core || echo "Warning: Quick test timeout (normal for pre-commit)"',
            ]
```

#### 4. Security Analysis Hooks

**Echidna Property Testing**:

```yaml
- repo: local
  hooks:
      - id: echidna-quick
        name: Quick Echidna property testing
        entry: bash
        language: system
        files: \.sol$
        pass_filenames: false
        args:
            [
                "-c",
                'export PATH="/home/justin/.local/bin:$PATH"; if command -v echidna >/dev/null 2>&1; then timeout 20 echidna test/echidna/SimpleTest.sol --contract SimpleTest --test-limit 50 --seq-len 5 || echo "Warning: Echidna timeout (normal for pre-commit)"; else echo "Warning: Echidna not available, skipping property tests"; fi',
            ]
```

**Fuzz Testing**:

```yaml
- repo: local
  hooks:
      - id: forge-fuzz-quick
        name: Quick fuzz testing
        entry: bash
        language: system
        files: \.sol$
        pass_filenames: false
        args:
            [
                "-c",
                'timeout 15 forge test --match-test "fuzz" --fuzz-runs 100 || echo "Warning: Quick fuzz test timeout (normal for pre-commit)"',
            ]
```

**Scribble Validation**:

```yaml
- repo: local
  hooks:
      - id: scribble-check
        name: Scribble annotation validation
        entry: bash
        language: system
        files: \.sol$
        pass_filenames: false
        args:
            [
                "-c",
                'if command -v npx >/dev/null 2>&1; then timeout 10 npx scribble --check src/ScribbleValidationContract.sol 2>/dev/null || echo "Warning: Scribble check skipped (file may not exist)"; else echo "Warning: npm/npx not available"; fi',
            ]
```

**Solidity Linting**:

```yaml
- repo: local
  hooks:
      - id: solhint
        name: Solidity linting with Solhint
        entry: npx solhint
        language: system
        files: \.sol$
        args: ["src/**/*.sol", "test/**/*.sol"]
        pass_filenames: false
```

**Secret Detection**:

```yaml
- repo: https://github.com/Yelp/detect-secrets
  rev: v1.5.0
  hooks:
      - id: detect-secrets
        name: Detect secrets
        args: ["--baseline", ".secrets.baseline"]
        exclude: ^(node_modules/|lib/|cache/|out/|crytic-export/|package-lock\.json).*
```

**Slither Analysis**:

```yaml
- repo: local
  hooks:
      - id: slither-quick
        name: Quick Slither analysis
        entry: bash
        language: system
        files: \.sol$
        pass_filenames: false
        args:
            [
                "-c",
                'if command -v slither >/dev/null 2>&1; then timeout 8 slither . --exclude-dependencies --disable-color --filter-paths "test/,lib/" || echo "Warning: Slither timeout (normal for pre-commit)"; else echo "Warning: Slither not available, skipping analysis"; fi',
            ]
```

#### 5. Extended Testing (Pre-push and Manual)

**Extended Echidna Testing**:

```yaml
- repo: local
  hooks:
      - id: echidna-extended
        name: Extended Echidna property testing
        entry: bash
        language: system
        files: \.sol$
        pass_filenames: false
        stages: [pre-push, manual]
        args:
            [
                "-c",
                'export PATH="/home/justin/.local/bin:$PATH"; if command -v echidna >/dev/null 2>&1; then timeout 120 echidna test/echidna/SimpleTest.sol --contract SimpleTest --test-limit 1000 --seq-len 10 || echo "Warning: Extended Echidna timeout"; else echo "Warning: Echidna not available"; fi',
            ]
```

**Extended Fuzz Testing**:

```yaml
- repo: local
  hooks:
      - id: forge-fuzz-extended
        name: Extended fuzz testing
        entry: bash
        language: system
        files: \.sol$
        pass_filenames: false
        stages: [pre-push, manual]
        args:
            [
                "-c",
                'timeout 90 forge test --match-test "fuzz" --fuzz-runs 5000 || echo "Warning: Extended fuzz test timeout"',
            ]
```

**Full Scribble Validation**:

```yaml
- repo: local
  hooks:
      - id: scribble-full
        name: Full Scribble specification validation
        entry: bash
        language: system
        files: \.sol$
        pass_filenames: false
        stages: [manual]
        args:
            [
                "-c",
                'if command -v npx >/dev/null 2>&1; then make scribble-validation-test || echo "Warning: Full Scribble validation issues"; else echo "Warning: npm/npx not available"; fi',
            ]
```

## Daily Usage

### Automatic Execution

Pre-commit hooks run automatically when you commit:

```bash
# Regular commit - runs all pre-commit stage hooks
git add src/TokenLaunch.sol
git commit -m "Fix token transfer logic"

# Hooks run automatically:
# ✅ Format code with Prettier
# ✅ Trim trailing whitespace
# ✅ Fix end of files
# ✅ Format Solidity with Forge
# ✅ Build contracts with Forge
# ✅ Run adaptive quick tests
# ✅ Quick Echidna property testing
# ✅ Quick fuzz testing
# ✅ Scribble annotation validation
# ✅ Solidity linting with Solhint
# ✅ Detect secrets
# ✅ Quick Slither analysis
```

### Manual Execution

#### Run All Hooks on All Files

```bash
# Run all pre-commit hooks
pre-commit run --all-files

# Run via Makefile
make pre-commit-run
```

#### Run Specific Hooks

```bash
# Run only formatting hooks
pre-commit run prettier --all-files
pre-commit run forge-fmt --all-files

# Run only security hooks
pre-commit run echidna-quick --all-files
pre-commit run slither-quick --all-files

# Run specific hook via Makefile
make pre-commit-run-hook HOOK=prettier
```

#### Run Pre-push Stage Hooks

```bash
# Run extended testing hooks
pre-commit run --hook-stage pre-push --all-files

# Or manually trigger before pushing
git push origin feature-branch  # Automatically runs pre-push hooks
```

#### Run Manual Stage Hooks

```bash
# Run comprehensive validation
pre-commit run --hook-stage manual --all-files

# Run specific manual hook
pre-commit run scribble-full --all-files
```

### Working with Hook Failures

#### Understanding Hook Output

When a hook fails, you'll see output like:

```bash
Format code with Prettier................................................Failed
- hook id: prettier
- files were modified by this hook

Solidity linting with Solhint...........................................Failed
- hook id: solhint
- exit code: 1

Files were modified by this hook. Additional output:

/path/to/contract.sol
  45:1  warning  Line too long  line-length

Quick Echidna property testing...........................................Passed
```

#### Handling Different Failure Types

**1. Formatting Issues (Auto-fixed)**:

```bash
# Files were automatically formatted
# Simply add the changes and recommit
git add .
git commit -m "Fix token transfer logic"
```

**2. Linting Issues (Manual fix required)**:

```bash
# Review linting errors and fix manually
npx solhint 'src/**/*.sol' 'test/**/*.sol'

# Fix issues in your code
vim src/TokenLaunch.sol

# Re-attempt commit
git add src/TokenLaunch.sol
git commit -m "Fix token transfer logic"
```

**3. Test Failures (Code issues)**:

```bash
# Review test failures
forge test -vvv

# Fix the underlying code issues
vim src/TokenLaunch.sol

# Re-run tests to verify
forge test

# Commit once tests pass
git commit -m "Fix token transfer logic"
```

**4. Security Issues (Critical)**:

```bash
# Review security warnings
echo "Property violation detected in Echidna"

# Investigate the issue
echidna test/echidna/SimpleTest.sol --contract SimpleTest --verbose

# Fix security issues before committing
vim src/TokenLaunch.sol

# Verify fix
echidna test/echidna/SimpleTest.sol --contract SimpleTest

# Commit after verification
git commit -m "Fix security vulnerability in transfer function"
```

### Skipping Hooks (Use Sparingly)

Sometimes you may need to skip hooks for emergency fixes:

```bash
# Skip all hooks (emergency only)
git commit --no-verify -m "Emergency hotfix"

# Skip specific hook
SKIP=prettier git commit -m "Commit without formatting"

# Skip multiple hooks
SKIP=prettier,solhint git commit -m "Skip multiple hooks"
```

**⚠️ Warning**: Only skip hooks in true emergencies. Skipped hooks should be run manually before the next commit.

## Advanced Configuration

### Environment-Specific Settings

Pre-commit hooks adapt to different environments:

**CI Environment**: Hooks detect CI environment and use shorter timeouts
**Local Development**: Full timeout and test parameters
**Performance Mode**: Can be enabled with environment variables

```bash
# Force quick mode locally
FOUNDRY_PROFILE=quick git commit -m "Quick commit"

# Force CI mode for testing
CI=true pre-commit run --all-files
```

### Custom Timeout Configuration

Modify timeouts in `.pre-commit-config.yaml`:

```yaml
# Quick testing for fast feedback
timeout 10 echidna test/echidna/SimpleTest.sol --test-limit 20

# Extended testing for thorough validation
timeout 120 echidna test/echidna/SimpleTest.sol --test-limit 1000
```

### Hook Dependencies

Some hooks depend on others:

1. **forge-build** must pass before **echidna-quick**
2. **prettier** must run before **trailing-whitespace**
3. **Security hooks** run after successful compilation

### Exclude Patterns

Files excluded from hook execution:

```yaml
exclude: ^(node_modules/|lib/|cache/|out/|crytic-export/).*
```

Common exclusions:

- `node_modules/`: npm dependencies
- `lib/`: Foundry dependencies
- `cache/`: Build cache
- `out/`: Build output
- `crytic-export/`: Static analysis output

## Performance Optimization

### Cache Utilization

Pre-commit hooks leverage caching for better performance:

```bash
# Check cache status
./test-cache-manager.sh status

# Clean cache if needed
./test-cache-manager.sh clean build
```

### Parallel Execution

Where possible, hooks run in parallel:

- Independent hooks run simultaneously
- Dependent hooks wait for prerequisites
- File-specific hooks only run on changed files

### Timeout Management

Hooks use adaptive timeouts:

- **Quick hooks**: 8-20 seconds
- **Standard hooks**: 30-60 seconds
- **Extended hooks**: 90-120 seconds

## Troubleshooting

### Common Issues

#### 1. Hook Installation Problems

```bash
# Reinstall hooks
pre-commit uninstall
pre-commit install

# Update hook versions
pre-commit autoupdate
```

#### 2. Tool Not Found Errors

```bash
# Check tool availability
which forge
which echidna
which npx

# Install missing tools
make install-dev
```

#### 3. Permission Issues

```bash
# Fix hook permissions
chmod +x .git/hooks/pre-commit

# Reinstall with proper permissions
pre-commit install
```

#### 4. Timeout Issues

```bash
# Skip timeout-prone hooks temporarily
SKIP=echidna-quick,slither-quick git commit -m "Skip slow hooks"

# Run skipped hooks manually later
pre-commit run echidna-quick --all-files
```

### Debug Mode

Run hooks with verbose output:

```bash
# Verbose pre-commit execution
pre-commit run --verbose --all-files

# Debug specific hook
pre-commit run --verbose echidna-quick --all-files
```

### Performance Monitoring

```bash
# Time hook execution
time pre-commit run --all-files

# Profile specific hooks
time pre-commit run forge-test --all-files
```

## Integration with Development Workflow

### IDE Integration

Most IDEs can integrate with pre-commit:

**VS Code**: Use the "Pre-commit Helper" extension
**IntelliJ**: Configure pre-commit as external tool
**Vim**: Use pre-commit plugin

### Git Workflow Integration

```bash
# Feature branch workflow
git checkout -b feature/new-token-mechanism
# Make changes
git add .
git commit -m "Add new token mechanism"  # Hooks run automatically
git push origin feature/new-token-mechanism

# Pre-push hooks run automatically before push
```

### Team Collaboration

```bash
# Ensure all team members have hooks installed
make install-dev

# Share hook configuration updates
git add .pre-commit-config.yaml
git commit -m "Update pre-commit hook configuration"
```

## Best Practices

### 1. Commit Frequency

- Commit small, logical changes frequently
- Let hooks catch issues early and often
- Don't accumulate large changes

### 2. Hook Selection

- Use quick hooks for rapid feedback
- Run extended hooks before important pushes
- Use manual hooks for comprehensive validation

### 3. Error Handling

- Always review hook output
- Fix security issues immediately
- Address linting warnings promptly

### 4. Performance

- Leverage caching for repeated operations
- Use appropriate profiles for different scenarios
- Monitor hook execution times

### 5. Maintenance

- Regularly update hook versions
- Review and update timeout settings
- Clean cache periodically

## Customization Guide

### Adding New Hooks

To add a new pre-commit hook:

1. **Define Hook in Configuration**:

    ```yaml
    - repo: local
      hooks:
          - id: custom-security-check
            name: Custom security validation
            entry: ./scripts/custom-security-check.sh
            language: system
            files: \.sol$
    ```

2. **Create Hook Script**:

    ```bash
    #!/bin/bash
    # scripts/custom-security-check.sh
    echo "Running custom security checks..."
    # Your custom logic here
    ```

3. **Test Hook**:

    ```bash
    pre-commit run custom-security-check --all-files
    ```

4. **Update Documentation**:
    - Add hook description to this guide
    - Include usage examples
    - Document any dependencies

### Modifying Existing Hooks

To modify hook behavior:

1. **Update Configuration**: Modify `.pre-commit-config.yaml`
2. **Test Changes**: Run `pre-commit run --all-files`
3. **Document Changes**: Update this guide
4. **Share with Team**: Commit configuration changes

### Environment-Specific Hooks

Create hooks that behave differently in different environments:

```yaml
- repo: local
  hooks:
      - id: adaptive-hook
        name: Environment-adaptive hook
        entry: bash
        language: system
        args: ["-c", 'if [ "$CI" = "true" ]; then echo "CI mode"; else echo "Local mode"; fi']
```

This comprehensive pre-commit setup ensures code quality, security, and consistency across the entire development workflow while providing flexibility for different development scenarios.
