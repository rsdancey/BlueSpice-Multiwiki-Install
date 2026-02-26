<?php
# ============================================
# BlueSpice Wiki Post-Init Settings Template
# ============================================
# This template should be copied to /bluespice/<wiki-name>/post-init-settings.php
# when creating a new wiki instance.
#
# Auth extensions are loaded only when their directories exist (is_dir check).
# This safely handles task containers that lack the extensions, and also
# allows update.php to see the schema so DB tables are created automatically.

# Set a useable /tmp directory
# $GLOBALS['mwsgRunJobsTriggerRunnerWorkingDir'] = '/tmp/wiki';

# Override the default with a bundle of filetypes:
$wgFileExtensions = array('png', 'gif', 'jpg', 'jpeg', 'ppt', 'pdf', 
'psd', 'mp3', 'xls', 'xlsx', 'doc','docx', 'mp4', 'mov', 'ico' );

$wgCookieExpiration = 86400;
$wgExtendedLoginCookieExpiration = null;

# May lock session value for 8 hours we'll see                                                                                        
$wgObjectCacheSessionExpiry = 28800;     

# sets a tmp directory other than the default                                                                                         
$wgTmpDirectory = "/tmp/wiki";     

# BlueSpice Extended Search Backend Configuration                                                                                     
$GLOBALS["bsgESBackendHost"] = "bluespice-search";                                                                                    
$GLOBALS["bsgESBackendPort"] = "9200";                                                                                                
$GLOBALS["bsgESBackendTransport"] = "http";                                                                                           
$GLOBALS["bsgESBackendUsername"] = "";                                                                                                
$GLOBALS["bsgESBackendPassword"] = "";  

# Whitelist some pages                                                                                                                
$wgWhitelistRead = [                                                                                                                  
    'Privacy Policy',                                                                                                                 
    'Special:Login',                                                                                                                  
    'Special:CreateAccount',                                                                                                          
    'Special:CreateAccount/return'                                                                                                    
];   

# add a function to autoadd new users to basic groups                                                                                 
# NOTE: Comment this out if you want the public to read and not edit
    $wgHooks['LocalUserCreated'][] = function ( User $user, $autocreated ) {
    $services = MediaWiki\MediaWikiServices::getInstance();
    $userGroupManager = $services->getUserGroupManager();
    $userGroupManager->addUserToGroup( $user, 'editor' );
    $userGroupManager->addUserToGroup( $user, 'reviewer' );
};       

# Post-initialization settings
# Additional configurations will be appended below

# ============================================
# SMTP Email Configuration
# ============================================

# Email configuration
$wgPasswordSender = '{{SMTP_USER}}';
$wgEmergencyContact = '{{SMTP_USER}}';
$wgNoReplyAddress = '{{SMTP_USER}}';

# SMTP configuration
$wgSMTP = [
    'host'     => '{{SMTP_HOST}}',
    'IDHost'   => '{{WIKI_HOST}}',
    'port'     => {{SMTP_PORT}},
    'auth'     => true,
    'username' => '{{SMTP_USER}}',
    'password' => '{{SMTP_PASS}}'
];

# ============================================
# OAuth Extensions Loading
# ============================================
# is_dir() checks safely handle task containers where extensions may not exist,
# and allow update.php to create required DB tables during initialization.

$pluggableAuthPath = '/app/bluespice/w/extensions/PluggableAuth';
$openIDConnectPath = '/app/bluespice/w/extensions/OpenIDConnect';

if ( is_dir( $pluggableAuthPath ) ) {
    wfLoadExtension( 'PluggableAuth' );
}

if ( is_dir( $openIDConnectPath ) ) {
    wfLoadExtension( 'OpenIDConnect' );
}

# ============================================
# Google OAuth Configuration
# ============================================
# Provider credentials are configured via BlueSpice ConfigManager UI
# (stored in bs_settings3 DB table as DistributionConnectorPluggableAuthConfig).
# Do not set $wgPluggableAuth_Config here - it conflicts with the DB config.

if ( is_dir( $pluggableAuthPath ) ) {
    # Enable local login alongside SSO so admins can always log in
    $wgPluggableAuth_EnableLocalLogin = true;
    $wgPluggableAuth_EnableAutoLogin = false;

    # autocreateaccount must be true for PluggableAuth to link SSO sessions to local accounts
    $wgGroupPermissions['*']['autocreateaccount'] = true;
    # Prevent manual self-registration via Special:CreateAccount
    $wgGroupPermissions['*']['createaccount'] = false;

    $wgPluggableAuth_EnableLocalProperties = true;
    $wgPluggableAuth_EnableLocalUsers = true;

    # Match SSO logins to existing accounts by email address
    $wgOpenIDConnect_MigrateUsersByEmail = true;
    $wgOpenIDConnect_UseEmailNameAsUserName = false;
    $wgOpenIDConnect_UseRealNameAsUserName = false;
    $wgOpenIDConnect_ForceLogout = false;
}

