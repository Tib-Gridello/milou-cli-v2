#!/bin/bash
# backup.sh - Backup and restore functionality
# Simple, reliable backup/restore for Milou

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/docker.sh"

#=============================================================================
# Backup Constants
#=============================================================================

BACKUP_DIR="${SCRIPT_DIR}/backups"

#=============================================================================
# Backup Operations
#=============================================================================

# Create backup of Milou installation
backup_create() {
    local backup_name="${1:-backup_$(date +%Y%m%d_%H%M%S)}"

    log_info "Creating backup: $backup_name"

    # Create backup directory
    mkdir -p "$BACKUP_DIR" || die "Failed to create backup directory"

    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"

    # Check if backup already exists
    if [[ -f "$backup_file" ]]; then
        if ! confirm "Backup $backup_name already exists. Overwrite?"; then
            die "Backup cancelled"
        fi
    fi

    # Create staging directory
    local staging_dir=$(mktemp -d) || die "Failed to create staging directory"
    trap "rm -rf '$staging_dir'" RETURN

    log_info "Backing up configuration files..."

    # Backup .env (preserve permissions)
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        install -m 600 "${SCRIPT_DIR}/.env" "${staging_dir}/.env" || \
            die "Failed to backup .env"
    fi

    # Backup docker-compose files
    for compose_file in docker-compose*.yml production.yml; do
        if [[ -f "${SCRIPT_DIR}/$compose_file" ]]; then
            cp -p "${SCRIPT_DIR}/$compose_file" "${staging_dir}/" || \
                log_warn "Failed to backup $compose_file"
        fi
    done

    # Backup SSL certificates if they exist
    if [[ -d "${SCRIPT_DIR}/ssl" ]]; then
        log_info "Backing up SSL certificates..."
        cp -rp "${SCRIPT_DIR}/ssl" "${staging_dir}/" || \
            log_warn "Failed to backup SSL directory"
    fi

    # Create backup manifest
    cat > "${staging_dir}/MANIFEST" <<EOF
Milou Backup Manifest
=====================
Backup Name: $backup_name
Created: $(date)
Host: $(hostname)
User: $(whoami)

Contents:
- Configuration files (.env, docker-compose files)
- SSL certificates (if present)

Restore with: milou restore $backup_name
EOF

    # Create tar.gz archive
    log_info "Creating archive..."
    tar -czf "$backup_file" -C "$staging_dir" . || \
        die "Failed to create backup archive"

    # Verify backup was created
    if [[ -f "$backup_file" ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        log_success "Backup created: $backup_file ($size)"
        return 0
    else
        die "Backup file not created"
    fi
}

# List available backups
backup_list() {
    log_info "Available backups:"
    echo ""

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        log_warn "No backups found"
        log_info "Create one with: milou backup"
        return 0
    fi

    local count=0
    for backup_file in "$BACKUP_DIR"/*.tar.gz; do
        if [[ -f "$backup_file" ]]; then
            local name=$(basename "$backup_file" .tar.gz)
            local size=$(du -h "$backup_file" | cut -f1)
            local date=$(stat -c %y "$backup_file" 2>/dev/null | cut -d. -f1 || \
                        stat -f %Sm -t "%Y-%m-%d %H:%M:%S" "$backup_file" 2>/dev/null)

            echo "  $name"
            echo "    Size: $size"
            echo "    Date: $date"
            echo ""

            count=$((count + 1))
        fi
    done

    log_info "Total backups: $count"
    return 0
}

# Restore from backup
backup_restore() {
    local backup_name="$1"

    [[ -z "$backup_name" ]] && die "Usage: milou restore <backup_name>"

    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"

    # Check if backup exists
    [[ -f "$backup_file" ]] || die "Backup not found: $backup_name"

    log_warn "Restoring from backup: $backup_name"
    echo ""
    log_warn "This will replace your current configuration!"
    echo ""

    if ! confirm "Continue with restore?"; then
        die "Restore cancelled"
    fi

    # Stop services before restore
    log_info "Stopping services..."
    docker_stop 2>/dev/null || log_warn "Services may not be running"

    # Create backup of current state before restoring
    log_info "Backing up current state before restore..."
    backup_create "pre_restore_$(date +%Y%m%d_%H%M%S)" || \
        log_warn "Failed to create pre-restore backup"

    # Create staging directory
    local staging_dir=$(mktemp -d) || die "Failed to create staging directory"
    trap "rm -rf '$staging_dir'" RETURN

    # Extract backup
    log_info "Extracting backup..."
    tar -xzf "$backup_file" -C "$staging_dir" || \
        die "Failed to extract backup"

    # Restore .env
    if [[ -f "${staging_dir}/.env" ]]; then
        log_info "Restoring .env..."
        install -m 600 "${staging_dir}/.env" "${SCRIPT_DIR}/.env" || \
            die "Failed to restore .env"
        log_success ".env restored with 600 permissions"
    fi

    # Restore docker-compose files
    for compose_file in docker-compose*.yml production.yml; do
        if [[ -f "${staging_dir}/$compose_file" ]]; then
            log_info "Restoring $compose_file..."
            cp -p "${staging_dir}/$compose_file" "${SCRIPT_DIR}/" || \
                log_warn "Failed to restore $compose_file"
        fi
    done

    # Restore SSL certificates
    if [[ -d "${staging_dir}/ssl" ]]; then
        log_info "Restoring SSL certificates..."
        rm -rf "${SCRIPT_DIR}/ssl"
        cp -rp "${staging_dir}/ssl" "${SCRIPT_DIR}/" || \
            log_warn "Failed to restore SSL directory"
    fi

    log_success "Restore completed successfully"
    echo ""
    log_info "Next steps:"
    log_info "  1. Review configuration: milou config show"
    log_info "  2. Start services: milou start"

    return 0
}

# Clean old backups (keep last N)
backup_clean() {
    local keep="${1:-10}"

    log_info "Cleaning old backups (keeping last $keep)..."

    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "No backups directory found"
        return 0
    fi

    # Count backups
    local total=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)

    if [[ $total -le $keep ]]; then
        log_info "Only $total backups found, nothing to clean"
        return 0
    fi

    # Remove oldest backups
    local to_remove=$((total - keep))
    log_info "Removing $to_remove old backup(s)..."

    ls -1t "$BACKUP_DIR"/*.tar.gz | tail -n "$to_remove" | while read -r old_backup; do
        local name=$(basename "$old_backup")
        log_info "  Removing: $name"
        rm -f "$old_backup" || log_warn "Failed to remove $old_backup"
    done

    log_success "Backup cleanup completed"
    return 0
}

# Command handler for 'milou backup' operations
backup_manage() {
    local action="${1:-create}"
    shift

    case "$action" in
        create|"")
            backup_create "$@"
            ;;
        list)
            backup_list "$@"
            ;;
        restore)
            backup_restore "$@"
            ;;
        clean)
            backup_clean "$@"
            ;;
        *)
            die "Invalid backup action: $action. Use: create, list, restore, clean"
            ;;
    esac
}

#=============================================================================
# Module loaded successfully
#=============================================================================
