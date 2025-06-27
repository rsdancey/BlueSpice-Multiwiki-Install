# BlueSpice MediaWiki Deployment System

BlueSpice is an enhanced version of [MediaWiki](https://www.mediawiki.org/wiki/MediaWiki). Our thanks to the team at (Hallo Welt!)[https://en.wiki.bluespice.com/wiki/Setup:Installation_Guide] for producing and supporting this amazing piece of software.

This system provides automated deployment and management of BlueSpice MediaWiki instances using Docker containers with proper database isolation.

## System Requirements

- Superuser access (i.e. sudo)
- apt-get or whatever package manager your system uses
- git
- Docker and Docker Compose
- Sufficient disk space for wiki containers and databases

## Overview

Using Docker Containers prepared by the [BlueSpice project](https://en.wiki.bluespice.com/wiki/Setup:Installation_Guide) this installer system will download, install, and configure a system using shared services and individual wikis.

The deployment system creates containerized BlueSpice MediaWiki installations with:
- Individual MySQL databases per wiki
- Isolated database user permissions
- SSL certificate management
- Automated BlueSpice extension configuration
- Wiki and Image import capabilities

## Core Components

### Main Scripts

- **`initialize-wiki`** - Primary deployment script that creates a new wiki instance
- **`bluespice-deploy-wiki`** - Core deployment logic called by initialize-wiki

### Architecture

Each wiki deployment consists of:
- Wiki container: `bluespice-${WIKI_NAME}-wiki-web`
- Database: `${WIKI_NAME}_wiki` 
- Database user: `${WIKI_NAME}_user` (restricted to specific database only)
- SSL certificates: `${WIKI_NAME}.alderac.com`

## Instructions for use

[This Medium article](https://medium.com/p/4cca25c38caf/edit) describes the process and includes directions on setting up a Google Compute VM to host the system.

### Simple Directions

'''bash
./setup-shared-services
'''

This will:
1. Download and check files from the [BlueSpice Project](https://en.wiki.bluespice.com/wiki/Setup:Installation_Guide)
2. Install and configure critical systems shared by all BlueSpice wikis on the system
3. Set global environment variables used by all BlueSpice wikis

```bash
./initialize-wiki <WIKI_NAME>
```

Example:
```bash
./initialize-wiki Test1
```

This will:
1. Create the wiki container `bluespice-Test1-wiki-web`
2. Set up database `Test1_wiki` with isolated user `Test1_user`
3. Configure SSL certificate for `Test1.alderac.com`
4. Install MediaWiki with BlueSpice extensions
5. Apply socket-based database connectivity
6. Generate admin credentials

### Access Your Wiki

- URL: `https://${WIKI_NAME}.alderac.com`
- Admin username: `WikiSysop`
- Admin password: Retrieved via `docker exec bluespice-${WIKI_NAME}-wiki-web cat /data/bluespice/initialAdminPassword`

You should not need other usernames or passwords used by the installer or the wikis but if you do you can find them in the .env and .shared.env files created by the installer system; there is an .env file in the /wikis/${WIKI_NAME} subdirectory for each wiki


### Security Best Practices
1. Regularly update Docker images: docker compose pull
2. Monitor container logs for suspicious activity
3. Use strong, unique passwords for all services
4. Keep SSL certificates current and valid
5. Implement proper firewall rules
6. Regular security audits of exposed services
7. Backup configuration and data regularly

### Backup and Recovery
#### Backup Strategy
'''bash

BACKUP_DIR="/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

docker exec bluespice-database mysqldump -u root -p"$DB_ROOT_PASS" \
  --all-databases --single-transaction > "$BACKUP_DIR/database.sql"

for wiki in /core/wikis/*/; do
  wiki_name=$(basename "$wiki")
  tar -czf "$BACKUP_DIR/${wiki_name}_data.tar.gz" "/data/bluespice/$wiki_name/"
  cp "$wiki/.env" "$BACKUP_DIR/${wiki_name}.env"
done

tar -czf "$BACKUP_DIR/configuration.tar.gz" \
  /core/core_install/ \
  /core/wikis/ \
  --exclude='*/data/*'
'''

#### Recovery Process

Stop all services:

'''bash
./bluespice-shared-services down
'''

Restore database:

'''bash
docker exec -i bluespice-database mysql -u root -p < backup/database.sql
Restore data directories:

tar -xzf backup/wiki_data.tar.gz -C /

tar -xzf backup/configuration.tar.gz -C /
'''

Restart all services and wiki

'''bash
./setup-shared-services
./bluespice-deploy-wiki --wiki-name=<wiki-name>
'''

### Upgrade Pipeline:

# Standard upgrade
'''bash
./bluespice-deploy-wiki --wiki-name=MyWiki --profile=upgrade
'''

# Force upgrade (skip compatibility checks)
'''bash
./bluespice-deploy-wiki --wiki-name=MyWiki --profile=upgrade-force
'''

## Database Architecture

### User Isolation
Each wiki has a dedicated MySQL user with permissions restricted to only their specific database:

This prevents MediaWiki's installer from detecting tables in other wikis' databases.

## Utility Scripts

These scripts are run as a part of the initialize-wiki system if you choose options involving imports but you can run them independently if you want to migrate content from another wiki after you have completed the setup process.

## Database Management

### Import Database

```bash
./smart_db_import.sh <WIKI_NAME> <SQL_FILE>
```

Features:
- Automatic database backup before import
- SQL file validation
- Progress monitoring
- Rollback capability on failure

To make the SQL_FILE, do a total backup of SQL from your wiki's database (i.e. don't use the MediaWiki's native export utility).

## Image Management

### Import Images from Archive

```bash
./import-images.sh <WIKI_NAME> <IMAGES_ZIP_FILE>
```

Features:
- Automatic backup of existing images
- ZIP file validation
- Safe extraction with conflict handling
- MediaWiki database synchronization via importImages.php
- Colored status output
- Interactive and command-line modes

Example:
```bash
./import-images.sh Test1 /path/to/images.zip
```

To make the IMAGES_ZIP_FILE, zip the /images directory in the root of your wiki's filesystem.

### Debugging Commands

```bash
# Check container status
docker ps | grep bluespice-${WIKI_NAME}

# View container logs
docker logs bluespice-${WIKI_NAME}-wiki-web

# Access container shell
docker exec -it bluespice-${WIKI_NAME}-wiki-web /bin/sh

# Retrieve admin password
docker exec bluespice-${WIKI_NAME}-wiki-web cat /data/bluespice/initialAdminPassword
```

## Pre-init and Post-init files

BlueSpice does not use MediaWiki's LocalSettings.php file. Instead there are two files you can manipulate, both inside the wiki-web container for your wiki, located at /data/bluespice

* pre-init-settings.php
* post-init-settings.php

Most of the commonplace changes you would make to a normal MediaWiki's default LocalSettings.php to customize your wiki's functions go in post-init.

In particular this file has the settings for your outbound SMTP email. If you need to adjust those settings you need to do it in post-init.

You can also add and load Extensions here if you wish to use them; you will install the extensions in the normal way.

---

This Deployment System was created by Ryan S. Dancey and is derived from the BlueSpice deployment system created by Hallo Walt!.

You can access the git repository for this project [here](https://github.com/rsdancey/BlueSpice-Multiwiki-Install?tab=readme-ov-file).

## Contributing
We welcome contributions! Please follow these guidelines:

### Development Setup
* Fork the repository
* Clone your fork locally
* Create a feature branch (git checkout -b feature/amazing-feature)
* Test changes in a development environment

### Code Standards
* Shell Scripts: Use shellcheck for linting
* YAML Files: Use yamllint for validation
* Docker: Follow Docker best practices
* Documentation: Update README for new features

### Testing Checklist
* All scripts pass shellcheck linting
* All YAML files pass yamllint validation
* Fresh installation works correctly
* Existing wiki deployment works
* Shared services start properly
* SSL certificates generate correctly
* Database connectivity functions
* Email configuration works

###Submission Process
* Commit your changes (git commit -m 'Add amazing feature')
* Push to the branch (git push origin feature/amazing-feature)
* Open a Pull Request with detailed description

# License
This project is licensed under the [MIT License](https://opensource.org/license/mit)

# WARRANTY NOTICE

***THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.***