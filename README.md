# BlueSpice MediaWiki Multi-Wiki Installation

A Docker-based deployment system for BlueSpice MediaWiki with support for multiple wiki instances and shared services infrastructure.

## Overview

This project provides a complete containerized environment for running BlueSpice MediaWiki installations with:

- **Multiple independent wiki instances** - Deploy and manage multiple wikis
- **Shared services architecture** - Database, proxy, SSL certificates, and caching
- **Automated deployment** - Interactive setup wizards and configuration management
- **SSL/TLS automation** - Let's Encrypt certificate management
- **Data persistence** - Reliable storage for wiki content and configurations

## Prerequisites

- **Docker** and **Docker Compose** (recent versions)
- **Git** for repository management
- **Domain name** with DNS properly configured to point to your server
- **Email account** for SMTP notifications (optional but recommended)
- **Linux server** with sufficient resources (2GB+ RAM recommended)

## Quick Start

### 1. Clone and Setup

```bash
# Clone the repository
git clone <repository-url>
cd core_install

# Make scripts executable
chmod +x *.sh setup-shared-services bluespice-* initialize-wiki
```

### 2. Initialize Shared Services

```bash
# Set up shared infrastructure (database, proxy, SSL)
./setup-shared-services
```

This will:
- Create shared services configuration
- Set up Docker networking
- Deploy database, cache, proxy, and SSL services
- Create the shared environment file with database credentials

### 3. Deploy Your First Wiki

```bash
# Interactive wiki setup wizard
./initialize-wiki
```

The wizard will prompt for:
- Wiki name (alphanumeric, dots, dashes, underscores)
- Domain name (e.g., wiki.example.com)
- Language preference
- SSL certificate setup (recommended)

## Architecture

### System Components

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Wiki Instance │    │   Wiki Instance │    │   Wiki Instance │
│   (Container)   │    │   (Container)   │    │   (Container)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
┌────────────────────────────────────────────────────────────────┐
│                    Shared Services Layer                       │
├─────────────────┬─────────────────┬─────────────────┬─────────┤
│   Database      │   Proxy/SSL     │   Cache (Redis) │  Other  │
│  (MariaDB)      │ (nginx/certbot) │                 │         │
└─────────────────┴─────────────────┴─────────────────┴─────────┘
```

### Directory Structure

```
core_install/
├── initialize-wiki              # Interactive wiki setup wizard
├── setup-shared-services        # Shared services initialization
├── bluespice-deploy-wiki        # Wiki deployment engine
├── bluespice-shared-services    # Shared services management
├── .global.env                  # Global configuration
├── .gitignore                   # Git ignore rules
├── shared/                      # Shared services configuration
│   ├── .shared.env             # Shared database & SSL config
│   ├── docker-compose.*.yml    # Service definitions
│   └── ...
├── wiki-template/               # Template files for new wikis
│   ├── .env.template           # Wiki configuration template
│   ├── docker-compose.*.yml    # Wiki service templates
│   └── ...
└── wikis/                       # Individual wiki instances (auto-created)
    ├── <wiki-name>/
    │   ├── .env                # Wiki-specific configuration
    │   ├── docker-compose.yml  # Wiki services
    │   └── data/               # Wiki data persistence
    └── ...
```

## Configuration Files

### Global Environment (.global.env)

Contains system-wide settings:
```env
VERSION=5.1
EDITION=free
LETSENCRYPT_EMAIL=admin@yourdomain.com
```

### Shared Environment (shared/.shared.env)

**Auto-created** by `setup-shared-services` with:
- Database root credentials (auto-detected)
- SSL/TLS configuration
- Let's Encrypt settings
- Resource limits

### Per-Wiki Environment (wikis/<name>/.env)

**Auto-created** by `initialize-wiki` with:
- Wiki-specific database credentials (auto-generated)
- Domain and SSL settings
- SMTP configuration
- Container settings

## Email Configuration

The system supports SMTP email for notifications and password resets.

### Supported Providers

- **Office 365**: `smtp.office365.com:587`
- **Gmail**: `smtp.gmail.com:587` (requires app password)
- **Custom SMTP**: Any standard SMTP server

### Configuration

SMTP settings can be configured per-wiki in the `.env` file:
```env
SMTP_HOST=smtp.office365.com
SMTP_PORT=587
SMTP_USER=wiki@yourdomain.com
SMTP_PASS=your-password
SMTP_ID_HOST=yourdomain.com
```

## Management Commands

### Shared Services Management

```bash
# Start all shared services
./bluespice-shared-services start

# Stop shared services
./bluespice-shared-services stop

# Restart services
./bluespice-shared-services restart

# View service status
./bluespice-shared-services status

# View logs
./bluespice-shared-services logs [service-name]
```

### Wiki Management

```bash
# Deploy new wiki (interactive)
./initialize-wiki

# Deploy wiki with specific settings
./bluespice-deploy-wiki --wiki-name=mywiki --domain=wiki.example.com --fresh-install

# Update existing wiki
./bluespice-deploy-wiki --wiki-name=mywiki --domain=wiki.example.com --run-update
```

### Container Operations

```bash
# View all BlueSpice containers
docker ps | grep bluespice

# View wiki logs
docker logs bluespice-<wiki-name>-wiki-web

# Access wiki container
docker exec -it bluespice-<wiki-name>-wiki-web bash

# Database access
docker exec -it bluespice-database mysql -u root -p
```

## SSL/TLS Certificates

SSL certificates are automatically managed via Let's Encrypt:

- **Automatic generation** for new wiki domains
- **Automatic renewal** (checked every hour)
- **HTTPS redirect** enabled by default
- **Modern SSL policies** (TLS 1.2+)

### SSL Certificate Management

```bash
# Check certificate status for a domain
docker exec bluespice-letsencrypt-service \
  openssl x509 -in /etc/nginx/certs/wiki.example.com.crt -noout -dates

# Force certificate renewal
docker exec bluespice-letsencrypt-service \
  /app/force_renew
```

## Database Management

### Database Access

```bash
# Connect to database
docker exec -it bluespice-database mysql -u root -p

# View all databases
docker exec bluespice-database mysql -u root -p -e "SHOW DATABASES;"
```

### Backup and Restore

```bash
# Create full backup
docker exec bluespice-database mysqldump -u root -p --all-databases > backup.sql

# Restore from backup
docker exec -i bluespice-database mysql -u root -p < backup.sql

# Backup specific wiki database
docker exec bluespice-database mysqldump -u root -p <wiki_name>_wiki > wiki_backup.sql
```

## Troubleshooting

### Common Issues

#### 1. "Shared environment file not found"
**Solution**: Run `./setup-shared-services` first to create shared infrastructure.

#### 2. SSL Certificate Issues
- Verify DNS points to your server
- Check Let's Encrypt rate limits (5 certificates per domain per week)
- Ensure email address is valid
- Check firewall allows ports 80 and 443

#### 3. Database Connection Issues
- Verify shared services are running: `docker ps | grep bluespice`
- Check database logs: `docker logs bluespice-database`
- Ensure network connectivity: `docker network ls | grep bluespice`

#### 4. Email Not Working
- Verify SMTP credentials in wiki `.env` file
- Test SMTP connection outside of wiki
- Check container logs for authentication errors
- For Gmail/Office 365, use app-specific passwords

### Diagnostic Commands

```bash
# Check all BlueSpice services status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep bluespice

# View resource usage
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Check Docker network
docker network inspect bluespice-network

# View system logs
journalctl -u docker --since "1 hour ago"
```

### Log Locations

```bash
# Shared services logs
docker-compose -f shared/docker-compose.*.yml logs

# Specific service logs
docker logs bluespice-database
docker logs bluespice-letsencrypt-service
docker logs bluespice-proxy

# Wiki logs
docker logs bluespice-<wiki-name>-wiki-web
docker logs bluespice-<wiki-name>-wiki-task
```

## Security Best Practices

### Passwords and Credentials
- Use strong, unique passwords for all accounts
- Database passwords are auto-generated (16+ characters)
- Store credentials securely (`.env` files are git-ignored)
- Use app-specific passwords for email providers

### Network Security
- Configure firewall to allow only necessary ports (80, 443, 22)
- Use HTTPS for all wiki access (auto-configured)
- Regularly update container images
- Monitor access logs

### Data Protection
- Regular database backups
- File system backups of wiki data
- Test restore procedures
- Monitor disk space usage

## Maintenance

### Regular Tasks

```bash
# Update container images (monthly)
docker-compose pull && docker-compose up -d

# Clean up unused images
docker image prune -f

# Monitor disk usage
df -h
docker system df

# Check SSL certificate expiry
./check-ssl-certificates.sh  # (if available)
```

### Updates and Upgrades

1. **Backup everything** before major updates
2. **Test updates** in a staging environment first
3. **Update container images** regularly
4. **Monitor logs** after updates for issues

## Development and Customization

### Adding New Wikis
Use the `initialize-wiki` script - it handles all configuration automatically.

### Modifying Templates
Edit files in `wiki-template/` to change default wiki configurations.

### Custom Services
Add new services to shared infrastructure by:
1. Creating new Docker Compose files in `shared/`
2. Updating `bluespice-shared-services` script
3. Testing integration with existing services

### Environment Customization
- Global settings: `.global.env`
- Shared settings: `shared/.shared.env`
- Per-wiki settings: `wikis/<name>/.env`

## Getting Help

### Troubleshooting Steps
1. **Check this README** for common solutions
2. **Review logs** for specific error messages
3. **Verify configuration** files are correct
4. **Test components individually** (database, proxy, wiki)
5. **Check Docker and system resources**

### Support Resources
- **BlueSpice Documentation**: Official MediaWiki documentation
- **Docker Documentation**: For container-related issues
- **Let's Encrypt Community**: For SSL certificate issues
- **Project Repository**: For installation script issues

## License

This deployment system is provided as-is for educational and production use. Please review the licensing terms of BlueSpice MediaWiki separately.
