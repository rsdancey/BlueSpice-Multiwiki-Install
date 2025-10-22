#!/bin/bash

# Logrotate configuration helper for BlueSpice wikis
# Provides per-wiki log rotation setup at installation time.

set -euo pipefail

# shellcheck source=./logging.sh
if [ -z "${SCRIPT_DIR:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/..
fi
if [ -f "${SCRIPT_DIR}/lib/logging.sh" ]; then
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/logging.sh"
else
  log_info() { echo "[INFO] $*" >&2; }
  log_warn() { echo "[WARN] $*" >&2; }
  log_error() { echo "[ERROR] $*" >&2; }
fi

# Create per-wiki logrotate config
# Args:
#   $1 - WIKI_NAME
#   $2 - DATA_DIR (host path root for all wikis)
create_wiki_logrotate_config() {
  local wiki_name="${1:-}"
  local data_dir="${2:-}"

  if [[ -z "$wiki_name" || -z "$data_dir" ]]; then
    log_warn "create_wiki_logrotate_config: missing args (wiki_name or data_dir)"
    return 1
  fi

  local logs_glob="${data_dir}/${wiki_name}/logs/*.log"
  local dest="/etc/logrotate.d/bluespice-${wiki_name}"

  # Compose config content
  local tmp
  tmp=$(mktemp)
  cat >"$tmp" <<EOF_INNER
${logs_glob} {
    daily
    rotate 14
    size 50M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF_INNER

  # Install with appropriate permissions; avoid tee per policy
  if [[ -d "/etc/logrotate.d" && -w "/etc/logrotate.d" ]]; then
    install -m 0644 "$tmp" "$dest"
  else
    if command -v sudo >/dev/null 2>&1; then
      if sudo install -m 0644 "$tmp" "$dest"; then
        :
      else
        log_warn "Could not install ${dest} (sudo failed). Temp file left at: $tmp"
        return 1
      fi
    else
      log_warn "Insufficient privileges to write ${dest}. Temp file: $tmp"
      return 1
    fi
  fi

  rm -f "$tmp" || true

  # Validate logrotate syntax if available
  if command -v logrotate >/dev/null 2>&1; then
    if ! logrotate -d "$dest" >/dev/null 2>&1; then
      log_warn "logrotate validation reported issues for ${dest}"
    fi
  fi

  log_info "Installed per-wiki logrotate config: ${dest} -> ${logs_glob}"
}

