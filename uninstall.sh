#!/bin/bash
# Uninstall Traefik CLI (tk) - Removes CLI from PATH
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Uninstalling Traefik CLI (tk)                    ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Detect shell
SHELL_RC=""
SHELL_NAME=""

if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
    SHELL_NAME="zsh"
elif [ -n "$BASH_VERSION" ] || [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
    SHELL_NAME="bash"
fi

# Check if installed
if [ -n "$SHELL_RC" ] && grep -q "# Traefik CLI" "$SHELL_RC" 2>/dev/null; then
    echo -e "${YELLOW}Removing Traefik CLI from ${SHELL_RC}...${NC}"

    # Backup
    cp "$SHELL_RC" "${SHELL_RC}.backup-$(date +%Y%m%d-%H%M%S)"

    # Remove configuration
    sed -i.tmp '/# Traefik CLI/,/# End Traefik CLI/d' "$SHELL_RC"
    rm -f "${SHELL_RC}.tmp"

    # Remove aliases if present
    sed -i.tmp '/# Traefik CLI Aliases/,/# End Traefik CLI Aliases/d' "$SHELL_RC"
    rm -f "${SHELL_RC}.tmp"

    echo -e "${GREEN}✓ Removed from ${SHELL_RC}${NC}"
else
    echo -e "${YELLOW}Traefik CLI not found in shell configuration${NC}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                      UNINSTALLED!                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo -e "  1. Reload your shell configuration:"
echo -e "     ${YELLOW}source ${SHELL_RC}${NC}"
echo ""
echo -e "  2. Or restart your terminal"
echo ""
echo -e "${YELLOW}Note: The tk script and other files were not deleted.${NC}"
echo -e "${YELLOW}To reinstall, run: ./install.sh${NC}"
echo ""
