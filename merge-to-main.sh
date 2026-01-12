#!/bin/bash
#==============================================================================
# Merge to Main Script
#==============================================================================
# Purpose: Create and optionally auto-merge a PR from develop to main
# Usage:   ./merge-to-main.sh [options]
#
# Options:
#   --auto          Enable auto-merge (will merge when checks pass)
#   --no-auto       Disable auto-merge (manual merge required)
#   --dry-run       Show what would be done without creating PR
#   --help          Show this help
#
# Examples:
#   ./merge-to-main.sh                    # Create PR with auto-merge
#   ./merge-to-main.sh --no-auto          # Create PR, manual merge
#   ./merge-to-main.sh --dry-run          # Preview only
#==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default options
AUTO_MERGE=true
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_MERGE=true
            shift
            ;;
        --no-auto)
            AUTO_MERGE=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            grep "^#" "$0" | grep -v "#!/bin/bash" | sed 's/^# //; s/^#//'
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Merge Develop to Main                             ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}✗ Error: GitHub CLI (gh) is not installed${NC}"
    echo ""
    echo "Install it with:"
    echo "  macOS:   brew install gh"
    echo "  Ubuntu:  sudo apt install gh"
    echo ""
    echo "Or visit: https://cli.github.com/"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${RED}✗ Error: Not authenticated with GitHub CLI${NC}"
    echo ""
    echo "Run: gh auth login"
    exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [ "$CURRENT_BRANCH" != "develop" ]; then
    echo -e "${YELLOW}⚠️  Warning: You're not on the develop branch${NC}"
    echo -e "   Current branch: ${BLUE}$CURRENT_BRANCH${NC}"
    echo ""
    read -p "Switch to develop branch? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git checkout develop
    else
        echo -e "${RED}Aborted${NC}"
        exit 1
    fi
fi

# Pull latest changes
echo -e "${BLUE}→ Pulling latest changes from develop...${NC}"
git pull origin develop

# Check if develop is ahead of main
COMMITS_AHEAD=$(git rev-list --count main..develop)

if [ "$COMMITS_AHEAD" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: develop is not ahead of main${NC}"
    echo -e "   No changes to merge."
    exit 0
fi

echo -e "${GREEN}✓ develop is $COMMITS_AHEAD commit(s) ahead of main${NC}"
echo ""

# Check latest workflow run on develop
echo -e "${BLUE}→ Checking latest test results on develop...${NC}"

LATEST_RUN=$(gh run list --branch develop --workflow "Test Suite" --limit 1 --json conclusion,status,headSha,databaseId)
RUN_STATUS=$(echo "$LATEST_RUN" | jq -r '.[0].status')
RUN_CONCLUSION=$(echo "$LATEST_RUN" | jq -r '.[0].conclusion')
RUN_SHA=$(echo "$LATEST_RUN" | jq -r '.[0].headSha')
RUN_ID=$(echo "$LATEST_RUN" | jq -r '.[0].databaseId')

CURRENT_SHA=$(git rev-parse HEAD)

if [ "$RUN_SHA" != "$CURRENT_SHA" ]; then
    echo -e "${YELLOW}⚠️  Warning: Latest workflow run is for a different commit${NC}"
    echo -e "   Current HEAD: ${CURRENT_SHA:0:7}"
    echo -e "   Tested commit: ${RUN_SHA:0:7}"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Aborted${NC}"
        exit 1
    fi
fi

if [ "$RUN_STATUS" = "in_progress" ] || [ "$RUN_STATUS" = "queued" ]; then
    echo -e "${YELLOW}⚠️  Tests are still running (status: $RUN_STATUS)${NC}"
    echo -e "   Workflow: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/actions/runs/$RUN_ID"
    echo ""
    read -p "Wait for tests to complete? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}→ Waiting for tests to complete...${NC}"
        gh run watch "$RUN_ID"
        # Re-check status
        LATEST_RUN=$(gh run view "$RUN_ID" --json conclusion)
        RUN_CONCLUSION=$(echo "$LATEST_RUN" | jq -r '.conclusion')
    else
        echo -e "${YELLOW}Proceeding without waiting...${NC}"
    fi
fi

if [ "$RUN_CONCLUSION" != "success" ]; then
    echo -e "${RED}✗ Latest test run failed or was cancelled${NC}"
    echo -e "   Conclusion: $RUN_CONCLUSION"
    echo -e "   Workflow: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/actions/runs/$RUN_ID"
    echo ""
    echo -e "${YELLOW}Fix the tests on develop before merging to main.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All tests passed${NC}"
echo ""

# Check if PR already exists
echo -e "${BLUE}→ Checking for existing PR...${NC}"
EXISTING_PR=$(gh pr list --head develop --base main --state open --json number --jq '.[0].number')

if [ -n "$EXISTING_PR" ]; then
    echo -e "${YELLOW}⚠️  PR already exists: #$EXISTING_PR${NC}"
    echo ""
    gh pr view "$EXISTING_PR"
    echo ""
    read -p "Update and merge this PR? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        PR_NUMBER="$EXISTING_PR"
        SKIP_CREATE=true
    else
        echo -e "${RED}Aborted${NC}"
        exit 1
    fi
else
    SKIP_CREATE=false
fi

# Generate PR title and body
COMMIT_COUNT=$COMMITS_AHEAD
if [ "$COMMIT_COUNT" -eq 1 ]; then
    PR_TITLE=$(git log -1 --pretty=%s)
else
    PR_TITLE="Merge develop to main ($COMMIT_COUNT commits)"
fi

PR_BODY=$(cat <<EOF
## 📦 Release from develop

This PR merges **$COMMIT_COUNT commit(s)** from develop to main.

### ✅ Test Results
All tests passed on develop branch.
- Workflow run: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/actions/runs/$RUN_ID

### 📝 Commits
$(git log --oneline main..develop | sed 's/^/- /')

---
*Created with merge-to-main.sh*
EOF
)

if [ "$DRY_RUN" = true ]; then
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          DRY RUN - No changes will be made                 ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}PR Title:${NC}"
    echo "$PR_TITLE"
    echo ""
    echo -e "${BLUE}PR Body:${NC}"
    echo "$PR_BODY"
    echo ""
    echo -e "${BLUE}Options:${NC}"
    echo "  Auto-merge: $AUTO_MERGE"
    exit 0
fi

# Create PR if it doesn't exist
if [ "$SKIP_CREATE" = false ]; then
    echo -e "${BLUE}→ Creating pull request...${NC}"

    # Create PR and capture the URL
    PR_URL=$(gh pr create \
        --base main \
        --head develop \
        --title "$PR_TITLE" \
        --body "$PR_BODY" 2>&1)

    # Extract PR number from URL (e.g., https://github.com/user/repo/pull/123)
    PR_NUMBER=$(echo "$PR_URL" | grep -o '/pull/[0-9]\+' | grep -o '[0-9]\+')

    if [ -z "$PR_NUMBER" ]; then
        echo -e "${RED}✗ Failed to create PR${NC}"
        echo "$PR_URL"
        exit 1
    fi

    echo -e "${GREEN}✓ Created PR #$PR_NUMBER${NC}"
    echo ""
fi

# Show PR
gh pr view "$PR_NUMBER"
echo ""

# Enable auto-merge if requested
if [ "$AUTO_MERGE" = true ]; then
    echo -e "${BLUE}→ Enabling auto-merge...${NC}"
    gh pr merge "$PR_NUMBER" --auto --squash

    echo -e "${GREEN}✓ Auto-merge enabled${NC}"
    echo -e "   PR will be merged automatically when all checks pass"
else
    echo -e "${YELLOW}⚠️  Auto-merge disabled${NC}"
    echo -e "   Merge manually when ready:"
    echo -e "   ${BLUE}gh pr merge $PR_NUMBER --squash${NC}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Pull Request Ready!                               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "PR URL: $(gh pr view "$PR_NUMBER" --json url -q .url)"

exit 0
