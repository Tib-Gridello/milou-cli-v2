#!/bin/bash
# ghcr.sh - GitHub Container Registry authentication
# Handles GHCR token management and Docker login

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

#=============================================================================
# GHCR Constants
#=============================================================================

GHCR_REGISTRY="${GHCR_REGISTRY:-ghcr.io}"
GHCR_NAMESPACE="${GHCR_NAMESPACE:-milou-sh/milou}"
GHCR_API_BASE="${GHCR_API_BASE:-https://api.github.com}"

#=============================================================================
# GHCR Authentication Functions
#=============================================================================

# Validate GHCR token by testing API access
ghcr_validate_token() {
    local token="${1:-}"

    [[ -z "$token" ]] && {
        log_error "GHCR token is required"
        return 1
    }

    log_debug "Validating GHCR token..."

    # Test token by querying GitHub API
    local response=$(curl -s -H "Authorization: token $token" \
        "${GHCR_API_BASE}/user" 2>/dev/null)

    if echo "$response" | grep -q '"login"'; then
        local username=$(echo "$response" | grep '"login"' | head -1 | cut -d'"' -f4)
        log_debug "Token valid for user: $username"
        return 0
    else
        log_error "Invalid GHCR token"
        return 1
    fi
}

# Login to GitHub Container Registry
ghcr_login() {
    local token="${1:-}"
    local quiet="${2:-false}"

    # Use provided token or get from environment
    if [[ -z "$token" ]]; then
        # Try to load from env.sh if available
        if command -v env_get >/dev/null 2>&1; then
            token=$(env_get "GHCR_TOKEN" 2>/dev/null || echo "")
        fi

        # Fall back to environment variable
        [[ -z "$token" ]] && token="${GHCR_TOKEN:-}"
    fi

    [[ -z "$token" ]] && {
        [[ "$quiet" != "true" ]] && log_error "GHCR token required for authentication"
        return 1
    }

    [[ "$quiet" != "true" ]] && log_info "Authenticating with GitHub Container Registry..."

    # Strategy 1: Use oauth2 as username (recommended for PATs)
    local login_error
    login_error=$(echo "$token" | docker login "$GHCR_REGISTRY" -u oauth2 --password-stdin 2>&1)
    local login_exit_code=$?

    if [[ $login_exit_code -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && log_success "✓ Authenticated with $GHCR_REGISTRY"
        export GHCR_AUTHENTICATED="true"
        return 0
    else
        [[ "$quiet" != "true" ]] && log_debug "oauth2 login failed, trying token as username..."

        # Strategy 2: Use token as username (fallback)
        login_error=$(echo "$token" | docker login "$GHCR_REGISTRY" -u "$token" --password-stdin 2>&1)
        login_exit_code=$?

        if [[ $login_exit_code -eq 0 ]]; then
            [[ "$quiet" != "true" ]] && log_success "✓ Authenticated with $GHCR_REGISTRY (fallback method)"
            export GHCR_AUTHENTICATED="true"
            return 0
        fi
    fi

    # Both strategies failed
    [[ "$quiet" != "true" ]] && log_error "Failed to authenticate with $GHCR_REGISTRY"
    [[ "$quiet" != "true" ]] && log_debug "Error: $login_error"
    return 1
}

# Check if already authenticated
ghcr_is_authenticated() {
    # Check if already logged in
    if [[ "${GHCR_AUTHENTICATED:-}" == "true" ]]; then
        return 0
    fi

    # Check Docker config for existing auth
    local docker_config="${HOME}/.docker/config.json"
    if [[ -f "$docker_config" ]]; then
        if grep -q "$GHCR_REGISTRY" "$docker_config" 2>/dev/null; then
            export GHCR_AUTHENTICATED="true"
            return 0
        fi
    fi

    return 1
}

# Ensure GHCR authentication (login if not already authenticated)
ghcr_ensure_auth() {
    local token="${1:-}"
    local quiet="${2:-false}"

    # If already authenticated, skip
    if ghcr_is_authenticated; then
        [[ "$quiet" != "true" ]] && log_debug "Already authenticated with $GHCR_REGISTRY"
        return 0
    fi

    # Attempt login
    ghcr_login "$token" "$quiet"
}

# Interactive GHCR token setup (for setup wizard)
ghcr_setup() {
    log_info "GitHub Container Registry (GHCR) Authentication"
    echo ""
    log_info "A GitHub Personal Access Token (PAT) is required to pull Milou images."
    log_info "Your token needs 'read:packages' permission."
    echo ""
    log_info "To create a token:"
    log_info "  1. Go to: https://github.com/settings/tokens/new"
    log_info "  2. Select scope: read:packages"
    log_info "  3. Generate token and copy it"
    echo ""

    local token=""
    while true; do
        read -s -p "$(log_color "$BLUE" "Enter your GHCR token: ")" token
        echo ""

        [[ -z "$token" ]] && {
            log_warn "Token cannot be empty"
            continue
        }

        # Validate token
        if ghcr_validate_token "$token"; then
            log_success "Token validated successfully"
            break
        else
            log_error "Invalid token. Please try again."
            echo ""
            if ! confirm "Try again?"; then
                return 1
            fi
        fi
    done

    # Test login
    if ghcr_login "$token" "false"; then
        # Store in environment
        if command -v env_set >/dev/null 2>&1; then
            env_set "GHCR_TOKEN" "$token"
            log_success "GHCR token saved to .env"
        else
            export GHCR_TOKEN="$token"
            log_warn "env module not available, token not persisted"
        fi
        return 0
    else
        log_error "Failed to authenticate with GHCR"
        return 1
    fi
}

# Get image versions from GHCR
ghcr_get_versions() {
    local package="${1:-backend}"
    local token="${2:-}"

    # Get token from env if not provided
    if [[ -z "$token" ]]; then
        if command -v env_get >/dev/null 2>&1; then
            token=$(env_get "GHCR_TOKEN" 2>/dev/null || echo "")
        fi
        [[ -z "$token" ]] && token="${GHCR_TOKEN:-}"
    fi

    [[ -z "$token" ]] && {
        log_error "GHCR token required to query versions"
        return 1
    }

    local api_url="${GHCR_API_BASE}/user/packages/container/${GHCR_NAMESPACE}%2F${package}/versions"

    log_debug "Querying versions from: $api_url"

    local versions=$(curl -s -H "Authorization: token $token" \
        -H "Accept: application/vnd.github.v3+json" \
        "$api_url" 2>/dev/null)

    if echo "$versions" | jq -e '.[].metadata.container.tags[]' >/dev/null 2>&1; then
        echo "$versions" | jq -r '.[].metadata.container.tags[]' | sort -V
        return 0
    else
        log_error "Failed to retrieve versions for $package"
        return 1
    fi
}

# Get latest version tag from GHCR
ghcr_get_latest_version() {
    local package="${1:-backend}"
    local token="${2:-}"

    local versions=$(ghcr_get_versions "$package" "$token")

    if [[ -n "$versions" ]]; then
        # Return the latest semver tag (ignoring 'latest', 'stable', etc.)
        echo "$versions" | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+' | tail -1
        return 0
    else
        echo "latest"
        return 1
    fi
}

# Command handler for 'milou ghcr' operations
ghcr_manage() {
    local action="${1:-}"
    shift

    case "$action" in
        login)
            ghcr_login "$@"
            ;;
        validate)
            local token="${1:-}"
            [[ -z "$token" ]] && die "Usage: milou ghcr validate <token>"
            ghcr_validate_token "$token"
            ;;
        setup)
            ghcr_setup "$@"
            ;;
        versions)
            local package="${1:-backend}"
            ghcr_get_versions "$package"
            ;;
        latest)
            local package="${1:-backend}"
            ghcr_get_latest_version "$package"
            ;;
        status)
            if ghcr_is_authenticated; then
                log_success "Authenticated with $GHCR_REGISTRY"
            else
                log_warn "Not authenticated with $GHCR_REGISTRY"
                echo "Run: milou ghcr login"
            fi
            ;;
        *)
            die "Invalid ghcr action: $action. Use: login, validate, setup, versions, latest, status"
            ;;
    esac
}

#=============================================================================
# Module loaded successfully
#=============================================================================
