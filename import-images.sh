#!/bin/bash

# Source logging functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logging.sh"

# Images Import Script for BlueSpice Wiki (Version 2)
# Fixes ownership issues by handling permissions on host side

# Color codes for output
# shellcheck disable=SC2034  # Colors may be used by sourced logging functions
RED='\033[0;31m'
# shellcheck disable=SC2034
GREEN='\033[0;32m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
BLUE='\033[0;34m'
# shellcheck disable=SC2034
NC='\033[0m' # No Color

# Function to print colored messages




# Function to display usage
usage() {
    echo "Usage: $0 [--wiki-name=WIKI_NAME] [--images-archive=PATH]"
    echo ""
    echo "Options:"
    echo "  --wiki-name=NAME     Specify the wiki name"
    echo "  --images-archive=PATH  Specify the path to images zip archive"
    echo "  --help               Show this help message"
    echo ""
    echo "Interactive mode will prompt for missing parameters."
}

# Parse command line arguments
WIKI_NAME=""
IMAGES_ARCHIVE=""

for arg in "$@"; do
    case $arg in
        --wiki-name=*)
            WIKI_NAME="${arg#*=}"
            shift
            ;;
        --images-archive=*)
            IMAGES_ARCHIVE="${arg#*=}"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown argument: $arg"
            usage
            exit 1
            ;;
    esac
done

# Function to validate wiki exists
validate_wiki() {
    local wiki_name="$1"
    local wiki_dir="/core/wikis/$wiki_name"
    
    if [[ ! -d "$wiki_dir" ]]; then
        log_error "Wiki directory not found: $wiki_dir"
        return 1
    fi
    
    if [[ ! -f "$wiki_dir/.env" ]]; then
        log_error "Wiki configuration not found: $wiki_dir/.env"
        return 1
    fi
    
    # Check if wiki container is running
    local container_name
    container_name=$(get_container_name "$wiki_name")
    if ! docker ps --format "table {{.Names}}" | grep -q "^$container_name$"; then
        log_error "Wiki container not running: $container_name"
        log_info "Please start the wiki first using:"
        log_info "./bluespice-deploy-wiki --wiki-name=$wiki_name"
        return 1
    fi
    
    return 0
}

# Function to validate images archive
validate_images_archive() {
    local archive_path="$1"
    
    if [[ ! -f "$archive_path" ]]; then
        log_error "Images archive not found: $archive_path"
        return 1
    fi
    
    # Check if it's a zip file
    if ! file "$archive_path" | grep -q "Zip archive"; then
        log_error "File is not a ZIP archive: $archive_path"
        return 1
    fi
    
    # Check if zip contains images directory
    if ! unzip -l "$archive_path" | grep -q "images/"; then
        log_warn "Archive does not appear to contain an 'images/' directory"
        log_info "Continuing anyway..."
    fi
    
    return 0
}

# Function to backup current images
backup_current_images() {
    local wiki_name="$1"
    local container_name
    container_name=$(get_container_name "$wiki_name")
    local backup_dir
    backup_dir="/tmp/images_backup_$(date +%Y%m%d_%H%M%S)"
    
    log_info "Creating backup of current images directory..."
    
    # Create backup directory on host
    mkdir -p "$backup_dir"
    
    # Copy current images from container to backup
    if docker cp "$container_name:/app/bluespice/w/images/." "$backup_dir/"; then
        log_info "Current images backed up to: $backup_dir"
        echo "$backup_dir"
        return 0
    else
        log_error "Failed to backup current images"
        return 1
    fi
}

# Function to get the correct UID for bluespice user
get_bluespice_uid() {
    local container_name="$1"
    # Get the UID of the bluespice user inside the container
    docker exec "$container_name" id -u bluespice 2>/dev/null || echo "1002"
}

# Function to import images with proper ownership
import_images() {
    local wiki_name="$1"
    local archive_path="$2"
    local container_name
    container_name=$(get_container_name "$wiki_name")
    local temp_dir
    temp_dir="/tmp/images_import_$(date +%Y%m%d_%H%M%S)"
    
    log_info "Importing images from archive..."
    
    # Get the bluespice UID
    local bluespice_uid
    bluespice_uid=$(get_bluespice_uid "$container_name")
    log_info "BlueSpice user UID: $bluespice_uid"
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    
    # Extract archive
    log_info "Extracting images archive..."
    if ! unzip -q "$archive_path" -d "$temp_dir"; then
        log_error "Failed to extract images archive"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Find images directory in extracted content
    local images_source=""
    if [[ -d "$temp_dir/images" ]]; then
        images_source="$temp_dir/images"
    elif [[ -d "$temp_dir" ]] && ls "$temp_dir"/*.png "$temp_dir"/*.jpg "$temp_dir"/*.gif 2>/dev/null; then
        # Archive contains image files directly
        images_source="$temp_dir"
    else
        # Look for images directory in subdirectories
        images_source=$(find "$temp_dir" -type d -name "images" | head -1)
        if [[ -z "$images_source" ]]; then
            log_error "Could not find images directory in archive"
            rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    log_info "Found images source: $images_source"
    
    # Fix ownership of extracted files on host BEFORE copying to container
    log_info "Fixing ownership of extracted files..."
    if command -v chown >/dev/null 2>&1; then
        # Try to change ownership to match bluespice user
        # Note: This might require sudo depending on current user permissions
        if ! chown -R "$bluespice_uid:$bluespice_uid" "$images_source" 2>/dev/null; then
            log_warn "Could not change ownership as current user, trying with sudo..."
            if command -v sudo >/dev/null 2>&1; then
                if sudo chown -R "$bluespice_uid:$bluespice_uid" "$images_source" 2>/dev/null; then
                    log_info "Ownership fixed using sudo"
                else
                    log_warn "Could not fix ownership with sudo, continuing anyway..."
                fi
            else
                log_warn "sudo not available, continuing with original ownership..."
            fi
        else
            log_info "Ownership fixed successfully"
        fi
    fi
    
    # Clear current images directory in container
    log_info "Clearing current images directory..."
    if ! docker exec "$container_name" sh -c "rm -rf /app/bluespice/w/images/* /app/bluespice/w/images/.[^.]*" 2>/dev/null; then
        log_warn "Could not fully clear images directory (some files may be in use)"
    fi
    
    # Copy new images to container
    log_info "Copying new images to wiki container..."
    if docker cp "$images_source/." "$container_name:/app/bluespice/w/images/"; then
        log_info "Images copied successfully"
    else
        log_error "Failed to copy images to container"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Final ownership fix inside container as backup
    log_info "Ensuring correct ownership inside container..."
    docker exec "$container_name" sh -c "chown -R bluespice:bluespice /app/bluespice/w/images/ 2>/dev/null || true"
    docker exec "$container_name" sh -c "chmod -R 755 /app/bluespice/w/images/ 2>/dev/null || true"
    
    # Verify ownership was fixed
    log_info "Verifying ownership and permissions..."
    docker exec "$container_name" ls -la /app/bluespice/w/images/ | head -5
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    return 0
}

# Function to rebuild images database
rebuild_images_database() {
    local wiki_name="$1"
    local container_name
    container_name=$(get_container_name "$wiki_name")
    
    log_info "Importing images into database..."
    
    # Run importImages.php maintenance script to register images in database
    log_info "Running importImages.php to register all images..."
    if docker exec --user bluespice "$container_name" php /app/bluespice/w/maintenance/importImages.php --search-recursively --overwrite /app/bluespice/w/images/; then
        log_info "Images imported into database successfully"
    else
        log_error "Failed to import images into database"
        log_info "Trying alternative approach..."
        
        # Try running as root user in case of permission issues
        if docker exec "$container_name" php /app/bluespice/w/maintenance/importImages.php --search-recursively --overwrite /app/bluespice/w/images/; then
            log_info "Images imported into database successfully (as root)"
        else
            log_error "Database import failed even as root user"
            return 1
        fi
    fi
    
    log_info "Running rebuildImages.php to synchronize database..."
    
    # Run RebuildImages.php maintenance script
    if docker exec --user bluespice "$container_name" php /app/bluespice/w/maintenance/rebuildImages.php 2>/dev/null; then
        log_info "Images database synchronized successfully"
        return 0
    elif docker exec "$container_name" php /app/bluespice/w/maintenance/rebuildImages.php 2>/dev/null; then
        log_info "Images database synchronized successfully (as root)"
        return 0
    else
        log_warn "Failed to synchronize images database, but import may still be successful"
        return 0
    fi
}

# Main function
main() {
    log_info "BlueSpice Wiki Images Import Tool (v2)"
    log_info "======================================"
    
    # Get wiki name if not provided
    if [[ -z "$WIKI_NAME" ]]; then
        echo -n "Enter wiki name: "
        read -r WIKI_NAME
    fi
    
    # Validate wiki
    if ! validate_wiki "$WIKI_NAME"; then
        exit 1
    fi
    
    log_info "Wiki '$WIKI_NAME' found and running"
    
    # Get images archive if not provided
    if [[ -z "$IMAGES_ARCHIVE" ]]; then
        echo -n "Enter path to images ZIP archive: "
        read -r IMAGES_ARCHIVE
    fi
    
    # Validate images archive
    if ! validate_images_archive "$IMAGES_ARCHIVE"; then
        exit 1
    fi
    
    log_info "Images archive validated: $IMAGES_ARCHIVE"
    
    # Show summary and confirm
    echo ""
    log_info "Import Summary:"
    log_info "  Wiki: $WIKI_NAME"
    log_info "  Images Archive: $IMAGES_ARCHIVE"
    echo ""
    log_warn "This will replace ALL current images in the wiki!"
    echo -n "Continue with import? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Import cancelled"
        exit 0
    fi
    
    # Backup current images
    log_info "Starting images import process..."
    if ! backup_path=$(backup_current_images "$WIKI_NAME"); then
        log_error "Failed to backup current images"
        exit 1
    fi
    
    # Import new images
    if ! import_images "$WIKI_NAME" "$IMAGES_ARCHIVE"; then
        log_error "Images import failed"
        if [[ -n "$backup_path" ]]; then
            log_info "You can restore from backup: $backup_path"
        fi
        exit 1
    fi
    
    # Rebuild images database
    if ! rebuild_images_database "$WIKI_NAME"; then
        log_warn "Images imported but database registration had issues"
        log_info "You may need to check the wiki manually"
    fi
    
    log_info "Images import process completed!"
    log_info "Backup of previous images: $backup_path"
    log_info "Wiki images have been updated and database import attempted"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
