# BlueSpice Multi-Wiki Upgrade Guide

This guide covers upgrading your BlueSpice multi-wiki installation using the `upgrade-bluespice` script. This is a custom upgrade orchestration system — Hallo Welt! does not provide a multi-wiki upgrade tool.

---

## Quick Reference

```bash
./upgrade-bluespice
```

The script is fully interactive. It will:

1. Auto-detect the latest BlueSpice version from Docker Hub
2. Ask whether to upgrade **shared services** or a **single wiki**
3. For a wiki upgrade: list available wikis, then ask whether to install or remove each optional extension:
   - OAuth / Google login (PluggableAuth + OpenIDConnect)
   - Google Analytics (GTag)
   - Semantic Web (SemanticMediaWiki + SESP)
4. Perform the upgrade, installing or actively removing each extension as requested

---

## Before You Start

```bash
# Check current status
./check-bluespice-versions
```

This shows the running version and container status for every wiki.

### Pre-upgrade database backup (recommended)

```bash
DB_ROOT_PASS=$(grep DB_ROOT_PASS /core/core_install/shared/.shared.env | cut -d= -f2)
docker exec bluespice-database \
  mariadb-dump -uroot -p"$DB_ROOT_PASS" --all-databases --single-transaction \
  > /backup/pre-upgrade-$(date +%Y%m%d).sql
```

The upgrade script automatically backs up each wiki's `.env` file to `/tmp/bluespice-upgrade-TIMESTAMP/` before making changes.

---

## Upgrade Process (what the script does)

For the selected wiki, `upgrade-bluespice` runs the following steps in order:

### 0. Remove unwanted extensions
If the user answered **no** to an extension that is currently installed, its files are removed from the host volume and its configuration block is removed from `post-init-settings.php` **before** the container is recreated. This ensures the new container starts clean without loading the removed extension.

| Extension | What is removed |
|---|---|
| **OAuth** | `/bluespice/WIKI_NAME/extensions/PluggableAuth/` and `OpenIDConnect/` (OAuth credentials stored in the database are not touched — disable OAuth via ConfigManager if needed) |
| **GTag** | `/bluespice/WIKI_NAME/extensions/GTag/`, the GTag config block from `post-init-settings.php`, and `GTAG_ANALYTICS_ID` from `.env` |
| **Semantic** | `/bluespice/WIKI_NAME/extensions/SemanticMediaWiki/` and `SemanticExtraSpecialProperties/`, and the SMW/SESP config block from `post-init-settings.php` |

### 1. Verify compose file env vars
Ensures these variables are present in the wiki's `docker-compose.main.yml` (adds them if missing):
- `DATADIR`, `WIKI_PRE_INIT_SETTINGS_FILE`, `WIKI_POST_INIT_SETTINGS_FILE`
- `WIKI_PORT`, `CACHE_HOST`, `CACHE_PORT`, `DB_TYPE`
- `INTERNAL_WIRE_API_KEY`

### 1b. Verify INTERNAL_WIKI_* secrets
BlueSpice 5.2.x requires four secrets:

| Variable | Purpose |
|---|---|
| `INTERNAL_WIKI_SECRETKEY` | `$wgSecretKey` — required for ResourceLoader and sessions |
| `INTERNAL_WIKI_UPGRADEKEY` | `$wgUpgradeKey` |
| `INTERNAL_WIKI_TOKEN_AUTH_SALT` | Token authenticator salt |
| `INTERNAL_WIRE_API_KEY` | Wire collaboration service API key |

Any missing from the wiki's `.env` are generated with `openssl rand -hex 32` and added automatically. Without these, the wiki UI shows raw `(bs-xxxxx)` placeholder strings.

### 1c. Verify extension volume mounts
Ensures bind-mounts for all five extension directories appear in `docker-compose.main.yml` (adds them if missing). The mounts are always added regardless of whether the extension is installed — `file_exists()` guards in `post-init-settings.php` prevent loading when the directory is empty.

### 1d. Verify tmpfs mounts
Ensures `/tmp/wiki` tmpfs entries are configured for both `wiki-web` and `wiki-task` services.

### 2. Pull the new Docker image

```
docker pull bluespice/wiki:VERSION
```

### 3. Update `.env`
Backs up the current `.env` to `$BACKUP_DIR`, then updates `VERSION` and `BLUESPICE_WIKI_IMAGE`. Also adds `DB_TYPE`, `CACHE_HOST`, and `CACHE_PORT` if missing.

### 4. Pre-create log directories
Creates `preupdate/` and `postupdate/` directories under `/bluespice/WIKI_NAME/logs/` before the container starts. The BlueSpice `run-updates` pipeline writes logs here; if they don't exist, it crashes.

### 5. Recreate containers

```
docker compose up -d --force-recreate
```

`/app` inside the container is ephemeral and is wiped here. Persistent data at `/data/bluespice/` (host path: `/bluespice/WIKI_NAME/`) is retained.

### 6. Wait for container + fix log ownership
Waits up to 120 seconds for the container to become healthy, then fixes ownership of the log directories so `run-updates` can write to them. Also ensures `post-init-settings.php` is group-writable so the upgrade script can modify it.

### 7a. Clean up ContentProvisioner blob data
Removes orphaned blob references left by prior partial runs of the ContentProvisioner (e.g. template pages with missing subpage slots). Resets the ContentProvisioner `updatelog` entry so it re-runs cleanly. This prevents `update.php` from failing on stale content.

### 7b. Run MediaWiki database update

```
php /app/bluespice/w/maintenance/run.php update --quick
```

Applies any database schema changes required by the new version.

### 8. Install / reinstall extensions
Extensions the user answered **yes** to are installed (or reinstalled if already present). All install functions are idempotent.

| Extension | Action |
|---|---|
| **OAuth** | Downloads and installs PluggableAuth + OpenIDConnect; runs Composer for OpenIDConnect dependencies |
| **GTag** | Downloads and installs the GTag extension; prompts for the analytics ID if not already in `.env`; writes the config block to `post-init-settings.php` |
| **Semantic** | Downloads SemanticMediaWiki + SESP via Composer; runs `update.php` and `setupStore.php`; writes the SMW/SESP config block to `post-init-settings.php`; rebuilds semantic data |

### 9. Bump wgCacheEpoch
Updates the `$wgCacheEpoch` timestamp in `post-init-settings.php` to bust stale browser and server caches.

### 10. Re-enable wire WebSocket URL
Removes any `mwsgWireServiceWebsocketUrl=''` override added by older installer versions. The wire collaboration container is now always deployed, so the override is no longer needed.

### 11. Enable parser cache
Adds `$GLOBALS['wgParserCacheType'] = CACHE_MEMCACHED` to `post-init-settings.php` if not already set. The BlueSpice container image defaults to `CACHE_NONE`, forcing a full wikitext re-parse on every page view. Enabling memcached here significantly reduces page load times.

### 12. Fix PermissionManagerActivePreset
For Free-edition wikis: if `PermissionManagerActivePreset` is set to `custom` (which is invalid for Free edition), it resets it to `public` to prevent permission errors.

### 13. Rebuild search index
Recreates OpenSearch indices with the current BlueSpice field mappings:

```
/app/bin/rebuild-searchindex --main
```

Required when a new BlueSpice version adds index fields (e.g. `suggestions-spellcheck` added in 5.2.x). Without this, searches throw `BadRequest400Exception` and the UI shows "Query cannot be executed, please change the search term."

---

## Shared Services Upgrade

When you select **shared services** at the prompt, the script:

1. Updates `VERSION` in `/core/core_install/shared/.shared.env`
2. Restarts `docker-compose.persistent-data-services.yml`
3. Restarts `docker-compose.stateless-services.yml` + `docker-compose.proxy.yml` + `docker-compose.proxy-letsencrypt.yml`

Always upgrade shared services before upgrading any wiki, so the database is running when `update.php` executes.

---

## Standard Workflow

### Upgrade shared services first, then each wiki

```bash
# Run once to upgrade shared infrastructure
./upgrade-bluespice
# → choose: 1) Shared services

# Run once per wiki
./upgrade-bluespice
# → choose: 2) A wiki
# → select the wiki by number
# → answer y/n for OAuth, GTag, Semantic Web
```

### Re-run if the wiki is already on the target version

The script will warn you and ask for confirmation before proceeding. Answer `y` to continue.

---

## Rollback

If an upgrade fails:

### 1. Restore the `.env` file

```bash
# Backup path is printed in the upgrade summary
cp /tmp/bluespice-upgrade-TIMESTAMP/WIKI_NAME.env.bak \
   /core/wikis/WIKI_NAME/.env
```

### 2. Bring the old image back up

```bash
docker compose -f /core/wikis/WIKI_NAME/docker-compose.main.yml \
  --env-file /core/wikis/WIKI_NAME/.env \
  up -d --force-recreate
```

### 3. Restore the database if needed

```bash
DB_ROOT_PASS=$(grep DB_ROOT_PASS /core/core_install/shared/.shared.env | cut -d= -f2)
docker exec -i bluespice-database \
  mariadb -uroot -p"$DB_ROOT_PASS" \
  < /backup/pre-upgrade-YYYYMMDD.sql
```

---

## Troubleshooting

### UI shows `(bs-xxxxx)` placeholder strings

`$wgSecretKey` is empty. The INTERNAL_WIKI_SECRETKEY secret is missing from the container environment. Check that:

1. The secret exists in `/core/wikis/WIKI_NAME/.env`
2. The `docker-compose.main.yml` passes it via the environment section
3. The startup wrapper scripts at `/opt/bluespice/scripts/` call `init-envs` and source `/app/.env`

Re-run `./upgrade-bluespice`, select the affected wiki, and answer `y` when asked whether to proceed despite already being on the target version. This regenerates missing secrets and re-runs all upgrade steps.

### Search returns "Query cannot be executed"

The OpenSearch index was built with old field mappings. Rebuild it:

```bash
docker exec bluespice-WIKI_NAME-wiki-web /app/bin/rebuild-searchindex --main
```

### Container fails to start after upgrade

```bash
docker logs bluespice-WIKI_NAME-wiki-web
docker logs bluespice-WIKI_NAME-wiki-task
```

Common cause: `run-updates` crashing because log directories don't exist. Create them manually:

```bash
mkdir -p /bluespice/WIKI_NAME/logs/preupdate /bluespice/WIKI_NAME/logs/postupdate
docker exec --user root bluespice-WIKI_NAME-wiki-web \
  chown 1002:bluespice /data/bluespice/logs/preupdate /data/bluespice/logs/postupdate
```

### OAuth login broken after upgrade

OAuth extensions are mounted from `/bluespice/WIKI_NAME/extensions/` via the volume mounts in `docker-compose.main.yml`. If the host volume copy is missing or outdated, re-run `./upgrade-bluespice`, select the affected wiki, answer `y` to OAuth, and `y` when asked whether to proceed despite already being on the target version.

Alternatively, reinstall manually by calling `install_auth_extensions` from the `oauth-config.sh` library.

### Check what version is actually running

```bash
docker exec bluespice-WIKI_NAME-wiki-web cat /app/bluespice/w/BLUESPICE-VERSION
```

### Verify wgSecretKey is set in a running container

```bash
docker exec bluespice-WIKI_NAME-wiki-web \
  php -r 'echo empty(getenv("INTERNAL_WIKI_SECRETKEY")) ? "MISSING\n" : "OK\n";'
```

---

## Container Architecture Notes

- `/app` inside the container is **ephemeral** — it is reset to the image contents on every `docker compose up --force-recreate`
- `/data/bluespice/` (container) = `/bluespice/WIKI_NAME/` (host) — this is the **persistent** volume
- The entrypoint wrapper scripts at `/opt/bluespice/scripts/` (shipped in the repo under `scripts/`, installed by `bluespice-deploy-wiki`) override the official entrypoint and:
  1. Call `init-envs` to populate `/app/.env` with secrets
  2. Source `/app/.env` to export the secrets into the shell environment
  3. Run `substitutePlaceholders` and `init-datadirectory` to prepare config and data
  4. Exec the original `start-web` or `start-task` script
- OAuth extensions are restored from persistent storage via the volume mounts in `docker-compose.main.yml`, not by the wrapper scripts
- BlueSpice 5.2.x `LocalSettings.php` is at `/app/conf/LocalSettings.php` and is fully environment-variable driven
