# BlueSpice MediaWiki Multi-Wiki Deployment System

BlueSpice is an enhanced version of [MediaWiki](https://www.mediawiki.org/wiki/MediaWiki), developed by [Hallo Welt!](https://bluespice.com/). This system provides automated deployment and management of multiple BlueSpice wiki instances on a single host using Docker, with shared infrastructure and isolated per-wiki containers.

**Current BlueSpice version: 5.2.2**

---

## System Requirements

- Debian/Ubuntu Linux (or compatible)
- `sudo` access
- Docker and Docker Compose plugin
- `git`, `curl`, `openssl`
- Sufficient disk space (~5 GB per wiki minimum)

---

## Initial Setup

### 1. Clone the repository

```bash
sudo mkdir -p /core
sudo chgrp $(whoami) /core
sudo chmod 775 /core
cd /core
git clone https://github.com/rsdancey/BlueSpice-Multiwiki-Install.git core_install
cd core_install
```

### 2. Install Docker

```bash
sudo apt-get install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update && sudo apt-get install docker-compose-plugin
sudo usermod --append --groups docker $USER
```

Log out and back in for the group change to take effect.

### 3. Set up shared services

```bash
./setup-shared-services
```

This creates and starts the infrastructure shared by all wikis:
- **MariaDB** (`bluespice-database`) — one database server for all wikis, with isolated per-wiki databases and users
- **OpenSearch** (`bluespice-search`) — full-text search
- **Memcached** (`bluespice-cache`) — object caching
- **Nginx** (`bluespice-proxy`) — reverse proxy with Let's Encrypt SSL

This only needs to be run once.

---

## Creating a Wiki

```bash
./initialize-wiki
```

The interactive wizard will ask for:
- Wiki name (used as an identifier, e.g. `mywiki`)
- Domain name (e.g. `mywiki.example.com`)
- Language
- SMTP settings for outbound email
- SSL preference

The script creates:
- `/core/wikis/{WIKI_NAME}/` — wiki configuration directory
- `/core/wikis/{WIKI_NAME}/.env` — all settings including auto-generated secrets
- `/core/wikis/{WIKI_NAME}/docker-compose.main.yml` — container definition
- `/core/wikis/{WIKI_NAME}/pre-init-settings.php` — PHP loaded before BlueSpice initializes
- `/core/wikis/{WIKI_NAME}/post-init-settings.php` — PHP loaded after BlueSpice initializes
- MariaDB database `{WIKI_NAME}_wiki` and user `{WIKI_NAME}_user`
- Two Docker containers: `bluespice-{WIKI_NAME}-wiki-web` and `bluespice-{WIKI_NAME}-wiki-task`

### Initial admin credentials

```bash
# Admin username is WikiSysop
# Retrieve the generated password:
cat /core/wikis/{WIKI_NAME}/admin_password.txt
```

---

## Architecture

### Directory layout

```
/core/
  core_install/          # This repository — scripts and templates
    lib/                 # Shared bash libraries
    wiki-template/       # Template for new wiki docker-compose files
    shared/              # Shared services compose files and .shared.env
  wikis/
    {WIKI_NAME}/         # Per-wiki configuration (git-tracked)
      .env               # All settings for this wiki
      docker-compose.main.yml
      pre-init-settings.php
      post-init-settings.php

/bluespice/
  {WIKI_NAME}/           # Per-wiki runtime data (not git-tracked)
    images/              # Uploaded files
    extensions/          # OAuth extensions (PluggableAuth, OpenIDConnect)
    logs/                # Update and install logs
    cache/               # Wiki cache files

/opt/bluespice/
  scripts/               # Container startup wrapper scripts
    start-web-wrapper.sh
    start-task-wrapper.sh
```

### Container architecture

Each wiki has two containers:

| Container | Role |
|---|---|
| `bluespice-{NAME}-wiki-web` | Serves HTTP/PHP via php-fpm + nginx |
| `bluespice-{NAME}-wiki-task` | Runs background jobs (`--runAll`) |

Both containers mount `/bluespice/{WIKI_NAME}` as `/data/bluespice` inside the container.

### Container startup (5.2.x)

The official BlueSpice 5.2.x container image uses `/app/bin/entrypoint` → `init-envs` → `start-web`/`start-task`. Our deployment overrides the entrypoint with wrapper scripts at `/opt/bluespice/scripts/` that:

1. Call `init-envs` and source `/app/.env` (mirrors the official entrypoint)
2. Restore OAuth extensions from the persistent host volume to `/app/bluespice/w/extensions/`
3. Exec the original `start-web` or `start-task` script

This is necessary because `/app` inside the container is ephemeral — it is reset to the image contents on every container recreate (i.e. on every upgrade).

### Configuration files (5.2.x)

BlueSpice 5.2.x uses `/app/conf/LocalSettings.php` (set via `MW_CONFIG_FILE`) rather than the standard MediaWiki `LocalSettings.php` location. This file is fully environment-variable driven and reads configuration from the container's environment at runtime.

Custom settings go in the two init files stored on the persistent host volume:

- **`pre-init-settings.php`** — loaded before BlueSpice initializes; use for low-level overrides
- **`post-init-settings.php`** — loaded after BlueSpice initializes; use for extensions, SMTP, and most customizations

These files are at `/bluespice/{WIKI_NAME}/pre-init-settings.php` (host) = `/data/bluespice/pre-init-settings.php` (container).

### Secrets

Each wiki has three auto-generated secrets stored in its `.env` file and passed to the container via docker-compose:

| Variable | Purpose |
|---|---|
| `INTERNAL_WIKI_SECRETKEY` | MediaWiki `$wgSecretKey` — required for ResourceLoader, sessions, and CSRF protection |
| `INTERNAL_WIKI_UPGRADEKEY` | MediaWiki `$wgUpgradeKey` |
| `INTERNAL_WIKI_TOKEN_AUTH_SALT` | Token authenticator salt |

These are generated automatically by `initialize-wiki`. **If they are missing or empty, the wiki UI will display raw message keys like `(bs-xxxxx)` instead of translated strings.**

### OAuth / Google login

`PluggableAuth` and `OpenIDConnect` extensions are installed to the persistent host volume at `/bluespice/{WIKI_NAME}/extensions/`. The startup wrapper scripts copy them into the container's `/app` path on each start.

OAuth client credentials are configured via BlueSpice's ConfigManager UI and stored in the wiki database — they are **not** stored in the `.env` file.

---

## Managing Wikis

### Check version status

```bash
./check-bluespice-versions
```

Shows current version, container status, and available updates for all wikis.

### Upgrade all wikis

See [UPGRADE_README.md](UPGRADE_README.md) for full details.

```bash
./upgrade-bluespice                     # auto-detect latest version
./upgrade-bluespice --version 5.2.2     # specific version
./upgrade-bluespice --wiki mywiki       # single wiki only
./upgrade-bluespice --dry-run           # preview without changes
```

### Restart a wiki

```bash
docker compose -f /core/wikis/{WIKI_NAME}/docker-compose.main.yml \
  --env-file /core/wikis/{WIKI_NAME}/.env restart
```

### Rebuild search index

```bash
docker exec bluespice-{WIKI_NAME}-wiki-web /app/bin/rebuild-searchindex --main
```

### Run MediaWiki maintenance

```bash
docker exec bluespice-{WIKI_NAME}-wiki-web \
  php /app/bluespice/w/maintenance/run.php {SCRIPT} [OPTIONS]
```

---

## Import Utilities

These are run automatically by `initialize-wiki` when restoring from backup, but can also be run independently.

### Import a database

```bash
./smart_db_import.sh {WIKI_NAME} /path/to/backup.sql
```

Use a full SQL dump of the wiki database (not MediaWiki's XML export).

### Import images

```bash
./import-images.sh {WIKI_NAME} /path/to/images.zip
```

The zip should contain the contents of the wiki's `/images` directory.

---

## Backup

```bash
BACKUP_DIR="/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Database
docker exec bluespice-database \
  mariadb-dump -uroot -p"$DB_ROOT_PASS" --all-databases --single-transaction \
  > "$BACKUP_DIR/all-databases.sql"

# Per-wiki runtime data and config
for wiki in /core/wikis/*/; do
  name=$(basename "$wiki")
  tar -czf "$BACKUP_DIR/${name}-data.tar.gz" "/bluespice/$name/"
  cp "$wiki/.env" "$BACKUP_DIR/${name}.env"
done

# Configuration repo
tar -czf "$BACKUP_DIR/core_install.tar.gz" /core/core_install/ /core/wikis/
```

---

## Debugging

```bash
# Container status
docker ps | grep bluespice

# Container logs
docker logs bluespice-{WIKI_NAME}-wiki-web
docker logs bluespice-{WIKI_NAME}-wiki-task

# Shell into container
docker exec -it bluespice-{WIKI_NAME}-wiki-web bash

# Check what version is running
docker exec bluespice-{WIKI_NAME}-wiki-web cat /app/bluespice/w/BLUESPICE-VERSION

# Verify wgSecretKey is set
docker exec bluespice-{WIKI_NAME}-wiki-web \
  php -r 'echo empty(getenv("INTERNAL_WIKI_SECRETKEY")) ? "MISSING\n" : "OK\n";'
```

---

## Contributing

- Shell scripts: lint with `shellcheck`
- YAML files: lint with `yamllint`
- Test a fresh `initialize-wiki` run in a development environment before submitting

---

## License

[MIT License](https://opensource.org/license/mit)

**THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.**

---

*This deployment system was created by Ryan S. Dancey, derived from the BlueSpice deployment system by Hallo Welt!*
*Repository: https://github.com/rsdancey/BlueSpice-Multiwiki-Install*
