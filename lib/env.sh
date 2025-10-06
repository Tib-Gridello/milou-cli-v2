#!/bin/bash
# env.sh - Atomic .env file operations
# Always preserves 600 permissions, no silent failures

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

#=============================================================================
# Environment File Operations
#=============================================================================

# Get value from .env file
env_get() {
    local key="$1"
    local env_file="${2:-${SCRIPT_DIR}/.env}"

    [[ -f "$env_file" ]] || die "Environment file not found: $env_file"

    # Extract value, handle comments and whitespace
    local value=$(grep "^${key}=" "$env_file" | head -n1 | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    echo "$value"
}

# Set value in .env file atomically
env_set() {
    local key="$1"
    local value="$2"
    local env_file="${3:-${SCRIPT_DIR}/.env}"

    [[ -f "$env_file" ]] || die "Environment file not found: $env_file"
    [[ -n "$key" ]] || die "Key cannot be empty"

    log_debug "Setting $key in $env_file"

    # Read current content
    local content=$(cat "$env_file")

    # Check if key exists
    if grep -q "^${key}=" "$env_file"; then
        # Replace existing key
        content=$(echo "$content" | sed "s|^${key}=.*|${key}=${value}|")
    else
        # Append new key
        if [[ -n "$content" ]]; then
            content="${content}
${key}=${value}"
        else
            content="${key}=${value}"
        fi
    fi

    # Write atomically with 600 permissions
    atomic_write "$env_file" "$content" "600"

    log_debug "Set $key successfully"
    return 0
}

# Generate .env from template with secure defaults
env_generate() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    local template_file="${2:-${SCRIPT_DIR}/.env.template}"

    log_info "Generating environment file..."

    # Check template exists
    [[ -f "$template_file" ]] || die "Template file not found: $template_file"

    # Read template
    local content=$(cat "$template_file")

    # Generate secure random values for secrets
    local jwt_secret=$(random_string 64 hex)
    local session_secret=$(random_string 64 hex)
    local encryption_key=$(random_string 64 hex)
    local db_password=$(random_string 32 alphanumeric)
    local redis_password=$(random_string 32 alphanumeric)
    local rabbitmq_password=$(random_string 32 alphanumeric)
    local rabbitmq_erlang_cookie=$(random_string 32 alphanumeric)
    local pgadmin_password=$(random_string 32 alphanumeric)
    local admin_password=$(random_string 16 alphanumeric)

    # Build RABBITMQ_URL with concrete values
    # Extract default values from template
    local rabbitmq_user=$(grep "^RABBITMQ_USER=" "$template_file" | cut -d= -f2 | tr -d ' ')
    local rabbitmq_host=$(grep "^RABBITMQ_HOST=" "$template_file" | cut -d= -f2 | tr -d ' ')
    local rabbitmq_port=$(grep "^RABBITMQ_PORT=" "$template_file" | cut -d= -f2 | tr -d ' ')
    local rabbitmq_url="amqp://${rabbitmq_user}:${rabbitmq_password}@${rabbitmq_host}:${rabbitmq_port}"

    # Replace placeholders
    content=$(echo "$content" | sed \
        -e "s|REPLACE_JWT_SECRET|${jwt_secret}|g" \
        -e "s|REPLACE_SESSION_SECRET|${session_secret}|g" \
        -e "s|REPLACE_ENCRYPTION_KEY|${encryption_key}|g" \
        -e "s|REPLACE_DB_PASSWORD|${db_password}|g" \
        -e "s|REPLACE_REDIS_PASSWORD|${redis_password}|g" \
        -e "s|REPLACE_RABBITMQ_PASSWORD|${rabbitmq_password}|g" \
        -e "s|REPLACE_ERLANG_COOKIE|${rabbitmq_erlang_cookie}|g" \
        -e "s|REPLACE_PGADMIN_PASSWORD|${pgadmin_password}|g" \
        -e "s|REPLACE_ADMIN_PASSWORD|${admin_password}|g" \
        -e "s|REPLACE_RABBITMQ_URL|${rabbitmq_url}|g")

    # Set ENGINE_URL based on environment
    if [[ "${NODE_ENV:-development}" == "production" ]]; then
        content=$(echo "$content" | sed "s|REPLACE_ENGINE_URL|http://engine:8089|g")
    else
        content=$(echo "$content" | sed "s|REPLACE_ENGINE_URL|http://localhost:8089|g")
    fi

    # Write atomically with 600 permissions
    atomic_write "$env_file" "$content" "600"

    log_success "Environment file generated: $env_file"
    log_warn "Secrets have been generated. Keep this file secure (600 permissions)."

    return 0
}

# Validate .env file
env_validate() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"

    log_info "Validating environment file..."

    [[ -f "$env_file" ]] || die "Environment file not found: $env_file"

    # Verify permissions
    verify_perms "$env_file" "600"

    # Check required keys
    local required_keys=(
        "DATABASE_URI"
        "REDIS_HOST"
        "REDIS_PORT"
        "SESSION_SECRET"
        "ENCRYPTION_KEY"
        "ENGINE_URL"
    )

    local missing=()
    for key in "${required_keys[@]}"; do
        local value=$(env_get "$key" "$env_file")
        [[ -z "$value" ]] && missing+=("$key")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for key in "${missing[@]}"; do
            log_error "  - $key"
        done
        die "Environment validation failed"
    fi

    # Check optional but recommended keys
    local ghcr_token=$(env_get "GHCR_TOKEN" "$env_file")
    if [[ -z "$ghcr_token" ]]; then
        log_warn "GHCR_TOKEN not set - image pulling may fail"
        log_info "Set with: milou ghcr setup"
    fi

    log_success "Environment file validated successfully"
    return 0
}

# Migrate old .env to new format (adds ENGINE_URL if missing)
env_migrate() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"

    [[ -f "$env_file" ]] || die "Environment file not found: $env_file"

    log_info "Migrating environment file..."

    # Check if ENGINE_URL exists
    local engine_url=$(env_get "ENGINE_URL" "$env_file")

    if [[ -z "$engine_url" ]]; then
        log_info "Adding ENGINE_URL to environment file..."

        # Determine value based on NODE_ENV
        local default_engine_url="http://engine:8089"
        local node_env=$(env_get "NODE_ENV" "$env_file")

        if [[ "$node_env" == "development" ]]; then
            default_engine_url="http://localhost:8089"
        fi

        # Add ENGINE_URL after RABBITMQ section
        local content=$(cat "$env_file")

        # Find line with RABBITMQ_PORT and add ENGINE_URL after it
        if grep -q "^RABBITMQ_PORT=" "$env_file"; then
            content=$(echo "$content" | sed "/^RABBITMQ_PORT=/a\\
\\
# Engine Configuration\\
# ----------------------------------------\\
ENGINE_URL=${default_engine_url}")
        else
            # Append at end if RABBITMQ_PORT not found
            content="${content}

# Engine Configuration
# ----------------------------------------
ENGINE_URL=${default_engine_url}"
        fi

        # Write atomically
        atomic_write "$env_file" "$content" "600"

        log_success "Added ENGINE_URL=${default_engine_url}"
    else
        log_info "ENGINE_URL already exists: $engine_url"
    fi

    # Verify permissions
    verify_perms "$env_file" "600"

    log_success "Migration completed successfully"
    return 0
}

# Command handler for 'milou config' operations
env_manage() {
    local action="${1:-}"
    shift

    case "$action" in
        get)
            local key="${1:-}"
            [[ -z "$key" ]] && die "Usage: milou config get <key>"
            local value=$(env_get "$key")
            [[ -z "$value" ]] && die "Key not found: $key"
            echo "$value"
            ;;
        set)
            local key="${1:-}"
            local value="${2:-}"
            [[ -z "$key" ]] && die "Usage: milou config set <key> <value>"
            [[ -z "$value" ]] && die "Value cannot be empty"
            env_set "$key" "$value"
            log_success "Set $key successfully"
            ;;
        generate)
            env_generate "$@"
            ;;
        validate)
            env_validate "$@"
            ;;
        migrate)
            env_migrate "$@"
            ;;
        show)
            local env_file="${SCRIPT_DIR}/.env"
            [[ -f "$env_file" ]] || die "Environment file not found: $env_file"
            verify_perms "$env_file" "600"
            cat "$env_file"
            ;;
        *)
            die "Invalid config action: $action. Use: get, set, generate, validate, migrate, show"
            ;;
    esac
}

#=============================================================================
# Module loaded successfully
#=============================================================================
