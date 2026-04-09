#!/bin/bash

# MediaWiki Configuration Management
# Handles creation and management of MediaWiki configuration files

set -euo pipefail

# Create pre-init-settings.php with base permissions
create_pre_init_settings() {
    local wiki_dir="$1"
    local wiki_name="$2"
    local pre_init_file="${wiki_dir}/pre-init-settings.php"
    
    log_info "Creating pre-init-settings.php with email permissions..."
    log_info "Wiki dir: $wiki_dir"
    log_info "Pre-init file path: $pre_init_file"
    
    # Check if directory exists
    if [[ ! -d "$wiki_dir" ]]; then
        log_error "Wiki directory does not exist: $wiki_dir"
        return 1
    fi
    
    # Check if we can write to the directory
    if [[ ! -w "$wiki_dir" ]]; then
        log_error "No write permission to wiki directory: $wiki_dir"
        return 1
    fi
    
    cat > "$pre_init_file" << PREINIT_EOF
<?php

# Enable email permissions for users
\$wgGroupPermissions['user']['sendemail'] = true;
\$wgGroupPermissions['autoconfirmed']['sendemail'] = true;

# Set temp directory for RunJobsTriggerRunner working dir
# Note: BlueSpiceFoundation overrides this to BSDATADIR at runtime,
# but we set it here as a fallback in case that behavior changes.
\$GLOBALS['mwsgRunJobsTriggerRunnerWorkingDir'] = '/tmp/wiki';
PREINIT_EOF
    
    # Check if file was created successfully
    if [[ ! -f "$pre_init_file" ]]; then
        log_error "Failed to create pre-init-settings.php file"
        return 1
    fi
    
    return 0
}

# Create post-init-settings.php with base configuration
create_post_init_settings() {
    local wiki_dir="$1"
    local wiki_name="$2"
    local post_init_file="${wiki_dir}/post-init-settings.php"
    
    log_info "Creating post-init-settings.php with guarded auth extension loading..."
    log_info "Wiki dir: $wiki_dir"
    log_info "Post-init file path: $post_init_file"
    
    # Use the complete template with guarded auth extension loading
    # This template includes /tmp/wiki standardization and CLI-aware auth loading
    if [ ! -f "/core/core_install/templates/post-init-settings-template.php" ]; then
        log_error "Template file not found: /core/core_install/templates/post-init-settings-template.php"
        return 1
    fi
    
    if ! cp /core/core_install/templates/post-init-settings-template.php "$post_init_file"; then
        log_error "Failed to copy post-init-settings template"
        return 1
    fi
    
    # Read SMTP settings from .env and substitute placeholders
    local env_file="${wiki_dir}/.env"
    if [ -f "$env_file" ]; then
        local smtp_host smtp_port smtp_user smtp_pass wiki_host
        smtp_host=$(grep "^SMTP_HOST=" "$env_file" | cut -d= -f2 || echo "mail.google.com")
        smtp_port=$(grep "^SMTP_PORT=" "$env_file" | cut -d= -f2 || echo "587")
        smtp_user=$(grep "^SMTP_USER=" "$env_file" | cut -d= -f2 || echo "alderacwiki@alderac.com")
        smtp_pass=$(grep "^SMTP_PASS=" "$env_file" | cut -d= -f2 || echo "")
        wiki_host=$(grep "^WIKI_HOST=" "$env_file" | cut -d= -f2 || echo "wiki.alderac.com")
        
        # Substitute placeholders in post-init-settings.php
        sed -i "s/{{SMTP_HOST}}/$smtp_host/g" "$post_init_file"
        sed -i "s/{{SMTP_PORT}}/$smtp_port/g" "$post_init_file"
        sed -i "s/{{SMTP_USER}}/$smtp_user/g" "$post_init_file"
        sed -i "s/{{SMTP_PASS}}/$smtp_pass/g" "$post_init_file"
        sed -i "s/{{WIKI_HOST}}/$wiki_host/g" "$post_init_file"

        gtag_analytics_id=$(grep "^GTAG_ANALYTICS_ID=" "$env_file" | cut -d= -f2 || echo "")
        sed -i "s/{{GTAG_ANALYTICS_ID}}/$gtag_analytics_id/g" "$post_init_file"
        
        log_info "GTag Analytics ID substituted from .env file"
        
        log_info "SMTP settings substituted from .env file"
    else
        log_warn ".env file not found - using default SMTP placeholders"
    fi
    
    log_info "Successfully created post-init-settings.php from template"
    return 0
}

# Main function to create complete MediaWiki configuration files
create-init-settings-config-files() {
    local wiki_dir="$1"
    local wiki_name="$2"

    log_info "Creating MediaWiki configuration files..."
    
    # Create pre-init-settings.php
    if ! create_pre_init_settings "$wiki_dir" "$wiki_name"; then
        log_error "Failed to create pre-init-settings.php"
        return 1
    fi
    
    # Create post-init-settings.php
    if ! create_post_init_settings "$wiki_dir" "$wiki_name"; then
        log_error "Failed to create post-init-settings.php"
        return 1
    fi
    
    log_info "MediaWiki configuration files created successfully"
    return 0
}

# Copy configuration files to running container
copy_config_files_to_container() {
    local wiki_name="$1"
    local wiki_dir="$2"
    local pre_init_file="${wiki_dir}/pre-init-settings.php"
    local post_init_file="${wiki_dir}/post-init-settings.php"
    
    log_info "Creating configuration files in container with correct ownership..."
    
    # Create pre-init-settings.php in container with correct ownership
    if [[ -f "$pre_init_file" ]]; then
        if ! docker_copy_to_container "$wiki_name" "$pre_init_file" "/data/bluespice/"; then
            echo "❌ Failed to copy pre-init-settings.php to container"
            return 1
        fi

        if ! docker_set_ownership "$wiki_name" "/data/bluespice/pre-init-settings.php"; then
            echo "❌ Failed to set ownership for pre-init-settings.php in container"
            return 1
        fi
        docker exec "bluespice-${wiki_name}-wiki-web" chmod 664 /data/bluespice/pre-init-settings.php 2>/dev/null || true
    fi

    # Create post-init-settings.php in container with correct ownership
    if [[ -f "$post_init_file" ]]; then
        if ! docker_copy_to_container "$wiki_name" "$post_init_file" "/data/bluespice/"; then
            echo "❌ Failed to copy post-init-settings.php to container"
            return 1
        fi

        if ! docker_set_ownership "$wiki_name" "/data/bluespice/post-init-settings.php"; then
            echo "❌ Failed to set ownership for post-init-settings.php in container"
            return 1
        fi
        docker exec "bluespice-${wiki_name}-wiki-web" chmod 664 /data/bluespice/post-init-settings.php 2>/dev/null || true
    fi
    
    return 0
}

# Interactive OAuth configuration setup
setup_interactive_oauth_config() {
    local wiki_name="$1"
    local wiki_domain="$2"

    echo ""
    echo "==================================================================="
    echo "Google OAuth / SSO Configuration (Optional)"
    echo "==================================================================="
    echo ""
    printf "Do you want to enable Google OAuth (Login with Google)? [y/N]: "
    read -r configure_oauth

    if [[ "${configure_oauth,,}" != "y" ]]; then
        log_info "OAuth configuration skipped"
        return 0
    fi

    echo ""
    echo "OAuth extensions have been installed. To complete setup:"
    echo ""
    echo "Step 1 — Create Google OAuth credentials:"
    echo "  1. Go to https://console.cloud.google.com"
    echo "  2. Create or select a project, then enable Google Auth Platform"
    echo "  3. Create OAuth 2.0 credentials (Web Application type)"
    echo "  4. Add this Authorized Redirect URI:"
    echo "     https://${wiki_domain}/wiki/Special:PluggableAuthLogin"
    echo ""
    echo "Step 2 — Enter credentials in BlueSpice ConfigManager:"
    echo "  1. Log in to the wiki as an admin"
    echo "  2. Go to Special:BluespiceConfigManager"
    echo "  3. Find 'PluggableAuth' settings and enter:"
    echo "       Issuer URL : https://accounts.google.com"
    echo "       Client ID  : (from Google Cloud Console)"
    echo "       Client Secret : (from Google Cloud Console)"
    echo "  4. Save the configuration"
    echo ""
    echo "These values are stored in the BlueSpice database — do not add them"
    echo "to post-init-settings.php or they will conflict with the DB config."
    echo ""

    return 0
}
