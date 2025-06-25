#!/bin/bash

# Script to wait for database initialization and verify password setup
DB_ROOT_PASS="${1:-}"
MAX_ATTEMPTS=30
ATTEMPT=1

echo "Waiting for database to be ready with password authentication..."

while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
    echo "Attempt $ATTEMPT of $MAX_ATTEMPTS..."
    
    if [ -n "$DB_ROOT_PASS" ]; then
        # Try with password
        if docker exec bluespice-database mariadb -u root -p"$DB_ROOT_PASS" -e "SELECT 1;" >/dev/null 2>&1; then
            echo "✓ Database is ready with password authentication!"
            exit 0
        fi
    else
        # Try without password for backward compatibility
        if docker exec bluespice-database mariadb -u root -e "SELECT 1;" >/dev/null 2>&1; then
            echo "✓ Database is ready (no password)!"
            exit 0
        fi
    fi
    
    sleep 5
    ATTEMPT=$((ATTEMPT + 1))
done

echo "✗ Database failed to initialize within expected time!"
exit 1
