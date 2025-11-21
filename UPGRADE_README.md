# BlueSpice Multi-Wiki Upgrade Guide

This guide explains how to upgrade your BlueSpice multi-wiki installation to newer versions.

## Overview

Your installation uses a **shared infrastructure** architecture:
- **Shared Services**: Single database, search, and cache containers
- **Individual Wikis**: Separate containers for each wiki instance
- **Centralized Upgrade**: All wikis can be upgraded together or individually

## Available Tools

### 1. `check-bluespice-versions`
Displays your current installation status and available versions.

```bash
/core/core_install/check-bluespice-versions
```

**Output includes:**
- Current shared infrastructure version
- Version of each wiki instance
- Available versions on Docker Hub
- Container status

### 2. `upgrade-bluespice`
Performs the actual upgrade process.

```bash
/core/core_install/upgrade-bluespice --version VERSION
```

## Upgrade Process

### Step 1: Check Current Status

```bash
/core/core_install/check-bluespice-versions
```

This shows you:
- Your current version
- Available updates
- Any version mismatches between wikis

### Step 2: Create Backup (Recommended)

Before upgrading, create a backup of your configurations:

```bash
/core/core_install/upgrade-bluespice --backup-only
```

Backups are stored in `/tmp/bluespice-upgrade-TIMESTAMP/`

### Step 3: Perform Upgrade

#### Upgrade Everything (Recommended)

Upgrade shared infrastructure and all wikis:

```bash
/core/core_install/upgrade-bluespice --version 5.1.3
```

#### Upgrade Specific Wiki Only

Upgrade just one wiki instance:

```bash
/core/core_install/upgrade-bluespice --version 5.1.3 --wiki-only mywiki
```

#### Upgrade Wikis Without Shared Services

If shared services are already upgraded:

```bash
/core/core_install/upgrade-bluespice --version 5.1.3 --skip-shared
```

## What Happens During Upgrade

The upgrade process:

1. **Backs up configurations**
   - Saves `.env` files to `/tmp/bluespice-upgrade-TIMESTAMP/`

2. **Pulls new Docker images**
   - `bluespice/wiki:VERSION`
   - `bluespice/helper:VERSION`
   - `bluespice/database:VERSION`
   - `bluespice/search:VERSION`
   - `bluespice/cache:VERSION`

3. **Updates shared infrastructure**
   - Updates version in `/core/core_install/shared/.shared.env`
   - Restarts database, search, and cache containers

4. **Upgrades each wiki**
   - Updates version in `/core/wikis/WIKI_NAME/.env`
   - Runs upgrade pipeline using `bluespice/helper` container
   - The upgrade pipeline:
     - Creates backups at `/bluespice/WIKI_NAME/upgrade_backup/`
     - Upgrades databases
     - Upgrades filesystem
     - Runs MediaWiki update scripts
     - Logs to `/bluespice/WIKI_NAME/logs/backend_upgrade_5.log`

## Rollback

If something goes wrong, you can rollback:

### Restore Configuration Files

```bash
# Restore shared configuration
cp /tmp/bluespice-upgrade-TIMESTAMP/shared.env.backup \
   /core/core_install/shared/.shared.env

# Restore individual wiki
cp /tmp/bluespice-upgrade-TIMESTAMP/WIKI_NAME.env.backup \
   /core/wikis/WIKI_NAME/.env
```

### Restart Containers

After restoring configuration:

```bash
# Restart shared services
cd /core/core_install/shared
docker compose -f docker-compose.persistent-data-services.yml up -d

# Restart wiki
cd /core/wikis/WIKI_NAME
docker compose -f docker-compose.main.yml up -d
```

## Upgrade Options

```
-v, --version VERSION    Target version (required, e.g., 5.1.3)
-f, --force              Force upgrade even if already on target version
-w, --wiki-only WIKI     Upgrade only specific wiki instance
-s, --skip-shared        Skip shared infrastructure upgrade
-b, --backup-only        Only create backups, don't upgrade
-h, --help               Show help message
```

## Examples

### Standard Upgrade

```bash
# Check what's available
/core/core_install/check-bluespice-versions

# Create backup first
/core/core_install/upgrade-bluespice --backup-only

# Perform upgrade
/core/core_install/upgrade-bluespice --version 5.1.3
```

### Upgrade Single Wiki

If you want to test on one wiki first:

```bash
# Upgrade just the test wiki
/core/core_install/upgrade-bluespice --version 5.1.3 --wiki-only test1

# If successful, upgrade the rest
/core/core_install/upgrade-bluespice --version 5.1.3 --skip-shared
```

### Force Re-upgrade

If an upgrade failed partway and you need to retry:

```bash
/core/core_install/upgrade-bluespice --version 5.1.3 --force
```

## Troubleshooting

### Check Upgrade Logs

Each wiki's upgrade is logged:

```bash
# View upgrade log
cat /bluespice/WIKI_NAME/logs/backend_upgrade_5.log

# View upgrade backup
ls -la /bluespice/WIKI_NAME/upgrade_backup/
```

### Check Container Status

```bash
# View all BlueSpice containers
docker ps -a | grep bluespice

# Check specific container logs
docker logs bluespice-WIKI_NAME-wiki-web
docker logs bluespice-database
```

### Verify Database Connection

```bash
# Test database connectivity
docker exec bluespice-database mariadb -uroot -p -e "SHOW DATABASES;"
```

### Manual Maintenance Commands

If you need to run maintenance commands manually:

```bash
# Enter wiki container
docker exec -it bluespice-WIKI_NAME-wiki-web bash

# Inside container
cd /app/bluespice/w

# Run update script
php maintenance/run.php update --quick

# Rebuild search index
php extensions/BlueSpiceExtendedSearch/maintenance/updateWikiPageIndex.php
```

## Best Practices

1. **Always backup before upgrading**
   ```bash
   /core/core_install/upgrade-bluespice --backup-only
   ```

2. **Test on development wiki first**
   ```bash
   /core/core_install/upgrade-bluespice --version VERSION --wiki-only development
   ```

3. **Upgrade during low-traffic period**

4. **Monitor logs during upgrade**
   ```bash
   # In another terminal
   docker logs -f bluespice-WIKI_NAME-wiki-web
   ```

5. **Verify after upgrade**
   ```bash
   /core/core_install/check-bluespice-versions
   ```

## Version Compatibility

- Your system currently uses **BlueSpice 5.1**
- Latest stable: **5.1.3**
- Upcoming: **5.2** (early 2026)

Minor version upgrades (e.g., 5.1 → 5.1.3) are typically safe and recommended.

Major version upgrades (e.g., 5.1 → 5.2) may require additional testing and preparation.

## Getting Help

- Check upgrade logs: `/bluespice/WIKI_NAME/logs/backend_upgrade_5.log`
- Check container logs: `docker logs bluespice-WIKI_NAME-wiki-web`
- View backup location from upgrade output
- BlueSpice documentation: https://en.wiki.bluespice.com/

## Additional Notes

- The upgrade script uses the same upgrade mechanism as `bluespice-deploy`
- Upgrades are non-destructive - backups are created automatically
- Database schema changes are handled by the upgrade pipeline
- Search indices are rebuilt as needed during upgrade
- No downtime is required for shared services if wikis are upgraded individually
