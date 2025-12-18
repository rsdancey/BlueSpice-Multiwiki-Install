#!/bin/bash

# BlueSpice ExtendedSearch index management
# Handles initialization and rebuilding of search indices

set -euo pipefail

# Source required libraries
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logging.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/docker-utils.sh"

# Rebuild search index for a wiki
rebuild_search_index() {
    local wiki_name="$1"
    
    log_info "🔍 Rebuilding search index for ${wiki_name}..."
    
    # Check if container is running
    if ! is_container_running "$wiki_name"; then
        log_error "Container for ${wiki_name} is not running"
        return 1
    fi
    
    # Run search index rebuild inside the web container
    local container_name
    container_name=$(get_container_name "$wiki_name")
    # container_name already includes -wiki-web from get_container_name
    
    if ! docker exec --user root "$container_name" sh -lc '
        set -e
        cd /app/bluespice/w
        echo "  Initializing search backends..."
        php extensions/BlueSpiceExtendedSearch/maintenance/initBackends.php
        echo "  Rebuilding search index..."
        php extensions/BlueSpiceExtendedSearch/maintenance/rebuildIndex.php
        echo "  Running index jobs..."
        php maintenance/runJobs.php
    ' 2>&1 | while IFS= read -r line; do echo "  $line"; done; then
        log_error "Search index rebuild failed for ${wiki_name}"
        return 1
    fi
    
    log_info "  ✓ Search index rebuilt for ${wiki_name}"
    
    # Verify index has documents
    if ! verify_search_index "$wiki_name"; then
        log_warn "  ⚠️  Could not verify search index for ${wiki_name}"
    fi
    
    return 0
}

# Verify search index has documents
verify_search_index() {
    local wiki_name="$1"
    local index_name="${wiki_name}_wiki_wikipage"
    
    # Query Elasticsearch to check document count
    local count_result
    if count_result=$(docker exec bluespice-search curl -s "http://localhost:9200/${index_name}/_count" 2>/dev/null); then
        if echo "$count_result" | grep -q '"count":[1-9]'; then
            local doc_count
            doc_count=$(echo "$count_result" | grep -oP '"count":\K[0-9]+')
            log_info "  ✓ Index verified: ${doc_count} documents in ${index_name}"
            return 0
        else
            log_warn "  ⚠️  Index ${index_name} appears empty"
            return 1
        fi
    else
        log_warn "  ⚠️  Could not query index ${index_name}"
        return 1
    fi
}
