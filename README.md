# BlueSpice MediaWiki Multi-Wiki Deployment System

BlueSpice is an enhanced MediaWiki distribution developed by [Hallo Welt!](https://bluespice.com/). This system automates deploying and managing multiple isolated BlueSpice wiki instances on a single host using Docker Compose, with shared infrastructure (database, search, cache, proxy) and per-wiki containers.

Repository: https://github.com/rsdancey/BlueSpice-Multiwiki-Install

---

## System Requirements

- Debian/Ubuntu Linux
- `sudo` access
- Docker with the Compose plugin
- `git`, `curl`, `openssl`
- ~5 GB disk space per wiki (minimum)

---

## First-Time Setup

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
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update && sudo apt-get install -y docker-compose-plugin
sudo usermod --append --groups docker "$USER"
```

Log out and back in for the group change to take effect.

### 3. Start shared services

```bash
./setup-shared-services
```

This creates the infrastructure shared by all wikis:

| Service | Container | Role |
|---|---|---|
| MariaDB | `bluespice-database` | One DB server; isolated per-wiki databases and users |
| OpenSearch | `bluespice-search` | Full-text search |
| Memcached | `bluespice-cache` | Object cache |
| Nginx | `bluespice-proxy` | Reverse proxy with Let's Encrypt SSL |

This only needs to be run once.

---

## Creating a Wiki

```bash
./initialize-wiki
```

The interactive wizard prompts for:

- Wiki name (identifier, e.g. `mywiki`)
- Domain name (e.g. `mywiki.example.com`)
- Language
- SMTP settings for outbound email
- SSL preference
- Optional: restore from a database backup and/or image archive

The wizard creates:

| Path | Contents |
|---|---|
| `/core/wikis/WIKI_NAME/.env` | All settings including auto-generated secrets |
| `/core/wikis/WIKI_NAME/docker-compose.main.yml` | Container definition |
| `/core/wikis/WIKI_NAME/pre-init-settings.php` | PHP loaded before BlueSpice initializes |
| `/core/wikis/WIKI_NAME/post-init-settings.php` | PHP loaded after BlueSpice initializes |
| `/bluespice/WIKI_NAME/` | Persistent runtime data (uploads, extensions, logs, cache) |

It also creates a MariaDB database `WIKI_NAME_wiki` and user `WIKI_NAME_user`, then starts the wiki containers.

### Initial admin credentials

Admin username is `WikiSysop`. Retrieve the generated password:

```bash
cat /bluespice/WIKI_NAME/initialAdminPassword
```

---

## Architecture

### Directory layout

```
/core/
  core_install/          # This repo — scripts, libraries, templates
    lib/                 # Bash libraries sourced by the main scripts
    wiki-template/       # docker-compose template for new wikis
    shared/              # Shared services compose files and .shared.env
    BLUESPICE_VERSION    # Canonical target version for new installs
  wikis/
    WIKI_NAME/           # Per-wiki configuration (git-tracked)
      .env
      docker-compose.main.yml
      pre-init-settings.php
      post-init-settings.php

/bluespice/
  WIKI_NAME/             # Per-wiki runtime data (not git-tracked)
    images/              # Uploaded files
    extensions/          # OAuth extensions (PluggableAuth, OpenIDConnect)
    logs/                # Update and install logs
    cache/               # Wiki cache files

/opt/bluespice/
  scripts/               # Container entrypoint wrapper scripts
    start-web-wrapper.sh
    start-task-wrapper.sh
```

### Containers

Each wiki runs two containers:

| Container | Role |
|---|---|
| `bluespice-WIKI_NAME-wiki-web` | Serves HTTP/PHP (php-fpm + nginx) |
| `bluespice-WIKI_NAME-wiki-task` | Runs background jobs (`--runAll`) |

Both containers mount `/bluespice/WIKI_NAME` as `/data/bluespice` inside the container.

### Configuration model

BlueSpice 5.x uses `/app/conf/LocalSettings.php` (referenced via `MW_CONFIG_FILE`) as its settings file. This file is baked into the Docker image and reads all configuration from **environment variables** at runtime — there is no generated `LocalSettings.php`.

Custom settings go in two PHP files on the persistent host volume:

| File | When loaded | Use for |
|---|---|---|
| `pre-init-settings.php` | Before BlueSpice initializes | Low-level overrides |
| `post-init-settings.php` | After BlueSpice initializes | Extensions, SMTP, most customizations |

Host path: `/bluespice/WIKI_NAME/pre-init-settings.php`  
Container path: `/data/bluespice/pre-init-settings.php`

### Startup wrapper scripts

`/app` inside the container is **ephemeral** — it is reset to the image contents on every container recreate (i.e. on every upgrade). The entrypoint wrapper scripts at `/opt/bluespice/scripts/` override the official entrypoint and:

1. Call `init-envs` and source `/app/.env` to populate secrets into the environment
2. Restore OAuth extensions from `/data/bluespice/extensions/` into `/app/bluespice/w/extensions/`
3. Exec the original `start-web` or `start-task` script

### Secrets

Each wiki has three secrets stored in its `.env` and passed to the container:

| Variable | Purpose |
|---|---|
| `INTERNAL_WIKI_SECRETKEY` | `$wgSecretKey` — required for ResourceLoader, sessions, CSRF |
| `INTERNAL_WIKI_UPGRADEKEY` | `$wgUpgradeKey` |
| `INTERNAL_WIKI_TOKEN_AUTH_SALT` | Token authenticator salt |

Generated automatically by `initialize-wiki`. If missing, the wiki UI displays raw `(bs-xxxxx)` placeholder strings instead of translated text.

### OAuth / Google login

`PluggableAuth` and `OpenIDConnect` are installed to `/bluespice/WIKI_NAME/extensions/` and restored into the container on each start by the wrapper scripts.

OAuth client credentials are configured via BlueSpice's ConfigManager UI and stored in the wiki database — not in the `.env` file.

---

## Scripts Reference

| Script | Purpose |
|---|---|
| `initialize-wiki` | Interactive wizard to create a new wiki |
| `setup-shared-services` | Start/update shared infrastructure (run once) |
| `upgrade-bluespice` | Upgrade all or selected wikis to a new version |
| `check-bluespice-versions` | Show running version and container status for all wikis |
| `bluespice-deploy-wiki` | Start/reinstall containers for a specific wiki |
| `import-images.sh` | Import an image archive into a wiki's data volume |
| `smart_db_import.sh` | Import a SQL database dump into a wiki |
| `mediawiki_backup.sh` | Database backup helper |

---

## Common Operations

### Check version status

```bash
./check-bluespice-versions
```

### Upgrade wikis

See [UPGRADE_README.md](UPGRADE_README.md) for full details.

```bash
./upgrade-bluespice                         # auto-detect latest version, all wikis
./upgrade-bluespice --version 5.2.3         # specific version
./upgrade-bluespice --wiki mywiki           # one wiki only
./upgrade-bluespice --dry-run               # preview without changes
```

### Restart a wiki

```bash
docker compose -f /core/wikis/WIKI_NAME/docker-compose.main.yml \
  --env-file /core/wikis/WIKI_NAME/.env restart
```

### Rebuild search index

```bash
docker exec bluespice-WIKI_NAME-wiki-web /app/bin/rebuild-searchindex --main
```

### Run a MediaWiki maintenance script

```bash
docker exec bluespice-WIKI_NAME-wiki-web \
  php /app/bluespice/w/maintenance/run.php SCRIPT [OPTIONS]
```

### Test outbound email

```bash
docker exec bluespice-WIKI_NAME-wiki-web \
  php /app/bluespice/w/maintenance/sendTestEmail.php --to=you@example.com
```

---

## Import Utilities

These run automatically during `initialize-wiki` when restoring from backup, but can be invoked independently.

### Import a database

```bash
./smart_db_import.sh WIKI_NAME /path/to/backup.sql
```

Use a full SQL dump of the wiki database (not a MediaWiki XML export).

### Import images

```bash
./import-images.sh WIKI_NAME /path/to/images.zip
```

The zip should contain the contents of the wiki's `images/` directory.

---

## Backup

```bash
BACKUP_DIR="/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# All databases
DB_ROOT_PASS=$(grep DB_ROOT_PASS /core/core_install/shared/.shared.env | cut -d= -f2)
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
docker logs bluespice-WIKI_NAME-wiki-web
docker logs bluespice-WIKI_NAME-wiki-task

# Shell into container
docker exec -it bluespice-WIKI_NAME-wiki-web bash

# Check running version
docker exec bluespice-WIKI_NAME-wiki-web cat /app/bluespice/w/BLUESPICE-VERSION

# Verify wgSecretKey is set
docker exec bluespice-WIKI_NAME-wiki-web \
  php -r 'echo empty(getenv("INTERNAL_WIKI_SECRETKEY")) ? "MISSING\n" : "OK\n";'
```

### UI shows `(bs-xxxxx)` placeholder strings

`$wgSecretKey` is empty. Check that `INTERNAL_WIKI_SECRETKEY` exists in `/core/wikis/WIKI_NAME/.env` and is passed via the `docker-compose.main.yml` environment section. Run `upgrade-bluespice --wiki WIKI_NAME --force` to regenerate missing secrets.

### Search returns "Query cannot be executed"

The OpenSearch index has stale field mappings. Rebuild it:

```bash
docker exec bluespice-WIKI_NAME-wiki-web /app/bin/rebuild-searchindex --main
```

---

## Contributing

- Lint shell scripts with `shellcheck -S style`
- Lint YAML files with `yamllint`
- Test a complete `initialize-wiki` run before submitting

---

## License

[MIT License](https://opensource.org/license/mit)

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.

---

*Created by Ryan S. Dancey, derived from the BlueSpice deployment system by Hallo Welt!*
