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

# Set a useable /tmp directory                                                                                              
\$GLOBALS['mwsgRunJobsTriggerRunnerWorkingDir'] = '/tmp/${wiki_name}';
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
    
    log_info "Creating post-init-settings.php with base configuration..."
    
    cat > "$post_init_file" << POSTINIT_BASE_EOF
<?php

# Set a useable /tmp directory
\$GLOBALS['mwsgRunJobsTriggerRunnerWorkingDir'] = '/tmp/${wiki_name}';

# Override the default with a bundle of filetypes:
\$wgFileExtensions = array('png', 'gif', 'jpg', 'jpeg', 'ppt', 'pdf', 
'psd', 'mp3', 'xls', 'xlsx', 'doc','docx', 'mp4', 'mov', 'ico' );

\$wgCookieExpiration = 86400;
\$wgExtendedLoginCookieExpiration = null;

# May lock session value for 8 hours we'll see                                                                                        
\$wgObjectCacheSessionExpiry = 28800;     

# sets a tmp directory other than the default                                                                                         
\$wgTmpDirectory = "/tmp/${wiki_name}";     

# BlueSpice Extended Search Backend Configuration                                                                                     
\$GLOBALS["bsgESBackendHost"] = "bluespice-search";                                                                                    
\$GLOBALS["bsgESBackendPort"] = "9200";                                                                                                
\$GLOBALS["bsgESBackendTransport"] = "http";                                                                                           
\$GLOBALS["bsgESBackendUsername"] = "";                                                                                                
\$GLOBALS["bsgESBackendPassword"] = "";  

# Whitelist some pages                                                                                                                
\$wgWhitelistRead = [                                                                                                                  
    'Privacy Policy',                                                                                                                 
    'Special:Login',                                                                                                                  
    'Special:CreateAccount',                                                                                                          
    'Special:CreateAccount/return'                                                                                                    
];   

# add a function to autoadd new users to basic groups                                                                                 
# NOTE: Comment this out if you want the public to read and not edit
    \$wgHooks['LocalUserCreated'][] = function ( User \$user, \$autocreated ) {
    \$services = MediaWiki\\MediaWikiServices::getInstance();
    \$userGroupManager = \$services->getUserGroupManager();
    \$userGroupManager->addUserToGroup( \$user, 'editor' );
    \$userGroupManager->addUserToGroup( \$user, 'reviewer' );
};       

# Post-initialization settings
# Additional configurations will be appended below
POSTINIT_BASE_EOF
    
    return 0
}

# Add SMTP configuration to post-init-settings.php
add_smtp_configuration() {
    local wiki_dir="$1"
    local smtp_host="$2"
    local smtp_port="$3"
    local smtp_user="$4"
    local smtp_pass="$5"
    local smtp_idhost="$6"
    local post_init_file="${wiki_dir}/post-init-settings.php"
    
    if [[ -z "$smtp_host" || -z "$smtp_user" || -z "$smtp_pass" ]]; then
        log_warn "SMTP configuration incomplete - skipping SMTP setup"
        return 0
    fi
    
    log_info "Adding SMTP configuration to post-init-settings.php..."
    
    cat >> "$post_init_file" << SMTP_CONFIG_EOF

# ============================================
# SMTP Email Configuration
# ============================================

# Email configuration
\$wgPasswordSender = '$smtp_user';
\$wgEmergencyContact = '$smtp_user';
\$wgNoReplyAddress = '$smtp_user';

# SMTP configuration
\$wgSMTP = [
    'host'     => '$smtp_host',
    'IDHost'   => '$smtp_idhost',
    'port'     => $smtp_port,
    'auth'     => true,
    'username' => '$smtp_user',
    'password' => '$smtp_pass'
];
SMTP_CONFIG_EOF
    
    return 0
}

# Add OAuth extension loading configuration
add_oauth_extensions_config() {
    local wiki_name="$1"
    local wiki_dir="$2"
    local post_init_file="${wiki_dir}/post-init-settings.php"

        
    log_info "Adding OAuth extension loading configuration..."
    
    cat >> "$post_init_file" << 'AUTH_EXTENSIONS_EOF'

# ============================================
# OAuth Extensions Loading
# ============================================

# Load web-only auth integrations (skip for CLI/maintenance)
if ( !isset($wgCommandLineMode) || !$wgCommandLineMode ) {
    wfLoadExtension( 'PluggableAuth' );
    
    # Ensure OpenIDConnect has its dependencies before loading
    \$openIDConnectPath = $IP . '/extensions/OpenIDConnect';
    if ( file_exists( \$openIDConnectPath . '/vendor/autoload.php' ) ) {
        require_once \$openIDConnectPath . '/vendor/autoload.php';
    } elseif ( file_exists( \$openIDConnectPath . '/vendor/jumbojett/openid-connect-php/src/OpenIDConnectClient.php' ) ) {
        require_once \$openIDConnectPath . '/vendor/jumbojett/openid-connect-php/src/OpenIDConnectClient.php';
    }
    
    wfLoadExtension( 'OpenIDConnect' );
}
AUTH_EXTENSIONS_EOF
    
    return 0
}

# Add Google OAuth configuration
add_google_oauth_config() {
    local post_init_file="$1"
    local oauth_client_id="$2"
    local oauth_client_secret="$3"
    local create_if_not_exist="$4"
    local email_matching_only="$5"
    
    log_info "Adding Google OAuth configuration..."
    
    cat >> "$post_init_file" << OAUTH_CONFIG_EOF

# ============================================
# Google OAuth Configuration
# ============================================

# Google OAuth configuration
\$wgPluggableAuth_Config["Google"] = [
    "plugin" => "OpenIDConnect",
    "data" => [
        "providerURL" => "https://accounts.google.com/.well-known/openid-configuration",
        "clientID" => "${oauth_client_id}",
        "clientSecret" => "${oauth_client_secret}",
        "scope" => ["openid", "email", "profile"],
        "email_key" => "email",
        "use_email_mapping" => true
    ],
    "buttonLabelMessage" => "Login with Google"
];

# Enable local login alongside PluggableAuth
\$wgPluggableAuth_EnableLocalLogin = true;
\$wgPluggableAuth_EnableAutoLogin = false;

# OAuth email matching and account creation settings
\$wgPluggableAuth_EmailMatchingOnly = ${email_matching_only};
\$wgPluggableAuth_CreateIfDoesNotExist = ${create_if_not_exist};

# Explicitly prevent automatic user creation if not enabled
\$wgGroupPermissions["*"]["autocreateaccount"] = ${create_if_not_exist};

# Additional OpenIDConnect settings
\$wgOpenIDConnect_UseEmailNameAsUserName = false;
\$wgOpenIDConnect_MigrateUsersByEmail = true;
\$wgOpenIDConnect_UseRealNameAsUserName = false;
OAUTH_CONFIG_EOF
    
    return 0
}

# Add OAuth placeholder configuration
add_oauth_placeholder_config() {
    local post_init_file="$1"
    
    log_info "Adding OAuth placeholder configuration..."
    
    cat >> "$post_init_file" << 'OAUTH_PLACEHOLDER_EOF'

# ============================================
# Google OAuth Configuration (Must be manually configured)
# ============================================
# To enable Google OAuth login:
# 1. Get credentials from https://console.cloud.google.com
# 2. Uncomment and update the configuration below
# 3. Add redirect URI: https://YOUR-DOMAIN/index.php/Special:PluggableAuthLogin

/*

\$wgPluggableAuth_Config["Google"] = [
    "plugin" => "OpenIDConnect",
    "data" => [
        "providerURL" => "https://accounts.google.com/.well-known/openid-configuration",
        "clientID" => "YOUR_GOOGLE_CLIENT_ID",
        "clientSecret" => "YOUR_GOOGLE_CLIENT_SECRET",
        "scope" => ["openid", "email", "profile"],
        "email_key" => "email",
        "use_email_mapping" => true
    ],
    "buttonLabelMessage" => "Login with Google"
];

# Enable local login alongside PluggableAuth
\$wgPluggableAuth_EnableLocalLogin = true;
\$wgPluggableAuth_EnableAutoLogin = false;

# OAuth email matching and account creation settings
\$wgPluggableAuth_EmailMatchingOnly = ${email_matching_only};
\$wgPluggableAuth_CreateIfDoesNotExist = ${create_if_not_exist};

# Explicitly prevent automatic user creation if not enabled
\$wgGroupPermissions["*"]["autocreateaccount"] = ${create_if_not_exist};

# Additional OpenIDConnect settings
\$wgOpenIDConnect_UseEmailNameAsUserName = false;
\$wgOpenIDConnect_MigrateUsersByEmail = true;
\$wgOpenIDConnect_UseRealNameAsUserName = false;
*/
OAUTH_PLACEHOLDER_EOF
    
    return 0
}

# Main function to create complete MediaWiki configuration files
create-init-settings-config-files() {
    local wiki_dir="$1"
    local wiki_name="$2"
    local env_file="${wiki_dir}/.env"
    
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
    
    # Read SMTP settings from .env file and add SMTP configuration
    if [[ -f "$env_file" ]]; then
        local smtp_host smtp_port smtp_user smtp_pass smtp_idhost
        smtp_host=$(grep "^SMTP_HOST=" "$env_file" | cut -d= -f2 2>/dev/null || echo "")
        smtp_port=$(grep "^SMTP_PORT=" "$env_file" | cut -d= -f2 2>/dev/null || echo "587")
        smtp_user=$(grep "^SMTP_USER=" "$env_file" | cut -d= -f2 2>/dev/null || echo "")
        smtp_pass=$(grep "^SMTP_PASS=" "$env_file" | cut -d= -f2 2>/dev/null || echo "")
        smtp_idhost=$(grep "^WIKI_HOST=" "$env_file" | cut -d= -f2 2>/dev/null || echo "")
        
        if ! add_smtp_configuration "$wiki_dir" "$smtp_host" "$smtp_port" "$smtp_user" "$smtp_pass" "$smtp_idhost"; then
            log_warn "Failed to add SMTP configuration"
        fi
    else
        log_warn ".env file not found - skipping SMTP configuration"
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
    fi
    
    return 0
}

# Interactive OAuth configuration setup
setup_interactive_oauth_config() {
    local wiki_name="$1"
    local wiki_domain="$2"
    
    echo ""
    echo "==================================================================="
    echo "Google OAuth Configuration (Optional)"
    echo "==================================================================="
    echo ""
    echo "To enable 'Login with Google' functionality, you need to:"
    echo "1. Create a Google Cloud project at https://console.cloud.google.com"
    echo "2. Enable Google Auth Platform"
    echo "3. Create OAuth 2.0 credentials in Clients as a Client ID for Web Application"
    echo "4. In Clients setup use this as authorized redirect URI:"
    echo "   https://${wiki_domain}/index.php/Special:PluggableAuthLogin"
    echo ""
    
    printf "Do you want to configure Google OAuth now? [y/N]: "
    read -r configure_oauth
    
    if [[ "${configure_oauth,,}" == "y" ]]; then
        # Get OAuth credentials
        printf "Enter Google OAuth Client ID: "
        read -r oauth_client_id
        
        while [[ -z "$oauth_client_id" ]]; do
                echo "Client ID is required"
                printf "Enter Google OAuth Client ID: "
                read -r oauth_client_id
            done

        printf "Enter Google OAuth Client Secret: "
        read -r oauth_client_secret
            
        while [[ -z "$oauth_client_secret" ]]; do
            echo "Client Secret is required when Client ID is provided"
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
            
        # Add Google OAuth configuration using the centralized function
        local wikis_dir
        wikis_dir="$(dirname "${SCRIPT_DIR}")/wikis"
        local wiki_dir="${wikis_dir}/${wiki_name}"
        local local_post_init_file="${wiki_dir}/post-init-settings.php"
        
        if ! add_google_oauth_config "$local_post_init_file" "$oauth_client_id" "$oauth_client_secret" "$create_if_not_exist" "$email_matching_only"; then
            echo "❌ Failed to add OAuth configuration" >&2
            return 1
        fi
            
        # Store OAuth settings in .env file for reference
        local env_file="${wikis_dir}/${wiki_name}/.env"
        {
            echo ""
            echo "# Google OAuth Settings"
            echo "OAUTH_CLIENT_ID=${oauth_client_id}"
            echo "OAUTH_CLIENT_SECRET=${oauth_client_secret}"
            echo "OAUTH_AUTOCREATE=${create_if_not_exist}"
        } >> "$env_file"
    else
        log_info "OAuth configuration skipped"
        # Add placeholder configuration using the centralized function
        local wikis_dir
        wikis_dir="$(dirname "${SCRIPT_DIR}")/wikis"
        local wiki_dir="${wikis_dir}/${wiki_name}"
        local local_post_init_file="${wiki_dir}/post-init-settings.php"
        
        if ! add_oauth_placeholder_config "$local_post_init_file"; then
            echo "❌ Failed to add OAuth placeholder configuration" >&2
            return 1
        fi
    fi
    
    return 0
}
