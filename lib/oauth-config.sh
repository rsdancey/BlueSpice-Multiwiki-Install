#!/bin/bash

# OAuth extension management for BlueSpice MediaWiki
# Handles installation and configuration of authentication extensions

set -euo pipefail

# Source required libraries
source "${SCRIPT_DIR}/lib/docker-utils.sh"
source "${SCRIPT_DIR}/lib/validation.sh"

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
    cleanup_temp() {
        cd /
        rm -rf "$temp_dir"
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
    
    if ! docker_copy_to_container "$wiki_name" "$temp_dir/OpenIDConnect" "/app/bluespice/w/extensions/"; then
        echo "❌ Failed to copy OpenIDConnect to container" >&2
        return 1
    fi
    
    # Set permissions in container
    echo "  🔐 Setting permissions..."
    docker_exec_safe "$wiki_name" chmod -R 755 /app/bluespice/w/extensions/PluggableAuth 2>/dev/null || true
    docker_exec_safe "$wiki_name" chmod -R 755 /app/bluespice/w/extensions/OpenIDConnect 2>/dev/null || true
    
    # Verify installation
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
    local post_init_file
    post_init_file=$(get_post_init_file_path)
    
    echo "⚙️ Configuring extension loading..."
    
    # Check if configuration already exists
    if docker_exec_safe "$wiki_name" grep -q "wfLoadExtension.*PluggableAuth" "$post_init_file" 2>/dev/null; then
        echo "✓ Extension configuration already exists in post-init-settings.php"
        return 0
    fi
    
    # Add the extension configuration
    local config_content='
# Load web-only auth integrations (skip for CLI/maintenance)
if ( !isset($wgCommandLineMode) || !$wgCommandLineMode ) {
    wfLoadExtension( '\''PluggableAuth'\'' );
    wfLoadExtension( '\''OpenIDConnect'\'' );
}'
    
    if docker_exec_safe "$wiki_name" bash -c "cat >> '$post_init_file' << 'AUTH_CONFIG_EOF'
$config_content
AUTH_CONFIG_EOF"; then
        echo "✓ Extension configuration added to post-init-settings.php"
        return 0
    else
        echo "❌ Failed to add extension configuration" >&2
        return 1
    fi
}

# Configure Google OAuth settings
configure_oauth_settings() {
    local wiki_name="$1"
    local wiki_domain="$2"
    local post_init_file
    post_init_file=$(get_post_init_file_path)
    
    echo ""
    echo "==================================================================="
    echo "🔐 Google OAuth Configuration (Optional)"
    echo "==================================================================="
    echo ""
    echo "To enable 'Login with Google' functionality, you need to:"
    echo "1. Create a Google Cloud project at https://console.cloud.google.com"
    echo "2. Enable Google+ API"
    echo "3. Create OAuth 2.0 credentials"
    echo "4. Add this as authorized redirect URI:"
    echo "   https://${wiki_domain}/index.php/Special:PluggableAuthLogin"
    echo ""
    
    printf "Do you want to configure Google OAuth now? [y/N]: "
    read -r configure_oauth
    
    if [[ "${configure_oauth,,}" != "y" ]]; then
        echo "ℹ️ OAuth configuration skipped. You can configure it later by editing post-init-settings.php"
        return 0
    fi
    
    # Get OAuth credentials
    printf "Enter Google OAuth Client ID (or press Enter to skip): "
    read -r oauth_client_id
    
    if [[ -z "$oauth_client_id" ]]; then
        echo "ℹ️ OAuth configuration skipped - no Client ID provided"
        return 0
    fi
    
    printf "Enter Google OAuth Client Secret: "
    read -r oauth_client_secret
    
    while [[ -z "$oauth_client_secret" ]]; do
        echo "❌ Client Secret is required when Client ID is provided"
        printf "Enter Google OAuth Client Secret: "
        read -r oauth_client_secret
    done
    
    # Ask about account creation settings
    printf "Allow automatic account creation for Google users? [y/N]: "
    read -r allow_autocreate
    
    local create_if_not_exist="false"
    local email_matching_only="true"
    
    if [[ "${allow_autocreate,,}" == "y" ]]; then
        create_if_not_exist="true"
        email_matching_only="false"
    fi
    
    # Write OAuth configuration to post-init-settings.php
    local oauth_config="
# ============================================
# Google OAuth Configuration
# ============================================

# Whitelist some pages for public access
\$wgWhitelistRead = [
    'Privacy Policy',
    'Special:Login',
    'Special:CreateAccount',
    'Special:CreateAccount/return'
];

# Google OAuth configuration
\$wgPluggableAuth_Config[\"Google\"] = [
    \"plugin\" => \"OpenIDConnect\",
    \"data\" => [
        \"providerURL\" => \"https://accounts.google.com/.well-known/openid-configuration\",
        \"clientID\" => \"${oauth_client_id}\",
        \"clientSecret\" => \"${oauth_client_secret}\",
        \"scope\" => [\"openid\", \"email\", \"profile\"],
        \"email_key\" => \"email\",
        \"use_email_mapping\" => true
    ],
    \"buttonLabelMessage\" => \"Login with Google\"
];

# Enable local login alongside PluggableAuth
\$wgPluggableAuth_EnableLocalLogin = true;
\$wgPluggableAuth_EnableAutoLogin = false;

# OAuth email matching and account creation settings
\$wgPluggableAuth_EmailMatchingOnly = ${email_matching_only};
\$wgPluggableAuth_CreateIfDoesNotExist = ${create_if_not_exist};

# Explicitly prevent automatic user creation if not enabled
\$wgGroupPermissions[\"*\"][\"autocreateaccount\"] = ${create_if_not_exist};"
    
    if docker_exec_safe "$wiki_name" bash -c "cat >> '$post_init_file' << 'OAUTH_CONFIG_EOF'
$oauth_config
OAUTH_CONFIG_EOF"; then
        echo "✅ OAuth configuration added successfully"
        echo ""
        echo "📋 OAuth Setup Summary:"
        echo "  • Client ID: ${oauth_client_id}"
        echo "  • Auto-create accounts: ${allow_autocreate,,}"
        echo "  • Redirect URI: https://${wiki_domain}/index.php/Special:PluggableAuthLogin"
        echo ""
        echo "⚠️  Remember to add the redirect URI to your Google OAuth configuration!"
        return 0
    else
        echo "❌ Failed to write OAuth configuration" >&2
        return 1
    fi
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
