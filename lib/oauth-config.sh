#!/bin/bash

# OAuth extension management for BlueSpice MediaWiki
# Handles installation and configuration of authentication extensions
# NOTE: This file is sourced by other scripts; do not use set -euo pipefail here.

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
    
    log_error "  ❌ Failed to download $extension_name from both sources"
    return 1
}

# Extract and prepare extension
extract_extension() {
    local extension_name="$1"
    local temp_dir="$2"
    
    log_info "  📦 Extracting $extension_name..."
    
    cd "$temp_dir" || return 1
    if ! tar -xzf "${extension_name}.tar.gz"; then
        log_error "  ❌ Failed to extract $extension_name"
        return 1
    fi

    # Find and rename extracted directory to proper name
    local extracted_dir
    extracted_dir=$(find . -maxdepth 1 -type d -name "*${extension_name}*" | head -1)

    if [[ -z "$extracted_dir" ]]; then
        log_error "  ❌ Could not find extracted $extension_name directory"
        return 1
    fi

    if [[ "$extracted_dir" != "./$extension_name" ]]; then
        mv "$extracted_dir" "$extension_name"
    fi

    # Verify extraction
    if [[ ! -d "$extension_name" ]] || [[ ! -f "$extension_name/extension.json" ]]; then
        log_error "  ❌ $extension_name extraction verification failed"
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
    # Also persist durable copies under /data/bluespice/extensions (host volume)
    docker_exec_safe "$wiki_name" mkdir -p /data/bluespice/extensions >/dev/null 2>&1 || true
    docker_exec_safe "$wiki_name" rm -rf /data/bluespice/extensions/PluggableAuth /data/bluespice/extensions/OpenIDConnect >/dev/null 2>&1 || true
    if ! docker_copy_to_container "$wiki_name" "$temp_dir/PluggableAuth" "/data/bluespice/extensions/"; then log_warn "⚠️ Failed to copy PluggableAuth to persistent /data; continuing"; fi
    if ! docker_copy_to_container "$wiki_name" "$temp_dir/OpenIDConnect" "/data/bluespice/extensions/"; then log_warn "⚠️ Failed to copy OpenIDConnect to persistent /data; continuing"; fi
    docker_exec_safe "$wiki_name" chown -R bluespice:bluespice /data/bluespice/extensions >/dev/null 2>&1 || true
    docker_exec_safe "$wiki_name" chmod -R g+rwX /data/bluespice/extensions >/dev/null 2>&1 || true

    # Install Composer to persistent storage if not already present.
    # Installing here (not to /app) ensures composer.phar survives container recreation.
    log_info "  📦 Installing Composer..."
    if ! docker_exec_safe "$wiki_name" "test -f /data/bluespice/extensions/composer.phar" 2>/dev/null; then
        log_info "  📥 Downloading Composer..."
        if docker_exec_safe "$wiki_name" "
            php -r \"copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');\" &&
            php /tmp/composer-setup.php --install-dir=/data/bluespice/extensions --filename=composer.phar &&
            php -r \"unlink('/tmp/composer-setup.php');\"
        "; then
            log_info "  ✓ Composer installed to persistent storage"
        else
            log_error "  ❌ Failed to install Composer"
            return 1
        fi
    fi

    # Install OpenIDConnect PHP dependencies into persistent storage.
    # Running Composer here (not against /app) means vendor/ is saved to the host
    # volume and will be included when the startup script restores extensions on restart.
    log_info "  📦 Installing OpenIDConnect PHP dependencies..."
    if ! docker_exec_safe "$wiki_name" "cd /data/bluespice/extensions/OpenIDConnect && php /data/bluespice/extensions/composer.phar install --no-dev --ignore-platform-reqs"; then
        log_error "  ❌ Composer install failed"
        return 1
    fi
    log_info "  ✓ OpenIDConnect dependencies installed"

    # Fix ownership on persistent extensions now that vendor/ has been written
    docker_exec_safe "$wiki_name" chown -R bluespice:bluespice /data/bluespice/extensions >/dev/null 2>&1 || true

    # Copy the complete extensions (including vendor/) to the active /app path for
    # immediate use. On future container restarts the startup script handles this.
    log_info "  📋 Activating extensions in container..."
    if ! docker_exec_safe "$wiki_name" "rm -rf /app/bluespice/w/extensions/PluggableAuth && cp -r /data/bluespice/extensions/PluggableAuth /app/bluespice/w/extensions/PluggableAuth"; then
        log_error "❌ Failed to activate PluggableAuth" >&2
        return 1
    fi
    if ! docker_exec_safe "$wiki_name" "rm -rf /app/bluespice/w/extensions/OpenIDConnect && cp -r /data/bluespice/extensions/OpenIDConnect /app/bluespice/w/extensions/OpenIDConnect"; then
        log_error "❌ Failed to activate OpenIDConnect" >&2
        return 1
    fi
    docker_set_ownership "$wiki_name" "/app/bluespice/w/extensions/PluggableAuth"
    docker_set_ownership "$wiki_name" "/app/bluespice/w/extensions/OpenIDConnect"

    # Verify all required files are present
    if ! docker_exec_safe "$wiki_name" "test -f /app/bluespice/w/extensions/PluggableAuth/extension.json"; then
        log_error "❌ PluggableAuth extension.json not found"
        return 1
    fi
    if ! docker_exec_safe "$wiki_name" "test -f /app/bluespice/w/extensions/OpenIDConnect/extension.json"; then
        log_error "❌ OpenIDConnect extension.json not found"
        return 1
    fi
    if ! docker_exec_safe "$wiki_name" "test -f /app/bluespice/w/extensions/OpenIDConnect/vendor/autoload.php"; then
        log_error "❌ OpenIDConnect vendor/autoload.php not found"
        return 1
    fi

    cd /
    [[ -n "${temp_dir:-}" ]] && rm -rf "$temp_dir"

    log_info "  ✓ OAuth extensions installed and activated"
    return 0
}

# Complete OAuth setup process
setup_oauth_extensions() {
    local wiki_name="$1"
    # $2 (wiki_dir) is accepted for API compatibility but not used internally
    local wiki_domain="$3"
    
    log_info "🚀 Starting OAuth extension setup for $wiki_name..."
    
    # Check if extensions need to be installed
    if check_auth_extensions_needed "$wiki_name"; then
        # Install extensions
        if ! install_auth_extensions "$wiki_name"; then
            log_error "❌ Failed to install authentication extensions"
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
