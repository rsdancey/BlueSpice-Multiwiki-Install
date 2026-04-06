#!/bin/bash

# GTag extension management for BlueSpice MediaWiki
# Handles installation and configuration of the Google Analytics GTag extension
# NOTE: This file is sourced by other scripts; do not use set -euo pipefail here.

# Download URL for the GTag extension
GTAG_DOWNLOAD_URL="https://github.com/SkizNet/mediawiki-GTag/archive/refs/heads/master.zip"

# Validate a Google Analytics / Tag Manager ID
# Accepts: UA-XXXXXXXXX-X, G-XXXXXXX, GT-XXXXXXXX, GTM-XXXXXXXX
validate_gtag_id() {
    local id="$1"

    if [[ -z "$id" ]]; then
        echo "❌ Analytics ID cannot be empty" >&2
        return 1
    fi

    if [[ "$id" =~ ^UA-[0-9]+-[0-9]+$ ]]; then
        return 0
    elif [[ "$id" =~ ^G-[A-Za-z0-9]+$ ]]; then
        return 0
    elif [[ "$id" =~ ^GT-[A-Za-z0-9]+$ ]]; then
        return 0
    elif [[ "$id" =~ ^GTM-[A-Za-z0-9]+$ ]]; then
        return 0
    fi

    echo "❌ Invalid analytics ID format. Expected UA-XXXXXXXXX-X, G-XXXXXXX, GT-XXXXXXXX, or GTM-XXXXXXXX" >&2
    return 1
}

# Prompt user for a Google Analytics tracking ID
# Sets GTAG_ANALYTICS_ID variable
prompt_gtag_analytics_id() {
    echo ""
    echo "📊 Google Analytics Configuration (GTag Extension)"
    echo "==================================================="
    echo ""
    echo "Enter your Google Analytics or Tag Manager ID."
    echo "Accepted formats: UA-XXXXXXXXX-X, G-XXXXXXX, GT-XXXXXXXX, GTM-XXXXXXXX"
    echo ""

    GTAG_ANALYTICS_ID=""
    while [[ -z "$GTAG_ANALYTICS_ID" ]]; do
        printf "Enter Analytics/Tag Manager ID: "
        read -r GTAG_ANALYTICS_ID
        if ! validate_gtag_id "$GTAG_ANALYTICS_ID"; then
            GTAG_ANALYTICS_ID=""
        fi
    done

    log_info "GTag Analytics ID set to: $GTAG_ANALYTICS_ID"
    return 0
}

# Check if GTag extension is installed in the container
check_gtag_extension_needed() {
    local wiki_name="$1"

    if docker_exec_safe "$wiki_name" test -d /app/bluespice/w/extensions/GTag 2>/dev/null && \
       docker_exec_safe "$wiki_name" test -f /app/bluespice/w/extensions/GTag/extension.json 2>/dev/null; then
        log_info "✓ GTag extension already installed"
        return 1
    fi

    log_info "ℹ️ GTag extension needs to be installed"
    return 0
}

# Download, extract and install the GTag extension into the container
install_gtag_extension() {
    local wiki_name="$1"
    local temp_dir="/tmp/mw_gtag_$$"

    log_info "🔧 Installing GTag extension for $wiki_name..."

    # Ensure container is ready
    if ! wait_for_container_ready "$wiki_name" 30; then
        log_error "❌ Container not ready for GTag extension installation" >&2
        return 1
    fi

    # Create temporary directory
    if ! mkdir -p "$temp_dir"; then
        log_error "❌ Failed to create temporary directory: $temp_dir" >&2
        return 1
    fi

    # Download the ZIP
    log_info "  📥 Downloading GTag extension..."
    if ! curl -L --fail --retry 3 --connect-timeout 10 \
         -o "$temp_dir/GTag.zip" "$GTAG_DOWNLOAD_URL"; then
        log_error "  ❌ Failed to download GTag extension from $GTAG_DOWNLOAD_URL"
        rm -rf "$temp_dir"
        return 1
    fi
    log_info "  ✓ Downloaded GTag extension"

    # Extract the ZIP
    log_info "  📦 Extracting GTag extension..."
    if command -v unzip >/dev/null 2>&1; then
        if ! unzip -q "$temp_dir/GTag.zip" -d "$temp_dir"; then
            log_error "  ❌ Failed to extract GTag extension"
            rm -rf "$temp_dir"
            return 1
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import zipfile; zipfile.ZipFile('$temp_dir/GTag.zip').extractall('$temp_dir')"; then
            log_error "  ❌ Failed to extract GTag extension with python3"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        log_error "  ❌ Neither unzip nor python3 found — cannot extract GTag extension"
        rm -rf "$temp_dir"
        return 1
    fi

    # Rename extracted directory to GTag
    local extracted_dir
    extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "mediawiki-GTag*" | head -1)

    if [[ -z "$extracted_dir" ]]; then
        log_error "  ❌ Could not find extracted GTag directory"
        rm -rf "$temp_dir"
        return 1
    fi

    mv "$extracted_dir" "$temp_dir/GTag"

    # Verify extraction
    if [[ ! -d "$temp_dir/GTag" ]] || [[ ! -f "$temp_dir/GTag/extension.json" ]]; then
        log_error "  ❌ GTag extraction verification failed"
        rm -rf "$temp_dir"
        return 1
    fi
    log_info "  ✓ GTag extracted and prepared"

    # Copy to persistent storage in container
    docker_exec_safe "$wiki_name" mkdir -p /data/bluespice/extensions >/dev/null 2>&1 || true
    docker_exec_safe "$wiki_name" rm -rf /data/bluespice/extensions/GTag >/dev/null 2>&1 || true
    if ! docker_copy_to_container "$wiki_name" "$temp_dir/GTag" "/data/bluespice/extensions/"; then
        log_error "  ❌ Failed to copy GTag to persistent /data"
        rm -rf "$temp_dir"
        return 1
    fi
    docker_exec_safe "$wiki_name" chown -R bluespice:bluespice /data/bluespice/extensions/GTag >/dev/null 2>&1 || true
    docker_exec_safe "$wiki_name" chmod -R g+rwX /data/bluespice/extensions/GTag >/dev/null 2>&1 || true

    # Activate in the running container
    log_info "  📋 Activating GTag extension in container..."
    if ! docker_exec_safe "$wiki_name" "rm -rf /app/bluespice/w/extensions/GTag && cp -r /data/bluespice/extensions/GTag /app/bluespice/w/extensions/GTag"; then
        log_error "  ❌ Failed to activate GTag extension" >&2
        rm -rf "$temp_dir"
        return 1
    fi
    docker_set_ownership "$wiki_name" "/app/bluespice/w/extensions/GTag"

    # Verify activation
    if ! docker_exec_safe "$wiki_name" "test -f /app/bluespice/w/extensions/GTag/extension.json"; then
        log_error "  ❌ GTag extension.json not found after activation"
        rm -rf "$temp_dir"
        return 1
    fi

    # Clean up
    rm -rf "$temp_dir"

    log_info "  ✓ GTag extension installed and activated"
    return 0
}

# Append GTag configuration block to an existing post-init-settings.php
# Used by the upgrade path when GTag was not previously installed
add_gtag_to_post_init_settings() {
    local post_init_file="$1"
    local analytics_id="$2"

    if [[ ! -f "$post_init_file" ]]; then
        log_error "post-init-settings.php not found: $post_init_file"
        return 1
    fi

    # Check if GTag config already exists
    if grep -q "wgGTagAnalyticsId" "$post_init_file"; then
        log_info "  GTag configuration already present in $(basename "$post_init_file") — skipping"
        return 0
    fi

    log_info "  Adding GTag configuration to $(basename "$post_init_file")..."

    cat >> "$post_init_file" <<GTAG_PHP

# ============================================
# GTag Extension (Google Analytics)
# ============================================
\$gtagPath = '/app/bluespice/w/extensions/GTag';
if ( file_exists( \$gtagPath . '/extension.json' ) ) {
    wfLoadExtension( 'GTag' );
    \$wgGTagAnalyticsId = '${analytics_id}';
}
GTAG_PHP

    log_info "  ✓ GTag configuration added to $(basename "$post_init_file")"
    return 0
}

# Full GTag setup for the upgrade path:
# install extension, prompt for ID, add config to post-init-settings.php
setup_gtag_extension() {
    local wiki_name="$1"
    local post_init_file="$2"

    log_info "🚀 Starting GTag extension setup for $wiki_name..."

    # Install extension files
    if ! install_gtag_extension "$wiki_name"; then
        log_error "❌ Failed to install GTag extension"
        return 1
    fi

    # Prompt for analytics ID
    prompt_gtag_analytics_id

    # Add configuration to post-init-settings.php
    if ! add_gtag_to_post_init_settings "$post_init_file" "$GTAG_ANALYTICS_ID"; then
        log_error "❌ Failed to add GTag configuration to post-init-settings.php"
        return 1
    fi

    log_info "✅ GTag extension setup completed successfully"
    return 0
}
