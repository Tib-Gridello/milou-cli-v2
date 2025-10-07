#!/bin/bash
# Milou CLI v2 - Minimal Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/milou-sh/milou-cli-v2/main/install.sh | bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REPO="https://github.com/milou-sh/milou-cli-v2"
BRANCH="${MILOU_BRANCH:-main}"
INSTALL_DIR="${MILOU_INSTALL_DIR:-$HOME/milou-cli}"

# Simple logging
log() { echo -e "${BLUE}→${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1" >&2; exit 1; }

# Check dependencies
check_deps() {
    log "Checking dependencies..."

    # Check for curl or wget
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        error "curl or wget is required"
    fi

    # Check for tar
    if ! command -v tar &>/dev/null; then
        error "tar is required"
    fi

    success "Dependencies OK"
}

# Backup existing installation if present
backup_existing() {
    if [[ -d "$INSTALL_DIR" ]]; then
        log "Existing installation found"

        # Backup important files
        local backup_dir="/tmp/milou_backup_$$"
        mkdir -p "$backup_dir"

        # Backup .env if it exists
        [[ -f "$INSTALL_DIR/.env" ]] && cp "$INSTALL_DIR/.env" "$backup_dir/"

        # Backup SSL certificates if they exist
        [[ -d "$INSTALL_DIR/ssl" ]] && cp -r "$INSTALL_DIR/ssl" "$backup_dir/"

        # Backup any backups
        [[ -d "$INSTALL_DIR/backups" ]] && cp -r "$INSTALL_DIR/backups" "$backup_dir/"

        echo "$backup_dir"
    else
        echo ""
    fi
}

# Restore backed up files
restore_backup() {
    local backup_dir="$1"

    if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
        log "Restoring configuration..."

        # Restore .env
        [[ -f "$backup_dir/.env" ]] && cp "$backup_dir/.env" "$INSTALL_DIR/"

        # Restore SSL certificates
        [[ -d "$backup_dir/ssl" ]] && cp -r "$backup_dir/ssl" "$INSTALL_DIR/"

        # Restore backups
        [[ -d "$backup_dir/backups" ]] && cp -r "$backup_dir/backups" "$INSTALL_DIR/"

        # Clean up temp backup
        rm -rf "$backup_dir"

        success "Configuration restored"
    fi
}

# Download and install
install() {
    log "Installing Milou CLI v2 to $INSTALL_DIR..."

    # Backup existing installation
    local backup_dir=$(backup_existing)

    # Remove old installation
    rm -rf "$INSTALL_DIR"

    # Create directory
    mkdir -p "$INSTALL_DIR"

    # Download and extract
    log "Downloading from $REPO..."
    if command -v curl &>/dev/null; then
        curl -fsSL "$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$INSTALL_DIR" --strip-components=1
    else
        wget -qO- "$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$INSTALL_DIR" --strip-components=1
    fi

    # Make executable
    chmod +x "$INSTALL_DIR/milou"
    chmod +x "$INSTALL_DIR/lib"/*.sh 2>/dev/null || true

    # Restore backup if exists
    restore_backup "$backup_dir"

    success "Installation complete!"
}

# Add to PATH
setup_path() {
    log "Setting up PATH..."

    local shell_rc=""

    # Detect shell configuration file
    if [[ -f "$HOME/.bashrc" ]]; then
        shell_rc="$HOME/.bashrc"
    elif [[ -f "$HOME/.zshrc" ]]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.profile"
    fi

    # Check if already in PATH
    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
        echo "" >> "$shell_rc"
        echo "# Milou CLI" >> "$shell_rc"
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$shell_rc"
        success "Added to PATH in $shell_rc"
        log "Run: source $shell_rc"
    else
        success "Already in PATH"
    fi
}

# Main
main() {
    echo ""
    echo "Milou CLI v2 Installer"
    echo "======================"
    echo ""

    check_deps
    install
    setup_path

    echo ""
    success "Installation successful!"
    echo ""
    echo "Next steps:"
    echo "  1. source your shell config or restart terminal"
    echo "  2. Run: milou setup"
    echo "  3. Run: milou start"
    echo ""
    echo "Documentation: https://milou.sh/docs"
    echo ""
}

# Run
main "$@"