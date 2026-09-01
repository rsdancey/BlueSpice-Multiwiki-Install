#!/bin/bash

# Container entrypoint wrapper script management for BlueSpice MediaWiki
# NOTE: This file is sourced by other scripts; do not use set -euo pipefail here.

# Scripts installed to /opt/bluespice/scripts and bind-mounted read-only into
# the wiki containers as /scripts. start-web-wrapper.sh and start-task-wrapper.sh
# are the container entrypoints; patch-bluespice.sh is invoked by both to
# re-apply local fixes to /app, which the image resets on every container create.
WRAPPER_SCRIPTS=(
    start-web-wrapper.sh
    start-task-wrapper.sh
    patch-bluespice.sh
)

# Install the entrypoint wrapper scripts to /opt/bluespice/scripts.
# They act as the containers' entrypoint, so they must be present and current
# before any container starts — on fresh installs and on every upgrade, since
# an upgrade recreates the containers.
install_wrapper_scripts() {
    local src_dir="${SCRIPT_DIR}/scripts"
    local dest_dir="/opt/bluespice/scripts"
    local script

    for script in "${WRAPPER_SCRIPTS[@]}"; do
        if [[ ! -f "${src_dir}/${script}" ]]; then
            log_error "Wrapper script not found: ${src_dir}/${script}"
            return 1
        fi
    done

    if [[ ! -d "$dest_dir" ]]; then
        sudo mkdir -p "$dest_dir" 2>/dev/null || mkdir -p "$dest_dir"
    fi

    for script in "${WRAPPER_SCRIPTS[@]}"; do
        sudo cp "${src_dir}/${script}" "${dest_dir}/" 2>/dev/null \
            || cp "${src_dir}/${script}" "${dest_dir}/" || return 1
        sudo chmod 0755 "${dest_dir}/${script}" 2>/dev/null \
            || chmod 0755 "${dest_dir}/${script}" || return 1
    done

    log_info "Installed container wrapper scripts to ${dest_dir}"
}
