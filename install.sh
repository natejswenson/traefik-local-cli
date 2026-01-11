#!/bin/bash
# Install Traefik CLI (tk) - Adds CLI to PATH via zshrc or bashrc
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TK_PATH="${SCRIPT_DIR}/tk"

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║            Installing Traefik CLI (tk)                    ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if tk exists
if [ ! -f "$TK_PATH" ]; then
    echo -e "${RED}Error: tk script not found at: $TK_PATH${NC}"
    exit 1
fi

# Make executable
chmod +x "$TK_PATH"
echo -e "${GREEN}✓ Made tk executable${NC}"

# Detect shell
SHELL_RC=""
SHELL_NAME=""

if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
    SHELL_NAME="zsh"
elif [ -n "$BASH_VERSION" ] || [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
    SHELL_NAME="bash"
else
    echo -e "${YELLOW}Warning: Could not detect shell type${NC}"
    echo -e "${YELLOW}Please add the following to your shell config manually:${NC}"
    echo ""
    echo -e "${CYAN}export PATH=\"\$PATH:${SCRIPT_DIR}\"${NC}"
    echo ""
    exit 0
fi

echo -e "${BLUE}Detected shell: ${SHELL_NAME}${NC}"
echo -e "${BLUE}Shell config: ${SHELL_RC}${NC}"
echo ""

# Check if already installed
if grep -q "# Traefik CLI" "$SHELL_RC" 2>/dev/null; then
    echo -e "${YELLOW}✓ Traefik CLI already configured in ${SHELL_RC}${NC}"
    echo -e "${YELLOW}  Updating existing configuration...${NC}"

    # Remove old configuration
    sed -i.backup '/# Traefik CLI/,/# End Traefik CLI/d' "$SHELL_RC"
fi

# Add to PATH
echo "" >> "$SHELL_RC"
echo "# Traefik CLI" >> "$SHELL_RC"
echo "export PATH=\"\$PATH:${SCRIPT_DIR}\"" >> "$SHELL_RC"
echo "# End Traefik CLI" >> "$SHELL_RC"

echo -e "${GREEN}✓ Added to ${SHELL_RC}${NC}"
echo ""

# Create optional alias
read -p "Would you like to create additional aliases? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "" >> "$SHELL_RC"
    echo "# Traefik CLI Aliases" >> "$SHELL_RC"
    echo "alias tk-up='tk start'" >> "$SHELL_RC"
    echo "alias tk-down='tk stop'" >> "$SHELL_RC"
    echo "alias tk-logs='tk logs'" >> "$SHELL_RC"
    echo "alias tk-ps='tk status'" >> "$SHELL_RC"
    echo "# End Traefik CLI Aliases" >> "$SHELL_RC"
    echo -e "${GREEN}✓ Aliases created${NC}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  INSTALLATION COMPLETE!                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo -e "  1. Reload your shell configuration:"
echo -e "     ${YELLOW}source ${SHELL_RC}${NC}"
echo ""
echo -e "  2. Or restart your terminal"
echo ""
echo -e "  3. Start using the CLI:"
echo -e "     ${YELLOW}tk help${NC}"
echo -e "     ${YELLOW}tk list${NC}"
echo -e "     ${YELLOW}tk status${NC}"
echo ""
echo -e "${BLUE}Tip: You can also run tk directly from this directory:${NC}"
echo -e "  ${CYAN}${TK_PATH}${NC}"
echo ""
