# BlueSpice MediaWiki Multi-Wiki Installation

A Docker-based deployment system for BlueSpice MediaWiki with support for multiple wiki instances and shared services.

## Overview

This project provides a complete containerized environment for running BlueSpice MediaWiki installations with:

- Multiple independent wiki instances
- Shared services (database, proxy, SSL certificates)
- Automated deployment and configuration
- Data persistence and backup capabilities

## Prerequisites

- Docker and Docker Compose
- Git
- Domain name with DNS configured
- Email account for SMTP (optional but recommended)

## Quick Start

### 1. Initial Setup

```bash
# Clone and navigate to the repository
git clone <repository-url>
cd core_install

# Set up shared services (database, proxy, SSL)
./bluespice-shared-services start

# Initialize and deploy your first wiki
./bluespice-deploy-wiki
```

### 2. Environment Configuration

The system uses environment files for configuration:

- `.global.env` - Global settings shared across all services
- `shared/.shared.env` - Shared services configuration
- Individual wiki `.env` files in the wikis directory

### 3. Wiki Deployment

The `bluespice-deploy-wiki` script will:
- Prompt for wiki configuration (name, domain, admin credentials)
- Generate necessary configuration files
- Deploy the wiki container
- Configure SSL certificates
- Set up email (if configured)

## Directory Structure

```
.
├── bluespice-deploy-wiki       # Main wiki deployment script
├── bluespice-shared-services   # Shared services management script
├── initialize-wiki             # Wiki initialization script
├── setup-shared-services       # Shared services setup script
├── .global.env                 # Global environment configuration
├── shared/                     # Shared services configuration
│   ├── .shared.env
│   ├── docker-compose.*.yml
│   └── ...
├── wiki-template/              # Template files for new wikis
│   ├── .env.template
│   ├── docker-compose.*.yml
│   └── ...
└── wikis/                      # Individual wiki instances (created during deployment)
    └── <wiki-name>/
        ├── .env
        ├── docker-compose.yml
        └── data/
```

## Configuration

### Global Settings (.global.env)

```env
# Network configuration
NETWORK_NAME=bluespice-network

# Domain and SSL
DOMAIN_SUFFIX=yourdomain.com
LETSENCRYPT_EMAIL=admin@yourdomain.com

# Database settings
DB_ROOT_PASSWORD=<secure-password>
DB_NAME=bluespice_wikis
DB_USER=wiki_user
DB_PASSWORD=<secure-password>

# Email settings (optional)
SMTP_HOST=smtp.yourmailprovider.com
SMTP_PORT=587
SMTP_USER=wiki@yourdomain.com
SMTP_PASS=<smtp-password>
```

### Per-Wiki Settings

Each wiki can override global settings in its own `.env` file:

```env
WIKI_NAME=mywiki
WIKI_HOST=mywiki.yourdomain.com
WIKI_ADMIN_USER=admin
WIKI_ADMIN_PASS=<secure-password>
WIKI_ADMIN_EMAIL=admin@yourdomain.com

# SMTP settings (inherits from global if not specified)
SMTP_HOST=smtp.yourmailprovider.com
SMTP_USER=wiki@yourdomain.com
SMTP_PASS=<app-password>
```

## Email Configuration

The system supports various SMTP providers:

- **Gmail**: `smtp.gmail.com:587` (requires app password)
- **Office 365**: `smtp.office365.com:587`
- **Other providers**: Any standard SMTP server with authentication

To configure email:
1. Set SMTP settings in `.global.env` or per-wiki `.env`
2. For Gmail/Office 365, use app-specific passwords
3. Test email functionality after deployment

## Management Commands

### Shared Services

```bash
# Start shared services (database, proxy, SSL)
./bluespice-shared-services start

# Stop shared services
./bluespice-shared-services stop

# Restart shared services
./bluespice-shared-services restart

# View status
./bluespice-shared-services status

# View logs
./bluespice-shared-services logs
```

### Wiki Management

```bash
# Deploy a new wiki
./bluespice-deploy-wiki

# Deploy with specific name
./bluespice-deploy-wiki --name mywiki

# View all wikis
docker ps | grep bluespice-wiki

# Access wiki logs
docker logs bluespice-wiki-<name>-web
```

## Data Persistence

- **Database**: Stored in Docker volumes, persists across container restarts
- **Wiki uploads**: Stored in per-wiki data directories
- **SSL certificates**: Automatically managed by Let's Encrypt

## Backup and Recovery

### Database Backup

```bash
# Create database backup
docker exec bluespice-database mysqldump -u root -p<password> --all-databases > backup.sql

# Restore from backup
docker exec -i bluespice-database mysql -u root -p<password> < backup.sql
```

### Wiki Data Backup

```bash
# Backup wiki files
tar -czf wiki-backup.tar.gz wikis/<wiki-name>/data/

# Restore wiki files
tar -xzf wiki-backup.tar.gz -C wikis/<wiki-name>/
```

## Troubleshooting

### Common Issues

1. **SSL Certificate Errors**
   - Ensure DNS is properly configured
   - Check Let's Encrypt rate limits
   - Verify email address is valid

2. **Database Connection Issues**
   - Verify shared services are running
   - Check database credentials in environment files
   - Ensure network connectivity between containers

3. **Email Not Working**
   - Verify SMTP credentials and settings
   - Check if provider requires app-specific passwords
   - Review container logs for email errors

### Viewing Logs

```bash
# Shared services logs
docker-compose -f shared/docker-compose.*.yml logs

# Specific service logs
docker logs <container-name>

# Wiki logs
docker logs bluespice-wiki-<name>-web
```

## Security Considerations

- Change default passwords in all environment files
- Use strong passwords for database and admin accounts
- Keep environment files secure and not in version control
- Regularly update container images
- Monitor access logs

## Development

### Making Changes

1. Modify scripts or configuration files
2. Test changes in development environment
3. Commit changes to git repository
4. Deploy to production environment

### Adding Features

The system is modular and extensible:
- Add new Docker Compose services in the `shared/` directory
- Extend deployment scripts for additional functionality
- Add new templates in `wiki-template/` directory

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review Docker and container logs
3. Consult BlueSpice MediaWiki documentation
4. Create an issue in the project repository

## License

This project is provided as-is for educational and deployment purposes.
