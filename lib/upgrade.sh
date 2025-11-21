#!/bin/bash

# BlueSpice version upgrade functionality
# Handles upgrading all wikis to a new version

set -euo pipefail

# Source required libraries
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logging.sh"

# Get the latest BlueSpice version from Docker Hub
get_latest_bluespice_version() {
    log_info "🔍 Checking for latest BlueSpice version..."
    
    # Query Docker Hub API for bluespice/wiki tags
    local api_url="https://registry.hub.docker.com/v2/repositories/bluespice/wiki/tags?page_size=100"
    local tags_json
    
    if ! tags_json=$(curl -s "$api_url"); then
        log_error "Failed to fetch version information from Docker Hub"
        return 1
    fi
    
    # Extract version tags (format: X.Y or X.Y.Z) and find the latest
    # Filter out 'latest' and other non-version tags, sort, and get the highest version
    local latest_version
    latest_version=$(echo "$tags_json" | \
        grep -oP '"name":\s*"\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=")' | \
        sort -V | \
        tail -1)
    
    if [[ -z "$latest_version" ]]; then
        log_error "Could not determine latest version from Docker Hub"
        return 1
    fi
    
    # Return just the major.minor version (e.g., 5.1 from 5.1.3)
    # This matches the format used in our configuration files
    echo "$latest_version" | grep -oP '^[0-9]+\.[0-9]+'
}


# Get list of all wiki directories
get_all_wikis() {
    local wikis_dir="$1"
    local wiki_list=()
    
    if [[ ! -d "$wikis_dir" ]]; then
        log_error "Wikis directory not found: $wikis_dir"
        return 1
    fi
    
    for wiki_dir in "$wikis_dir"/*/; do
        if [[ -f "${wiki_dir}.env" ]]; then
            local wiki_name=$(basename "$wiki_dir")
            wiki_list+=("$wiki_name")
        fi
    done
    
    echo "${wiki_list[@]}"
}

# Update version in a file
update_version_in_file() {
    local file_path="$1"
    local new_version="$2"
    
    if [[ ! -f "$file_path" ]]; then
        log_error "File not found: $file_path"
        return 1
    fi
    
    log_info "  Updating version in $(basename "$file_path")..."
    
    # Update VERSION= line
    sed -i "s/^VERSION=.*/VERSION=${new_version}/" "$file_path"
    
    # Update Docker image version
    sed -i "s|bluespice/wiki:[0-9.]*|bluespice/wiki:${new_version}|g" "$file_path"
    
    return 0
}

# Perform upgrade for all wikis
perform_system_upgrade() {
    local new_version="$1"
    local script_dir="$2"
    local wikis_dir="${script_dir}/../wikis"
    
    log_info "🚀 Starting BlueSpice system upgrade to version ${new_version}"
    echo
    
    # Confirm with user
    log_warn "This will upgrade ALL wikis to version ${new_version}"
    log_warn "It is recommended to backup your data before proceeding"
    echo
    printf "Do you want to continue? [y/N]: "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Upgrade cancelled"
        return 0
    fi
    
    echo
    log_info "📝 Step 1: Updating configuration files..."
    
    # Update global configuration
    if [[ -f "${script_dir}/.global.env" ]]; then
        update_version_in_file "${script_dir}/.global.env" "$new_version"
    fi
    
    # Update template
    if [[ -f "${script_dir}/wiki-template/.env.template" ]]; then
        update_version_in_file "${script_dir}/wiki-template/.env.template" "$new_version"
    fi
    
    # Get list of wikis
    local wikis=($(get_all_wikis "$wikis_dir"))
    
    if [[ ${#wikis[@]} -eq 0 ]]; then
        log_warn "No wikis found to upgrade"
        return 0
    fi
    
    log_info "  Found ${#wikis[@]} wiki(s) to upgrade: ${wikis[*]}"
    echo
    
    # Update each wiki's .env file
    log_info "📝 Step 2: Updating wiki configuration files..."
    for wiki_name in "${wikis[@]}"; do
        local wiki_env="${wikis_dir}/${wiki_name}/.env"
        if [[ -f "$wiki_env" ]]; then
            update_version_in_file "$wiki_env" "$new_version"
        fi
    done
    
    echo
    log_info "📦 Step 3: Pulling new Docker image..."
    if docker pull "bluespice/wiki:${new_version}"; then
        log_info "  ✓ Docker image pulled successfully"
    else
        log_error "Failed to pull Docker image for version ${new_version}"
        log_error "Please check your internet connection and that version ${new_version} exists"
        return 1
    fi
    
    echo
    log_info "⬆️  Step 4: Upgrading wikis..."
    local failed_wikis=()
    
    for wiki_name in "${wikis[@]}"; do
        log_info "  Upgrading wiki: $wiki_name"
        
        if "${script_dir}/bluespice-deploy-wiki" --wiki-name="$wiki_name" --profile=upgrade 2>&1 | \
           while IFS= read -r line; do echo "    $line"; done; then
            log_info "  ✓ $wiki_name upgraded successfully"
        else
            log_error "  ✗ Failed to upgrade $wiki_name"
            failed_wikis+=("$wiki_name")
        fi
        echo
    done
    
    # Summary
    echo
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Upgrade Summary"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ ${#failed_wikis[@]} -eq 0 ]]; then
        log_info "✓ All wikis upgraded successfully to version ${new_version}"
    else
        log_warn "⚠️  Some wikis failed to upgrade:"
        for wiki in "${failed_wikis[@]}"; do
            log_error "  - $wiki"
        done
        log_warn "Please check the logs above for details"
        return 1
    fi
    
    return 0
}

# Interactive upgrade - automatically fetches latest version
interactive_upgrade() {
    local script_dir="$1"
    
    echo
    echo "BlueSpice System Upgrade"
    echo "========================"
    echo
    
    # Get current version
    local current_version=""
    if [[ -f "${script_dir}/.global.env" ]]; then
        current_version=$(grep "^VERSION=" "${script_dir}/.global.env" | cut -d= -f2)
        echo "Current version: ${current_version}"
    fi
    
    # Automatically fetch latest version
    local new_version
    if ! new_version=$(get_latest_bluespice_version); then
        log_error "Failed to determine latest version"
        return 1
    fi
    
    echo "Latest version: ${new_version}"
    echo
    
    # Check if already up to date
    if [[ "$current_version" == "$new_version" ]]; then
        log_info "✓ Already running the latest version (${new_version})"
        return 0
    fi
    
    log_info "Upgrade available: ${current_version} → ${new_version}"
    echo
    
    perform_system_upgrade "$new_version" "$script_dir"
}
