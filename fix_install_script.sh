#!/bin/bash

# Function to fix the MediaWiki install script to use proper dbport parameter
fix_mediawiki_install_script() {
    local container="$1"
    
    echo "Fixing MediaWiki install script to use proper database port handling..."
    
    docker exec "$container" bash -c 'cat > /app/bin/run-installation.d/020-install-database << "INSTALL_EOF"
#!/bin/bash

installdbuser=${DB_USER}
installdbpass=${DB_PASS}
lang=${WIKI_LANG:-en}
dbport=${DB_PORT:-3306}

echo "Installing database with values:"
echo "dbserver: $DB_HOST"
echo "dbport: $dbport"
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

# If there is for whatever reason a LocalSettings.php file in the appDir, we need to remove it
# before we run the installation script. This is because the installation script will
# not run if there is a LocalSettings.php file present.
if [ -f $appDir/LocalSettings.php ]; then
	mv $appDir/LocalSettings.php $appDir/LocalSettings.$timestamp.php
fi

php $appDir/maintenance/install.php \
	--dbserver=$DB_HOST \
	--dbport=$dbport \
	--dbname=$DB_NAME \
	--installdbuser=$installdbuser \
	--installdbpass=$installdbpass \
	--dbuser=$DB_USER \
	--dbpass=$DB_PASS \
	--pass=$adminPass \
	--lang=$lang \
	--scriptpath=/w \
	"$WIKI_NAME" \
	"$adminUserName" \
	| tee -a /data/bluespice/logs/install-$timestamp.log

# We dont need the default LocalSettings.php file, as we have one hardwired in this container
if [ -f $appDir/LocalSettings.php ]; then
	rm $appDir/LocalSettings.php
fi
INSTALL_EOF'
    
    docker exec "$container" chmod +x /app/bin/run-installation.d/020-install-database
    
    echo "✓ MediaWiki install script fixed"
}

# Usage: fix_install_script.sh <container_name>
if [[ $# -eq 1 ]]; then
    fix_mediawiki_install_script "$1"
else
    echo "Usage: $0 <container_name>"
    exit 1
fi
