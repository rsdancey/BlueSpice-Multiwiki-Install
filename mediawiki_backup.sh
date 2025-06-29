#!/bin/bash

# MediaWiki Comprehensive Backup Script
# This script creates a complete backup of a MediaWiki installation
# including database, files, images, and configuration

set -euo pipefail

# Configuration - MODIFY THESE VARIABLES FOR YOUR SETUP
MEDIAWIKI_PATH="/var/www/html/wiki"           # Path to MediaWiki installation
BACKUP_BASE_DIR="/backup/mediawiki"           # Base backup directory
DB_NAME="mediawiki"                           # Database name
DB_USER="wiki_user"                           # Database username
DB_PASSWORD=""                                # Database password (leave empty to prompt)
DB_HOST="localhost"                           # Database host
BACKUP_RETENTION_DAYS=30                      # How many days to keep backups
COMPRESS_BACKUPS=true                         # Set to false to disable compression
EXCLUDE_CACHE=true                            # Set to false to include cache directories

# Derived variables
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="${BACKUP_BASE_DIR}/${TIMESTAMP}"
LOG_FILE="${BACKUP_DIR}/backup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root or with sudo
check_permissions() {
    if [[ $EUID -ne 0 ]]; then
        warning "Script not running as root. Some files may not be accessible."
        warning "Consider running with sudo for complete backup."
    fi
}

# Create backup directory
create_backup_dir() {
    log "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
}

# Get database password if not provided
get_db_password() {
    if [[ -z "$DB_PASSWORD" ]]; then
        echo -n "Enter database password for user $DB_USER: "
        read -s DB_PASSWORD
        echo
    fi
}

# Backup database
backup_database() {
    log "Starting database backup..."
    
    local db_backup_file="${BACKUP_DIR}/database_${DB_NAME}_${TIMESTAMP}.sql"
    
    # Create database dump with extended options for MediaWiki
    if mysqldump \
        --host="$DB_HOST" \
        --user="$DB_USER" \
        --password="$DB_PASSWORD" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --add-drop-table \
        --add-locks \
        --extended-insert \
        --quick \
        --lock-tables=false \
        "$DB_NAME" > "$db_backup_file" 2>>"$LOG_FILE"; then
        
        success "Database backup completed: $(basename "$db_backup_file")"
        
        # Compress database backup if enabled
        if [[ "$COMPRESS_BACKUPS" == "true" ]]; then
            log "Compressing database backup..."
            gzip "$db_backup_file"
            success "Database backup compressed: $(basename "$db_backup_file").gz"
        fi
    else
        error "Database backup failed!"
    fi
}

# Backup MediaWiki files
backup_files() {
    log "Starting file system backup..."
    
    local files_backup_dir="${BACKUP_DIR}/files"
    mkdir -p "$files_backup_dir"
    
    # Prepare exclusion list
    local exclude_args=""
    if [[ "$EXCLUDE_CACHE" == "true" ]]; then
        exclude_args="--exclude=cache --exclude=*/cache/* --exclude=temp --exclude=*/temp/*"
    fi
    
    # Additional common exclusions
    exclude_args="$exclude_args --exclude=*.log --exclude=*.tmp --exclude=.git --exclude=.svn"
    
    # Copy MediaWiki installation
    log "Backing up MediaWiki installation directory..."
    if rsync -avh $exclude_args "$MEDIAWIKI_PATH/" "$files_backup_dir/" 2>>"$LOG_FILE"; then
        success "MediaWiki files backup completed"
    else
        error "MediaWiki files backup failed!"
    fi
    
    # Create tarball if compression is enabled
    if [[ "$COMPRESS_BACKUPS" == "true" ]]; then
        log "Creating compressed archive of files..."
        local tar_file="${BACKUP_DIR}/mediawiki_files_${TIMESTAMP}.tar.gz"
        
        if tar -czf "$tar_file" -C "$files_backup_dir" . 2>>"$LOG_FILE"; then
            success "Files compressed: $(basename "$tar_file")"
            # Remove uncompressed files to save space
            rm -rf "$files_backup_dir"
        else
            warning "File compression failed, keeping uncompressed backup"
        fi
    fi
}

# Backup specific MediaWiki components
backup_mediawiki_specifics() {
    log "Backing up MediaWiki-specific components..."
    
    local specifics_dir="${BACKUP_DIR}/mediawiki_specifics"
    mkdir -p "$specifics_dir"
    
    # Backup LocalSettings.php (critical configuration file)
    if [[ -f "${MEDIAWIKI_PATH}/LocalSettings.php" ]]; then
        cp "${MEDIAWIKI_PATH}/LocalSettings.php" "$specifics_dir/"
        success "LocalSettings.php backed up"
    else
        warning "LocalSettings.php not found at expected location"
    fi
    
    # Backup .htaccess if present
    if [[ -f "${MEDIAWIKI_PATH}/.htaccess" ]]; then
        cp "${MEDIAWIKI_PATH}/.htaccess" "$specifics_dir/"
        success ".htaccess backed up"
    fi
    
    # Backup composer.local.json if present
    if [[ -f "${MEDIAWIKI_PATH}/composer.local.json" ]]; then
        cp "${MEDIAWIKI_PATH}/composer.local.json" "$specifics_dir/"
        success "composer.local.json backed up"
    fi
    
    # Create list of installed extensions
    if [[ -d "${MEDIAWIKI_PATH}/extensions" ]]; then
        ls -la "${MEDIAWIKI_PATH}/extensions" > "$specifics_dir/installed_extensions.txt"
        success "Extension list created"
    fi
    
    # Create list of installed skins
    if [[ -d "${MEDIAWIKI_PATH}/skins" ]]; then
        ls -la "${MEDIAWIKI_PATH}/skins" > "$specifics_dir/installed_skins.txt"
        success "Skin list created"
    fi
}

# Create backup manifest
create_manifest() {
    log "Creating backup manifest..."
    
    local manifest_file="${BACKUP_DIR}/MANIFEST.txt"
    
    cat > "$manifest_file" << EOF
MediaWiki Backup Manifest
========================
Backup Date: $(date '+%Y-%m-%d %H:%M:%S')
Backup Directory: $BACKUP_DIR
MediaWiki Path: $MEDIAWIKI_PATH
Database: $DB_NAME
Hostname: $(hostname)
Script Version: 1.0

Backup Contents:
EOF
    
    # List all files in backup
    find "$BACKUP_DIR" -type f -exec ls -lh {} \; >> "$manifest_file"
    
    # Add disk usage summary
    echo "" >> "$manifest_file"
    echo "Backup Size Summary:" >> "$manifest_file"
    du -sh "$BACKUP_DIR" >> "$manifest_file"
    
    success "Backup manifest created"
}

# Verify backup integrity
verify_backup() {
    log "Verifying backup integrity..."
    
    local verification_file="${BACKUP_DIR}/VERIFICATION.txt"
    
    # Create checksums for all backup files
    find "$BACKUP_DIR" -type f -name "*.sql*" -o -name "*.tar.gz" | while read -r file; do
        sha256sum "$file" >> "$verification_file"
    done
    
    # Test database backup if not compressed
    if [[ -f "${BACKUP_DIR}/database_${DB_NAME}_${TIMESTAMP}.sql" ]]; then
        if head -10 "${BACKUP_DIR}/database_${DB_NAME}_${TIMESTAMP}.sql" | grep -q "MySQL dump"; then
            success "Database backup file appears valid"
        else
            warning "Database backup file may be corrupted"
        fi
    fi
    
    success "Backup verification completed"
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."
    
    local deleted_count=0
    
    # Find and delete old backup directories
    find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "20*" -mtime +$BACKUP_RETENTION_DAYS | while read -r old_backup; do
        log "Removing old backup: $(basename "$old_backup")"
        rm -rf "$old_backup"
        ((deleted_count++))
    done
    
    if [[ $deleted_count -gt 0 ]]; then
        success "Cleaned up $deleted_count old backup(s)"
    else
        log "No old backups to clean up"
    fi
}

# Send notification (optional - implement as needed)
send_notification() {
    local status=$1
    local message=$2
    
    # Placeholder for notification system
    # You can implement email, Slack, or other notification methods here
    log "Notification: $status - $message"
}

# Main backup function
main() {
    log "Starting MediaWiki backup process..."
    log "Backup timestamp: $TIMESTAMP"
    
    # Pre-flight checks
    check_permissions
    
    # Verify MediaWiki installation exists
    if [[ ! -d "$MEDIAWIKI_PATH" ]]; then
        error "MediaWiki installation not found at: $MEDIAWIKI_PATH"
    fi
    
    # Create backup directory
    create_backup_dir
    
    # Get database credentials
    get_db_password
    
    # Perform backup steps
    backup_database
    backup_files
    backup_mediawiki_specifics
    create_manifest
    verify_backup
    
    # Cleanup
    cleanup_old_backups
    
    # Calculate total backup size
    local total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    
    success "MediaWiki backup completed successfully!"
    success "Backup location: $BACKUP_DIR"
    success "Total backup size: $total_size"
    
    # Send success notification
    send_notification "SUCCESS" "MediaWiki backup completed. Size: $total_size"
}

# Error handling
trap 'error "Backup script failed at line $LINENO"' ERR

# Run main function
main "$@"
