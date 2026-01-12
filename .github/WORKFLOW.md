# GitHub Actions Workflow Guide

## Branch Strategy

This repository uses a **develop → main** workflow with automated testing and manual PR merging.

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
       │  Create PR       │
       │  (manual/script) │
       │  develop→main    │
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

### 3. **Create Pull Request** (When Ready)

Once tests pass and you're ready to merge to main, create a PR:

**Option A: Using the helper script** (Recommended)
```bash
./scripts/merge-to-main.sh
```

**Option B: Using gh CLI**
```bash
gh pr create \
  --base main \
  --head develop \
  --title "Merge develop to main" \
  --body "All tests passed on develop branch. Ready to merge." \
  --label "release"

# Enable auto-merge (optional but recommended)
gh pr merge --auto --squash
```

**Option C: Via GitHub UI**
1. Go to: https://github.com/natejswenson/traefik-local-cli/compare/main...develop
2. Click "Create pull request"
3. Fill in title and description
4. Enable "Auto-merge" if desired
5. Click "Create pull request"

### 4. **PR Checks & Merge**

- The PR will show test status from develop
- Review changes if needed
- Merge when ready (or auto-merge will handle it)
- Uses **squash merge** to keep main history clean

## Quick Reference

### Daily Development Workflow

```bash
# 1. Start on develop
git checkout develop
git pull origin develop

# 2. Make changes
# ... edit files ...

# 3. Test locally
./run-tests.sh

# 4. Commit and push
git add .
git commit -m "feat: Your feature description"
git push origin develop

# 5. Wait for tests to pass
# Monitor: https://github.com/natejswenson/traefik-local-cli/actions

# 6. When ready to release, create PR
./scripts/merge-to-main.sh
# OR
gh pr create --base main --head develop

# 7. Merge the PR
gh pr merge --auto --squash
# OR merge via GitHub UI
```

### Helper Commands

```bash
# Check test status
gh run list --branch develop --limit 5

# View latest workflow run
gh run view

# Watch workflow in real-time
gh run watch

# Create and auto-merge PR in one command
gh pr create --base main --head develop --title "Release" --body "Tests passed" && gh pr merge --auto --squash
```

## Configuration

### Test Workflow
**File:** `.github/workflows/test.yml`

**Triggers:**
```yaml
on:
  push:
    branches: [ develop ]
  pull_request:
    branches: [ main, develop ]
  workflow_dispatch:
```

**Environment variables:**
```yaml
env:
  COVERAGE_THRESHOLD: 95  # Minimum code coverage (optional)
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

# Run with verbose output
./run-tests.sh --verbose
```

### When to Create PRs

**Create a PR from develop → main when:**
- ✅ All tests pass on develop
- ✅ You're ready to release changes
- ✅ Features are complete and tested
- ✅ Documentation is updated

**Don't wait for:**
- ❌ Every single commit
- ❌ Minor fixes or typos
- ❌ Work in progress

**Good practice:** Bundle related changes into meaningful releases.

### Branch Protection

Consider enabling these protections on main:
- ✅ Require pull request reviews
- ✅ Require status checks to pass
- ✅ Require branches to be up to date
- ✅ Do not allow bypassing settings

## Troubleshooting

### Tests Fail
- Check the workflow logs: `https://github.com/natejswenson/traefik-local-cli/actions`
- Fix issues on develop branch
- Push again - workflow will re-run

### Can't Create PR
```bash
# Check if gh CLI is installed
gh --version

# Authenticate if needed
gh auth login

# Check if develop is ahead of main
git log main..develop
```

### Merge Conflicts
If develop has conflicts with main:

```bash
# From develop branch
git checkout develop
git pull origin develop
git merge origin/main

# Resolve conflicts
# ... edit files ...

git add .
git commit -m "chore: Resolve merge conflicts"
git push origin develop

# Now create PR
gh pr create --base main --head develop
```

### PR Already Exists
If a PR already exists from develop to main:

```bash
# Find the PR number
gh pr list --head develop --base main

# Update the PR description or merge it
gh pr merge <PR_NUMBER> --squash
```

## Advanced Usage

### Release Process with Tags

```bash
# After merging to main, tag the release
git checkout main
git pull origin main
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# Create GitHub release
gh release create v1.0.0 --title "v1.0.0" --notes "Release notes here"
```

### Hotfix Process

For urgent fixes that can't wait:

```bash
# Create hotfix branch from main
git checkout main
git pull origin main
git checkout -b hotfix/critical-bug

# Make fix
# ... edit files ...

# Test
./run-tests.sh

# Commit and push
git commit -am "fix: Critical bug"
git push origin hotfix/critical-bug

# Create PR to main
gh pr create --base main --head hotfix/critical-bug

# After merging to main, merge back to develop
git checkout develop
git merge main
git push origin develop
```

## Workflow Files Reference

| File | Purpose | Triggers |
|------|---------|----------|
| `test.yml` | Run all tests, linting, security scans | Push to develop, PRs to main/develop |

## Questions?

For issues or questions:
- Open an issue: https://github.com/natejswenson/traefik-local-cli/issues
- Check workflow runs: https://github.com/natejswenson/traefik-local-cli/actions
- Read the docs: [README.md](../README.md)
