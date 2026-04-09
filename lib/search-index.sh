#!/bin/bash

# BlueSpice ExtendedSearch index management
# Handles initialization and rebuilding of search indices

# Note: set -euo pipefail is intentionally omitted here because this file
# is sourced into other scripts that manage their own error handling.

# Source required libraries
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logging.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/docker-utils.sh"

# Ensure /tmp/wiki exists and is writable in both web and task containers.
# This is a runtime safety net — the directory should already exist via
# docker-compose tmpfs mounts, but may be missing on older deployments.
ensure_tmp_wiki_dir() {
    local wiki_name="$1"
    local web_container task_container
    web_container=$(get_container_name "$wiki_name")
    task_container="bluespice-${wiki_name}-wiki-task"

    for ctr in "$web_container" "$task_container"; do
        if docker inspect --format '{{.State.Running}}' "$ctr" 2>/dev/null | grep -q true; then
            docker exec --user root "$ctr" sh -c \
                'mkdir -p /tmp/wiki && chown bluespice:bluespice /tmp/wiki && chmod 1777 /tmp/wiki' \
                2>/dev/null || log_warn "  Could not ensure /tmp/wiki in ${ctr}"
        fi
    done
}

# Clear stuck updateWikiPageIndex jobs so a fresh rebuild can succeed.
# Jobs with 3+ failed attempts are permanently stuck ("none-ready").
clear_stuck_index_jobs() {
    local wiki_name="$1"

    # Read DB credentials from the wiki's environment
    local env_file="/core/wikis/${wiki_name}/.env"
    if [[ ! -f "$env_file" ]]; then
        log_warn "  Could not find ${env_file} — skipping stuck job cleanup"
        return 0
    fi

    local db_name db_user db_pass
    db_name=$(grep '^DB_NAME=' "$env_file" | head -1 | cut -d= -f2-)
    db_user=$(grep '^DB_USER=' "$env_file" | head -1 | cut -d= -f2-)
    db_pass=$(grep '^DB_PASS=' "$env_file" | head -1 | cut -d= -f2-)

    if [[ -z "$db_name" || -z "$db_user" || -z "$db_pass" ]]; then
        log_warn "  Missing DB credentials — skipping stuck job cleanup"
        return 0
    fi

    local stuck_count
    stuck_count=$(docker exec bluespice-database mariadb -u "$db_user" -p"$db_pass" "$db_name" \
        -sNe "SELECT COUNT(*) FROM job WHERE job_cmd='updateWikiPageIndex' AND job_attempts >= 3;" 2>/dev/null) || stuck_count=0

    if [[ "$stuck_count" -gt 0 ]]; then
        log_info "  Clearing ${stuck_count} stuck updateWikiPageIndex jobs..."
        docker exec bluespice-database mariadb -u "$db_user" -p"$db_pass" "$db_name" \
            -e "DELETE FROM job WHERE job_cmd='updateWikiPageIndex' AND job_attempts >= 3;" 2>/dev/null \
            || log_warn "  Could not clear stuck jobs"
    fi
}

# Rebuild search index for a wiki
rebuild_search_index() {
    local wiki_name="$1"
    
    log_info "Rebuilding search index for ${wiki_name}..."
    
    # Check if container is running
    if ! is_container_running "$wiki_name"; then
        log_error "Container for ${wiki_name} is not running"
        return 1
    fi

    # Ensure /tmp/wiki is available in both containers
    ensure_tmp_wiki_dir "$wiki_name"

    # Clear any stuck index jobs from previous failed attempts
    clear_stuck_index_jobs "$wiki_name"
    
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
    
    log_info "  Search index rebuilt for ${wiki_name}"
    
    # Verify index has documents
    if ! verify_search_index "$wiki_name"; then
        log_warn "  Could not verify search index for ${wiki_name}"
    fi
    
    return 0
}

# Verify search index has documents
verify_search_index() {
    local wiki_name="$1"
    local index_name="${wiki_name}_wiki_wikipage"
    
    # Query OpenSearch to check document count
    local count_result
    if count_result=$(docker exec bluespice-search curl -s "http://localhost:9200/${index_name}/_count" 2>/dev/null); then
        if echo "$count_result" | grep -q '"count":[1-9]'; then
            local doc_count
            doc_count=$(echo "$count_result" | grep -oP '"count":\K[0-9]+')
            log_info "  Index verified: ${doc_count} documents in ${index_name}"
            return 0
        else
            log_warn "  Index ${index_name} appears empty"
            return 1
        fi
    else
        log_warn "  Could not query index ${index_name}"
        return 1
    fi
}
