#!/bin/bash
# Fix MediaWiki installer to use DB_ROOT credentials

echo "Modifying MediaWiki installer to use DB_ROOT credentials..."

# Wait for container to be available
sleep 2

# Patch the installer to use DB_ROOT_USER and DB_ROOT_PASS
docker exec bluespice-wiki-wiki-web sed -i 's/installdbuser=${DB_USER}/installdbuser=${DB_ROOT_USER}/' /app/bin/run-installation.d/020-install-database
docker exec bluespice-wiki-wiki-web sed -i 's/installdbpass=${DB_PASS}/installdbpass=${DB_ROOT_PASS}/' /app/bin/run-installation.d/020-install-database

# Also add the missing --dbport parameter
docker exec bluespice-wiki-wiki-web sed -i '/--dbserver=/a\\t--dbport=${DB_PORT:-3306} \\' /app/bin/run-installation.d/020-install-database

echo "MediaWiki installer modified to use DB_ROOT credentials"
