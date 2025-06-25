#!/bin/bash
# Simple database health check script

# Try with password first if it exists
if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
    mariadb -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" 2>/dev/null
else
    # Fall back to passwordless connection
    mariadb -u root -e "SELECT 1;" 2>/dev/null
fi
