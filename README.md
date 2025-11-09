# Milou CLI v2 - Production Ready

A **complete rewrite** of the Milou CLI tool, focused on **security**, **simplicity**, and **reliability**.

## ✨ What's New in v2

### 🔐 Security by Default
- ✅ **.env always 600 permissions** - Credentials never exposed
- ✅ **SSL keys always 600** - Private keys properly protected
- ✅ **No silent failures** - Every error caught and reported
- ✅ **Atomic operations** - Files never corrupted mid-write
- ✅ **Always verified** - Permissions checked after every operation

### 🎯 Massive Simplification
- ✅ **83% size reduction** - From 13,202 lines to 2,200 lines
- ✅ **7 clean modules** - vs 13 over-engineered modules
- ✅ **6 setup functions** - vs 48 duplicate functions
- ✅ **Simple & clean** - Every line has a purpose

### 🚀 Production Features (Phase 1 - COMPLETE)
- ✅ **GHCR Authentication** - Pull private images from GitHub Container Registry
- ✅ **Multi-Environment Support** - Auto-detects dev/prod from NODE_ENV
- ✅ **Backup/Restore** - Safe updates with automatic backups
- ✅ **Auto-Migration** - Adds ENGINE_URL to existing installations
- ✅ **.env.template** - Complete configuration reference

## 🏁 Quick Start

### System Installation (Recommended for Production)

```bash
# Install to /opt/milou with dedicated user (requires root)
curl -fsSL https://raw.githubusercontent.com/Tib-Gridello/milou-cli-v2/master/install.sh | sudo bash

# Or with wget
wget -qO- https://raw.githubusercontent.com/Tib-Gridello/milou-cli-v2/master/install.sh | sudo bash
```

This will:
- Install to `/opt/milou`
- Create a `milou` system user
- Add `milou` to the `docker` group
- Create `/usr/local/bin/milou` wrapper
- Commands run as `milou` user (never as root)

### Custom Installation (Development/Testing)

```bash
# Install to custom location (no root needed)
MILOU_INSTALL_DIR=~/milou-dev curl -fsSL https://raw.githubusercontent.com/Tib-Gridello/milou-cli-v2/master/install.sh | bash
```

### After Installation

```bash
# 1. Run setup wizard
milou setup

# 2. Start services
milou start
```

### Non-Interactive Setup

Need to run the wizard unattended? Use the new flags and environment overrides:

```bash
# Accept defaults for every prompt, using env overrides when provided
MILOU_SETUP_DOMAIN=demo.milou.sh \
MILOU_SETUP_ADMIN_EMAIL=ops@milou.sh \
MILOU_SETUP_GHCR_TOKEN=ghp_xxx \
milou setup --yes

# Skip the optional image pull step (useful on air-gapped hosts)
milou setup --yes --no-pull
```

Supported overrides:

- `MILOU_SETUP_NODE_ENV` (`development` or `production`)
- `MILOU_SETUP_DOMAIN`
- `MILOU_SETUP_ADMIN_EMAIL`
- `MILOU_SETUP_GHCR_TOKEN`

When `--yes` (or `MILOU_SETUP_ASSUME_YES=true`) is set, the wizard automatically selects the documented defaults for every prompt, so make sure to export the variables above if you need custom values.

### Manual Installation

```bash
# 1. Clone or download
git clone https://github.com/Tib-Gridello/milou-cli-v2.git ~/milou-cli
cd ~/milou-cli

# 2. Run setup wizard (checks prerequisites, guides you through config)
./milou setup

# The wizard will:
# ✓ Check Docker is installed and running
# ✓ Create .env with secure auto-generated passwords
# ✓ Setup SSL certificates (import or generate)
# ✓ Authenticate to GHCR (GitHub Container Registry)

# 3. Start services
./milou start

# Done! Milou is running.
```

### Updating Existing Installation

```bash
# Your .env is automatically preserved!
cd /opt/milou

# Run setup again (it detects existing .env and skips regeneration)
./milou setup

# Or just edit .env directly
nano .env

# Then restart services
./milou restart
```

### Security Model

Milou v2 runs with a **dedicated user** for enhanced security:

- **Installation**: Requires root once to set up `/opt/milou` and create `milou` user
- **Runtime**: All commands run as `milou` user (never as root)
- **Docker Access**: `milou` user is added to `docker` group
- **File Permissions**: Configuration and SSL keys have restricted permissions (600)
- **Updates**: Can be performed without root access

### Existing Installation Upgrade

```bash
# For system installation (/opt/milou)
curl -fsSL https://raw.githubusercontent.com/Tib-Gridello/milou-cli-v2/master/install.sh | sudo bash

# The installer will:
# - Detect existing installation
# - Backup your .env, SSL certificates, and backups
# - Update the code
# - Restore your configuration
# - Preserve the milou user setup
```

## 📖 Complete Command Reference

### Service Management
```bash
milou start                    # Start all services
milou stop                     # Stop all services
milou restart                  # Restart all services
milou status                   # Show service status
milou logs [service]           # View logs (optional: specific service)
milou update                   # Update to latest (auto-backup)
milou update --no-backup       # Update without backup (not recommended)
```

### Configuration Management
```bash
milou config get ENGINE_URL              # Get a configuration value
milou config set KEY VALUE               # Set a value (atomic, 600 perms)
milou config show                        # Show full configuration
milou config validate                    # Validate required values
milou config migrate                     # Add ENGINE_URL to existing .env
```

### GHCR Authentication
```bash
milou ghcr setup                # Interactive token setup
milou ghcr login [token]        # Login with token
milou ghcr status               # Check authentication status
milou ghcr validate <token>     # Validate a token
milou ghcr versions <package>   # List available image versions
milou ghcr latest <package>     # Get latest version tag
```

### SSL Certificate Management
```bash
milou ssl generate [domain]              # Generate self-signed certificate
milou ssl import <cert.pem> <key.pem>   # Import existing certificate
milou ssl verify                         # Verify certificate validity
milou ssl info                           # Show certificate details
milou ssl renew [domain]                 # Renew certificate (auto-backup old)
milou ssl remove                         # Remove certificates (with backup)
```

### Backup & Restore
```bash
milou backup                    # Create backup with timestamp
milou backup mybackup           # Create named backup
milou backup list               # List available backups
milou restore <backup_name>     # Restore from backup
milou backup clean              # Clean old backups (keep last 10)
milou backup clean 5            # Keep only last 5 backups
```

### Setup & Help
```bash
milou setup                     # Interactive setup wizard
milou setup quick               # Quick setup with defaults
milou setup env                 # Re-configure environment only
milou setup ssl                 # Re-configure SSL only
milou help                      # Show help
milou version                   # Show version info
```

## 🏗️ Architecture

### Module Structure
```
milou-cli-v2/
├── milou                      # Main entry point (162 lines)
├── .env.template             # Configuration template (130 lines)
├── lib/
│   ├── core.sh               # Utilities & atomic operations (226 lines)
│   ├── env.sh                # Environment management (235 lines)
│   ├── ghcr.sh               # GHCR authentication (320 lines)
│   ├── ssl.sh                # SSL certificates (249 lines)
│   ├── docker.sh             # Docker operations (297 lines)
│   ├── backup.sh             # Backup/restore (230 lines)
│   └── setup.sh              # Setup wizard (304 lines)
├── tests/
│   ├── test_env.sh           # Environment tests (240 lines)
│   ├── test_ssl.sh           # SSL tests (220 lines)
│   └── run_tests.sh          # Test runner (120 lines)
└── docs/
    ├── README.md             # This file
    ├── INSTALLATION.md       # Fresh installation guide
    ├── UPGRADING.md          # Upgrade guide
    └── IMPLEMENTATION_SUMMARY.md  # Technical details
```

### Key Design Principles

**1. Atomic Operations**
```bash
# Never use sed -i (loses permissions)
# Always use: temp file + mv
atomic_write() {
    local tmp=$(mktemp)
    echo "$content" > "$tmp"
    chmod "$perms" "$tmp"      # Set BEFORE move
    mv "$tmp" "$file"          # Atomic replace
    verify_perms "$file" "$perms"  # Always verify
}
```

**2. Explicit Error Handling**
```bash
# No || true silent failures
# Always die() on errors
docker-compose pull || die "Failed to pull images"
chmod 600 "$file" || die "Failed to set permissions"
```

**3. Permission Preservation**
```bash
# Use install command for atomic + permissions
install -m 600 source.env target/.env
install -m 644 cert.pem ssl/cert.pem
install -m 600 key.pem ssl/key.pem
```

## 🔒 Security Features

### What We Fixed from v1

| Issue | Old Behavior | New Behavior |
|-------|-------------|--------------|
| .env permissions | Lost after sed -i → 644 (world-readable) | Always 600 (atomic write) |
| SSL key permissions | Silent failures with \|\| true | Explicit verification |
| Backup permissions | cp without -p (lost perms) | install -m (preserves) |
| Error handling | Hides errors | Fail fast, clear messages |
| File operations | sed -i (not atomic) | temp + mv (atomic) |

### Security Guarantees

1. ✅ **.env files are ALWAYS 600** - After every operation
2. ✅ **SSL private keys are ALWAYS 600** - No exceptions
3. ✅ **Operations are atomic** - No partial writes
4. ✅ **Errors are explicit** - No silent failures
5. ✅ **Permissions are verified** - After every write
6. ✅ **Backups preserve permissions** - Using install command

## 🚀 Production Deployment

### For Fresh Server (e.g., Eden, BLC)

```bash
# 1. Prepare your GHCR token
#    Go to: https://github.com/settings/tokens/new
#    Scope: read:packages
#    Copy the token

# 2. SSH to server and clone
ssh user@server
cd /opt
git clone <repository> milou
cd milou

# 3. Run setup (will prompt for GHCR token)
./milou setup

# 4. Verify and start
./milou config validate
./milou start
./milou status
```

### For Existing Milou Installation

```bash
# 1. Backup first (manual)
ssh user@server
cd /opt/milou
cp -rp . ../milou.backup.$(date +%Y%m%d)

# 2. Update CLI files
cp -r /path/to/milou-cli-v2/* .

# 3. Migrate configuration
./milou config migrate

# 4. Update services (auto-backup)
./milou update

# 5. Verify
./milou status
./milou config show
```

## 🔧 Multi-Environment Support

The CLI automatically detects the environment from `NODE_ENV` in `.env`:

### Development
```bash
# .env file:
NODE_ENV=development
```
- Uses: `docker-compose.dev.yml` (if exists)
- ENGINE_URL: `http://localhost:8089`
- Fallback: `docker-compose.yml`

### Production
```bash
# .env file:
NODE_ENV=production
```
- Uses: `production.yml` (if exists)
- Or: `docker-compose.prod.yml`
- ENGINE_URL: `http://engine:8089`
- Fallback: `docker-compose.yml`

**No flags needed - it just works!**

## 📊 Statistics

### Size Comparison

| Metric | Old CLI (v1) | New CLI (v2) | Reduction |
|--------|--------------|--------------|-----------|
| Total lines | 13,202 | 2,200 | **83%** |
| Modules | 13 | 7 | **46%** |
| Config functions | 39 | 6 | **85%** |
| Setup functions | 48 | 6 | **88%** |

### Feature Comparison

| Feature | v1 | v2 | Status |
|---------|----|----|--------|
| Fresh installation | Manual | Automated wizard | ✅ NEW |
| GHCR authentication | None | Full support | ✅ NEW |
| Backup/restore | None | Automated | ✅ NEW |
| Multi-environment | Manual files | Auto-detect | ✅ IMPROVED |
| .env management | Broken (sed -i) | Atomic & safe | ✅ FIXED |
| SSL management | Silent failures | Explicit errors | ✅ FIXED |
| Permission safety | Lost on update | Always preserved | ✅ FIXED |
| Update mechanism | Manual | Auto-backup | ✅ IMPROVED |

## 🧪 Testing

Run the test suite:

```bash
./tests/run_tests.sh
```

Tests cover:
- ✅ Syntax validation (all modules)
- ✅ Module loading
- ✅ Atomic operations
- ✅ Permission preservation (600 for .env)
- ✅ SSL certificate operations
- ✅ GHCR authentication

## 📝 Environment Variables

See [.env.template](.env.template) for complete reference.

### Required Variables
- `DATABASE_URI` - PostgreSQL connection string
- `REDIS_HOST`, `REDIS_PORT` - Redis configuration
- `SESSION_SECRET`, `ENCRYPTION_KEY` - Security secrets
- `ENGINE_URL` - Rendering engine URL

### Optional Variables
- `GHCR_TOKEN` - GitHub Container Registry token (recommended)
- `AZURE_OPENAI_API_KEY` - For AI features
- `PGADMIN_EMAIL`, `PGADMIN_PASSWORD` - For database admin

### Auto-Generated
The setup wizard automatically generates:
- Database passwords (32-char alphanumeric)
- Redis passwords (32-char alphanumeric)
- RabbitMQ passwords (32-char alphanumeric)
- JWT secrets (64-char hex)
- Session secrets (64-char hex)
- Encryption keys (64-char hex)

## 🐛 Troubleshooting

### GHCR Authentication Failed
```bash
# Check token
./milou ghcr validate <your_token>

# Re-setup
./milou ghcr setup

# Manual login
echo "<your_token>" | docker login ghcr.io -u oauth2 --password-stdin
```

### Services Won't Start
```bash
# Check configuration
./milou config validate

# Check Docker
docker info
docker-compose version

# Check logs
./milou logs
```

### Permission Issues
```bash
# Check .env permissions
ls -la .env
# Should be: -rw------- (600)

# Fix permissions
chmod 600 .env

# Verify SSL permissions
ls -la ssl/
# cert.pem: -rw-r--r-- (644)
# key.pem: -rw------- (600)
```

### Restore from Backup
```bash
# List backups
./milou backup list

# Restore
./milou restore backup_20251006_143022

# Restart services
./milou start
```

## 🤝 Contributing

### Code Style
- **Simplify** - If it can be done in fewer lines, do it
- **Fix** - Security and correctness over cleverness
- **Improve** - Every change should make it better
- **Clean** - Remove what you don't need

### Testing
```bash
# Check syntax
bash -n lib/*.sh milou

# Run tests
./tests/run_tests.sh

# Test specific module
bash tests/test_env.sh
```

## 📚 Documentation

- **[INSTALLATION.md](INSTALLATION.md)** - Fresh server installation guide
- **[UPGRADING.md](UPGRADING.md)** - Upgrade existing installations
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Technical implementation details
- **[SECURITY_FIXES.md](SECURITY_FIXES.md)** - Security improvements from v1 to v2

## 🎯 Roadmap

### Phase 1: Production Ready ✅ COMPLETE
- ✅ GHCR authentication
- ✅ Multi-environment support
- ✅ Backup/restore
- ✅ Auto-backup before updates
- ✅ .env.template

### Phase 2: Production Hardening (Optional)
- ⏳ Let's Encrypt integration
- ⏳ Image version pinning/rollback
- ⏳ Health check integration
- ⏳ Input validation (domains, ports)

### Phase 3: Advanced Features (Future)
- ⏳ Volume backup/restore
- ⏳ Database backup integration
- ⏳ Monitoring/alerting
- ⏳ Auto-updates with notifications

## 📄 License

Same as Milou project

## 🙏 Support

For issues or questions:
1. Check this documentation
2. Run `milou help`
3. Review logs: `milou logs`
4. Check backups: `milou backup list`

---

**Built with security and simplicity in mind. Every line of code matters.**

**Principles: Simplify. Fix. Improve. Clean.**
