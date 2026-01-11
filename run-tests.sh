#!/bin/bash
#==============================================================================
# Test Runner Script
#==============================================================================
# Purpose: Run all tests with coverage reporting
# Usage:   ./run-tests.sh [options]
#
# Options:
#   --unit          Run only unit tests
#   --integration   Run only integration tests
#   --coverage      Generate coverage report
#   --verbose       Verbose output
#   --help          Show this help
#
# Examples:
#   ./run-tests.sh                    # Run all tests
#   ./run-tests.sh --unit             # Run only unit tests
#   ./run-tests.sh --coverage         # Run all tests with coverage
#==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/tests"
COVERAGE_DIR="${TEST_DIR}/coverage"

# Default options
RUN_UNIT=true
RUN_INTEGRATION=true
GENERATE_COVERAGE=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --unit)
            RUN_INTEGRATION=false
            shift
            ;;
        --integration)
            RUN_UNIT=false
            shift
            ;;
        --coverage)
            GENERATE_COVERAGE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            grep "^#" "$0" | grep -v "#!/bin/bash" | sed 's/^# //; s/^#//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if bats is installed
if ! command -v bats &> /dev/null; then
    echo -e "${RED}ERROR: bats is not installed${NC}"
    echo ""
    echo "Install bats using one of these methods:"
    echo "  macOS:   brew install bats-core"
    echo "  Ubuntu:  sudo apt-get install bats"
    echo "  npm:     npm install -g bats"
    exit 1
fi

# Check if kcov is installed (for coverage)
if [ "$GENERATE_COVERAGE" = true ] && ! command -v kcov &> /dev/null; then
    echo -e "${YELLOW}WARNING: kcov is not installed, skipping coverage${NC}"
    echo "Install kcov: brew install kcov (macOS) or apt-get install kcov (Linux)"
    GENERATE_COVERAGE=false
fi

# Create coverage directory
mkdir -p "$COVERAGE_DIR"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Traefik Scripts Test Suite                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Run unit tests
if [ "$RUN_UNIT" = true ]; then
    echo -e "${YELLOW}Running unit tests...${NC}"

    if [ "$VERBOSE" = true ]; then
        BATS_FLAGS="--verbose-run --show-output-of-passing-tests"
    else
        BATS_FLAGS=""
    fi

    if [ "$GENERATE_COVERAGE" = true ]; then
        kcov --exclude-pattern=/usr,/tmp "$COVERAGE_DIR/unit" \
            bats $BATS_FLAGS "$TEST_DIR/unit"
    else
        bats $BATS_FLAGS "$TEST_DIR/unit"
    fi

    echo -e "${GREEN}✓ Unit tests completed${NC}"
    echo ""
fi

# Run integration tests
if [ "$RUN_INTEGRATION" = true ]; then
    echo -e "${YELLOW}Running integration tests...${NC}"

    if [ "$VERBOSE" = true ]; then
        BATS_FLAGS="--verbose-run --show-output-of-passing-tests"
    else
        BATS_FLAGS=""
    fi

    if [ "$GENERATE_COVERAGE" = true ]; then
        kcov --exclude-pattern=/usr,/tmp "$COVERAGE_DIR/integration" \
            bats $BATS_FLAGS "$TEST_DIR/integration"
    else
        bats $BATS_FLAGS "$TEST_DIR/integration"
    fi

    echo -e "${GREEN}✓ Integration tests completed${NC}"
    echo ""
fi

# Generate coverage report
if [ "$GENERATE_COVERAGE" = true ]; then
    echo -e "${YELLOW}Generating coverage report...${NC}"

    # Merge coverage reports
    if command -v kcov &> /dev/null; then
        kcov --merge "$COVERAGE_DIR/merged" \
            "$COVERAGE_DIR/unit" \
            "$COVERAGE_DIR/integration" 2>/dev/null || true
    fi

    # Generate summary
    if [ -f "$COVERAGE_DIR/merged/index.html" ]; then
        # Extract coverage percentage
        COVERAGE_PCT=$(grep -o 'covered">[0-9.]*%' "$COVERAGE_DIR/merged/index.html" | head -1 | grep -o '[0-9.]*' || echo "0")

        echo "Total Coverage: ${COVERAGE_PCT}%" > "$COVERAGE_DIR/coverage-summary.txt"

        echo -e "${GREEN}✓ Coverage report generated${NC}"
        echo -e "${BLUE}Coverage: ${COVERAGE_PCT}%${NC}"
        echo -e "${BLUE}Report: ${COVERAGE_DIR}/merged/index.html${NC}"

        # Check if coverage meets threshold
        THRESHOLD=95
        if (( $(echo "$COVERAGE_PCT >= $THRESHOLD" | bc -l) )); then
            echo -e "${GREEN}✓ Coverage meets ${THRESHOLD}% threshold${NC}"
        else
            echo -e "${RED}✗ Coverage below ${THRESHOLD}% threshold${NC}"
            exit 1
        fi
    fi
    echo ""
fi

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          All Tests Passed ✓                                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

exit 0
