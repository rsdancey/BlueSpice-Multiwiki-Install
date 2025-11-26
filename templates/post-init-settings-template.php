<?php
# ============================================
# BlueSpice Wiki Post-Init Settings Template
# ============================================
# This template should be copied to /bluespice/<wiki-name>/post-init-settings.php
# when creating a new wiki instance.
#
# IMPORTANT: Auth extension loading is guarded to prevent task runner crashes
# when PluggableAuth/OpenIDConnect are not present in task containers.

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
# IMPORTANT: These guards prevent fatal errors in task containers
# where PluggableAuth/OpenIDConnect extensions may not exist.
# DO NOT REMOVE THESE GUARDS!

# Load auth extensions only in web context and if they exist
$loadAuth = ( PHP_SAPI !== 'cli' );
$pluggableAuthPath = '/app/bluespice/w/extensions/PluggableAuth';
$openIDConnectPath = '/app/bluespice/w/extensions/OpenIDConnect';

if ( $loadAuth && is_dir( $pluggableAuthPath ) ) {
    wfLoadExtension( 'PluggableAuth' );
}

if ( $loadAuth && is_dir( $openIDConnectPath ) ) {
    wfLoadExtension( 'OpenIDConnect' );
}

# ============================================
# Google OAuth Configuration
# ============================================

# Google OAuth configuration - only if PluggableAuth is loaded
if ( $loadAuth && is_dir( $pluggableAuthPath ) ) {
    $wgPluggableAuth_Config["Google"] = [
        "plugin" => "OpenIDConnect",
        "data" => [
            "providerURL" => "https://accounts.google.com/.well-known/openid-configuration",
            "clientID" => "{{OAUTH_CLIENT_ID}}",
            "clientSecret" => "{{OAUTH_CLIENT_SECRET}}",
            "scope" => ["openid", "email", "profile"],
            "email_key" => "email",
            "use_email_mapping" => true
        ],
        "buttonLabelMessage" => "Login with Google"
    ];

    # Enable local login alongside PluggableAuth
    $wgPluggableAuth_EnableLocalLogin = true;
    $wgPluggableAuth_EnableAutoLogin = false;

    # OAuth email matching and account creation settings
    # These settings restrict the ability of a user to self-create an account by authenticating via google
    $wgOpenIDConnect_MigrateUsers = false;  
    $wgGroupPermissions['*']['autocreateaccount'] = false;
    $wgGroupPermissions['*']['createaccount'] = false;

    # Essential settings to prevent pluggableauth-fatal-error
    $wgPluggableAuth_EnableLocalProperties = true;
    $wgPluggableAuth_EnableLocalUsers = true;

    # OpenIDConnect specific settings for proper user mapping
    $wgOpenIDConnect_UseEmailNameAsUserName = false;
    $wgOpenIDConnect_MigrateUsersByEmail = true;
    $wgOpenIDConnect_UseRealNameAsUserName = false;
    $wgOpenIDConnect_ForceLogout = false;
}

