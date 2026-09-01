#!/bin/bash

# Behavioural verification of the BlueSpice patches applied by
# scripts/patch-bluespice.sh.
# NOTE: This file is sourced by other scripts; do not use set -euo pipefail here.

# Locate something that can run the JS harnesses. The wiki image ships no node,
# so they run elsewhere. Prefer a running container; fall back to a throwaway
# container from an image that has one, so a stopped shared service does not
# silently skip the check.
# Echoes "exec <container>" or "run <image>". Returns 1 if neither is available.
_find_node_runner() {
    local candidate image

    for candidate in $(docker ps --format '{{.Names}}' 2>/dev/null); do
        if docker exec "$candidate" sh -c 'command -v node' >/dev/null 2>&1; then
            echo "exec $candidate"
            return 0
        fi
    done

    for image in $(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
        | grep -E '^bluespice/(formula|pdf|diagram|collabpads):' | head -8); do
        if docker run --rm --entrypoint sh "$image" -c 'command -v node' >/dev/null 2>&1; then
            echo "run $image"
            return 0
        fi
    done

    return 1
}

# _run_js_harness <label> <harness_file> <wiki_container> <container_source>...
#
# Stages the harness next to the live sources it needs — pulled out of the
# running wiki container, so the check sees exactly what the entrypoint left in
# /app — and runs it under node.
# Returns 0 on pass, 1 on a real failure, 2 if the check could not be run.
_run_js_harness() {
    local label="$1" harness="$2" wiki_container="$3"
    shift 3

    local runner mode target staging source rc out

    if [[ ! -f "$harness" ]]; then
        log_error "  ${label}: harness not found at ${harness} — NOT VERIFIED"
        return 2
    fi

    if ! runner=$(_find_node_runner); then
        log_error "  ${label}: no container or image with node available — NOT VERIFIED"
        return 2
    fi
    mode="${runner%% *}"
    target="${runner#* }"

    if ! staging=$(mktemp -d); then
        log_error "  ${label}: could not create staging directory — NOT VERIFIED"
        return 2
    fi

    rc=0
    for source in "$@"; do
        docker cp "${wiki_container}:${source}" "${staging}/$(basename "$source")" \
            >/dev/null 2>&1 || rc=1
    done
    cp "$harness" "${staging}/harness.js" 2>/dev/null || rc=1

    if [[ $rc -ne 0 ]]; then
        rm -rf "$staging"
        log_error "  ${label}: could not collect sources from ${wiki_container} — NOT VERIFIED"
        return 2
    fi

    # The harness runs as whatever user the runner uses, which is not this one.
    chmod 0755 "$staging" 2>/dev/null
    chmod 0644 "$staging"/* 2>/dev/null

    if [[ "$mode" == "exec" ]]; then
        if ! docker cp "$staging" "${target}:/tmp/bs-patch-check" >/dev/null 2>&1; then
            rm -rf "$staging"
            log_error "  ${label}: could not stage harness in ${target} — NOT VERIFIED"
            return 2
        fi
        rc=0
        out=$(docker exec "$target" node /tmp/bs-patch-check/harness.js 2>&1) || rc=$?
        docker exec --user root "$target" rm -rf /tmp/bs-patch-check >/dev/null 2>&1
    else
        rc=0
        out=$(docker run --rm -v "${staging}:/harness:ro" --entrypoint node \
            "$target" /harness/harness.js 2>&1) || rc=$?
    fi
    rm -rf "$staging"

    _report_harness "$label" "$rc" "$out"
}

# _run_php_harness <label> <harness_file> <wiki_container>
#
# The PHP patch is verified inside the wiki container itself, which always
# exists — so this check runs even when nothing on the host has node.
# Returns 0 on pass, 1 on a real failure, 2 if the check could not be run.
_run_php_harness() {
    local label="$1" harness="$2" wiki_container="$3"
    local remote="/tmp/bs-patch-check.php" rc out

    if [[ ! -f "$harness" ]]; then
        log_error "  ${label}: harness not found at ${harness} — NOT VERIFIED"
        return 2
    fi

    if ! docker cp "$harness" "${wiki_container}:${remote}" >/dev/null 2>&1; then
        log_error "  ${label}: could not stage harness in ${wiki_container} — NOT VERIFIED"
        return 2
    fi

    rc=0
    out=$(docker exec "$wiki_container" php "$remote" 2>&1) || rc=$?
    docker exec --user root "$wiki_container" rm -f "$remote" >/dev/null 2>&1

    _report_harness "$label" "$rc" "$out"
}

# _report_harness <label> <rc> <output>
_report_harness() {
    local label="$1" rc="$2" out="$3" line

    if [[ $rc -eq 0 ]]; then
        log_info "  ✓ ${label} verified ($(echo "$out" | grep -c '  PASS  ') checks)"
        return 0
    fi

    if [[ $rc -eq 2 ]]; then
        log_error "  ${label}: harness could not run — NOT VERIFIED"
        log_error "    ${out}"
        return 2
    fi

    log_error "  ✗ ${label} FAILED"
    while IFS= read -r line; do
        [[ -n "$line" ]] && log_error "    ${line}"
    done <<< "$(echo "$out" | grep -E 'FAIL')"
    return 1
}

# Check that the fixes patch-bluespice.sh applies to the ConfigManager
# Authentication tab still behave.
#
# A SKIP line from patch-bluespice.sh only proves a patch did not apply. These
# harnesses prove the patched code works: they pull the live sources out of the
# wiki container and exercise them. One covers each patch group —
#
#   Authentication config encoding  KeyObjectInputWidget.php  (PHP, in-container)
#   Authentication tab restore      ConfigManager.js          (node)
#   Save-button change propagation  the three OOUI widgets    (node)
#
# Returns 0 when everything ran and passed, 1 if any check failed, 2 if any
# check could not be run. Callers treat 2 as non-fatal — it is reported as an
# error so an unverified upgrade is never mistaken for a verified one, but a
# missing node runtime is not by itself a bad upgrade.
verify_configmanager_patches() {
    local wiki_name="$1"
    local wiki_container="bluespice-${wiki_name}-wiki-web"
    local tests="${SCRIPT_DIR}/tests"
    local widget_dir="/app/bluespice/w/extensions/BlueSpiceFoundation/resources/bluespice.oojs/ui/widget"
    local oojs="/app/bluespice/w/resources/lib/oojs/oojs.js"
    local rcs=() rc failures=0 skipped=0

    rc=0
    _run_php_harness "Authentication config encoding" \
        "${tests}/configmanager-keyobject-harness.php" "$wiki_container" || rc=$?
    rcs+=( "$rc" )

    rc=0
    _run_js_harness "Authentication tab restore" \
        "${tests}/configmanager-panel-harness.js" "$wiki_container" \
        "$oojs" \
        "/app/bluespice/w/extensions/BlueSpiceConfigManager/resources/ui/panel/ConfigManager.js" || rc=$?
    rcs+=( "$rc" )

    rc=0
    _run_js_harness "Save-button change propagation" \
        "${tests}/configmanager-widget-harness.js" "$wiki_container" \
        "$oojs" \
        "${widget_dir}/JsonArrayInputWidget.js" \
        "${widget_dir}/ObjectInputWidget.js" \
        "${widget_dir}/KeyValueInputWidget.js" \
        "${widget_dir}/KeyObjectInputWidget.js" || rc=$?
    rcs+=( "$rc" )

    for rc in "${rcs[@]}"; do
        if [[ $rc -eq 1 ]]; then
            failures=$(( failures + 1 ))
        elif [[ $rc -eq 2 ]]; then
            skipped=$(( skipped + 1 ))
        fi
    done

    if [[ $failures -gt 0 ]]; then
        log_error "  ${failures} ConfigManager check(s) FAILED. Configuring authentication"
        log_error "    may wipe the OAuth config or leave Save greyed out. Re-check"
        log_error "    scripts/patch-bluespice.sh against this BlueSpice version."
        return 1
    fi

    if [[ $skipped -gt 0 ]]; then
        log_error "  ${skipped} ConfigManager check(s) DID NOT RUN — the patches are unverified."
        log_error "    See the README for how to run them by hand."
        return 2
    fi

    return 0
}
