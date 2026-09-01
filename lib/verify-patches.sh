#!/bin/bash

# Behavioural verification of the BlueSpice patches applied by
# scripts/patch-bluespice.sh.
# NOTE: This file is sourced by other scripts; do not use set -euo pipefail here.

# The wiki image ships no node binary, so the harness runs in a sibling
# container that has one. Both candidates are part of a normal deployment:
# <wiki>-wire is per-wiki, bluespice-formula is shared.
_find_node_container() {
    local wiki_name="$1" candidate
    for candidate in "bluespice-${wiki_name}-wire" bluespice-formula; do
        if docker exec "$candidate" sh -c 'command -v node' >/dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# Check that editing a saved PluggableAuth entry still arms the Save button.
#
# A SKIP line from patch-bluespice.sh only proves a patch did not apply. This
# proves the patched widgets behave: it pulls the live sources out of the wiki
# container and exercises them under node.
#
# Returns 0 on pass, 1 on a real failure, 2 if the check could not be run.
# Callers treat 2 as non-fatal — a missing node container is not a bad upgrade.
verify_configmanager_patches() {
    local wiki_name="$1"
    local harness="${SCRIPT_DIR}/tests/configmanager-widget-harness.js"
    local wiki_container="bluespice-${wiki_name}-wiki-web"
    local widget_dir="/app/bluespice/w/extensions/BlueSpiceFoundation/resources/bluespice.oojs/ui/widget"
    local node_container staging widget rc out

    if [[ ! -f "$harness" ]]; then
        log_warn "  Widget harness not found at ${harness} — skipping verification"
        return 2
    fi

    if ! node_container=$(_find_node_container "$wiki_name"); then
        log_warn "  No container with node available — skipping widget verification"
        return 2
    fi

    if ! staging=$(mktemp -d); then
        log_warn "  Could not create staging directory — skipping widget verification"
        return 2
    fi

    rc=0
    for widget in JsonArrayInputWidget ObjectInputWidget KeyValueInputWidget KeyObjectInputWidget; do
        docker cp "${wiki_container}:${widget_dir}/${widget}.js" "${staging}/${widget}.js" \
            >/dev/null 2>&1 || rc=1
    done
    docker cp "${wiki_container}:/app/bluespice/w/resources/lib/oojs/oojs.js" \
        "${staging}/oojs.js" >/dev/null 2>&1 || rc=1
    cp "$harness" "${staging}/harness.js" 2>/dev/null || rc=1

    if [[ $rc -ne 0 ]]; then
        rm -rf "$staging"
        log_warn "  Could not collect widget sources — skipping widget verification"
        return 2
    fi

    if ! docker cp "$staging" "${node_container}:/tmp/bs-widget-check" >/dev/null 2>&1; then
        rm -rf "$staging"
        log_warn "  Could not stage harness in ${node_container} — skipping verification"
        return 2
    fi
    rm -rf "$staging"

    out=$(docker exec "$node_container" node /tmp/bs-widget-check/harness.js 2>&1)
    rc=$?
    docker exec --user root "$node_container" rm -rf /tmp/bs-widget-check >/dev/null 2>&1

    if [[ $rc -eq 0 ]]; then
        log_info "  ✓ ConfigManager widget behaviour verified ($(echo "$out" | grep -c '  PASS  ') checks)"
        return 0
    fi

    if [[ $rc -eq 2 ]]; then
        log_warn "  Widget harness could not run: ${out}"
        return 2
    fi

    log_error "  ✗ ConfigManager widget verification FAILED"
    while IFS= read -r line; do
        [[ -n "$line" ]] && log_error "    ${line}"
    done <<< "$(echo "$out" | grep -E 'FAIL')"
    log_error "    Editing a saved OAuth config may not re-enable Save, or saving may"
    log_error "    wipe it. Re-check scripts/patch-bluespice.sh against this BlueSpice"
    log_error "    version before configuring authentication."
    return 1
}
