#!/bin/bash

# Upstream service inventory check
# Compares services in the official hallowelt/bluespice-deploy repo against
# the known services list in core_install. Warns if new services are found.

# Source logging if available
if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/lib/logging.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/lib/logging.sh" 2>/dev/null || true
fi

# Fallback log functions if logging.sh not loaded
if ! command -v log_info &>/dev/null; then
    log_info()  { echo "[INFO]  $*"; }
    log_warn()  { echo "[WARN]  $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# Check upstream bluespice-deploy for new services not yet in core_install.
# Returns 0 if all services are known, 1 if new services found, 0 on fetch failure.
# Usage: check_upstream_services <version>
check_upstream_services() {
    local version="$1"
    local known_file="${SCRIPT_DIR}/lib/known-upstream-services.txt"
    local base_url="https://raw.githubusercontent.com/hallowelt/bluespice-deploy/${version}/compose"

    if [[ ! -f "$known_file" ]]; then
        log_warn "Known services file not found: $known_file — skipping upstream check"
        return 0
    fi

    log_info "Checking upstream bluespice-deploy ${version} for new services..."

    # Compose files to scan
    local compose_files=(
        "docker-compose.main.yml"
        "docker-compose.stateless-services.yml"
        "docker-compose.persistent-data-services.yml"
        "docker-compose.helper-service.yml"
        "docker-compose.proxy.yml"
        "docker-compose.collabpads-service.yml"
    )

    # Fetch and extract service names from all compose files
    local all_services=""
    local fetch_ok=false
    for cf in "${compose_files[@]}"; do
        local url="${base_url}/${cf}"
        local body
        body=$(curl -sS --max-time 10 "$url" 2>/dev/null) || continue
        fetch_ok=true
        # Extract service names: lines with exactly 2-space indent followed by word chars and colon
        local services
        services=$(echo "$body" | grep -E '^\s{2}[a-zA-Z][a-zA-Z0-9_-]*:\s*$' | sed 's/^\s*//' | sed 's/:\s*$//')
        all_services="${all_services}${services}"$'\n'
    done

    if [[ "$fetch_ok" != "true" ]]; then
        log_warn "Could not fetch upstream compose files (network issue?) — skipping check"
        return 0
    fi

    # Deduplicate upstream services
    local upstream_list
    upstream_list=$(echo "$all_services" | sort -u | grep -v '^$')

    # Load known services (strip comments and blank lines)
    local known_list
    known_list=$(grep -v '^\s*#' "$known_file" | grep -v '^\s*$' | sort -u)

    # Find unknown services
    local unknown=""
    while IFS= read -r svc; do
        if ! echo "$known_list" | grep -qxF "$svc"; then
            unknown="${unknown}  - ${svc}"$'\n'
        fi
    done <<< "$upstream_list"

    if [[ -n "$unknown" ]]; then
        echo ""
        log_error "============================================================"
        log_error "NEW UPSTREAM SERVICES DETECTED in bluespice-deploy ${version}"
        log_error "============================================================"
        log_error ""
        log_error "The following services were found in the official"
        log_error "hallowelt/bluespice-deploy ${version} but are not yet"
        log_error "integrated into the core_install system:"
        log_error ""
        echo "$unknown" | while IFS= read -r line; do
            [[ -n "$line" ]] && log_error "$line"
        done
        log_error ""
        log_error "The core_install system needs to be updated to support"
        log_error "these services before proceeding."
        log_error ""
        log_error "To add a service to the known list after integrating it,"
        log_error "edit: ${known_file}"
        log_error "============================================================"
        echo ""
        return 1
    fi

    log_info "  All upstream services are known — OK"
    return 0
}
