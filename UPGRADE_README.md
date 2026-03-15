# BlueSpice Multi-Wiki Upgrade Guide

**Current version: 5.2.2**

This guide covers upgrading your BlueSpice multi-wiki installation using the `upgrade-bluespice` script. This is a fully homemade upgrade orchestration system — HelloWalt does not provide a multi-wiki upgrade tool.

---

## Quick Reference

```bash
./upgrade-bluespice                        # auto-detect latest version, upgrade all wikis
./upgrade-bluespice --version 5.2.2        # upgrade all wikis to a specific version
./upgrade-bluespice --wiki mywiki          # upgrade only one wiki
./upgrade-bluespice --dry-run              # preview what would happen, no changes
./upgrade-bluespice --force                # re-run upgrade even if already on target version
./upgrade-bluespice --skip-shared          # skip shared services, upgrade wikis only
```

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

For each wiki, `upgrade-bluespice` runs the following steps in order:

### 1. Verify compose file env vars
Ensures these variables are present in the wiki's `docker-compose.main.yml`:
- `DATADIR`
- `WIKI_PRE_INIT_SETTINGS_FILE` / `WIKI_POST_INIT_SETTINGS_FILE`
- `CACHE_HOST` / `CACHE_PORT`

### 1b. Verify INTERNAL_WIKI_* secrets
BlueSpice 5.2.x requires three secrets to be set:

| Variable | Purpose |
|---|---|
| `INTERNAL_WIKI_SECRETKEY` | `$wgSecretKey` — required for ResourceLoader and sessions |
| `INTERNAL_WIKI_UPGRADEKEY` | `$wgUpgradeKey` |
| `INTERNAL_WIKI_TOKEN_AUTH_SALT` | Token authenticator salt |

If any are missing from the wiki's `.env`, the script generates them with `openssl rand -hex 32` and adds them automatically. Without these, the wiki UI shows raw `(bs-xxxxx)` placeholder strings.

### 2. Pull the new Docker image

```
docker pull bluespice/wiki:VERSION
```

### 3. Update `.env`
Backs up the current `.env` to `$BACKUP_DIR`, then updates `VERSION` and `BLUESPICE_WIKI_IMAGE`.

### 4. Pre-create log directories
Creates `preupdate/` and `postupdate/` directories under `/data/bluespice/logs/` before the container starts. The BlueSpice `run-updates` pipeline writes logs here; if they don't exist, it crashes.

### 5. Recreate containers

```
docker compose up -d --force-recreate
```

`/app` inside the container is ephemeral and is wiped here. Persistent data at `/data/bluespice/` (host path: `/bluespice/{WIKI_NAME}/`) is retained.

### 6. Wait for container + fix log ownership
Waits up to 120 seconds for the container to become healthy, then fixes ownership of the log directories so `run-updates` can write to them.

### 7. Run MediaWiki database update

```
php /app/bluespice/w/maintenance/run.php update --quick
```

Applies any database schema changes required by the new version.

### 8. Reinstall OAuth extensions
If OAuth extensions (PluggableAuth, OpenIDConnect) were present on the host volume before the upgrade, they are reinstalled. This is necessary because:
- `/app` is wiped on container recreate
- The startup wrapper scripts restore extensions from `/data/bluespice/extensions/` on each start
- After an upgrade, a fresh reinstall ensures the extension version matches the new BlueSpice version

### 9. Bump wgCacheEpoch
Updates the `$wgCacheEpoch` timestamp in `post-init-settings.php` to bust stale browser and server caches.

### 10. Fix PermissionManagerActivePreset
For Free-edition wikis: if `PermissionManagerActivePreset` is set to `custom` (which is invalid for Free edition), it resets it to `public` to prevent permission errors.

### 11. Rebuild search index
Recreates OpenSearch indices with the current BlueSpice field mappings:

```
/app/bin/rebuild-searchindex --main
```

This is required when a new BlueSpice version adds index fields (e.g. `suggestions-spellcheck` added in 5.2.x). Without it, searches throw `BadRequest400Exception` and the UI shows "Query cannot be executed, please change the search term."

---

## Shared Services Upgrade

Unless `--skip-shared` is specified, the script also upgrades the shared services (MariaDB, OpenSearch, Memcached, Nginx) by:
1. Updating `VERSION` in `/core/core_install/shared/.shared.env`
2. Restarting `docker-compose.persistent-data-services.yml`
3. Restarting `docker-compose.stateless-services.yml` + `docker-compose.proxy.yml` + `docker-compose.proxy-letsencrypt.yml`

Shared services are upgraded **before** wikis so the database is running when `update.php` executes.

---

## All Options

```
-v, --version VERSION   Target version (default: auto-detect from Docker Hub)
-f, --force             Re-run upgrade even if already on target version
-w, --wiki WIKI_NAME    Upgrade only the named wiki (default: all)
-s, --skip-shared       Skip shared services upgrade
-n, --dry-run           Show what would be done without making changes
-h, --help              Show help
```

---

## Examples

### Standard upgrade (auto-detect latest)

```bash
./upgrade-bluespice
```

### Upgrade a single wiki first, then the rest

```bash
# Upgrade shared services + one wiki as a canary
./upgrade-bluespice --version 5.2.3 --wiki mywiki

# If that looks good, upgrade the rest (shared services already done)
./upgrade-bluespice --version 5.2.3 --skip-shared
```

### Retry a failed upgrade

```bash
./upgrade-bluespice --version 5.2.2 --wiki mywiki --force
```

### Preview without changes

```bash
./upgrade-bluespice --version 5.2.3 --dry-run
```

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
3. The startup wrapper scripts at `/opt/bluespice/scripts/` call `init-envs` before restoring OAuth extensions

Run `upgrade-bluespice --force` to regenerate missing secrets and re-run all steps.

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

The startup wrapper scripts restore OAuth extensions from `/bluespice/WIKI_NAME/extensions/`. If the host volume copy is missing or outdated, reinstall:

```bash
./upgrade-bluespice --version 5.2.2 --wiki WIKI_NAME --force
```

Or reinstall manually by running `initialize-wiki` in restore mode, or by calling `install_auth_extensions` from the `oauth-config.sh` library.

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
- The entrypoint wrapper scripts at `/opt/bluespice/scripts/` override the official entrypoint and must:
  1. Call `init-envs` to populate `/app/.env` with secrets
  2. Source `/app/.env` to export the secrets into the shell environment
  3. Restore OAuth extensions from persistent storage
  4. Exec the original `start-web` or `start-task` script
- BlueSpice 5.2.x `LocalSettings.php` is at `/app/conf/LocalSettings.php` and is fully environment-variable driven
