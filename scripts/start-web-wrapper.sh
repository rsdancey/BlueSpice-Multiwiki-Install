#!/bin/bash
set -e

init-envs
source /app/.env
substitutePlaceholders /app/bin/config/clamd.conf
init-datadirectory

# Re-apply local fixes to /app, which the image resets on every container create.
# Guarded so a container started against an older /opt/bluespice/scripts (no patch
# script yet) still boots, rather than dying on `set -e`.
if [[ -x /scripts/patch-bluespice.sh ]]; then
    /scripts/patch-bluespice.sh || true
fi

exec /app/bin/start-web
