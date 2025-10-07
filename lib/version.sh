#!/bin/bash
# version.sh - Simple version management using GitHub releases manifest
# Clean approach: local has version number, check manifest for latest

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

#=============================================================================
# Configuration
#=============================================================================

GITHUB_ORG="${GITHUB_ORG:-milou-sh}"
GITHUB_REPO="${GITHUB_REPO:-milou}"
MANIFEST_URL="https://api.github.com/repos/$GITHUB_ORG/$GITHUB_REPO/releases/latest"

#=============================================================================
# Version Check Functions
#=============================================================================

# Get current version from .env
version_get_current() {
    local version=$(env_get "MILOU_VERSION" 2>/dev/null || echo "")

    # Default to a safe version if not set or if set to "latest"
    if [[ -z "$version" || "$version" == "latest" ]]; then
        version="1.0.0"
        log_warn "MILOU_VERSION not set or set to 'latest'. Defaulting to $version"
        log_info "Run 'milou config set MILOU_VERSION $version' to set explicitly"
    fi

    echo "$version"
}

# Get latest version from GitHub releases manifest
version_get_latest() {
    local response=$(curl -s "$MANIFEST_URL" 2>/dev/null || echo "")

    if [[ -z "$response" ]] || echo "$response" | grep -q '"message"'; then
        log_debug "Could not fetch version manifest from GitHub"
        echo ""
        return 1
    fi

    # Extract tag_name which contains the version
    local latest=$(echo "$response" | grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/^v//')

    if [[ -z "$latest" ]]; then
        # Fallback: try to get from release body if it contains manifest
        local body=$(echo "$response" | grep -A50 '"body"' | head -51)
        latest=$(echo "$body" | grep '"latest"' | head -1 | cut -d'"' -f4)
    fi

    echo "$latest"
}

# Compare two semantic versions
# Returns: 0 if v1 < v2, 1 if v1 >= v2
version_needs_update() {
    local current="$1"
    local latest="$2"

    # Remove v prefix if present
    current="${current#v}"
    latest="${latest#v}"

    # Simple string comparison using sort -V
    if [[ "$current" == "$latest" ]]; then
        return 1  # No update needed
    fi

    # Check if current is less than latest
    local sorted=$(echo -e "$current\n$latest" | sort -V | head -1)

    if [[ "$sorted" == "$current" ]]; then
        return 0  # Update needed
    else
        return 1  # Current is newer (shouldn't happen but handle it)
    fi
}

#=============================================================================
# Main Functions
#=============================================================================

# Check for updates
version_check_updates() {
    local quiet="${1:-false}"

    [[ "$quiet" != "true" ]] && log_info "Checking for updates..."

    local current=$(version_get_current)
    local latest=$(version_get_latest)

    if [[ -z "$latest" ]]; then
        [[ "$quiet" != "true" ]] && log_warn "Could not check for updates (no internet or GitHub API issue)"
        return 2
    fi

    if version_needs_update "$current" "$latest"; then
        [[ "$quiet" != "true" ]] && {
            log_success "Update available: v$current → v$latest"
            echo ""
            log_info "To update, run:"
            echo "  1. milou config set MILOU_VERSION $latest"
            echo "  2. milou update"
        }
        return 0
    else
        [[ "$quiet" != "true" ]] && log_success "You are running the latest version (v$current)"
        return 1
    fi
}

# Show version information
version_show() {
    local current=$(version_get_current)
    local latest=$(version_get_latest)

    echo "Milou Version Information"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "CLI Version:     v2.0.0"
    echo "Current Images:  v$current"

    if [[ -n "$latest" ]]; then
        echo "Latest Available: v$latest"

        if version_needs_update "$current" "$latest"; then
            echo "Status:          Update available!"
        else
            echo "Status:          Up to date"
        fi
    else
        echo "Latest Available: (could not check)"
        echo "Status:          Unknown"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

#=============================================================================
# Command Handler
#=============================================================================

version_manage() {
    local action="${1:-show}"

    case "$action" in
        check|check-updates)
            version_check_updates "false"
            ;;
        current)
            version_get_current
            ;;
        latest)
            local latest=$(version_get_latest)
            if [[ -n "$latest" ]]; then
                echo "$latest"
            else
                log_error "Could not fetch latest version"
                return 1
            fi
            ;;
        show|"")
            version_show
            ;;
        *)
            log_error "Unknown version command: $action"
            echo "Usage: milou version [check|current|latest|show]"
            return 1
            ;;
    esac
}