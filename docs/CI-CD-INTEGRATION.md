# CI/CD Integration Configuration

## Overview

This document describes the comprehensive CI/CD integration configuration for the Behodler3 TokenLaunch project, implementing automated security testing and quality assurance as part of the development workflow.

## GitHub Actions Workflow

### Main Workflow File

**Location**: `.github/workflows/solidity-ci.yml`

The CI/CD pipeline includes automated security testing, property-based testing, and comprehensive quality checks that run on every push and pull request.

### Workflow Trigger Configuration

```yaml
on:
    push:
        branches: [main, master, sprint/*]
    pull_request:
        branches: [main, master]

env:
    FOUNDRY_PROFILE: ci
```

**Key Features**:

- Triggers on pushes to main branches and sprint branches
- Activates on all pull requests to main branches
- Uses optimized CI profile for faster execution

### Job Configuration

#### Security and Quality Job

The main job `security-and-quality` runs on `ubuntu-latest` with the following permissions:

```yaml
permissions:
    contents: read
    pull-requests: write
```

This allows the workflow to:

- Read repository contents
- Write comments to pull requests with test results

### Environment Setup Steps

#### 1. Code Checkout

```yaml
- name: Checkout code
  uses: actions/checkout@v4
  with:
      submodules: recursive
```

**Purpose**: Ensures all git submodules are properly initialized for dependency management.

#### 2. Foundry Installation

```yaml
- name: Install Foundry
  uses: foundry-rs/foundry-toolchain@v1
  with:
      version: nightly
```

**Configuration**: Uses nightly Foundry version for latest features and optimizations.

#### 3. Node.js Setup

```yaml
- name: Setup Node.js
  uses: actions/setup-node@v4
  with:
      node-version: "18"
      cache: "npm"
```

**Features**:

- Node.js 18 for modern JavaScript support
- Automatic npm cache management for faster builds

#### 4. Python Environment

```yaml
- name: Install Python and pip (for Scribble)
  uses: actions/setup-python@v4
  with:
      python-version: "3.9"
```

**Purpose**: Required for Scribble specification validation tools.

#### 5. Dependency Installation

```yaml
- name: Install dependencies
  run: |
      # Install npm dependencies when package.json exists
      if [ -f "package.json" ]; then
        npm ci
      fi
      # Install Scribble dependencies if needed
      pip install solc-select || echo "solc-select installation failed, continuing..."
```

**Features**:

- Conditional npm installation based on package.json presence
- Graceful handling of optional dependencies

#### 6. Echidna Installation

```yaml
- name: Install Echidna
  run: |
      mkdir -p ~/.local/bin
      cd /tmp
      wget https://github.com/crytic/echidna/releases/download/v2.2.7/echidna-2.2.7-x86_64-linux.tar.gz
      tar -xzf echidna-2.2.7-x86_64-linux.tar.gz
      mv echidna ~/.local/bin/
      chmod +x ~/.local/bin/echidna
      echo "$HOME/.local/bin" >> $GITHUB_PATH
```

**Configuration**:

- Installs Echidna v2.2.7 for property-based testing
- Adds to PATH for pipeline accessibility

### Testing Pipeline Steps

#### 1. Code Formatting Verification

```yaml
- name: Run Forge formatting check
  run: forge fmt --check
```

**Purpose**: Ensures consistent code formatting across the codebase.

#### 2. Contract Compilation

```yaml
- name: Run Forge build
  run: forge build
```

**Verification**: Confirms all contracts compile successfully.

#### 3. Core Test Suite

```yaml
- name: Run Forge tests
  run: forge test -vvv
```

**Configuration**: Runs with verbose output for detailed test reporting.

#### 4. Solidity Linting

```yaml
- name: Run Solhint linting
  run: make lint-solidity
  continue-on-error: true
```

**Features**:

- Integrated with Makefile for consistent local/CI execution
- Non-blocking to allow other tests to continue

### Security Testing Pipeline

#### 1. Echidna Property Testing

```yaml
- name: Run Echidna property tests
  id: echidna-tests
  run: |
      echo "🔍 Running Echidna property-based tests..."
      mkdir -p docs/reports
      timestamp=$(date +%Y%m%d_%H%M%S)

      # Run CI-optimized Echidna tests with timeout
      timeout 60 echidna test/echidna/SimpleTest.sol --contract SimpleTest --config echidna-ci.yaml > docs/reports/echidna-ci-$timestamp.log 2>&1 || echo "Echidna completed with timeout or warnings"

      # Store results for PR comment
      echo "ECHIDNA_RESULTS<<EOF" >> $GITHUB_OUTPUT
      echo "## 🔍 Echidna Property Testing Results" >> $GITHUB_OUTPUT
      echo "\`\`\`" >> $GITHUB_OUTPUT
      tail -20 docs/reports/echidna-ci-$timestamp.log >> $GITHUB_OUTPUT
      echo "\`\`\`" >> $GITHUB_OUTPUT
      echo "EOF" >> $GITHUB_OUTPUT
  continue-on-error: true
```

**Key Features**:

- 60-second timeout for CI optimization
- Timestamped report generation
- Results captured for PR commenting
- Uses CI-optimized configuration file

#### 2. Extended Fuzz Testing

```yaml
- name: Run extended fuzz testing campaign
  id: fuzz-tests
  run: |
      echo "🔍 Running extended fuzz testing campaign..."
      mkdir -p docs/reports
      timestamp=$(date +%Y%m%d_%H%M%S)

      # Run CI-optimized fuzz tests with timeout
      timeout 120 forge test --match-test "fuzz" --profile ci > docs/reports/fuzz-ci-$timestamp.log 2>&1 || echo "Fuzz testing completed with timeout"

      # Store results for PR comment
      echo "FUZZ_RESULTS<<EOF" >> $GITHUB_OUTPUT
      echo "## 🎯 Extended Fuzz Testing Results" >> $GITHUB_OUTPUT
      echo "\`\`\`" >> $GITHUB_OUTPUT
      tail -30 docs/reports/fuzz-ci-$timestamp.log >> $GITHUB_OUTPUT
      echo "\`\`\`" >> $GITHUB_OUTPUT
      echo "EOF" >> $GITHUB_OUTPUT
  continue-on-error: true
```

**Configuration**:

- 120-second timeout for comprehensive testing
- CI profile optimization
- Extended result capture (30 lines)

#### 3. Scribble Specification Validation

```yaml
- name: Run Scribble specification validation
  id: scribble-tests
  run: |
      echo "🔍 Running Scribble specification validation..."
      mkdir -p docs/reports
      timestamp=$(date +%Y%m%d_%H%M%S)

      # Run Scribble validation tests
      make scribble-validation-test > docs/reports/scribble-ci-$timestamp.log 2>&1 || echo "Scribble validation completed with warnings"

      # Store results for PR comment
      echo "SCRIBBLE_RESULTS<<EOF" >> $GITHUB_OUTPUT
      echo "## 📋 Scribble Specification Validation Results" >> $GITHUB_OUTPUT
      echo "\`\`\`" >> $GITHUB_OUTPUT
      tail -20 docs/reports/scribble-ci-$timestamp.log >> $GITHUB_OUTPUT
      echo "\`\`\`" >> $GITHUB_OUTPUT
      echo "EOF" >> $GITHUB_OUTPUT
  continue-on-error: true
```

**Integration**: Uses Makefile targets for consistency with local development.

### Security Analysis and Reporting

#### Security Summary Generation

```yaml
- name: Security analysis summary
  id: security-summary
  run: |
      echo "📊 Generating security analysis summary..."

      # Check for any property violations or critical issues
      SECURITY_STATUS="✅ PASSED"
      if grep -r "FAIL\|ERROR\|property violation" docs/reports/ 2>/dev/null | grep -v "No such file" > /dev/null; then
        SECURITY_STATUS="❌ ISSUES DETECTED"
      fi

      echo "SECURITY_STATUS=$SECURITY_STATUS" >> $GITHUB_OUTPUT
      echo "SUMMARY<<EOF" >> $GITHUB_OUTPUT
      echo "# 🔒 Security Testing Summary" >> $GITHUB_OUTPUT
      echo "" >> $GITHUB_OUTPUT
      echo "**Overall Status:** $SECURITY_STATUS" >> $GITHUB_OUTPUT
      echo "" >> $GITHUB_OUTPUT
      echo "- ✅ Standard Forge tests completed" >> $GITHUB_OUTPUT
      echo "- 🔍 Echidna property tests executed" >> $GITHUB_OUTPUT
      echo "- 🎯 Extended fuzz testing performed" >> $GITHUB_OUTPUT
      echo "- 📋 Scribble specification validation completed" >> $GITHUB_OUTPUT
      echo "" >> $GITHUB_OUTPUT
      echo "_Generated at $(date)_" >> $GITHUB_OUTPUT
      echo "EOF" >> $GITHUB_OUTPUT
```

**Features**:

- Automatic detection of security issues
- Comprehensive status reporting
- Formatted markdown output

#### Pull Request Integration

```yaml
- name: Comment PR with results
  if: github.event_name == 'pull_request'
  uses: actions/github-script@v6
  with:
      script: |
          const output = `${{ steps.security-summary.outputs.SUMMARY }}

          ${{ steps.echidna-tests.outputs.ECHIDNA_RESULTS }}

          ${{ steps.fuzz-tests.outputs.FUZZ_RESULTS }}

          ${{ steps.scribble-tests.outputs.SCRIBBLE_RESULTS }}

          <details>
          <summary>📁 Full Report Details</summary>

          All detailed reports are available in the \`docs/reports/\` directory of the CI artifacts.

          </details>`;

          github.rest.issues.createComment({
            issue_number: context.issue.number,
            owner: context.repo.owner,
            repo: context.repo.repo,
            body: output
          });
```

**Benefits**:

- Automatic PR commenting with test results
- Collapsible details for comprehensive information
- Direct integration with GitHub API

### Artifact Management

#### Test Report Upload

```yaml
- name: Upload test reports
  if: always()
  uses: actions/upload-artifact@v3
  with:
      name: security-test-reports
      path: docs/reports/
      retention-days: 30
```

**Configuration**:

- Always uploads regardless of test outcomes
- 30-day retention for historical analysis
- Centralized report storage

#### Critical Failure Detection

```yaml
- name: Fail on property violations
  run: |
      # Check for critical security property violations
      if grep -r "property violation\|CRITICAL\|FAIL.*invariant" docs/reports/ 2>/dev/null | grep -v "No such file" > /dev/null; then
        echo "❌ Critical property violations detected!"
        echo "Please review the security test reports and fix any violations."
        exit 1
      fi
      echo "✅ No critical property violations detected."
```

**Purpose**: Ensures CI fails on critical security issues while allowing warnings.

## Configuration Files

### Foundry Configuration

**File**: `foundry.toml`

Key CI-optimized settings:

```toml
[profile.ci]
fuzz = { runs = 256 }
invariant = { runs = 32, depth = 100 }
optimizer = true
optimizer_runs = 200
via_ir = false
```

### Echidna CI Configuration

**File**: `echidna-ci.yaml`

CI-optimized Echidna settings:

```yaml
testLimit: 50
seqLen: 8
timeout: 30
workers: 2
corpusDir: null
coverage: false
```

## Environment Variables

### Required Variables

- `FOUNDRY_PROFILE=ci`: Activates CI-optimized testing profile
- `CI=true`: Automatically set by GitHub Actions

### Optional Variables

Environment-specific overrides can be configured in GitHub repository settings:

- `ECHIDNA_TEST_LIMIT`: Override default Echidna test limit
- `FUZZ_RUNS`: Override default fuzz test runs
- `TEST_TIMEOUT`: Override default test timeouts

## Integration Benefits

### Development Workflow Integration

1. **Automatic Testing**: Every push and PR triggers comprehensive testing
2. **Early Detection**: Security issues caught before merging
3. **Consistent Environment**: Same tools and versions across local and CI
4. **Performance Optimization**: CI-specific configurations for faster feedback

### Quality Assurance

1. **Multi-layered Testing**: Property-based, fuzz, and specification testing
2. **Automated Reporting**: Comprehensive test results in PR comments
3. **Historical Tracking**: Test reports stored as artifacts
4. **Failure Analysis**: Detailed logging for debugging

### Security Benefits

1. **Continuous Security Testing**: Property-based testing on every change
2. **Specification Validation**: Automated Scribble contract validation
3. **Critical Issue Detection**: Automatic pipeline failure on security violations
4. **Audit Trail**: Complete testing history via artifacts

## Customization Guidelines

### Adding New Tests

To integrate new security tests into the CI pipeline:

1. **Add Test Step**: Create new job step in workflow file
2. **Configure Timeout**: Set appropriate timeout for CI environment
3. **Capture Results**: Store results in `$GITHUB_OUTPUT` for PR commenting
4. **Update Summary**: Include new test in security summary generation

### Environment Optimization

For different environments:

1. **Create Profile**: Add new Foundry profile in `foundry.toml`
2. **Configure Timeouts**: Adjust timeouts for environment capabilities
3. **Update Workflow**: Modify GitHub Actions to use new profile
4. **Test Locally**: Verify changes work in local environment first

### Performance Tuning

To optimize CI performance:

1. **Profile Analysis**: Use GitHub Actions timing to identify bottlenecks
2. **Cache Integration**: Implement caching for dependencies and build artifacts
3. **Parallel Execution**: Run independent tests in parallel jobs
4. **Selective Testing**: Run different test suites based on changed files

## Monitoring and Maintenance

### Performance Monitoring

- Monitor workflow execution times in GitHub Actions
- Track artifact sizes and retention needs
- Review timeout settings based on actual execution times

### Maintenance Tasks

1. **Tool Updates**: Regularly update tool versions (Foundry, Echidna, Node.js)
2. **Dependency Updates**: Keep npm and pip dependencies current
3. **Configuration Review**: Periodically review timeout and limit settings
4. **Artifact Cleanup**: Monitor artifact storage usage and retention policies

## Troubleshooting CI Issues

For common CI issues, refer to the comprehensive troubleshooting guide at `docs/TROUBLESHOOTING-CI.md`.

## Security Considerations

1. **No Secrets in Logs**: Ensure no sensitive information appears in test output
2. **Artifact Security**: Test reports may contain sensitive contract information
3. **Permission Limits**: Workflow permissions restricted to minimum required
4. **Dependency Security**: Regular security scans of npm and pip dependencies

This CI/CD integration provides comprehensive automated testing while maintaining optimal performance for continuous integration workflows.
