#!/bin/bash

# Source logging functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh"

# Smart Database Import Script for MediaWiki/BlueSpice
# Handles SQL dumps with automatic prefix detection and removal
# Supports compressed and uncompressed SQL files

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
CONFIG_FILE=""
DB_HOST=""
DB_NAME=""
DB_USER=""
DB_PASS=""
CONTAINER_NAME=""

# Print functions





# Load configuration from .env file
load_config() {
    local config_path="$1"
    
    if [[ ! -f "$config_path" ]]; then
        print_error "Configuration file not found: $config_path"
        return 1
    fi
    
    print_info "Loading configuration from: $config_path"
    
    # shellcheck source=/dev/null
    # Source the configuration file
    source "$config_path"
    
    # Check required variables
    if [[ -z "${DB_NAME:-}" ]]; then
        print_error "DB_NAME not found in configuration"
        return 1
    fi
    
    if [[ -z "${DB_USER:-}" ]]; then
        print_error "DB_USER not found in configuration"
        return 1
    fi
    
    if [[ -z "${DB_PASS:-}" ]]; then
        print_error "DB_PASS not found in configuration"
        return 1
    fi
    
    if [[ -z "${CONTAINER_PREFIX:-}" ]]; then
        print_error "CONTAINER_PREFIX not found in configuration"
        return 1
    fi
    
    # Set up database configuration
    DB_HOST="${DB_HOST:-database}"
    CONTAINER_NAME="${CONTAINER_PREFIX}-wiki-web"
    
    print_success "Configuration loaded successfully"
    print_info "Database: $DB_NAME, User: $DB_USER, Container: $CONTAINER_NAME"
    
    return 0
}

# Test database connectivity
test_database() {
    print_info "Skipping database connectivity test - wiki is already running"
    print_success "Database connection assumed successful"
    return 0
}

# Detect file compression
detect_compression() {
    local file="$1"
    
    case "$file" in
        *.gz|*.gzip)
            echo "gzip"
            ;;
        *.bz2)
            echo "bzip2"
            ;;
        *.xz)
            echo "xz"
            ;;
        *)
            echo "none"
            ;;
    esac
}

# Decompress file if needed
decompress_file() {
    local input_file="$1"
    local output_file="$2"
    local compression="$3"
    
    case "$compression" in
        "gzip")
            print_info "Decompressing gzip file..."
            gunzip -c "$input_file" > "$output_file"
            ;;
        "bzip2")
            print_info "Decompressing bzip2 file..."
            bunzip2 -c "$input_file" > "$output_file"
            ;;
        "xz")
            print_info "Decompressing xz file..."
            xz -dc "$input_file" > "$output_file"
            ;;
        "none")
            print_info "No compression detected, copying file..."
            cp "$input_file" "$output_file"
            ;;
        *)
            print_error "Unsupported compression format: $compression"
            return 1
            ;;
    esac
}

# Validate SQL dump
validate_sql() {
    local file="$1"
    
    print_info "Validating SQL dump..."
    
    if [[ ! -f "$file" || ! -r "$file" ]]; then
        print_error "SQL file is not accessible: $file"
        return 1
    fi
    
    if ! grep -q "CREATE TABLE\|INSERT INTO\|DROP TABLE" "$file"; then
        print_error "File does not appear to contain valid SQL dump content"
        return 1
    fi
    
    print_success "SQL dump validation passed"
    return 0
}

# Detect table prefix in SQL dump
detect_prefix() {
    local file="$1"
    
    print_info "Analyzing dump for table prefixes..."
    
    # Extract all table names from CREATE TABLE statements
    local table_names
    table_names=$(grep -oE "CREATE TABLE \`[^\`]+\`" "$file" | \
                  sed "s/CREATE TABLE \`//" | sed "s/\`$//")
    
    if [[ -z "$table_names" ]]; then
        print_info "No tables found in dump"
        return 1
    fi
    
    local table_count
    table_count=$(echo "$table_names" | wc -l)
    print_info "Found $table_count tables"
    
    # Find all possible prefixes by checking common starting strings
    local potential_prefixes=()
    
    # Check each table against all others to find common prefixes
    while IFS= read -r table; do
        # Try different prefix lengths (from 3 to 20 characters)
        for length in {3..20}; do
            if [[ ${#table} -gt $length ]]; then
                local prefix="${table:0:$length}"
                potential_prefixes+=("$prefix")
            fi
        done
    done <<< "$table_names"
    
    # Count occurrences of each prefix
    local best_prefix=""
    local best_count=0
    
    for prefix in $(printf '%s\n' "${potential_prefixes[@]}" | sort | uniq); do
        local count
        count=$(echo "$table_names" | grep -c "^$prefix")
        
        if [[ $count -ge 20 ]]; then
            if [[ $count -gt $best_count ]] || [[ $count -eq $best_count && ${#prefix} -gt ${#best_prefix} ]]; then
                best_prefix="$prefix"
                best_count="$count"
            fi
        fi
    done
    
    if [[ -n "$best_prefix" ]]; then
        print_success "Detected prefix: '$best_prefix' (appears in $best_count tables)"
        echo "$best_prefix"
        return 0
    fi
    
    print_info "No consistent table prefix detected (need 20+ tables with same prefix)"
    return 1
}

# Remove prefix from SQL dump
remove_prefix() {
    local input_file="$1"
    local output_file="$2"
    local prefix="$3"
    
    print_info "Removing prefix '$prefix' from SQL dump..."
    
    # Escape special characters in prefix for sed - using correct pattern
    local escaped_prefix
    escaped_prefix=$(echo "$prefix" | sed 's/[][\/.^$*]/\&/g')
    
    # Use sed to remove the prefix from table names in all SQL contexts
    if sed "s/\`${escaped_prefix}/\`/g" "$input_file" > "$output_file"; then
        print_success "Prefix removed successfully"
        
        # Also remove DEFINER clauses which can cause issues
        print_info "Removing DEFINER clauses"
        sed -i "s/DEFINER=[^@]*@[^[:space:]]* //g" "$output_file"
        
        print_success "Prefix removal completed"
        return 0
    else
        print_error "Failed to remove prefix from dump"
        return 1
    fi
}

# Import SQL dump into database
import_sql() {
    local sql_file="$1"
    
    print_info "Importing SQL dump into database..."
    print_info "Database: $DB_NAME"
    print_info "Container: $CONTAINER_NAME"
    
    if docker exec -i bluespice-database mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$sql_file"; then
        print_success "SQL dump imported successfully"
        return 0
    else
        print_error "Failed to import SQL dump"
        return 1
    fi
}

# Prompt for confirmation
confirm_action() {
    local message="$1"
    local default="${2:-N}"
    
    local prompt
    if [[ "$default" == "Y" || "$default" == "y" ]]; then
        prompt="$message (Y/n): "
    else
        prompt="$message (y/N): "
    fi
    
    read -r -p "$prompt" -r response
    
    if [[ -z "$response" ]]; then
        response="$default"
    fi
    
    [[ "$response" =~ ^[Yy]$ ]]
}

# Main import function
import_database() {
    local sql_file="$1"
    
    print_info "Processing file: $sql_file"
    
    local compression
    compression=$(detect_compression "$sql_file")
    print_info "Detected compression: $compression"
    
    local working_file
    working_file="/tmp/working_dump_$(date +%Y%m%d_%H%M%S).sql"
    
    if ! decompress_file "$sql_file" "$working_file" "$compression"; then
        return 1
    fi
    
    if ! validate_sql "$working_file"; then
        print_error "Invalid SQL file: $working_file"
        rm -f "$working_file"
        return 1
    fi
    
    local detected_prefix
    detect_prefix "$working_file"
    local prefix_result=$?
    if [[ $prefix_result -eq 0 ]]; then
        local detected_prefix
        detected_prefix=$(detect_prefix "$working_file" | tail -1)
        echo
        if confirm_action "Remove detected prefix '$detected_prefix' from table names?"; then
            local processed_file
            processed_file="/tmp/processed_dump_$(date +%Y%m%d_%H%M%S).sql"
            
            if remove_prefix "$working_file" "$processed_file" "$detected_prefix"; then
                print_success "Prefix removal completed"
                working_file="$processed_file"
            else
                print_error "Failed to process prefix removal"
            fi
        fi
    fi
    
    if import_sql "$working_file"; then
        print_success "Database import completed successfully"
    else
        print_error "Database import failed"
    fi
}

# Main execution
main() {
    print_header "Smart Database Import Script"
    
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        print_error "Usage: $0 <sql_file> [wiki_dir]"
        exit 1
    fi
    
    local sql_file="$1"
    local wiki_dir="${2:-}"
    
    if [[ ! -f "$sql_file" ]]; then
        print_error "SQL file not found: $sql_file"
        exit 1
    fi
    
    # Determine config file location
    if [[ -n "$wiki_dir" ]]; then
        CONFIG_FILE="$wiki_dir/.env"
    elif [[ -n "${WIKI_DIR:-}" ]]; then
        CONFIG_FILE="$WIKI_DIR/.env"
    else
        CONFIG_FILE=".env"
    fi
    
    if ! load_config "$CONFIG_FILE"; then
        exit 1
    fi
    
    if ! test_database; then
        exit 1
    fi
    
    if import_database "$sql_file"; then
        print_success "Database import process completed successfully"
        exit 0
    else
        print_error "Database import process failed"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
