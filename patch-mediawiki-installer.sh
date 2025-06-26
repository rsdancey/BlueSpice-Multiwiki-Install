#!/bin/bash
# Patch MediaWiki installer to handle socket connections properly

echo "Patching MediaWiki installer for socket connection support..."

# Wait for containers to be ready
sleep 5

# First, sync the localhost password
./sync-localhost-password.sh

# Patch the installer script to support both TCP and socket connections
docker exec bluespice-wiki-wiki-web bash -c 'cat > /app/bin/run-installation.d/020-install-database << "PATCH_EOF"
#!/bin/bash

installdbuser=${DB_USER}
installdbpass=${DB_PASS}
lang=${WIKI_LANG:-en}

echo "Installing database with values:"
echo "dbserver: $DB_HOST"
echo "dbname: $DB_NAME"
echo "dbuser: $DB_USER"
echo "dbpass: ${DB_PASS:0:1}********${DB_PASS: -1}"
echo "installdbuser: $installdbuser"
echo "installdbpass: ${installdbpass:0:1}********${installdbpass: -1}"
echo "lang: $lang"
echo "admin user: $adminUserName"
echo "pass: ${adminPass:0:1}********${adminPass: -1}"
echo "wiki name: $WIKI_NAME"
echo ""

# Try socket connection first (localhost), fallback to TCP
echo "Attempting MediaWiki installation with socket connection..."

# Force socket connection by using localhost as DB host
php /app/bluespice/w/maintenance/install.php \
    --dbtype=mysql \
    --dbserver=localhost \
    --dbuser="$installdbuser" \
    --dbpass="$installdbpass" \
    --dbname="$DB_NAME" \
    --server="$WIKI_SERVER" \
    --scriptpath="/w" \
    --pass="$adminPass" \
    "$WIKI_NAME" \
    "$adminUserName"

INSTALL_RESULT=$?

if [ $INSTALL_RESULT -ne 0 ]; then
    echo "Socket connection failed, trying TCP connection..."
    
    # Fallback to TCP connection
    php /app/bluespice/w/maintenance/install.php \
        --dbtype=mysql \
        --dbserver="$DB_HOST" \
        --dbport="$DB_PORT" \
        --dbuser="$installdbuser" \
        --dbpass="$installdbpass" \
        --dbname="$DB_NAME" \
        --server="$WIKI_SERVER" \
        --scriptpath="/w" \
        --pass="$adminPass" \
        "$WIKI_NAME" \
        "$adminUserName"
    
    INSTALL_RESULT=$?
fi

if [ $INSTALL_RESULT -eq 0 ]; then
    echo "MediaWiki installation completed successfully"
else
    echo "MediaWiki installation failed with both socket and TCP connections"
    exit 1
fi
PATCH_EOF'

chmod +x /app/bin/run-installation.d/020-install-database

echo "MediaWiki installer patch applied successfully"
