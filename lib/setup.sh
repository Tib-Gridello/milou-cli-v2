#!/bin/bash
# setup.sh - Interactive setup wizard for fresh installations
# Guides users through initial configuration

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ssl.sh"
source "$(dirname "${BASH_SOURCE[0]}")/docker.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ghcr.sh"

#=============================================================================
# Setup Wizard
#=============================================================================

# Interactive prompt with default value
prompt() {
    local question="$1"
    local default="$2"
    local response

    if [[ -n "$default" ]]; then
        read -p "$(log_color "$BLUE" "?") $question [$default]: " response
        echo "${response:-$default}"
    else
        read -p "$(log_color "$BLUE" "?") $question: " response
        echo "$response"
    fi
}

# Yes/no prompt
prompt_yn() {
    local question="$1"
    local default="${2:-n}"
    local response

    local prompt_text="$question [y/N]"
    [[ "$default" == "y" ]] && prompt_text="$question [Y/n]"

    while true; do
        read -p "$(log_color "$BLUE" "?") $prompt_text: " response
        response="${response:-$default}"

        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                log_warn "Please answer yes or no"
                ;;
        esac
    done
}

# Setup environment file
setup_env() {
    log_info "Configuring environment variables..."

    local env_file="${SCRIPT_DIR}/.env"

    # Check if .env already exists FIRST before prompting
    if [[ -f "$env_file" ]]; then
        log_warn "Configuration file already exists: $env_file"
        echo ""
        log_info "Your existing credentials and settings are preserved"
        log_info "To reconfigure: delete .env and run setup again, or edit .env directly"
        echo ""

        # Migrate in case new variables are needed
        env_migrate "$env_file"

        log_success "Using existing configuration"
        return 0
    fi

    # Get environment type
    local node_env="production"
    if prompt_yn "Is this a development environment?" "n"; then
        node_env="development"
    fi

    # Get domain
    local domain
    while true; do
        domain=$(prompt "Enter domain name" "localhost")
        if validate_domain "$domain"; then
            break
        else
            log_warn "Invalid domain name. Use alphanumeric characters, dots, and hyphens only."
        fi
    done

    # Generate all secure credentials automatically
    log_info "Generating secure credentials for all services..."

    # Database configuration (uses Docker service name)
    local db_host="database"
    local db_port="5432"
    local db_name="milou"
    local db_user="milou"
    local db_pass=$(random_string 32 alphanumeric)
    log_success "✓ Database password generated"

    # Redis configuration (uses Docker service name)
    local redis_host="redis"
    local redis_port="6379"
    local redis_pass=$(random_string 32 alphanumeric)
    log_success "✓ Redis password generated"

    # RabbitMQ configuration (uses Docker service name)
    local rabbitmq_host="rabbitmq"
    local rabbitmq_port="5672"
    local rabbitmq_user="milou"
    local rabbitmq_pass=$(random_string 32 alphanumeric)
    log_success "✓ RabbitMQ password generated"

    # Get admin user configuration
    echo ""
    log_info "Admin User Configuration..."
    log_info "Creating the first administrator account for Milou"
    echo ""

    local admin_email="admin@localhost"

    # Only prompt if interactive
    if [[ -t 0 ]]; then
        while true; do
            local input_email=$(prompt "Admin email address" "admin@localhost")
            if [[ "$input_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                admin_email="$input_email"
                break
            else
                log_warn "Invalid email format. Please enter a valid email address."
            fi
        done
    else
        log_info "Using default admin email: $admin_email"
    fi

    local admin_password=$(random_string 16 alphanumeric)
    log_info "Generated secure admin password"

    # Get GHCR token for image pulling
    echo ""
    log_info "GitHub Container Registry (GHCR) Authentication..."
    log_info "A token is required to pull Milou images from ghcr.io"
    echo ""

    local ghcr_token=""
    if prompt_yn "Do you have a GHCR token?" "y"; then
        while true; do
            read -s -p "$(log_color "$BLUE" "Enter GHCR token: ")" ghcr_token || true
            echo ""

            if [[ -n "$ghcr_token" ]]; then
                if ghcr_validate_token "$ghcr_token"; then
                    log_success "Token validated"
                    break
                else
                    log_error "Invalid token"
                    if ! prompt_yn "Try again?" "y"; then
                        ghcr_token=""
                        break
                    fi
                fi
            else
                log_warn "No token provided - you'll need to login manually later"
                break
            fi
        done
    else
        log_warn "Skipping GHCR authentication - you can set it up later with 'milou ghcr setup'"
    fi

    # Determine ENGINE_URL based on environment
    local engine_url="http://engine:8089"
    [[ "$node_env" == "development" ]] && engine_url="http://localhost:8089"

    # Generate secrets
    local jwt_secret=$(random_string 64 hex)
    local session_secret=$(random_string 64 hex)
    local encryption_key=$(random_string 64 hex)

    # Build .env content
    local env_content="# Milou Environment Configuration
# Generated on $(date)
# ========================================

# Environment
NODE_ENV=${node_env}
DOMAIN=${domain}

# Database Configuration
DATABASE_URI=postgresql://${db_user}:${db_pass}@${db_host}:${db_port}/${db_name}
DB_HOST=${db_host}
DB_PORT=${db_port}
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_pass}

# PostgreSQL Container Configuration
POSTGRES_USER=${db_user}
POSTGRES_PASSWORD=${db_pass}
POSTGRES_DB=${db_name}

# Redis Configuration
REDIS_HOST=${redis_host}
REDIS_PORT=${redis_port}
REDIS_PASSWORD=${redis_pass}

# RabbitMQ Configuration
RABBITMQ_HOST=${rabbitmq_host}
RABBITMQ_PORT=${rabbitmq_port}
RABBITMQ_USER=${rabbitmq_user}
RABBITMQ_PASSWORD=${rabbitmq_pass}
RABBITMQ_ERLANG_COOKIE=$(random_string 32 alphanumeric)
RABBITMQ_URL=amqp://${rabbitmq_user}:${rabbitmq_pass}@${rabbitmq_host}:${rabbitmq_port}

# Engine Configuration
ENGINE_URL=${engine_url}

# GitHub Container Registry
GHCR_TOKEN=${ghcr_token}

# Security
JWT_SECRET=${jwt_secret}
SESSION_SECRET=${session_secret}
ENCRYPTION_KEY=${encryption_key}

# Admin User
ADMIN_EMAIL=${admin_email}
ADMIN_PASSWORD=${admin_password}
ADMIN_USERNAME=admin

# Application
PORT=3000
LOG_LEVEL=info
"

    # Write atomically with 600 permissions
    atomic_write "$env_file" "$env_content" "600"

    log_success "Environment file created: $env_file"
    log_warn "Credentials have been generated. Keep .env secure (600 permissions)."


    # Login to GHCR if token was provided
    if [[ -n "$ghcr_token" ]]; then
        echo ""
        if ghcr_login "$ghcr_token" "false"; then
            log_success "GHCR authentication successful"
        else
            log_warn "GHCR authentication failed - you can retry with 'milou ghcr login'"
        fi
    fi

    return 0
}

# Setup SSL certificates
setup_ssl() {
    log_info "Configuring SSL certificates..."

    if prompt_yn "Do you have existing SSL certificates?" "n"; then
        local cert_path
        while true; do
            cert_path=$(prompt "Path to certificate file (.crt or .pem)")
            if validate_file "$cert_path"; then
                break
            else
                log_warn "File not found or not readable: $cert_path"
            fi
        done

        local key_path
        while true; do
            key_path=$(prompt "Path to private key file (.key or .pem)")
            if validate_file "$key_path"; then
                break
            else
                log_warn "File not found or not readable: $key_path"
            fi
        done

        local ca_path=""
        if prompt_yn "Do you have a CA certificate?" "n"; then
            while true; do
                ca_path=$(prompt "Path to CA certificate file")
                if [[ -z "$ca_path" ]] || validate_file "$ca_path"; then
                    break
                else
                    log_warn "File not found or not readable: $ca_path"
                fi
            done
        fi

        ssl_import "$cert_path" "$key_path" "$ca_path"
    else
        local domain=$(env_get "DOMAIN" 2>/dev/null || echo "localhost")
        log_info "Generating self-signed certificate for $domain..."
        ssl_generate_self_signed "$domain" 365
        log_warn "Using self-signed certificate. Consider obtaining a proper SSL certificate for production."
    fi

    return 0
}

# Setup Docker
setup_docker() {
    log_info "Checking Docker installation..."

    if ! docker_check 2>/dev/null; then
        log_error "Docker is not installed or not running"
        log_info "Please install Docker and Docker Compose:"
        log_info "  https://docs.docker.com/get-docker/"

        if prompt_yn "Continue without Docker?" "n"; then
            log_warn "Skipping Docker setup"
            return 0
        else
            die "Docker is required for Milou"
        fi
    fi

    log_success "Docker is ready"

    if prompt_yn "Pull Docker images now?" "y"; then
        docker_pull
    fi

    return 0
}

# Minimal Docker installation (no over-engineering)
install_docker_minimal() {
    log_info "Installing Docker..."

    # Check if curl is available
    if ! command -v curl &>/dev/null; then
        log_error "curl is required for Docker installation"
        return 1
    fi

    # Use Docker's official installation script
    log_info "Running Docker installation script..."
    if curl -fsSL https://get.docker.com | sh; then
        log_success "Docker installed successfully"

        # Start Docker
        log_info "Starting Docker service..."
        systemctl start docker 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true

        # Install docker-compose plugin
        log_info "Installing Docker Compose plugin..."
        apt-get update -qq 2>/dev/null
        apt-get install -y docker-compose-plugin 2>/dev/null || {
            log_warn "Could not install docker-compose-plugin automatically"
            log_info "Please install it manually: apt install docker-compose-plugin"
        }

        return 0
    else
        log_error "Docker installation failed"
        return 1
    fi
}

# Check prerequisites before setup
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()
    local issues=()

    # Check: Docker installed
    if ! command -v docker &>/dev/null; then
        missing+=("docker")
    else
        # Check: Docker daemon running
        if ! docker info &>/dev/null 2>&1; then
            issues+=("docker_not_running")
        fi

        # Check: Current user can access Docker
        if ! docker ps &>/dev/null 2>&1; then
            issues+=("docker_permission")
        fi
    fi

    # Check: docker-compose or docker compose
    if ! command -v docker-compose &>/dev/null 2>&1; then
        if ! docker compose version &>/dev/null 2>&1; then
            missing+=("docker-compose")
        fi
    fi

    # Report missing prerequisites
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required software:"
        echo ""

        for tool in "${missing[@]}"; do
            case "$tool" in
                docker)
                    log_color "$RED" "  ✗ Docker Engine"
                    log_info "    Install: https://docs.docker.com/get-docker/"
                    log_info "    Ubuntu/Debian: curl -fsSL https://get.docker.com | sh"
                    ;;
                docker-compose)
                    log_color "$RED" "  ✗ Docker Compose"
                    log_info "    Install: apt install docker-compose-plugin"
                    log_info "    Or: https://docs.docker.com/compose/install/"
                    ;;
            esac
            echo ""
        done

        # Offer to install automatically
        echo ""
        if [[ $EUID -eq 0 ]]; then
            # Running as root, can install directly
            if prompt_yn "Would you like to install Docker automatically?" "y"; then
                install_docker_minimal
                # Re-check after installation
                check_prerequisites
                return $?
            fi
        else
            # Not root, provide instructions
            log_warn "Not running as root - cannot install automatically"
            log_info "To install automatically, run: sudo ./milou setup"
            echo ""
        fi

        die "Please install missing software and try again"
    fi

    # Report issues
    if [[ ${#issues[@]} -gt 0 ]]; then
        log_error "Configuration issues detected:"
        echo ""

        for issue in "${issues[@]}"; do
            case "$issue" in
                docker_not_running)
                    log_color "$RED" "  ✗ Docker daemon is not running"
                    log_info "    Start: sudo systemctl start docker"
                    log_info "    Enable at boot: sudo systemctl enable docker"
                    ;;
                docker_permission)
                    log_color "$RED" "  ✗ Current user cannot access Docker"
                    log_info "    Add user to docker group: sudo usermod -aG docker \$USER"
                    log_info "    Then logout and login again"
                    log_info "    Or run as root: sudo ./milou setup"
                    ;;
            esac
            echo ""
        done

        die "Please fix issues above and try again"
    fi

    log_success "All prerequisites are available"
    return 0
}

# Main setup - interactive, prompts user for inputs
setup() {
    local total_steps=5

    log_info "Welcome to Milou Setup"
    echo ""

    log_step 1 $total_steps "Prerequisites Check"
    check_prerequisites

    log_step 2 $total_steps "Environment Configuration"
    setup_env

    # Save admin credentials for later display
    local admin_email=$(env_get "ADMIN_EMAIL" 2>/dev/null || echo "")
    local admin_password=$(env_get "ADMIN_PASSWORD" 2>/dev/null || echo "")

    log_step 3 $total_steps "SSL Certificate Setup"
    setup_ssl

    log_step 4 $total_steps "Pulling Docker Images"
    if docker_check 2>/dev/null; then
        log_info "Pulling latest Docker images..."
        # Source docker module if needed
        source "$(dirname "${BASH_SOURCE[0]}")/docker.sh" 2>/dev/null || true
        if docker_pull 2>/dev/null; then
            log_success "Docker images pulled successfully"
        else
            log_warn "Could not pull images - will pull on first start"
        fi
    else
        log_warn "Docker not available - images will be pulled on first start"
    fi

    log_step 5 $total_steps "Final Setup"
    log_success "All services configured"

    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}✓ Setup Completed Successfully!${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Show admin credentials if available
    if [[ -n "$admin_email" && -n "$admin_password" ]]; then
        echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}${YELLOW}⚠️  ADMIN CREDENTIALS - SAVE THESE!${NC}"
        echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${CYAN}Email:${NC}    ${GREEN}$admin_email${NC}"
        echo -e "  ${CYAN}Password:${NC} ${GREEN}$admin_password${NC}"
        echo ""
        echo -e "  ${YELLOW}⚠️  Change your password after first login!${NC}"
        echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    fi

    log_info "Next steps:"
    log_info "  1. Start Milou:  ${CYAN}milou start${NC}"
    log_info "  2. Check status: ${CYAN}milou status${NC}"
    log_info "  3. View logs:    ${CYAN}milou logs${NC}"
    echo ""

    return 0
}

# Command handler for 'milou setup' operations
setup_manage() {
    local action="${1:-}"

    case "$action" in
        env)
            shift
            setup_env "$@"
            ;;
        ssl)
            shift
            setup_ssl "$@"
            ;;
        "")
            # No sub-command - run main setup
            setup
            ;;
        *)
            # Unknown option - show warning and run setup
            log_warn "Unknown setup option: '$action' - running main setup"
            setup
            ;;
    esac
}

#=============================================================================
# Module loaded successfully
#=============================================================================
