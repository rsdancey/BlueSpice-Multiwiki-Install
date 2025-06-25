# BlueSpice MediaWiki Multi-Wiki Deployment System

A comprehensive Docker-based solution for deploying and managing multiple BlueSpice MediaWiki instances with shared infrastructure services, automated SSL management, and streamlined configuration.

## ✨ Overview

This system provides a robust, production-ready environment for running multiple independent MediaWiki instances that share common infrastructure components while maintaining complete isolation between wikis.

### Key Features

- **🏗️ Multi-Wiki Architecture**: Deploy unlimited independent wiki instances
- **⚡ Shared Infrastructure**: Centralized database, proxy, SSL, and caching services  
- **🔒 Automated SSL/TLS**: Let's Encrypt integration with automatic certificate renewal
- **📧 Email Integration**: Built-in SMTP configuration support with Office 365 compatibility
- **🔍 Full-Text Search**: OpenSearch integration for powerful wiki search capabilities
- **📊 Collaborative Editing**: CollabPads service for real-time document collaboration
- **🔐 Enterprise Authentication**: Optional Kerberos proxy for enterprise SSO
- **⚙️ Automated Maintenance**: Built-in upgrade and maintenance pipeline

## 📋 Prerequisites

Ensure your system meets these requirements:

| Component | Requirement |
|-----------|-------------|
| **Docker** | Version 20.10+ |
| **Docker Compose** | Version 2.0+ |
| **Git** | Latest stable version |
| **Domain(s)** | DNS configured to point to your server |
| **System Access** | Root or sudo privileges |
| **Storage** | Minimum 10GB free space |
| **Memory** | 4GB RAM recommended |
| **SMTP Service** | Optional, for email notifications |

## 🚀 Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd core_install
```

### 2. Initialize Shared Services
Set up the foundational infrastructure:
```bash
./setup-shared-services
```

This script will:
- Configure Let's Encrypt email for SSL certificates
- Set up shared Docker network and services 
- Auto-detect and configure database credentials
- Pull required Docker images
- Start core infrastructure services (database, cache, search, proxy)

### 3. Create Your First Wiki
Launch the interactive wiki creation wizard:
```bash
./initialize-wiki
```

You'll be prompted for:
- **Wiki Name**: Alphanumeric characters, dots, dashes, underscores only
- **Domain**: Your wiki's domain (e.g., `wiki.company.com`)
- **Language**: Choose from supported languages (en, de, fr, es, it, pt, nl, pl, ru, ja, zh)
- **Setup Type**: SSL certificate, HTTP only, or restore from backup

### 4. Deploy Your Wiki
Deploy the configured wiki instance:
```bash
./bluespice-deploy-wiki --wiki-name=<your-wiki-name> --fresh-install
```

**Important**: The deployment script reads all configuration (including domain) from the wiki's `.env` file located at `/core/wikis/<wiki-name>/.env`.

## 🔧 Advanced Usage

### Deployment Options

| Flag | Description | Use Case |
|------|-------------|----------|
| `--wiki-name=<name>` | **Required**: Name of wiki to deploy | All deployments |
| `--fresh-install` | ⚠️ Destroys existing data and performs clean install | New wiki setup |
| `--run-update` | Executes maintenance updates after deployment | Software updates |
| `--profile=upgrade` | Run upgrade pipeline after deployment | Version upgrades |
| `--profile=upgrade-force` | Run upgrade pipeline with force flag | Force upgrades |
| `--enable-kerberos` | Enable Kerberos authentication proxy | Enterprise SSO |
| `--help` | Display detailed usage information | Reference |

### Edition-Specific Features

The system automatically detects BlueSpice edition and enables appropriate services:

**Free Edition**:
- Core wiki functionality
- Basic services (database, cache, search, proxy)

**Pro/Farm Editions**:
- All Free edition features
- CollabPads collaborative editing service
- Additional enterprise features

### Common Deployment Scenarios

**Standard Deployment** (existing wiki):
```bash
./bluespice-deploy-wiki --wiki-name=CompanyWiki
```

**New Wiki Installation**:
```bash
./bluespice-deploy-wiki --wiki-name=CompanyWiki --fresh-install
```

**Enterprise Deployment with Kerberos**:
```bash
./bluespice-deploy-wiki --wiki-name=CompanyWiki --fresh-install --enable-kerberos
```

**Upgrade Deployment**:
```bash
./bluespice-deploy-wiki --wiki-name=CompanyWiki --profile=upgrade
```

**Complete Fresh Setup with Updates**:
```bash
./bluespice-deploy-wiki --wiki-name=CompanyWiki --fresh-install --run-update
```

## 📁 Project Structure

```
core_install/                    # Main deployment scripts
├── setup-shared-services        # Infrastructure initialization
├── initialize-wiki              # Wiki creation wizard  
├── bluespice-deploy-wiki        # Wiki deployment engine
├── bluespice-shared-services    # Shared services management
├── shared/                      # Shared services configuration
│   ├── .shared.env             # Global environment settings
│   └── docker-compose-*.yml    # Service definitions
└── wiki-template/               # New wiki template files
    ├── .env.template           # Wiki configuration template
    └── docker-compose-*.yml    # Wiki service definitions

../wikis/                        # Wiki instances (created dynamically)
├── wiki1/
│   ├── .env                    # Wiki-specific configuration
│   ├── docker-compose.yml     # Wiki service definitions
│   └── data/                   # Wiki data and uploads
└── wiki2/
    ├── .env
    ├── docker-compose.yml
    └── data/
```

## ⚙️ Services Architecture

### Shared Infrastructure Services

| Service | Container Name | Purpose | Ports |
|---------|---------------|---------|-------|
| **Database** | `bluespice-database` | MariaDB database server | 3306 |
| **Cache** | `bluespice-cache` | Memcached for performance | 11211 |
| **Search** | `bluespice-search` | OpenSearch for wiki search | 9200 |
| **Proxy** | `bluespice-proxy` | Nginx reverse proxy | 80, 443 |
| **SSL Manager** | `bluespice-letsencrypt` | SSL certificate management | - |
| **PDF Generator** | `bluespice-pdf` | PDF generation service | 3000 |
| **Formula Renderer** | `bluespice-formula` | Math formula rendering | 10044 |
| **Diagram Generator** | `bluespice-diagram` | Diagram creation service | 8080 |

### Per-Wiki Services

| Service | Container Name | Purpose |
|---------|---------------|---------|
| **Wiki Web** | `<wiki>-wiki-web` | MediaWiki web application |
| **Wiki Tasks** | `<wiki>-wiki-task` | Background job processing |
| **CollabPads** | `<wiki>-collabpads` | Collaborative editing (Pro/Farm) |
| **CollabPads DB** | `<wiki>-collabpads-database` | MongoDB for CollabPads (Pro/Farm) |
| **Kerberos Proxy** | `<wiki>-kerberos-proxy` | SSO authentication (optional) |

## 🔧 Configuration Management

### Wiki-Specific Settings
Each wiki's configuration is stored in `/core/wikis/<wiki-name>/.env`:

```bash
# Core Identity
WIKI_NAME=MyWiki                    # Internal identifier
WIKI_HOST=wiki.example.com          # Public domain
WIKI_LANG=en                        # Wiki language

# Docker Configuration
CONTAINER_PREFIX=bluespice-mywiki    # Container naming prefix
DATADIR=/data/bluespice             # Data directory base path

# Database Configuration
DB_NAME=mywiki_wiki                 # Database name
DB_USER=mywiki_user                 # Database user
DB_PASS=secure_password             # Database password
DB_HOST=bluespice-database          # Database host

# BlueSpice Configuration
BLUESPICE_WIKI_IMAGE=bluespice/wiki:5.1        # Wiki Docker image
BLUESPICE_SERVICE_REPOSITORY=bluespice         # Service repository
VERSION=5.1                         # BlueSpice version
EDITION=free                        # Edition (free/pro/farm)

# Proxy Configuration
VIRTUAL_HOST=wiki.example.com       # Virtual host for proxy
VIRTUAL_PORT=9090                   # Internal port
```

### Shared Infrastructure Settings
Global configuration in `shared/.shared.env`:

```bash
# Version and Repository
VERSION=5.1
BLUESPICE_SERVICE_REPOSITORY=bluespice

# Data Directory
DATADIR=/data/bluespice

# Database Root Access
DB_ROOT_USER=root
DB_ROOT_PASS=auto_generated_password

# Network Configuration
HTTP_PORT=80
ENABLE_IPV6=true

# SSL Configuration
HTTPS_METHOD=redirect
ENABLE_HSTS=true
SSL_POLICY=Mozilla-Modern

# Let's Encrypt
ACME_CA_URI=https://acme-v02.api.letsencrypt.org/directory
ADMIN_MAIL=admin@company.com

# Resource Limits
UPLOAD_MAX_SIZE=100m
```

## 🛠️ Operations and Maintenance

### Service Management

**Shared Services**:
```bash
# Start all shared services
./bluespice-shared-services up

# Stop all shared services  
./bluespice-shared-services down

# Check service status
./bluespice-shared-services status
```

**Individual Wikis**:
```bash
# Standard deployment
./bluespice-deploy-wiki --wiki-name=MyWiki

# Fresh installation  
./bluespice-deploy-wiki --wiki-name=MyWiki --fresh-install

# Run maintenance updates
./bluespice-deploy-wiki --wiki-name=MyWiki --run-update
```

### Health Monitoring
```bash
# View all containers
docker ps

# Check specific container logs
docker logs <container-name>

# Monitor service health with auto-refresh
watch docker ps

# View resource usage
docker stats
```

### Database Operations
```bash
# Test database connectivity
docker exec bluespice-database mariadb -u root -e "SELECT 1;"

# Access database shell
docker exec -it bluespice-database mariadb -u root -p

# Create database backup
docker exec bluespice-database mysqldump -u root -p --all-databases > backup.sql
```

## 🔍 Troubleshooting Guide

### Common Issues and Solutions

#### 1. Shared Services Won't Start
**Symptoms**: Infrastructure services fail to start
**Solutions**:
```bash
# Check Docker daemon status
systemctl status docker

# Recreate Docker network
docker network prune
./setup-shared-services

# Check available resources
df -h
free -h
```

#### 2. Database Connection Problems
**Symptoms**: Wiki cannot connect to database
**Solutions**:
```bash
# Verify database is running
docker ps | grep bluespice-database

# Test database connectivity
docker exec bluespice-database mariadb -u root -e "SELECT 1;"

# Check network connectivity
docker network inspect bluespice-network
```

#### 3. SSL Certificate Issues
**Symptoms**: SSL certificate not issued or expired
**Solutions**:
```bash
# Verify DNS points to your server
nslookup your-domain.com

# Check Let's Encrypt logs
docker logs bluespice-letsencrypt

# Manually trigger certificate renewal
docker exec bluespice-letsencrypt certbot renew
```

#### 4. Wiki Data Not Initializing
**Symptoms**: Wiki shows setup page instead of content
**Solutions**:
```bash
# Check if prepare service ran
docker logs <wiki>-prepare

# Manually run prepare service
cd /core/wikis/<wiki-name>
docker compose -f docker-compose.helper-service.yml run --rm prepare

# Verify data directory structure
ls -la /data/bluespice/<wiki-name>/
```

#### 5. Container Startup Failures
**Symptoms**: Containers fail to start or crash
**Solutions**:
```bash
# Check available disk space
df -h

# Review container logs  
docker logs <container-name>

# Verify Docker Compose syntax
docker compose config

# Check for port conflicts
netstat -tulpn | grep :<port>
```

### Log Locations and Debugging

**Application Logs**:
```bash
# Individual container logs
docker logs <container-name>

# Follow logs in real-time
docker logs -f <container-name>

# Shared services logs
docker compose -f shared/docker-compose-*.yml logs

# Specific wiki logs
cd /core/wikis/<wiki-name>
docker compose logs
```

**System Logs**:
```bash
# Docker daemon logs
journalctl -u docker

# System resource usage
top
iotop
```

## 🔒 Security Features

### Built-in Security Measures
- **🔐 Auto-Generated Passwords**: Secure database credentials using OpenSSL
- **🛡️ SSL/TLS Encryption**: Modern security policies (Mozilla-Modern)
- **📁 Proper Permissions**: Secure file and directory ownership (911:911, 1002:bluespice)
- **🌐 Network Isolation**: Services communicate through isolated Docker networks
- **🔑 Credential Management**: Secure storage of sensitive configuration
- **🚫 Resource Limits**: Container resource constraints prevent abuse

### Security Best Practices
- Regularly update Docker images: `docker compose pull`
- Monitor container logs for suspicious activity
- Use strong, unique passwords for all services
- Keep SSL certificates current and valid
- Implement proper firewall rules
- Regular security audits of exposed services
- Backup configuration and data regularly

### Email Configuration Security
The system includes secure SMTP configuration with Office 365 support:
```bash
# Office 365 SMTP settings (from user rules)
SMTP_HOST=smtp.office365.com
SMTP_USER=wiki@ryandancey.com  
SMTP_PORT=587
```

## 📚 Backup and Recovery

### Automated Backup Strategy
```bash
#!/bin/bash
# Complete backup script

BACKUP_DIR="/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Database backup
docker exec bluespice-database mysqldump -u root -p"$DB_ROOT_PASS" \
  --all-databases --single-transaction > "$BACKUP_DIR/database.sql"

# Wiki data backup
for wiki in /core/wikis/*/; do
  wiki_name=$(basename "$wiki")
  tar -czf "$BACKUP_DIR/${wiki_name}_data.tar.gz" "/data/bluespice/$wiki_name/"
  cp "$wiki/.env" "$BACKUP_DIR/${wiki_name}.env"
done

# Configuration backup
tar -czf "$BACKUP_DIR/configuration.tar.gz" \
  /core/core_install/ \
  /core/wikis/ \
  --exclude='*/data/*'
```

### Recovery Process
1. **Stop all services**:
   ```bash
   ./bluespice-shared-services down
   ```

2. **Restore database**:
   ```bash
   docker exec -i bluespice-database mysql -u root -p < backup/database.sql
   ```

3. **Restore data directories**:
   ```bash
   tar -xzf backup/wiki_data.tar.gz -C /
   ```

4. **Restore configuration**:
   ```bash
   tar -xzf backup/configuration.tar.gz -C /
   ```

5. **Restart services**:
   ```bash
   ./setup-shared-services
   ./bluespice-deploy-wiki --wiki-name=<wiki-name>
   ```

## 🚀 Advanced Features

### Enterprise Integration

**Kerberos Authentication**:
```bash
# Deploy with Kerberos SSO
./bluespice-deploy-wiki --wiki-name=CompanyWiki --enable-kerberos
```

**Collaborative Editing** (Pro/Farm editions):
- Real-time document collaboration via CollabPads
- MongoDB backend for collaborative sessions
- Automatic service inclusion for Pro/Farm editions

**Upgrade Pipeline**:
```bash
# Standard upgrade
./bluespice-deploy-wiki --wiki-name=MyWiki --profile=upgrade

# Force upgrade (skip compatibility checks)
./bluespice-deploy-wiki --wiki-name=MyWiki --profile=upgrade-force
```

### Performance Optimization

**Resource Tuning**:
- CPU limits: 0.5-1.0 cores per service
- Memory limits: 256M-1G depending on service
- Disk I/O optimization through volume mounting

**Caching Strategy**:
- Memcached for object caching
- Nginx proxy caching for static content
- Database query optimization

## 🤝 Contributing

We welcome contributions! Please follow these guidelines:

### Development Setup
1. **Fork** the repository
2. **Clone** your fork locally
3. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
4. **Test** changes in a development environment

### Code Standards
- **Shell Scripts**: Use shellcheck for linting
- **YAML Files**: Use yamllint for validation
- **Docker**: Follow Docker best practices
- **Documentation**: Update README for new features

### Testing Checklist
- [ ] All scripts pass shellcheck linting
- [ ] All YAML files pass yamllint validation
- [ ] Fresh installation works correctly
- [ ] Existing wiki deployment works
- [ ] Shared services start properly
- [ ] SSL certificates generate correctly
- [ ] Database connectivity functions
- [ ] Email configuration works

### Submission Process
1. **Commit** your changes (`git commit -m 'Add amazing feature'`)
2. **Push** to the branch (`git push origin feature/amazing-feature`)  
3. **Open** a Pull Request with detailed description
4. **Address** review feedback promptly

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support and Resources

### Getting Help
- **Documentation**: This README and inline code comments
- **Bug Reports**: Open GitHub issue with logs and configuration
- **Feature Requests**: Submit enhancement requests via GitHub issues
- **Security Issues**: Report privately via email

### Useful Resources
- [BlueSpice MediaWiki Documentation](https://en.wiki.bluespice.com/)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [MediaWiki System Administration](https://www.mediawiki.org/wiki/Manual:System_administration)

### Community
- **BlueSpice Community**: [BlueSpice Forum](https://forum.bluespice.com/)
- **MediaWiki Community**: [MediaWiki.org](https://www.mediawiki.org/)
- **Docker Community**: [Docker Forums](https://forums.docker.com/)

---

## 🙏 Acknowledgments

- **BlueSpice Team**: For creating excellent MediaWiki enterprise software
- **Docker Community**: For revolutionizing application deployment
- **Let's Encrypt**: For providing free SSL certificates
- **MediaWiki Foundation**: For the underlying wiki platform
- **OpenSearch**: For powerful search capabilities
- **MariaDB**: For reliable database services

---

## 📊 Version Information

| Component | Version | Notes |
|-----------|---------|-------|
| **BlueSpice** | 5.1 | Current stable release |
| **MediaWiki** | Latest LTS | Included with BlueSpice |
| **Docker Compose** | 2.0+ | Required for advanced features |
| **Let's Encrypt** | ACME v2 | Modern certificate protocol |
| **MariaDB** | Latest stable | Database backend |
| **OpenSearch** | Latest | Search engine |

---

*Built with ❤️ for the MediaWiki community*
