#!/bin/bash

# Semantic MediaWiki extension management for BlueSpice MediaWiki
# Handles installation of SemanticMediaWiki and SemanticExtraSpecialProperties
# using Composer for dependency resolution.
#
# Each extension is installed into /data/bluespice/extensions/<ExtName>/ with
# its own standalone vendor/ directory (same pattern as OpenIDConnect).
# Volume mounts expose these to /app/bluespice/w/extensions/<ExtName>/.
#
# NOTE: This file is sourced by other scripts; do not use set -euo pipefail here.

# ---------------------------------------------------------------------------
# _ensure_composer  — install composer.phar into /data/bluespice/extensions/
# if it is not already present.
# ---------------------------------------------------------------------------
_smw_ensure_composer() {
    local wiki_name="$1"

    if docker_exec_safe "$wiki_name" \
            "test -f /data/bluespice/extensions/composer.phar" 2>/dev/null; then
        log_info "  ✓ Composer already available"
        return 0
    fi

    log_info "  📥 Downloading Composer..."
    if docker_exec_safe "$wiki_name" "
        php -r \"copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');\" &&
        php /tmp/composer-setup.php --install-dir=/data/bluespice/extensions --filename=composer.phar &&
        php -r \"unlink('/tmp/composer-setup.php');\"
    "; then
        log_info "  ✓ Composer installed to persistent storage"
        return 0
    fi

    log_error "  ❌ Failed to install Composer"
    return 1
}

# ---------------------------------------------------------------------------
# _install_composer_extension
#   Download a Composer-managed MediaWiki extension and install it with its
#   own standalone vendor/ directory into /data/bluespice/extensions/<ExtName>.
#
#   Arguments:
#     wiki_name  – wiki instance name
#     pkg_name   – Composer package name  (e.g. mediawiki/semantic-media-wiki)
#     ext_name   – Extension dir name     (e.g. SemanticMediaWiki)
# ---------------------------------------------------------------------------
_install_composer_extension() {
    local wiki_name="$1"
    local pkg_name="$2"
    local ext_name="$3"

    local temp_proj="/tmp/mw_${ext_name}_$$"
    local ext_dest="/data/bluespice/extensions/${ext_name}"
    local composer="/data/bluespice/extensions/composer.phar"

    log_info "  📦 Downloading ${ext_name} via Composer..."

    # Write a minimal composer.json on the HOST (clean heredoc — no quoting
    # issues) then docker-cp it into the container.
    local host_json
    host_json="$(mktemp /tmp/smw_composer_XXXXXX.json)"
    cat > "$host_json" << COMPJSON
{
    "require": {
        "${pkg_name}": "*"
    },
    "minimum-stability": "stable",
    "prefer-stable": true
}
COMPJSON

    local container_json="${temp_proj}_composer.json"
    if ! docker_copy_to_container "$wiki_name" "$host_json" "$container_json"; then
        log_error "  ❌ Failed to copy composer.json into container for ${ext_name}"
        rm -f "$host_json"
        return 1
    fi
    rm -f "$host_json"

    # Create temp project dir and install.
    # --no-plugins prevents the mediawiki-installer plugin from trying to move
    # the extension; the package stays in vendor/<pkg_name>/.
    # --no-scripts avoids running post-install hooks that require MW internals.
    if ! docker_exec_safe "$wiki_name" "
        mkdir -p '${temp_proj}' &&
        cp '${container_json}' '${temp_proj}/composer.json' &&
        rm -f '${container_json}' &&
        cd '${temp_proj}' &&
        php '${composer}' install \
            --prefer-dist --no-dev --ignore-platform-reqs \
            --no-plugins --no-scripts --no-interaction 2>&1
    "; then
        log_error "  ❌ Composer install (download) failed for ${ext_name}"
        docker_exec_safe "$wiki_name" "rm -rf '${temp_proj}'" 2>/dev/null || true
        return 1
    fi

    # Verify the package landed in vendor/
    if ! docker_exec_safe "$wiki_name" \
            "test -f '${temp_proj}/vendor/${pkg_name}/extension.json'" 2>/dev/null; then
        log_error "  ❌ ${ext_name}/extension.json not found in temp vendor after download"
        docker_exec_safe "$wiki_name" "rm -rf '${temp_proj}'" 2>/dev/null || true
        return 1
    fi

    # Copy the downloaded extension to persistent storage.
    # IMPORTANT: preserve the existing directory (and its inode) rather than
    # deleting and recreating it.  The Docker bind mount at
    # /app/bluespice/w/extensions/<ExtName> captured the directory's inode at
    # container-start time; rm -rf + mv replaces the inode and the bind mount
    # then points to a stale dentry, making the extension invisible through
    # /app/bluespice/w/extensions/.
    log_info "  📋 Copying ${ext_name} to persistent storage..."
    if ! docker_exec_safe "$wiki_name" "
        mkdir -p '${ext_dest}' &&
        find '${ext_dest}' -mindepth 1 -delete 2>/dev/null || true &&
        cp -r '${temp_proj}/vendor/${pkg_name}/.' '${ext_dest}/' &&
        rm -rf '${temp_proj}'
    "; then
        log_error "  ❌ Failed to copy ${ext_name} to persistent storage"
        docker_exec_safe "$wiki_name" "rm -rf '${temp_proj}'" 2>/dev/null || true
        return 1
    fi

    # Run composer install INSIDE the extension directory so it gets its own
    # standalone vendor/.  This mirrors the OpenIDConnect pattern and makes the
    # extension self-contained across container recreations.
    log_info "  📦 Installing ${ext_name} standalone vendor..."
    if ! docker_exec_safe "$wiki_name" "
        cd '${ext_dest}' &&
        php '${composer}' install \
            --no-dev --ignore-platform-reqs \
            --no-plugins --no-scripts --no-interaction 2>&1
    "; then
        log_error "  ❌ Composer standalone install failed for ${ext_name}"
        return 1
    fi

    # Fix ownership to match the bluespice container user (uid/gid 1002)
    docker_exec_safe "$wiki_name" \
        "chown -R bluespice:bluespice '${ext_dest}'" 2>/dev/null || true
    docker_exec_safe "$wiki_name" \
        "chmod -R g+rwX '${ext_dest}'" 2>/dev/null || true

    log_info "  ✓ ${ext_name} installed"
    return 0
}

# ---------------------------------------------------------------------------
# install_semantic_extensions
#   Full download + standalone-vendor install for SMW and SESP.
# ---------------------------------------------------------------------------
install_semantic_extensions() {
    local wiki_name="$1"

    log_info "🔧 Installing Semantic extensions for ${wiki_name}..."

    # Container must be running before we can exec into it.
    if ! wait_for_container_ready "$wiki_name" 30; then
        log_error "❌ Container not ready for Semantic extension installation"
        return 1
    fi

    # Persistent extension directory must exist.
    docker_exec_safe "$wiki_name" \
        "mkdir -p /data/bluespice/extensions" 2>/dev/null || true

    # Ensure Composer is available.
    if ! _smw_ensure_composer "$wiki_name"; then
        return 1
    fi

    # Install SemanticMediaWiki.
    if ! _install_composer_extension \
            "$wiki_name" \
            "mediawiki/semantic-media-wiki" \
            "SemanticMediaWiki"; then
        log_error "❌ Failed to install SemanticMediaWiki"
        return 1
    fi

    # Install SemanticExtraSpecialProperties.
    if ! _install_composer_extension \
            "$wiki_name" \
            "mediawiki/semantic-extra-special-properties" \
            "SemanticExtraSpecialProperties"; then
        log_error "❌ Failed to install SemanticExtraSpecialProperties"
        return 1
    fi

    # Verify that the volume mounts are live (paths under /app/bluespice/w/
    # are only available via bind-mount, which must be configured in
    # docker-compose.main.yml before this function is called).
    if ! docker_exec_safe "$wiki_name" \
            "test -f /app/bluespice/w/extensions/SemanticMediaWiki/extension.json" \
            2>/dev/null; then
        log_error "❌ SemanticMediaWiki not visible at /app/bluespice/w/extensions/ — check volume mount"
        return 1
    fi
    if ! docker_exec_safe "$wiki_name" \
            "test -f /app/bluespice/w/extensions/SemanticExtraSpecialProperties/extension.json" \
            2>/dev/null; then
        log_error "❌ SemanticExtraSpecialProperties not visible at /app/bluespice/w/extensions/ — check volume mount"
        return 1
    fi

    log_info "  ✓ Semantic extensions installed and volume mounts verified"
    return 0
}

# ---------------------------------------------------------------------------
# run_smw_update
#   Run MediaWiki's update.php so that SMW's database tables are created,
#   then run SMW's setupStore.php to write the upgrade key (required to
#   clear the "missing valid upgrade key" error on page load).
# ---------------------------------------------------------------------------
run_smw_update() {
    local wiki_name="$1"

    log_info "  🗄️ Running SMW database update (update.php)..."
    if docker_exec_safe "$wiki_name" \
            "php /app/bluespice/w/maintenance/run.php update --quick" 2>/dev/null; then
        log_info "  ✓ SMW database update completed"
    else
        log_warn "  ⚠️ update.php exited non-zero for SMW (may be non-fatal — continuing)"
    fi

    log_info "  🗄️ Running SMW setupStore (initialises SMW store and upgrade key)..."
    if docker_exec_safe "$wiki_name" \
            "php /app/bluespice/w/extensions/SemanticMediaWiki/maintenance/setupStore.php --nochecks" 2>/dev/null; then
        log_info "  ✓ SMW store initialised"
    else
        log_warn "  ⚠️ setupStore.php exited non-zero (may be non-fatal — continuing)"
    fi

    log_info "  🔄 Rebuilding SMW data for User namespace (populates User edit count for #ask queries)..."
    if docker_exec_safe "$wiki_name" \
            "php /app/bluespice/w/extensions/SemanticMediaWiki/maintenance/rebuildData.php --namespace=2 --quiet" 2>/dev/null; then
        log_info "  ✓ User namespace SMW data rebuilt"
    else
        log_warn "  ⚠️ rebuildData.php exited non-zero (may be non-fatal — User edit counts will populate on next page view)"
    fi
}

# ---------------------------------------------------------------------------
# add_semantic_to_post_init_settings
#   Append wfLoadExtension calls (with file_exists guards) to the
#   post-init-settings.php inside the running container.  Writing via
#   docker_exec_safe (always root) avoids host-side permission issues on
#   data-volume files owned by the container user (uid 1002).
#   Idempotent — skips if the block is already present.
#
#   Arguments:
#     wiki_name – wiki instance name (used to docker-exec into the container)
# ---------------------------------------------------------------------------
add_semantic_to_post_init_settings() {
    local wiki_name="$1"
    local container_path="/data/bluespice/post-init-settings.php"

    if ! docker_exec_safe "$wiki_name" \
            "test -f '${container_path}'" 2>/dev/null; then
        log_error "post-init-settings.php not found in container at ${container_path}"
        return 1
    fi

    if docker_exec_safe "$wiki_name" \
            "grep -q 'SemanticMediaWiki' '${container_path}'" 2>/dev/null; then
        log_info "  SemanticMediaWiki already configured in post-init-settings.php — skipping"
        return 0
    fi

    log_info "  Adding SemanticMediaWiki configuration to post-init-settings.php..."

    # Write the PHP block to a host temp file, copy it into the container,
    # then append it to the live settings file.  This avoids quoting hell
    # with heredocs-inside-docker-exec and host permission issues.
    local host_tmp
    host_tmp="$(mktemp /tmp/smw_config_XXXXXX.php)"
    cat > "$host_tmp" << 'SMW_PHP'

# ============================================
# SemanticMediaWiki + SemanticExtraSpecialProperties
# ============================================
# file_exists() guards allow update.php to create DB tables safely and
# handle containers where the extension has not yet been installed.
$smwPath  = '/app/bluespice/w/extensions/SemanticMediaWiki';
$sespPath = '/app/bluespice/w/extensions/SemanticExtraSpecialProperties';

if ( file_exists( $smwPath . '/extension.json' ) ) {
    wfLoadExtension( 'SemanticMediaWiki' );
}

if ( file_exists( $sespPath . '/extension.json' ) ) {
    wfLoadExtension( 'SemanticExtraSpecialProperties' );
    // Enable user edit-count tracking so #ask queries can build contributor leaderboards.
    \$sespgEnabledPropertyList = [ '_USEREDITCNT' ];
}
SMW_PHP

    local container_tmp="/tmp/smw_config_$$.php"
    local ok=true
    if ! docker_copy_to_container "$wiki_name" "$host_tmp" "$container_tmp"; then
        log_error "  ❌ Failed to copy SMW config block into container"
        ok=false
    elif ! docker_exec_safe "$wiki_name" \
            "cat '${container_tmp}' >> '${container_path}' && rm -f '${container_tmp}'"; then
        log_error "  ❌ Failed to append SMW config to ${container_path}"
        docker_exec_safe "$wiki_name" "rm -f '${container_tmp}'" 2>/dev/null || true
        ok=false
    fi

    rm -f "$host_tmp"

    if [[ "$ok" == "false" ]]; then
        return 1
    fi

    log_info "  ✓ SemanticMediaWiki configuration added to post-init-settings.php"
    return 0
}

# ---------------------------------------------------------------------------
# setup_semantic_extensions
#   Top-level orchestrator: install, run update.php, add to post-init settings.
#   Called from initialize-wiki (fresh install) and upgrade-bluespice (reinstall).
#
#   Arguments:
#     wiki_name      – wiki instance name
#     wiki_dir       – host path to wiki config dir (/core/wikis/<name>)
#                      (kept for call-site compatibility; no longer used here)
#     post_init_file – (ignored; kept for backward-compat with upgrade-bluespice)
#                      Settings are written directly into the container via
#                      docker_exec_safe to avoid host permission issues on
#                      data-volume files.
# ---------------------------------------------------------------------------
setup_semantic_extensions() {
    local wiki_name="$1"
    # $2 (wiki_dir) and $3 (post_init_file) accepted but not used — the write
    # now happens inside the container via add_semantic_to_post_init_settings.

    log_info "🚀 Starting Semantic extension setup for ${wiki_name}..."

    local install_ok=true
    if ! install_semantic_extensions "$wiki_name"; then
        log_error "❌ Failed to install Semantic extensions"
        install_ok=false
    fi

    # Run update.php only when extensions were successfully installed so that
    # SMW can register its DB schema.
    if [[ "$install_ok" == "true" ]]; then
        run_smw_update "$wiki_name"
    fi

    # Always attempt to write the wfLoadExtension block to post-init-settings,
    # even when the install step failed.  If the extension files are already on
    # the volume from a prior run the wiki can still load them; and callers
    # (update.php at the end of initialize-wiki, or a later upgrade) will create
    # the DB tables once the extension is visible to MediaWiki.
    if ! add_semantic_to_post_init_settings "$wiki_name"; then
        log_error "❌ Failed to update post-init-settings.php for Semantic extensions"
        return 1
    fi

    if [[ "$install_ok" == "false" ]]; then
        log_warn "⚠️  Extension install had issues — post-init-settings updated but SMW may not load"
        return 1
    fi

    log_info "✅ Semantic extension setup completed successfully"
    return 0
}
