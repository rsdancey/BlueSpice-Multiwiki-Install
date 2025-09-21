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

# Get consistent post-init file path
get_post_init_file_path() {
    echo "/data/bluespice/post-init-settings.php"
}

# Check if authentication extensions need to be installed
check_auth_extensions_needed() {
    local wiki_name="$1"
    local container_name
    container_name=$(get_container_name "$wiki_name")
    
    # Check if container is running
    if ! is_container_running "$wiki_name"; then
        echo "❌ Container $container_name is not running" >&2
        return 2
    fi
    
    # Check if extensions already exist
    if docker_exec_safe "$wiki_name" test -d /app/bluespice/w/extensions/PluggableAuth 2>/dev/null && \
       docker_exec_safe "$wiki_name" test -d /app/bluespice/w/extensions/OpenIDConnect 2>/dev/null; then
        echo "✓ Authentication extensions already installed"
        return 1
    fi
    
    # Extensions need to be installed
    echo "ℹ️ Authentication extensions need to be installed"
    return 0
}

# Download and verify extension
download_extension() {
    local extension_name="$1"
    local temp_dir="$2"
    local primary_url="$3"
    local fallback_url="$4"
    
    echo "  📥 Downloading $extension_name extension..."
    
    # Try primary URL first
    if curl -L --fail --retry 3 --connect-timeout 10 \
       -o "$temp_dir/${extension_name}.tar.gz" "$primary_url"; then
        echo "  ✓ Downloaded $extension_name from primary source"
        return 0
    fi
    
    echo "  ⚠️ Primary download failed, trying fallback source..."
    
    # Try fallback URL
    if curl -L --fail --retry 3 --connect-timeout 10 \
       -o "$temp_dir/${extension_name}.tar.gz" "$fallback_url"; then
        echo "  ✓ Downloaded $extension_name from fallback source"
        return 0
    fi
    
    echo "  ❌ Failed to download $extension_name from both sources" >&2
    return 1
}

# Extract and prepare extension
extract_extension() {
    local extension_name="$1"
    local temp_dir="$2"
    
    echo "  📦 Extracting $extension_name..."
    
    cd "$temp_dir"
    if ! tar -xzf "${extension_name}.tar.gz"; then
        echo "  ❌ Failed to extract $extension_name" >&2
        return 1
    fi
    
    # Find and rename extracted directory to proper name
    local extracted_dir
    extracted_dir=$(find . -maxdepth 1 -type d -name "*${extension_name}*" | head -1)
    
    if [[ -z "$extracted_dir" ]]; then
        echo "  ❌ Could not find extracted $extension_name directory" >&2
        return 1
    fi
    
    if [[ "$extracted_dir" != "./$extension_name" ]]; then
        mv "$extracted_dir" "$extension_name"
    fi
    
    # Verify extraction
    if [[ ! -d "$extension_name" ]] || [[ ! -f "$extension_name/extension.json" ]]; then
        echo "  ❌ $extension_name extraction verification failed" >&2
        return 1
    fi
    
    # Set proper permissions
    chmod -R 755 "$extension_name"
    echo "  ✓ $extension_name extracted and prepared"
    return 0
}

# Install authentication extensions
install_auth_extensions() {
    local wiki_name="$1"
    local temp_dir="/tmp/mw_extensions_$$"
    local container_name
    container_name=$(get_container_name "$wiki_name")
    
    echo "🔧 Installing authentication extensions for $wiki_name..."
    
    # Validate inputs
    if ! validate_wiki_name "$wiki_name"; then
        return 1
    fi
    
    # Ensure container is ready
    if ! wait_for_container_ready "$wiki_name" 30; then
        echo "❌ Container not ready for extension installation" >&2
        return 1
    fi
    
    # Create temporary directory for downloads
    if ! mkdir -p "$temp_dir"; then
        echo "❌ Failed to create temporary directory: $temp_dir" >&2
        return 1
    fi
    
    # Cleanup function
    # shellcheck disable=SC2329
    cleanup_temp() {
        cd /
        [[ -n "${temp_dir:-}" ]] && rm -rf "$temp_dir"
    }
    trap cleanup_temp EXIT
    
    # Download PluggableAuth extension
    if ! download_extension "PluggableAuth" "$temp_dir" \
        "https://extdist.wmflabs.org/dist/extensions/PluggableAuth-REL1_43-8d3e70f.tar.gz" \
        "https://github.com/wikimedia/mediawiki-extensions-PluggableAuth/archive/refs/heads/REL1_43.tar.gz"; then
        return 1
    fi
    
    # Download OpenIDConnect extension
    if ! download_extension "OpenIDConnect" "$temp_dir" \
        "https://extdist.wmflabs.org/dist/extensions/OpenIDConnect-REL1_43-52e0b73.tar.gz" \
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
        echo "❌ Failed to copy PluggableAuth to container" >&2
        return 1
    fi

    if ! docker_set_ownership "$wiki_name" "/app/bluespice/w/extensions/PluggableAuth"; then
        echo "❌ Failed to set ownership for PluggableAuth in container" >&2
        return 1
    fi

    if ! docker_copy_to_container "$wiki_name" "$temp_dir/OpenIDConnect" "/app/bluespice/w/extensions/"; then
        echo "❌ Failed to copy OpenIDConnect to container" >&2
        return 1
    fi

    if ! docker_set_ownership "$wiki_name" "/app/bluespice/w/extensions/OpenIDConnect"; then
        echo "❌ Failed to set ownership for OpenIDConnect in container" >&2
        return 1
    fi



    # Install Composer in the container if not already present
    echo "  📦 Installing Composer in container..."
    if ! docker_exec_safe "$wiki_name" test -f /app/bluespice/w/composer.phar 2>/dev/null; then
        echo "  📥 Downloading and installing Composer using official method..."
        if docker_exec_safe "$wiki_name" bash -c "
            cd /app/bluespice/w &&
            php -r \"copy('https://getcomposer.org/installer', 'composer-setup.php');\" &&
            php -r \"if (hash_file('sha384', 'composer-setup.php') === 'ed0feb545ba87161262f2d45a633e34f591ebb3381f2e0063c345ebea4d228dd0043083717770234ec00c5a9f9593792') { echo 'Installer verified'.PHP_EOL; } else { echo 'Installer corrupt'.PHP_EOL; unlink('composer-setup.php'); exit(1); }\" &&
            php composer-setup.php &&
            php -r \"unlink('composer-setup.php');\" &&
            ls -la composer.phar
        " 2>/dev/null; then
            echo "  ✓ Composer installed successfully at /app/bluespice/w/composer.phar"
        else
            echo "  ❌ Failed to install Composer using official method"
            composer_failed=true
        fi
    else
        echo "  ✓ Composer already available at /app/bluespice/w/composer.phar"
    fi

    # Install OpenIDConnect PHP dependencies using the specific commands
    echo "  📦 Installing OpenIDConnect PHP dependencies..."
    if [[ "${composer_failed:-false}" != "true" ]]; then
        if docker_exec_safe "$wiki_name" bash -c "cd /app/bluespice/w/extensions/OpenIDConnect && php /app/bluespice/w/composer.phar install --no-dev"; then
            echo "  ✓ OpenIDConnect dependencies installed successfully (method 1)"
        elif docker_exec_safe "$wiki_name" sh -c "cd /app/bluespice/w/extensions/OpenIDConnect && /app/bluespice/w/composer.phar install"; then
            echo "  ✓ OpenIDConnect dependencies installed successfully (method 2)"
        else
            echo "  ⚠️ Composer methods failed, trying manual installation..."
            composer_failed=true
        fi
    fi

    # Set permissions in container
    echo "  🔐 Setting permissions..."
    docker_exec_safe "$wiki_name" chmod -R 755 /app/bluespice/w/extensions/PluggableAuth 2>/dev/null || true
    docker_exec_safe "$wiki_name" chmod -R 755 /app/bluespice/w/extensions/OpenIDConnect 2>/dev/null || true    # Verify installation
    echo "  ✅ Verifying installation..."
    if ! docker_exec_safe "$wiki_name" test -f /app/bluespice/w/extensions/PluggableAuth/extension.json || \
       ! docker_exec_safe "$wiki_name" test -f /app/bluespice/w/extensions/OpenIDConnect/extension.json; then
        echo "❌ Extension installation verification failed" >&2
        return 1
    fi
    
    echo "✅ Authentication extensions installed successfully"
    return 0
}

# Add extension configuration to MediaWiki
configure_extension_loading() {
    local wiki_name="$1"
    local container_name="bluespice-${wiki_name}-wiki-web"
    
    echo "⚙️ Configuring extension loading..."
    
    # Construct the wiki directory path and post-init file path
    local wikis_dir
    wikis_dir="$(dirname "${SCRIPT_DIR}")/wikis"
    local wiki_dir="${wikis_dir}/${wiki_name}"
    local post_init_file="${wiki_dir}/post-init-settings.php"
    
    # Use the new init-settings-config library function
    if ! add_oauth_extensions_config "$post_init_file"; then
        echo "❌ Failed to add OAuth extension configuration" >&2
        return 1
    fi
    
    echo "✅ Extension loading configuration completed"
    return 0
}

# Configure Google OAuth settings (now using init-settings-config library)
configure_oauth_settings() {
    local wiki_name="$1"
    local wiki_domain="$2"
    
    # Use the new interactive OAuth configuration from init-settings-config library
    setup_interactive_oauth_config "$wiki_name" "$wiki_domain"
}
# Complete OAuth setup process
setup_oauth_extensions() {
    local wiki_name="$1"
    local wiki_domain="$2"
    
    echo "🚀 Starting OAuth extension setup for $wiki_name..."
    
    # Validate inputs
    if ! validate_wiki_name "$wiki_name"; then
        return 1
    fi
    
    if ! validate_domain "$wiki_domain"; then
        return 1
    fi
    
    # Check if extensions need to be installed
    if check_auth_extensions_needed "$wiki_name"; then
        # Install extensions
        if ! install_auth_extensions "$wiki_name"; then
            echo "❌ Failed to install authentication extensions" >&2
            return 1
        fi
        
        # Configure extension loading
        if ! configure_extension_loading "$wiki_name"; then
            echo "❌ Failed to configure extension loading" >&2
            return 1
        fi
        
        # Configure OAuth settings
        if ! configure_oauth_settings "$wiki_name" "$wiki_domain"; then
            echo "❌ Failed to configure OAuth settings" >&2
            return 1
        fi
        
        echo "✅ OAuth extension setup completed successfully"
    else
        echo "ℹ️ Authentication extensions already configured"
    fi
    
    return 0
}
