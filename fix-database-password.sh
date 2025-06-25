#!/bin/bash

# Fix database root password to match configured password
# This script ensures the database health check works correctly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared environment to get DB_ROOT_PASS
if [[ -f "${SCRIPT_DIR}/shared/.shared.env" ]]; then
    source "${SCRIPT_DIR}/shared/.shared.env"
else
    echo "Error: Shared environment file not found"
    exit 1
fi

echo "Fixing database root password..."

# Check if database container is running
if ! docker ps --format "{{.Names}}" | grep -q "^bluespice-database$"; then
    echo "Error: Database container is not running"
    exit 1
fi

# Test if password already works
if docker exec bluespice-database mariadb -u root -p"${DB_ROOT_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then
    echo "✓ Database password is already correct"
    exit 0
fi

# Try to connect without password first
if docker exec bluespice-database mariadb -u root -e "SELECT 1;" >/dev/null 2>&1; then
    echo "Setting root password..."
    docker exec bluespice-database mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';"
    docker exec bluespice-database mariadb -u root -p"${DB_ROOT_PASS}" -e "FLUSH PRIVILEGES;"
    echo "✓ Root password set successfully"
else
    echo "Error: Cannot connect to database"
    exit 1
fi

# Verify the fix worked
if docker exec bluespice-database mariadb -u root -p"${DB_ROOT_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then
    echo "✓ Database password fix verified"
else
    echo "Error: Password fix failed"
    exit 1
fi
