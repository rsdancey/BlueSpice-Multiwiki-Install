#!/bin/bash

# Images Import Script for BlueSpice Wiki
# Imports and replaces images directory from a zipped archive

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

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
            print_error "Unknown argument: $arg"
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
        print_error "Wiki directory not found: $wiki_dir"
        return 1
    fi
    
    if [[ ! -f "$wiki_dir/.env" ]]; then
        print_error "Wiki configuration not found: $wiki_dir/.env"
        return 1
    fi
    
    # Check if wiki container is running
    local container_name="bluespice-$wiki_name-wiki-web"
    if ! docker ps --format "table {{.Names}}" | grep -q "^$container_name$"; then
        print_error "Wiki container not running: $container_name"
        print_info "Please start the wiki first using:"
        print_info "./bluespice-deploy-wiki --wiki-name=$wiki_name"
        return 1
    fi
    
    return 0
}

# Function to validate images archive
validate_images_archive() {
    local archive_path="$1"
    
    if [[ ! -f "$archive_path" ]]; then
        print_error "Images archive not found: $archive_path"
        return 1
    fi
    
    # Check if it's a zip file
    if ! file "$archive_path" | grep -q "Zip archive"; then
        print_error "File is not a ZIP archive: $archive_path"
        return 1
    fi
    
    # Check if zip contains images directory
    if ! unzip -l "$archive_path" | grep -q "images/"; then
        print_warning "Archive does not appear to contain an 'images/' directory"
        print_info "Continuing anyway..."
    fi
    
    return 0
}

# Function to backup current images
backup_current_images() {
    local wiki_name="$1"
    local container_name="bluespice-$wiki_name-wiki-web"
    local backup_dir
    backup_dir="/tmp/images_backup_$(date +%Y%m%d_%H%M%S)"
    
    print_info "Creating backup of current images directory..."
    
    # Create backup directory on host
    mkdir -p "$backup_dir"
    
    # Copy current images from container to backup
    if docker cp "$container_name:/app/bluespice/w/images/." "$backup_dir/"; then
        print_success "Current images backed up to: $backup_dir"
        echo "$backup_dir"
        return 0
    else
        print_error "Failed to backup current images"
        return 1
    fi
}

# Function to import images
import_images() {
    local wiki_name="$1"
    local archive_path="$2"
    local container_name="bluespice-$wiki_name-wiki-web"
    local temp_dir
    temp_dir="/tmp/images_import_$(date +%Y%m%d_%H%M%S)"
    
    print_info "Importing images from archive..."
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    
    # Extract archive
    print_info "Extracting images archive..."
    if ! unzip -q "$archive_path" -d "$temp_dir"; then
        print_error "Failed to extract images archive"
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
            print_error "Could not find images directory in archive"
            rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    print_info "Found images source: $images_source"
    
    # Clear current images directory in container
    print_info "Clearing current images directory..."
    if ! docker exec "$container_name" sh -c "rm -rf /app/bluespice/w/images/* /app/bluespice/w/images/.[^.]*"; then
        print_warning "Could not fully clear images directory (some files may be in use)"
    fi
    
    # Copy new images to container
    print_info "Copying new images to wiki container..."
    if docker cp "$images_source/." "$container_name:/app/bluespice/w/images/"; then
        print_success "Images copied successfully"
    else
        print_error "Failed to copy images to container"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Fix permissions
    print_info "Fixing images directory permissions..."
    docker exec "$container_name" chown -R bluespice:bluespice /app/bluespice/w/images/
    docker exec "$container_name" chmod -R 755 /app/bluespice/w/images/
    
    # Clean up
    rm -rf "$temp_dir"
    
    return 0
}

# Function to rebuild images database
rebuild_images_database() {
    local wiki_name="$1"
    local container_name="bluespice-$wiki_name-wiki-web"
    
    print_info "Importing images into database..."
    
    # Run importImages.php maintenance script to register images in database
    print_info "Running importImages.php to register all images..."
    if docker exec "$container_name" php /app/bluespice/w/maintenance/importImages.php --search-recursively --overwrite /app/bluespice/w/images/; then
        print_success "Images imported into database successfully"
    else
        print_error "Failed to import images into database"
        return 1
    fi
    
    print_info "Running rebuildImages.php to synchronize database..."
    
    # Run RebuildImages.php maintenance script
    if docker exec "$container_name" php /app/bluespice/w/maintenance/rebuildImages.php; then
        print_success "Images database synchronized successfully"
        return 0
    else
        print_error "Failed to synchronize images database"
        return 1
    fi
}

# Main function
main() {
    print_info "BlueSpice Wiki Images Import Tool"
    print_info "================================="
    
    # Get wiki name if not provided
    if [[ -z "$WIKI_NAME" ]]; then
        echo -n "Enter wiki name: "
        read -r WIKI_NAME
    fi
    
    # Validate wiki
    if ! validate_wiki "$WIKI_NAME"; then
        exit 1
    fi
    
    print_success "Wiki '$WIKI_NAME' found and running"
    
    # Get images archive if not provided
    if [[ -z "$IMAGES_ARCHIVE" ]]; then
        echo -n "Enter path to images ZIP archive: "
        read -r IMAGES_ARCHIVE
    fi
    
    # Validate images archive
    if ! validate_images_archive "$IMAGES_ARCHIVE"; then
        exit 1
    fi
    
    print_success "Images archive validated: $IMAGES_ARCHIVE"
    
    # Show summary and confirm
    echo ""
    print_info "Import Summary:"
    print_info "  Wiki: $WIKI_NAME"
    print_info "  Images Archive: $IMAGES_ARCHIVE"
    echo ""
    print_warning "This will replace ALL current images in the wiki!"
    echo -n "Continue with import? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Import cancelled"
        exit 0
    fi
    
    # Backup current images
    print_info "Starting images import process..."
    if ! backup_path=$(backup_current_images "$WIKI_NAME"); then
        print_error "Failed to backup current images"
        exit 1
    fi
    
    # Import new images
    if ! import_images "$WIKI_NAME" "$IMAGES_ARCHIVE"; then
        print_error "Images import failed"
        if [[ -n "$backup_path" ]]; then
            print_info "You can restore from backup: $backup_path"
        fi
        exit 1
    fi
    
    # Rebuild images database
    if ! rebuild_images_database "$WIKI_NAME"; then
        print_warning "Images imported but database registration failed"
        print_info "You may need to run this manually:"
        print_info "docker exec bluespice-$WIKI_NAME-wiki-web php /app/bluespice/w/maintenance/importImages.php --search-recursively --overwrite /app/bluespice/w/images/"
    fi
    
    print_success "Images import completed successfully!"
    print_info "Backup of previous images: $backup_path"
    print_info "Wiki images have been updated, imported into database, and synchronized"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
