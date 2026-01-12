# GitHub Actions Workflow Guide

## Branch Strategy

This repository uses a **develop → main** workflow with automated testing and merging.

### Branch Structure

- **`main`** - Production-ready code. Protected branch.
- **`develop`** - Integration branch for development. All changes go here first.

## Workflow Overview

```
┌─────────────┐
│   Commit    │
│  to develop │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│  Test Suite     │
│  - Unit Tests   │
│  - Integration  │
│  - Linting      │
│  - Security     │
└──────┬──────────┘
       │
       ├─── ❌ Tests Fail ──→ Fix and retry
       │
       └─── ✅ Tests Pass
              │
              ▼
       ┌──────────────────┐
       │  Auto-Merge      │
       │  - Create PR     │
       │  - develop→main  │
       │  - Auto-merge    │
       └────────┬─────────┘
                │
                ▼
         ┌──────────────┐
         │  main branch │
         │   updated    │
         └──────────────┘
```

## How It Works

### 1. **Push to Develop**
When you push commits to the `develop` branch, the Test Suite workflow automatically runs.

```bash
git checkout develop
git add .
git commit -m "feat: Add new feature"
git push origin develop
```

### 2. **Test Suite Runs**
The Test Suite workflow (`.github/workflows/test.yml`) executes:

- ✅ **Unit Tests** - 43 tests covering core functionality
- ✅ **Integration Tests** - 21 tests for end-to-end workflows
- ✅ **Linting** - ShellCheck on all scripts (errors only)
- ✅ **Security Scan** - Checks for hardcoded secrets and dangerous commands
- ✅ **Permission Check** - Validates all scripts are executable

**Triggers:**
- Push to `develop` branch
- Pull requests to `main` or `develop`
- Manual trigger via workflow_dispatch

### 3. **Auto-Merge Workflow**
If all tests pass, the Auto-Merge workflow (`.github/workflows/auto-merge.yml`) triggers:

**Steps:**
1. **Check for existing PR** - Looks for open PR from develop to main
2. **Create PR** (if none exists) - Creates PR with test results and commit info
3. **Wait for checks** - Waits for any additional PR checks to complete
4. **Auto-merge** - Squash merges the PR into main
5. **Delete branch** - Cleans up the develop branch after merge

**What gets merged:**
- Uses **squash merge** to keep main history clean
- Deletes the source branch after merge (optional)
- Includes test results and workflow links in PR description

## Configuration

### Test Workflow
**File:** `.github/workflows/test.yml`

**Key settings:**
```yaml
on:
  push:
    branches: [ develop ]
  pull_request:
    branches: [ main, develop ]
```

**Environment variables:**
```yaml
env:
  COVERAGE_THRESHOLD: 95  # Minimum code coverage (optional)
```

### Auto-Merge Workflow
**File:** `.github/workflows/auto-merge.yml`

**Key settings:**
```yaml
on:
  workflow_run:
    workflows: ["Test Suite"]
    types: [completed]
    branches: [develop]
```

**Permissions required:**
```yaml
permissions:
  contents: write        # To merge PRs
  pull-requests: write   # To create and manage PRs
```

## Manual Override

### Disable Auto-Merge for Specific Commits
If you want tests to run without auto-merging, you can:

1. **Push to a feature branch** instead of develop:
   ```bash
   git checkout -b feature/my-feature
   git push origin feature/my-feature
   ```

2. **Close the auto-created PR** and merge manually later

### Manual Merge
To manually merge develop to main:

```bash
# From main branch
git checkout main
git pull origin main

# Merge develop
git merge develop

# Push to main
git push origin main
```

## Troubleshooting

### Tests Fail
- Check the workflow logs: `https://github.com/natejswenson/traefik-local-cli/actions`
- Fix issues on develop branch
- Push again - workflow will re-run

### Auto-Merge Fails
The workflow will add a comment to the PR with failure reason. Common issues:
- **Merge conflicts** - Resolve conflicts manually
- **PR not mergeable** - Check branch protection rules
- **Checks pending** - Wait for all checks to complete

You can always merge manually using:
```bash
gh pr merge <PR_NUMBER> --squash
```

### Workflow Not Triggering
- Verify you pushed to `develop` branch
- Check workflow file syntax is valid
- Ensure GitHub Actions are enabled in repository settings

## Development Workflow

### Recommended Process

1. **Clone and setup**
   ```bash
   git clone https://github.com/natejswenson/traefik-local-cli.git
   cd traefik-local-cli
   git checkout develop
   ```

2. **Make changes**
   ```bash
   # Edit files
   vim tk

   # Test locally
   ./run-tests.sh
   ```

3. **Commit and push**
   ```bash
   git add .
   git commit -m "feat: Your feature description"
   git push origin develop
   ```

4. **Monitor workflow**
   - Visit: https://github.com/natejswenson/traefik-local-cli/actions
   - Wait for tests to pass
   - Auto-merge will trigger automatically

5. **Verify merge**
   ```bash
   git checkout main
   git pull origin main
   # Verify your changes are in main
   ```

## Best Practices

### Commit Messages
Use conventional commit format:
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `test:` - Test additions/changes
- `refactor:` - Code refactoring
- `chore:` - Maintenance tasks

Example: `feat: Add support for PostgreSQL detection`

### Testing Before Push
Always run tests locally before pushing:

```bash
# Run all tests
./run-tests.sh

# Run specific test suites
./run-tests.sh --unit
./run-tests.sh --integration

# Run with coverage
./run-tests.sh --coverage
```

### Branch Protection
Consider enabling these protections on main:
- ✅ Require pull request reviews
- ✅ Require status checks to pass
- ✅ Require branches to be up to date
- ✅ Do not allow bypassing settings

## Workflow Files Reference

| File | Purpose | Triggers |
|------|---------|----------|
| `test.yml` | Run all tests, linting, security scans | Push to develop, PRs to main/develop |
| `auto-merge.yml` | Create and auto-merge PR to main | Test suite passes on develop |

## Questions?

For issues or questions:
- Open an issue: https://github.com/natejswenson/traefik-local-cli/issues
- Check workflow runs: https://github.com/natejswenson/traefik-local-cli/actions
