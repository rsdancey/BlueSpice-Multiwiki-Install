#!/bin/bash
set -e

init-envs
source /app/.env
substitutePlaceholders /app/bin/config/clamd.conf
init-datadirectory

exec /app/bin/start-web
