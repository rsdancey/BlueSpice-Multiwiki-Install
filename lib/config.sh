#!/bin/bash

# Configuration management for BlueSpice MediaWiki deployment
# Centralized configuration validation and management

set -euo pipefail

# Source validation library
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/validation.sh"

# Define required configuration variables
declare -A REQUIRED_CONFIG=(
    ["WIKI_NAME"]="Wiki instance name (alphanumeric, dots, dashes, underscores)"
    ["WIKI_DOMAIN"]="Wiki domain name (e.g., wiki.example.com)"
    ["WIKI_LANG"]="Wiki language code (en, de, fr, es, it, pt, nl, pl, ru, ja, zh)"
    ["SMTP_HOST"]="SMTP server hostname"
    ["SMTP_PORT"]="SMTP server port number"
    ["SMTP_USER"]="SMTP username"
    ["SMTP_PASS"]="SMTP password"
)

# Define optional configuration with defaults
declare -A DEFAULT_CONFIG=(
    ["WIKI_LANG"]="en"
    ["SMTP_PORT"]="587"
    ["SSL_ENABLED"]="false"
    ["SKIP_DIRECTORY_SETUP"]="false"
)

# Validate all required configuration
validate_configuration() {
    local missing=()
    local invalid=()
    
    echo "🔍 Validating configuration..."
    
    # Check required variables
    for var in "${!REQUIRED_CONFIG[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var: ${REQUIRED_CONFIG[$var]}")
        else
            # Validate specific formats
            case "$var" in
                "WIKI_NAME")
                    if ! validate_wiki_name "${!var}"; then
                        invalid+=("$var")
                    fi
                    ;;
                "WIKI_DOMAIN")
                    if ! validate_domain "${!var}"; then
                        invalid+=("$var")
                    fi
                    ;;
                "WIKI_LANG")
                    if ! validate_language_code "${!var}"; then
                        invalid+=("$var")
                    fi
                    ;;
                "SMTP_HOST")
                    if ! validate_smtp_host "${!var}"; then
                        invalid+=("$var")
                    fi
                    ;;
                "SMTP_PORT")
                    if ! validate_port "${!var}" "SMTP port"; then
                        invalid+=("$var")
                    fi
                    ;;
                "SMTP_USER")
                    if ! validate_email "${!var}"; then
                        invalid+=("$var")
                    fi
                    ;;
                "SMTP_PASS")
                    if ! validate_smtp_pass "${!var}"; then
                        invalid+=("$var")
                    fi
                    ;;
            esac
        fi
    done
    
    # Report missing configuration
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "❌ Missing required configuration:" >&2
        printf "   %s\n" "${missing[@]}" >&2
        return 1
    fi
    
    # Report invalid configuration
    if [[ ${#invalid[@]} -gt 0 ]]; then
        echo "❌ Invalid configuration detected for: ${invalid[*]}" >&2
        return 1
    fi
    
    echo "✅ Configuration validation passed"
    return 0
}

# Apply default values for optional configuration
apply_defaults() {
    echo "⚙️ Applying default configuration values..."
    
    for var in "${!DEFAULT_CONFIG[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            declare -g "$var"="${DEFAULT_CONFIG[$var]}"
            echo "  • Set $var = ${DEFAULT_CONFIG[$var]} (default)"
        fi
    done
}

# Display configuration summary
show_configuration_summary() {
    echo ""
    echo "📋 Configuration Summary:"
    echo "======================================="
    echo "  Wiki Name: $WIKI_NAME"
    echo "  Domain: $WIKI_DOMAIN" 
    echo "  Language: $WIKI_LANG"
    echo "  SSL Enabled: $SSL_ENABLED"
    echo ""
    echo "  SMTP Host: $SMTP_HOST"
    echo "  SMTP Port: $SMTP_PORT"
    echo "  SMTP User: $SMTP_USER"
    echo "  SMTP Password: [CONFIGURED]"
    
    if [[ "${SETUP_MODE:-}" == "restore" ]]; then
        echo "  Backup File: ${BACKUP_FILE:-[NOT SET]}"
    elif [[ "${SETUP_MODE:-}" == "restore_with_images" ]]; then
        echo "  Backup File: ${BACKUP_FILE:-[NOT SET]}"
        echo "  Images File: ${IMAGES_FILE:-[NOT SET]}"
    fi
    echo "======================================="
    echo ""
}

# Prompt for confirmation
confirm_configuration() {
    show_configuration_summary
    
    printf "Proceed with this configuration? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "ℹ️ Setup cancelled by user."
        return 1
    fi
    
    return 0
}

# Save configuration to environment file
save_configuration() {
    local wiki_dir="$1"
    local env_file="$wiki_dir/.env"
    
    echo "💾 Saving configuration to $env_file..."
    
    # Generate secure passwords
    local db_password
    local db_root_password
    db_password=$(openssl rand -base64 16 | tr -d "=+/")
    db_root_password=$(openssl rand -base64 16 | tr -d "=+/")
    
    # Create environment file with all configuration
    cat > "$env_file" << EOF
# BlueSpice Wiki Configuration
# Generated on $(date)

# Wiki Configuration
WIKI_NAME=$WIKI_NAME
WIKI_HOST=$WIKI_DOMAIN
WIKI_LANG=$WIKI_LANG

# Database Configuration
DB_HOST=database
DB_PORT=3306
DB_NAME=${WIKI_NAME}_wiki
DB_USER=${WIKI_NAME}_user
DB_PASS=$db_password
DB_ROOT_PASS=$db_root_password

# Version and Edition
VERSION=$($SCRIPT_DIR/lib/get-latest-bluespice-version.sh)
EDITION=free

# Service Repository (needed for docker-compose)
BLUESPICE_SERVICE_REPOSITORY=bluespice

# Data Directory (for this wiki)
DATA_DIR=/bluespice

# Web Configuration
VIRTUAL_PROTO=http
HTTP_PORT=80
HTTPS_PORT=443

# SSL/TLS Configuration
HTTPS_METHOD=redirect
ENABLE_HSTS=true
HSTS_SUBDOMAINS=true
SSL_POLICY=Mozilla-Modern

# Let's Encrypt Configuration
LETSENCRYPT_TEST=false
ACME_CA_URI=https://acme-v02.api.letsencrypt.org/directory
RENEWAL_INTERVAL=3600

# Resource Limits
UPLOAD_MAX_SIZE=100m

# IPv6 Support
ENABLE_IPV6=true

# Email settings
SMTP_HOST=$SMTP_HOST
SMTP_PORT=$SMTP_PORT
SMTP_USER=$SMTP_USER
SMTP_PASS=$SMTP_PASS
SMTP_ID_HOST=$WIKI_DOMAIN

# Proxy Configuration
VIRTUAL_HOST=$WIKI_DOMAIN
VIRTUAL_PORT=9090
LETSENCRYPT_HOST=$WIKI_DOMAIN
ADMIN_MAIL=$SMTP_USER

# Container Configuration
CONTAINER_PREFIX=bluespice-$WIKI_NAME
BLUESPICE_WIKI_IMAGE=bluespice/wiki:5.1

# SSL Configuration
SSL_ENABLED=$SSL_ENABLED
EOF

    echo "✅ Configuration saved successfully"
}
