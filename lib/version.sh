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
# Use all releases endpoint since /latest might not work for all repos
MANIFEST_URL="https://api.github.com/repos/$GITHUB_ORG/$GITHUB_REPO/releases"

#=============================================================================
# Version Check Functions
#=============================================================================

# Get current version from .env
version_get_current() {
    local version=$(env_get "MILOU_VERSION" 2>/dev/null || echo "")

    # If version is not set or is "latest", try to resolve it
    if [[ -z "$version" || "$version" == "latest" ]]; then
        # Try to get the actual latest version
        local latest=$(version_get_latest)
        if [[ -n "$latest" ]]; then
            version="$latest"
            # Update the .env file with the resolved version
            env_set "MILOU_VERSION" "$version" 2>/dev/null || true
            log_info "Resolved MILOU_VERSION to $version"
        else
            # If we still can't determine version, use the template default
            version="1.0.14"  # Current latest as of now
            log_info "Using default version: $version"
        fi
    fi

    echo "$version"
}

# Get latest version from GitHub releases manifest
version_get_latest() {
    # Try to get GitHub token from .env if available
    local github_token=$(env_get "GITHUB_TOKEN" 2>/dev/null || echo "")

    local response=""
    if [[ -n "$github_token" ]]; then
        # Use authenticated request for private repos
        response=$(curl -s -H "Authorization: Bearer $github_token" "$MANIFEST_URL" 2>/dev/null || echo "")
    else
        # Try without auth (only works for public repos)
        response=$(curl -s "$MANIFEST_URL" 2>/dev/null || echo "")
    fi

    # Check for valid response
    if [[ -z "$response" ]]; then
        log_debug "No response from GitHub API"
        echo ""
        return 1
    fi

    # Check for error messages
    if echo "$response" | grep -q '"message".*"Not Found"'; then
        log_debug "GitHub releases not accessible (private repo needs token)"
        echo ""
        return 1
    fi

    if echo "$response" | grep -q '"message".*"rate limit"'; then
        log_debug "GitHub API rate limit exceeded"
        echo ""
        return 1
    fi

    # Extract tag_name from first release (latest) - use jq if available for reliability
    local latest=""
    if command -v jq >/dev/null 2>&1; then
        # Get first non-draft, non-prerelease version
        latest=$(echo "$response" | jq -r '[.[] | select(.draft == false and .prerelease == false)] | .[0].tag_name' 2>/dev/null | sed 's/^v//')
        # If that fails, just get the first release
        if [[ -z "$latest" ]]; then
            latest=$(echo "$response" | jq -r '.[0].tag_name' 2>/dev/null | sed 's/^v//')
        fi
    else
        latest=$(echo "$response" | grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
    fi

    if [[ -z "$latest" ]]; then
        log_debug "Could not extract version from GitHub response"
        echo ""
        return 1
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