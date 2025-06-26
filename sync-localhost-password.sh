#!/bin/bash
# Sync wiki_user@localhost password with network password

echo "Synchronizing localhost database user password..."

# Wait for database to be ready
sleep 2

# Get the current DB_PASS from the wiki container environment
DB_PASS=$(docker exec bluespice-wiki-wiki-web printenv DB_PASS)

if [ -z "$DB_PASS" ]; then
    echo "Error: Could not retrieve DB_PASS from wiki container"
    exit 1
fi

echo "Updating wiki_user@localhost password to match network password..."

# Update the localhost user password to match the network user
docker exec bluespice-database mysql -u root -pRF3EKMqm6hsTkoCm -e "
SET PASSWORD FOR 'wiki_user'@'localhost' = PASSWORD('$DB_PASS');
FLUSH PRIVILEGES;
"

if [ $? -eq 0 ]; then
    echo "✓ Successfully synchronized localhost password"
else
    echo "✗ Failed to synchronize localhost password"
    exit 1
fi
