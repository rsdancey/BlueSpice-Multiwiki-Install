#!/bin/bash

# Fix MediaWiki Image Database Import
# This script clears existing image records and re-imports them properly

WIKI_NAME="$1"
if [[ -z "$WIKI_NAME" ]]; then
    echo "Usage: $0 <wiki_name>"
    exit 1
fi

CONTAINER_NAME="bluespice-$WIKI_NAME-wiki-web"

echo "🔧 Fixing MediaWiki image database for wiki: $WIKI_NAME"

# Check if container is running
if ! docker ps --format "table {{.Names}}" | grep -q "^$CONTAINER_NAME$"; then
    echo "❌ Container $CONTAINER_NAME is not running"
    exit 1
fi

echo "📊 Current image count in database:"
docker exec "$CONTAINER_NAME" php -r "
require_once '/app/bluespice/w/maintenance/Maintenance.php';
\$db = wfGetDB( DB_REPLICA );
\$count = \$db->selectField('image', 'COUNT(*)', '', __METHOD__);
echo \"Images in database: \$count\n\";
"

echo "🗑️  Clearing existing image records from database..."
docker exec "$CONTAINER_NAME" php -r "
require_once '/app/bluespice/w/maintenance/Maintenance.php';
\$db = wfGetDB( DB_MASTER );
\$db->delete('image', '*', __METHOD__);
\$db->delete('oldimage', '*', __METHOD__);
\$db->delete('filearchive', '*', __METHOD__);
echo \"Database image tables cleared\n\";
"

echo "📁 Counting files in images directory:"
docker exec "$CONTAINER_NAME" find /app/bluespice/w/images/ -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.pdf" -o -name "*.svg" \) | wc -l

echo "🔄 Re-importing images into database (without overwrite flag)..."
docker exec --user bluespice "$CONTAINER_NAME" php /app/bluespice/w/maintenance/importImages.php --search-recursively /app/bluespice/w/images/

echo "📊 Final image count in database:"
docker exec "$CONTAINER_NAME" php -r "
require_once '/app/bluespice/w/maintenance/Maintenance.php';
\$db = wfGetDB( DB_REPLICA );
\$count = \$db->selectField('image', 'COUNT(*)', '', __METHOD__);
echo \"Images in database: \$count\n\";
"

echo "✅ Database import fix completed!"
