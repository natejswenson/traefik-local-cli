#!/usr/bin/env bash
#
# setup-commit-signing.sh - Setup GPG commit signing for Git
#
# This script helps developers configure GPG commit signing
# to meet the repository's security requirements.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Git GPG Commit Signing Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if GPG is installed
if ! command -v gpg >/dev/null 2>&1; then
  echo -e "${RED}Error: GPG is not installed${NC}"
  echo ""
  echo "Install GPG:"
  echo -e "  ${GREEN}macOS:${NC}  brew install gnupg"
  echo -e "  ${GREEN}Ubuntu:${NC} sudo apt-get install gnupg"
  echo -e "  ${GREEN}Fedora:${NC} sudo dnf install gnupg2"
  echo ""
  exit 1
fi

echo -e "${GREEN}✓${NC} GPG is installed"
echo ""

# Check for existing GPG keys
echo "Checking for existing GPG keys..."
if gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep -q "sec"; then
  echo -e "${GREEN}✓${NC} Existing GPG keys found:"
  echo ""
  gpg --list-secret-keys --keyid-format LONG
  echo ""
  read -p "Do you want to use an existing key? (y/n): " use_existing

  if [[ "$use_existing" == "y" || "$use_existing" == "Y" ]]; then
    # Use existing key
    echo ""
    read -p "Enter the GPG key ID (e.g., 3AA5C34371567BD2): " key_id
  else
    # Generate new key
    echo ""
    echo "Generating new GPG key..."
    echo ""
    echo "Please enter your information:"
    echo "  - Name: Your full name"
    echo "  - Email: Your Git email address"
    echo "  - Passphrase: A strong password to protect your key"
    echo ""
    gpg --full-generate-key
    echo ""
    echo "Key generated successfully!"
    echo ""
    gpg --list-secret-keys --keyid-format LONG
    echo ""
    read -p "Enter the GPG key ID from above (e.g., 3AA5C34371567BD2): " key_id
  fi
else
  # No keys found, generate new one
  echo -e "${YELLOW}No GPG keys found.${NC} Generating new key..."
  echo ""
  echo "Please enter your information:"
  echo "  - Name: Your full name"
  echo "  - Email: Your Git email address (must match your Git config)"
  echo "  - Passphrase: A strong password to protect your key"
  echo ""
  gpg --full-generate-key
  echo ""
  echo -e "${GREEN}✓${NC} Key generated successfully!"
  echo ""
  gpg --list-secret-keys --keyid-format LONG
  echo ""
  read -p "Enter the GPG key ID from above (e.g., 3AA5C34371567BD2): " key_id
fi

# Validate key ID
if [[ -z "$key_id" ]]; then
  echo -e "${RED}Error: Key ID cannot be empty${NC}"
  exit 1
fi

# Configure Git to use GPG key
echo ""
echo "Configuring Git to use GPG key: $key_id"
git config --global user.signingkey "$key_id"
git config --global commit.gpgsign true
git config --global tag.gpgsign true

echo -e "${GREEN}✓${NC} Git configured successfully"
echo ""

# Configure GPG to use the correct TTY
echo "Configuring GPG TTY..."
if [[ -n "${BASH_VERSION:-}" ]]; then
  shell_config="$HOME/.bashrc"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  shell_config="$HOME/.zshrc"
else
  shell_config="$HOME/.profile"
fi

if ! grep -q "GPG_TTY" "$shell_config" 2>/dev/null; then
  echo 'export GPG_TTY=$(tty)' >> "$shell_config"
  echo -e "${GREEN}✓${NC} Added GPG_TTY to $shell_config"
else
  echo -e "${YELLOW}•${NC} GPG_TTY already configured in $shell_config"
fi

echo ""
echo "=========================================="
echo "Your GPG Public Key (for GitHub)"
echo "=========================================="
gpg --armor --export "$key_id"
echo "=========================================="
echo ""

# Instructions for adding to GitHub
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Copy the GPG key above (including the BEGIN and END lines)"
echo ""
echo "2. Add it to GitHub:"
echo -e "   ${BLUE}•${NC} Go to: https://github.com/settings/keys"
echo -e "   ${BLUE}•${NC} Click 'New GPG key'"
echo -e "   ${BLUE}•${NC} Paste the key"
echo -e "   ${BLUE}•${NC} Click 'Add GPG key'"
echo ""
echo "3. Verify your email address in GitHub matches your GPG key email"
echo ""
echo "4. Reload your shell:"
echo -e "   ${GREEN}source $shell_config${NC}"
echo ""

# Test commit signing
echo "Testing commit signing..."
echo ""

# Create a temporary test file
test_file=$(mktemp)
echo "test" > "$test_file"

# Try to create a test commit in current repo if it's a git repo
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # We're in a git repo
  if git add "$test_file" 2>/dev/null && git commit -S -m "Test signed commit (will be reset)" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Commit signing test successful!"
    # Reset the test commit
    git reset HEAD~1 >/dev/null 2>&1
    git restore --staged "$test_file" 2>/dev/null || git reset HEAD "$test_file" 2>/dev/null || true
  else
    echo -e "${YELLOW}⚠${NC}  Commit signing test failed"
    echo "   This might be due to GPG agent issues or incorrect configuration"
    echo "   Try creating a real commit to test signing"
  fi
else
  echo -e "${YELLOW}⚠${NC}  Not in a git repository - skipping commit test"
  echo "   Create a commit in a git repository to test signing"
fi

# Cleanup
rm -f "$test_file" 2>/dev/null || true

echo ""
echo "=========================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "All future commits will be signed automatically."
echo ""
echo "To verify a commit is signed:"
echo -e "  ${GREEN}git log --show-signature${NC}"
echo ""
echo "To sign existing commits:"
echo -e "  ${GREEN}git rebase --exec 'git commit --amend --no-edit -S' -i HEAD~N${NC}"
echo ""
