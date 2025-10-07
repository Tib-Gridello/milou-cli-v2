#!/bin/bash
# docker.sh - Docker operations and management
# Handles docker-compose operations with proper error handling

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ghcr.sh"

#=============================================================================
# Helper Functions
#=============================================================================

# Run docker compose command with v2/v1 compatibility
docker_compose() {
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose "$@"
    else
        docker compose "$@"
    fi
}

# Lazy load backup module to avoid circular dependency
load_backup_module() {
    if [[ "${BACKUP_MODULE_LOADED:-}" != "true" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/backup.sh"
        export BACKUP_MODULE_LOADED="true"
    fi
}

#=============================================================================
# Docker Operations
#=============================================================================

# Determine which compose file to use based on environment
docker_get_compose_file() {
    local env="${MILOU_ENV:-}"

    # If no environment specified, auto-detect from NODE_ENV
    if [[ -z "$env" ]]; then
        local node_env=$(env_get "NODE_ENV" 2>/dev/null || echo "production")
        [[ "$node_env" == "development" ]] && env="dev" || env="prod"
    fi

    # Check for environment-specific compose file
    local compose_file=""

    case "$env" in
        dev|development)
            if [[ -f "${SCRIPT_DIR}/docker-compose.dev.yml" ]]; then
                compose_file="${SCRIPT_DIR}/docker-compose.dev.yml"
            else
                compose_file="${SCRIPT_DIR}/docker-compose.yml"
            fi
            ;;
        prod|production)
            # Check for production.yml first (legacy), then docker-compose.prod.yml
            if [[ -f "${SCRIPT_DIR}/production.yml" ]]; then
                compose_file="${SCRIPT_DIR}/production.yml"
            elif [[ -f "${SCRIPT_DIR}/docker-compose.prod.yml" ]]; then
                compose_file="${SCRIPT_DIR}/docker-compose.prod.yml"
            else
                compose_file="${SCRIPT_DIR}/docker-compose.yml"
            fi
            ;;
        *)
            # Default to docker-compose.yml
            compose_file="${SCRIPT_DIR}/docker-compose.yml"
            ;;
    esac

    echo "$compose_file"
}

# Check if Docker is installed and running
docker_check() {
    # log_debug "Checking Docker installation..."

    if ! command -v docker &>/dev/null; then
        die "Docker is not installed. Install: https://docs.docker.com/get-docker/"
    fi

    # Check for docker compose (v2) or docker-compose (v1)
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        die "docker-compose is not installed. Install: apt install docker-compose-plugin"
    fi

    # Check if Docker daemon is running
    if ! docker info &>/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        log_info "Start: sudo systemctl start docker"
        log_info "Enable: sudo systemctl enable docker"
        die "Docker must be running"
    fi

    # log_debug "Docker is ready"
    return 0
}

# Start Milou services
docker_start() {
    local compose_file=$(docker_get_compose_file)
    local compose_args="-f $compose_file"

    # Check for override file and include it if it exists
    if [[ -f "${SCRIPT_DIR}/docker-compose.override.yml" ]]; then
        compose_args="$compose_args -f ${SCRIPT_DIR}/docker-compose.override.yml"
        log_debug "Using override file: docker-compose.override.yml"
    fi

    log_info "Starting Milou services..."
    log_debug "Using compose file: $compose_file"

    docker_check
    [[ -f "$compose_file" ]] || die "Compose file not found: $compose_file"
    [[ -f "${SCRIPT_DIR}/.env" ]] || die ".env file not found. Run 'milou setup' first."

    # Verify .env has ENGINE_URL
    local engine_url=$(env_get "ENGINE_URL")
    [[ -z "$engine_url" ]] && {
        log_warn "ENGINE_URL not found in .env, running migration..."
        env_migrate
    }

    # Ensure GHCR authentication if using GHCR images
    if ! ghcr_is_authenticated; then
        log_debug "Attempting GHCR authentication..."
        ghcr_ensure_auth "" "true"  # Quiet mode, don't fail if no token
    fi

    cd "$SCRIPT_DIR" || die "Failed to change directory"

    # Start database first
    docker_compose $compose_args up -d database || die "Failed to start database"

    # Wait for database to be healthy
    log_info "Waiting for database..."
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if docker_compose $compose_args ps database 2>/dev/null | grep -q "healthy"; then
            break
        fi
        sleep 1
        ((attempt++))
    done

    # Skip migrations unless explicitly requested via environment variable
    if [[ "${RUN_MIGRATIONS_ON_START:-false}" == "true" ]]; then
        log_info "Running database migrations..."
        db_migrate >/dev/null 2>&1 || log_debug "Migrations check completed"
    else
        log_debug "Skipping migrations (set RUN_MIGRATIONS_ON_START=true to enable)"
    fi

    # Start remaining services (explicitly include nginx to ensure it starts)
    docker_compose $compose_args up -d redis rabbitmq backend frontend engine nginx pgadmin || die "Failed to start services"

    log_success "Milou services started successfully"
    docker_status

    return 0
}

# Stop Milou services
docker_stop() {
    local compose_file=$(docker_get_compose_file)
    local compose_args="-f $compose_file"

    # Check for override file and include it if it exists
    if [[ -f "${SCRIPT_DIR}/docker-compose.override.yml" ]]; then
        compose_args="$compose_args -f ${SCRIPT_DIR}/docker-compose.override.yml"
    fi

    log_info "Stopping Milou services..."

    docker_check
    [[ -f "$compose_file" ]] || die "docker-compose.yml not found: $compose_file"

    cd "$SCRIPT_DIR" || die "Failed to change directory"

    docker_compose $compose_args down || die "Failed to stop services"

    log_success "Milou services stopped successfully"
    return 0
}

# Restart Milou services
docker_restart() {
    log_info "Restarting Milou services..."

    docker_stop
    sleep 2
    docker_start

    return 0
}

# Show service status
docker_status() {
    local compose_file=$(docker_get_compose_file)
    local compose_args="-f $compose_file"

    # Check for override file and include it if it exists
    if [[ -f "${SCRIPT_DIR}/docker-compose.override.yml" ]]; then
        compose_args="$compose_args -f ${SCRIPT_DIR}/docker-compose.override.yml"
    fi

    docker_check
    [[ -f "$compose_file" ]] || die "docker-compose.yml not found: $compose_file"

    cd "$SCRIPT_DIR" || die "Failed to change directory"
    docker_compose $compose_args ps || true

    return 0
}

# Show service logs
docker_logs() {
    local service="${1:-}"
    local compose_file=$(docker_get_compose_file)
    local compose_args="-f $compose_file"

    # Check for override file and include it if it exists
    if [[ -f "${SCRIPT_DIR}/docker-compose.override.yml" ]]; then
        compose_args="$compose_args -f ${SCRIPT_DIR}/docker-compose.override.yml"
    fi

    docker_check
    [[ -f "$compose_file" ]] || die "docker-compose.yml not found: $compose_file"

    cd "$SCRIPT_DIR" || die "Failed to change directory"

    if [[ -z "$service" ]]; then
        docker_compose $compose_args logs --tail=100 -f
    else
        docker_compose $compose_args logs --tail=100 -f "$service"
    fi

    return 0
}

# Pull images with optional version selection
docker_pull() {
    local target_version="${1:-}"
    local compose_file=$(docker_get_compose_file)
    local compose_args="-f $compose_file"

    # Check for override file and include it if it exists
    if [[ -f "${SCRIPT_DIR}/docker-compose.override.yml" ]]; then
        compose_args="$compose_args -f ${SCRIPT_DIR}/docker-compose.override.yml"
    fi

    docker_check
    [[ -f "$compose_file" ]] || die "docker-compose.yml not found: $compose_file"

    # Ensure GHCR authentication before pulling
    if ! ghcr_is_authenticated; then
        log_info "Authenticating with GitHub Container Registry..."
        if ! ghcr_ensure_auth "" "false"; then
            log_warn "GHCR authentication failed - some images may not be accessible"
            log_info "Set GHCR_TOKEN in .env or run 'milou ghcr setup'"
        fi
    fi

    # If version specified, update .env before pulling
    if [[ -n "$target_version" ]]; then
        local current_version=$(env_get "MILOU_VERSION" 2>/dev/null || echo "latest")
        if [[ "$current_version" != "$target_version" ]]; then
            log_info "Updating MILOU_VERSION: $current_version → $target_version"
            env_set "MILOU_VERSION" "$target_version"
        fi
        log_info "Pulling Docker images for version: $target_version"
    else
        local current_version=$(env_get "MILOU_VERSION" 2>/dev/null || echo "latest")
        log_info "Pulling Docker images for version: $current_version"
    fi

    cd "$SCRIPT_DIR" || die "Failed to change directory"
    docker_compose $compose_args pull || die "Failed to pull images"

    log_success "Docker images updated successfully"
    return 0
}

# Rebuild services
docker_build() {
    local compose_file=$(docker_get_compose_file)
    local compose_args="-f $compose_file"

    # Check for override file and include it if it exists
    if [[ -f "${SCRIPT_DIR}/docker-compose.override.yml" ]]; then
        compose_args="$compose_args -f ${SCRIPT_DIR}/docker-compose.override.yml"
    fi

    log_info "Building Docker images..."

    docker_check
    [[ -f "$compose_file" ]] || die "docker-compose.yml not found: $compose_file"

    cd "$SCRIPT_DIR" || die "Failed to change directory"
    docker_compose $compose_args build || die "Failed to build images"

    log_success "Docker images built successfully"
    return 0
}

# Clean up Docker resources
docker_clean() {
    log_warn "Cleaning up Docker resources..."

    docker_check

    # Stop services first
    docker_stop 2>/dev/null || true

    # Remove stopped containers
    log_info "Removing stopped containers..."
    docker container prune -f || log_warn "Failed to remove containers"

    # Remove unused images
    log_info "Removing unused images..."
    docker image prune -f || log_warn "Failed to remove images"

    # Remove unused volumes
    log_info "Removing unused volumes..."
    docker volume prune -f || log_warn "Failed to remove volumes"

    # Remove unused networks
    log_info "Removing unused networks..."
    docker network prune -f || log_warn "Failed to remove networks"

    log_success "Docker cleanup completed"
    return 0
}

# Update Milou (pull images and restart)
docker_update() {
    local skip_backup="${1:-false}"
    local target_version="${2:-}"

    log_info "Updating Milou..."

    # Check for updates first
    if command -v version_check_updates >/dev/null 2>&1; then
        if [[ -z "$target_version" ]]; then
            # Check if update is available
            if version_check_updates "true"; then
                local latest=$(version_get_latest 2>/dev/null || echo "")
                if [[ -n "$latest" ]]; then
                    target_version="$latest"
                    log_info "Updating to latest version: $target_version"
                fi
            else
                log_info "Already running latest version"
            fi
        fi
    fi

    # Ensure ENGINE_URL exists
    local engine_url=$(env_get "ENGINE_URL" 2>/dev/null || echo "")
    [[ -z "$engine_url" ]] && {
        log_info "Migrating .env to include ENGINE_URL..."
        env_migrate
    }

    # Create backup before update (unless skipped)
    if [[ "$skip_backup" != "true" ]] && [[ "$skip_backup" != "--no-backup" ]]; then
        log_info "Creating pre-update backup..."
        load_backup_module
        backup_create "pre_update_$(date +%Y%m%d_%H%M%S)" || \
            log_warn "Backup failed, but continuing with update"
    else
        log_warn "Skipping backup (--no-backup flag used)"
    fi

    # Pull images (with version if specified)
    docker_pull "$target_version"

    # Restart services
    docker_restart

    log_success "Milou updated successfully"
    if [[ -n "$target_version" ]]; then
        log_info "Now running version: $target_version"
    fi
    log_info "Backup available in: ${SCRIPT_DIR}/backups/"
    return 0
}

# Run database migrations
db_migrate() {
    local compose_file=$(docker_get_compose_file)
    local compose_args="-f $compose_file"

    # Check for override file and include it if it exists
    if [[ -f "${SCRIPT_DIR}/docker-compose.override.yml" ]]; then
        compose_args="$compose_args -f ${SCRIPT_DIR}/docker-compose.override.yml"
    fi

    log_info "Running database migrations..."

    docker_check
    [[ -f "$compose_file" ]] || die "Compose file not found: $compose_file"
    [[ -f "${SCRIPT_DIR}/.env" ]] || die ".env file not found. Run 'milou setup' first."

    cd "$SCRIPT_DIR" || die "Failed to change directory"

    # Run the database-migrations service with the profile
    if docker_compose $compose_args --profile database-migrations up database-migrations --remove-orphans --abort-on-container-exit --exit-code-from database-migrations; then
        log_success "Database migrations completed successfully"
        # Bring down the migration service
        docker_compose $compose_args --profile database-migrations down database-migrations 2>/dev/null || true
        return 0
    else
        log_error "Database migrations failed"
        # Bring down the migration service even on failure
        docker_compose $compose_args --profile database-migrations down database-migrations 2>/dev/null || true
        return 1
    fi
}

# Command handler for 'milou db' operations
db_manage() {
    local action="${1:-}"
    shift

    case "$action" in
        migrate)
            db_migrate "$@"
            ;;
        *)
            die "Invalid db action: $action. Use: migrate"
            ;;
    esac
}

# Command handler for 'milou docker' operations
docker_manage() {
    local action="${1:-}"
    shift

    case "$action" in
        start)
            docker_start "$@"
            ;;
        stop)
            docker_stop "$@"
            ;;
        restart)
            docker_restart "$@"
            ;;
        status)
            docker_status "$@"
            ;;
        logs)
            docker_logs "$@"
            ;;
        pull)
            docker_pull "$@"
            ;;
        build)
            docker_build "$@"
            ;;
        clean)
            docker_clean "$@"
            ;;
        update)
            docker_update "$@"
            ;;
        *)
            die "Invalid docker action: $action. Use: start, stop, restart, status, logs, pull, build, clean, update"
            ;;
    esac
}

#=============================================================================
# Module loaded successfully
#=============================================================================
