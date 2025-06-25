#!/bin/bash

# Script to set the database root password after container initialization
DB_ROOT_PASS="${1:-}"
CONTAINER_NAME="${2:-bluespice-database}"

if [ -z "$DB_ROOT_PASS" ]; then
    echo "Usage: $0 <password> [container_name]"
    exit 1
fi

echo "Setting root password for MariaDB in container $CONTAINER_NAME..."

# First, try to set the password using passwordless access
if docker exec "$CONTAINER_NAME" mariadb -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$DB_ROOT_PASS'); FLUSH PRIVILEGES;" 2>/dev/null; then
    echo "✓ Root password set successfully"
    
    # Verify the password works
    if docker exec "$CONTAINER_NAME" mariadb -u root -p"$DB_ROOT_PASS" -e "SELECT 1;" >/dev/null 2>&1; then
        echo "✓ Password verification successful"
    else
        echo "✗ Password verification failed"
        exit 1
    fi
else
    echo "✗ Failed to set root password"
    exit 1
fi
