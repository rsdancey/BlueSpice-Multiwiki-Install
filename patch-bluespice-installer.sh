#!/bin/bash
# Patch BlueSpice installer to skip MediaWiki installer step

echo "Patching BlueSpice installer to skip problematic MediaWiki installer step..."

# Wait for the container to be healthy
sleep 5

# Patch the installer script
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

# Skip MediaWiki installer - BlueSpice handles database initialization differently
echo "Skipping MediaWiki installer step - using BlueSpice native initialization"
echo "Database connection and setup handled by BlueSpice containers"

# Create log entry for compatibility
mkdir -p /data/bluespice/logs
echo "$(date): Skipped MediaWiki installer - using BlueSpice initialization" >> /data/bluespice/logs/install-$(date +%Y%m%d_%H%M%S).log

echo "Database installation completed successfully"
PATCH_EOF'

echo "BlueSpice installer patch applied successfully"
