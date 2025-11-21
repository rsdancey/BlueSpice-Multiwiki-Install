#!/bin/bash

# OAuth extension management for BlueSpice MediaWiki
# Handles installation and configuration of authentication extensions

set -euo pipefail

# Source required libraries
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/docker-utils.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/validation.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/init-settings-config.sh"


# Check if authentication extensions need to be installed
check_auth_extensions_needed() {
    local wiki_name="$1"
    
    # Check if extensions already exist
    if docker_exec_safe "$wiki_name" test -d /app/bluespice/w/extensions/PluggableAuth 2>/dev/null && \
       docker_exec_safe "$wiki_name" test -d /app/bluespice/w/extensions/OpenIDConnect 2>/dev/null; then
        log_info "✓ Authentication extensions already installed"
        return 1
    fi
    
    # Extensions need to be installed
    log_info "ℹ️ Authentication extensions need to be installed"
    return 0
}

# Download and verify extension
download_extension() {
    local extension_name="$1"
    local temp_dir="$2"
    local primary_url="$3"
    local fallback_url="$4"
    
    log_info "  📥 Downloading $extension_name extension..."
    
    # Try primary URL first
    if curl -L --fail --retry 3 --connect-timeout 10 \
       -o "$temp_dir/${extension_name}.tar.gz" "$primary_url"; then
        log_info "  ✓ Downloaded $extension_name from primary source"
        return 0
    fi
    
    log_warn "**$primary_url** failed"
    log_warn "  ⚠️ Primary download failed, trying fallback source..."
    
    # Try fallback URL
    if curl -L --fail --retry 3 --connect-timeout 10 \
       -o "$temp_dir/${extension_name}.tar.gz" "$fallback_url"; then
        log_info "  ✓ Downloaded $extension_name from fallback source"
        return 0
    fi
    
    log_error "  ❌ Failed to download $extension_name from both sources" >&2
    return 1
}

# Extract and prepare extension
extract_extension() {
    local extension_name="$1"
    local temp_dir="$2"
    
    log_info "  📦 Extracting $extension_name..."
    
    cd "$temp_dir"
    if ! tar -xzf "${extension_name}.tar.gz"; then
        log_error "  ❌ Failed to extract $extension_name" >&2
        return 1
    fi
    
    # Find and rename extracted directory to proper name
    local extracted_dir
    extracted_dir=$(find . -maxdepth 1 -type d -name "*${extension_name}*" | head -1)
    
    if [[ -z "$extracted_dir" ]]; then
        log_error "  ❌ Could not find extracted $extension_name directory" >&2
        return 1
    fi
    
    if [[ "$extracted_dir" != "./$extension_name" ]]; then
        mv "$extracted_dir" "$extension_name"
    fi
    
    # Verify extraction
    if [[ ! -d "$extension_name" ]] || [[ ! -f "$extension_name/extension.json" ]]; then
        log_error "  ❌ $extension_name extraction verification failed" >&2
        return 1
    fi
    
    log_info "  ✓ $extension_name extracted and prepared"
    return 0
}

# Install authentication extensions
install_auth_extensions() {
    local wiki_name="$1"
    local temp_dir="/tmp/mw_extensions_$$"

    log_info "🔧 Installing authentication extensions for $wiki_name..."
    
    # Ensure container is ready
    if ! wait_for_container_ready "$wiki_name" 30; then
        log_error "❌ Container not ready for extension installation" >&2
        return 1
    fi
    
    # Create temporary directory for downloads
    if ! mkdir -p "$temp_dir"; then
        log_error "❌ Failed to create temporary directory: $temp_dir" >&2
        return 1
    fi
    
    # Download PluggableAuth extension
    if ! download_extension "PluggableAuth" "$temp_dir" \
        "https://extdist.wmflabs.org/dist/extensions/PluggableAuth-REL1_43-21f9a51.tar.gz" \
        "https://github.com/wikimedia/mediawiki-extensions-PluggableAuth/archive/refs/heads/REL1_43.tar.gz"; then
        return 1
    fi
    
    # Download OpenIDConnect extension
    if ! download_extension "OpenIDConnect" "$temp_dir" \
        "https://extdist.wmflabs.org/dist/extensions/OpenIDConnect-REL1_43-c6a351c.tar.gz" \
        "https://github.com/wikimedia/mediawiki-extensions-OpenIDConnect/archive/refs/heads/REL1_43.tar.gz"; then
        return 1
    fi
    
    # Extract extensions
    if ! extract_extension "PluggableAuth" "$temp_dir"; then
        return 1
    fi
    
    if ! extract_extension "OpenIDConnect" "$temp_dir"; then
        return 1
    fi
    
    # Copy extensions to container
    echo "  📋 Installing extensions in container..."
    if ! docker_copy_to_container "$wiki_name" "$temp_dir/PluggableAuth" "/app/bluespice/w/extensions/"; then
        log_error "❌ Failed to copy PluggableAuth to container" >&2
        return 1
    fi

    if ! docker_set_ownership "$wiki_name" "/app/bluespice/w/extensions/PluggableAuth"; then
        log_error "❌ Failed to set ownership for PluggableAuth in container" >&2
        return 1
    fi

    if ! docker_copy_to_container "$wiki_name" "$temp_dir/OpenIDConnect" "/app/bluespice/w/extensions/"; then
        log_error "❌ Failed to copy OpenIDConnect to container" >&2
        return 1
    fi

    if ! docker_set_ownership "$wiki_name" "/app/bluespice/w/extensions/OpenIDConnect"; then
        log_error "❌ Failed to set ownership for OpenIDConnect in container" >&2
        return 1
    fi

    # Install Composer in the container if not already present
    log_info "  📦 Installing Composer in container..."
    if ! docker_exec_safe "$wiki_name" test -f /app/bluespice/w/composer.phar 2>/dev/null; then
        log_info "  📥 Downloading and installing Composer using official method..."
        if docker_exec_safe "$wiki_name" "
            cd /app/bluespice/w &&
            php -r \"copy('https://getcomposer.org/installer', 'composer-setup.php');\" &&
            php -r \"copy('https://composer.github.io/installer.sig', 'composer-setup.sig');\" &&
            php -r \"\\\$expected_hash = trim(file_get_contents('composer-setup.sig')); \\\$actual_hash = hash_file('sha384', 'composer-setup.php'); if (\\\$actual_hash === \\\$expected_hash) { echo 'Installer verified'.PHP_EOL; } else { echo 'Installer corrupt: expected '.\\\$expected_hash.' but got '.\\\$actual_hash.PHP_EOL; unlink('composer-setup.php'); unlink('composer-setup.sig'); exit(1); }\" &&
            php composer-setup.php &&
            php -r \"unlink('composer-setup.php'); if (file_exists('composer-setup.sig')) unlink('composer-setup.sig');\" &&
            ls -la composer.phar
        " 2>/dev/null; then
            echo "  ✓ Composer installed successfully at /app/bluespice/w/composer.phar"
        else
            log_error "  ❌ Failed to install Composer using official method"
            return 1
        fi
    fi

    # Install OpenIDConnect PHP dependencies using the specific commands
    log_info "  📦 Installing OpenIDConnect PHP dependencies..."
    if [[ "${composer_failed:-false}" != "true" ]]; then
        if docker_exec_safe "$wiki_name" "cd /app/bluespice/w/extensions/OpenIDConnect && php /app/bluespice/w/composer.phar install --no-dev"; then
            log_info "  ✓ OpenIDConnect dependencies installed successfully (method 1)"
        elif docker_exec_safe "$wiki_name" "cd /app/bluespice/w/extensions/OpenIDConnect && /app/bluespice/w/composer.phar install"; then
            log_info "  ✓ OpenIDConnect dependencies installed successfully (method 2)"
        else
            log_error "  ❌ Composer methods failed"
            return 1
        fi
    fi

    # Set permissions in container
    if ! docker_set_ownership "$wiki_name" "/app/bluespice/w/extensions/PluggableAuth"; then
        log_error "❌ Failed to set ownership for PluggableAuth in container"
        return 1
    fi

    if ! docker_set_ownership "$wiki_name" "/app/bluespice/w/extensions/OpenIDConnect"; then
        log_error "❌ Failed to set ownership for OpenIDConnect in container"
        return 1
    fi

    # Check if both extension.json files exist
    if ! docker_exec_safe "$wiki_name" "test -f /app/bluespice/w/extensions/PluggableAuth/extension.json"; then
        log_error "❌ PluggableAuth extension.json not found"
        return 1
    fi
    
    if ! docker_exec_safe "$wiki_name" "test -f /app/bluespice/w/extensions/OpenIDConnect/extension.json"; then
        log_error "❌ OpenIDConnect extension.json not found"
        return 1
    fi

    cd /
    [[ -n "${temp_dir:-}" ]] && rm -rf "$temp_dir"
 
    if docker_exec_safe "$wiki_name" "cd /app/bluespice/w php composer.phar update" 2>/dev/null; then
        echo "  ✓ Composer update has run"
    else
        log_error "  ❌ Failed to run Composer update"
        return 1
    fi

    if docker_exec_safe "$wiki_name" "cd /app/bluespice/w php composer.phar install" 2>/dev/null; then
        echo "  ✓ Composer install has run"
    else
        log_error "  ❌ Failed to run Composer install"
        return 1
    fi


    return 0
}

# Complete OAuth setup process
setup_oauth_extensions() {
    local wiki_name="$1"
    local wiki_dir="$2"
    local wiki_domain="$3"
    
    log_info "🚀 Starting OAuth extension setup for $wiki_name..."
    
    # Check if extensions need to be installed
    if check_auth_extensions_needed "$wiki_name"; then
        # Install extensions
        if ! install_auth_extensions "$wiki_name"; then
            log_error "❌ Failed to install authentication extensions"
            return 1
        fi
        
        # Configure extension loading
        if ! add_oauth_extensions_config "$wiki_name" "$wiki_dir"; then
            log_error "❌ Failed to configure authentication extensions"
            return 1
        fi
        
        # Configure OAuth settings
        if ! setup_interactive_oauth_config "$wiki_name" "$wiki_domain"; then
            log_error "❌ Failed to configure OAuth settings"
            return 1
        fi
        
        log_info "✅ OAuth extension setup completed successfully"
    else
        log_info "ℹ️ Authentication extensions already configured"
    fi
    
    return 0
}
# Extract OAuth credentials from existing post-init-settings.php
extract_oauth_credentials_from_container() {
    local wiki_name="$1"
    local container_post_init="/data/bluespice/post-init-settings.php"
    
    log_info "Extracting existing OAuth credentials from container..."
    
    # Check if post-init-settings.php exists in container
    if ! docker_exec_safe "$wiki_name" "test -f $container_post_init" 2>/dev/null; then
        log_info "No existing post-init-settings.php found in container"
        return 1
    fi
    
    # Extract clientID
    local client_id
    client_id=$(docker exec "bluespice-${wiki_name}-wiki-web" grep -oP '"clientID"\s*=>\s*"\K[^"]+' "$container_post_init" 2>/dev/null | head -1)
    
    # Extract clientSecret
    local client_secret
    client_secret=$(docker exec "bluespice-${wiki_name}-wiki-web" grep -oP '"clientSecret"\s*=>\s*"\K[^"]+' "$container_post_init" 2>/dev/null | head -1)
    
    if [[ -n "$client_id" ]] && [[ -n "$client_secret" ]]; then
        log_info "✓ Found existing OAuth credentials in container"
        echo "$client_id|$client_secret"
        return 0
    else
        log_info "No OAuth credentials found in container post-init-settings.php"
        return 1
    fi
}

# Setup OAuth extensions with automatic credential extraction for upgrades
setup_oauth_extensions_for_upgrade() {
    local wiki_name="$1"
    local wiki_dir="$2"
    local wiki_domain="$3"
    
    log_info "🚀 Starting OAuth extension setup for $wiki_name (upgrade mode)..."
    
    # Check if extensions need to be installed
    if check_auth_extensions_needed "$wiki_name"; then
        # Install extensions
        if ! install_auth_extensions "$wiki_name"; then
            log_error "❌ Failed to install authentication extensions"
            return 1
        fi
        
        # Configure extension loading
        if ! add_oauth_extensions_config "$wiki_name" "$wiki_dir"; then
            log_error "❌ Failed to configure authentication extensions"
            return 1
        fi
        
        # Try to extract existing OAuth credentials from container
        local credentials
        if credentials=$(extract_oauth_credentials_from_container "$wiki_name"); then
            local client_id
            local client_secret
            client_id=$(echo "$credentials" | cut -d'|' -f1)
            client_secret=$(echo "$credentials" | cut -d'|' -f2)
            
            log_info "Using existing OAuth credentials from container configuration"
            
            # Add OAuth configuration directly without prompting
            local local_post_init_file="${wiki_dir}/post-init-settings.php"
            if ! add_google_oauth_config "$local_post_init_file" "$client_id" "$client_secret"; then
                log_error "❌ Failed to add OAuth configuration"
                return 1
            fi
            
            log_info "✅ OAuth extensions configured with existing credentials"
        else
            log_warn "⚠ No existing OAuth credentials found - skipping OAuth configuration"
            log_info "  Extensions are installed but not configured"
            log_info "  You can configure OAuth manually later if needed"
        fi
        
        log_info "✅ OAuth extension setup completed"
    else
        log_info "ℹ️ Authentication extensions already configured"
    fi
    
    return 0
}
