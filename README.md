# BlueSpice MediaWiki Multi-Wiki Deployment System

A comprehensive Docker-based solution for deploying and managing multiple BlueSpice MediaWiki instances with shared infrastructure services, automated SSL management, and streamlined configuration.

## ✨ Overview

This system provides a robust, production-ready environment for running multiple independent MediaWiki instances that share common infrastructure components while maintaining complete isolation between wikis.

### Key Benefits

- **🏗️ Multi-Wiki Architecture**: Deploy unlimited independent wiki instances
- **⚡ Shared Infrastructure**: Centralized database, proxy, SSL, and caching services
- **🔒 Automated SSL/TLS**: Let's Encrypt integration with automatic certificate renewal
- **🎯 Interactive Setup**: User-friendly configuration wizards
- **📊 Smart Database Management**: Automatic credential detection and configuration
- **💾 Data Persistence**: Reliable storage with Docker volumes
- **📧 Email Integration**: Built-in SMTP configuration support

## 📋 Prerequisites

Ensure your system meets these requirements:

| Component | Requirement |
|-----------|-------------|
| **Docker** | Version 20.10+ |
| **Docker Compose** | Version 2.0+ |
| **Git** | Latest stable version |
| **Domain(s)** | DNS configured to point to your server |
| **System Access** | Root or sudo privileges |
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
- ✅ Configure Let's Encrypt email for SSL certificates
- ✅ Set up shared Docker network and services
- ✅ Auto-detect and configure database credentials
- ✅ Create shared environment configuration

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
./bluespice-deploy-wiki --wiki-name=<your-wiki-name>
```

## 🔧 Advanced Usage

### Deployment Options

| Flag | Description | Use Case |
|------|-------------|----------|
| `--fresh-install` | ⚠️ Destroys existing data and performs clean install | New wiki setup |
| `--run-update` | Executes maintenance updates after deployment | Software updates |
| `--help` | Display detailed usage information | Reference |

### Common Deployment Scenarios

**Standard Deployment** (existing wiki):
```bash
./bluespice-deploy-wiki --wiki-name=CompanyWiki
```

**New Wiki Installation**:
```bash
./bluespice-deploy-wiki --wiki-name=CompanyWiki --fresh-install
```

**Deploy with Updates**:
```bash
./bluespice-deploy-wiki --wiki-name=CompanyWiki --run-update
```

**Complete Fresh Setup**:
```bash
./bluespice-deploy-wiki --wiki-name=CompanyWiki --fresh-install --run-update
```

## 📁 Project Structure

```
core_install/                    # Main deployment scripts
├── setup-shared-services        # Infrastructure initialization
├── initialize-wiki              # Wiki creation wizard
├── bluespice-deploy-wiki        # Wiki deployment engine
├── shared/                      # Shared services configuration
│   └── .shared.env             # Global environment settings
└── wiki-template/               # New wiki template files

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

## ⚙️ Configuration Management

### Wiki-Specific Settings
Each wiki's configuration is stored in `/core/wikis/<wiki-name>/.env`:

```bash
# Core Identity
WIKI_NAME=MyWiki                    # Internal identifier
WIKI_HOST=wiki.example.com          # Public domain

# Database Configuration
DB_NAME=mywiki_db                   # Database name
DB_USER=mywiki_user                 # Database user
DB_PASS=secure_password             # Database password

# Email Configuration (SMTP)
SMTP_HOST=smtp.office365.com        # SMTP server
SMTP_PORT=587                       # SMTP port
SMTP_USER=wiki@company.com          # SMTP username
SMTP_PASS=email_password            # SMTP password

# SSL and Proxy Settings
SSL_ENABLED=true                    # Enable SSL/TLS
PROXY_NETWORK=bluespice_network     # Docker network
```

### Shared Infrastructure Settings
Global configuration in `shared/.shared.env`:

```bash
# Database Root Access
DB_ROOT_PASS=auto_generated_password

# SSL Certificate Management
LETSENCRYPT_EMAIL=admin@company.com

# Network Configuration
SHARED_NETWORK=bluespice_shared
```

## 🛠️ Operations and Maintenance

### Health Monitoring
Check system status:
```bash
# View all containers
docker ps

# Check specific container logs
docker logs <container-name>

# Monitor service health
docker compose logs -f
```

### Database Operations
```bash
# Test database connectivity
docker exec bluespice-database mysql -u root -e "SELECT 1;"

# Access database shell
docker exec -it bluespice-database mysql -u root -p
```

### Updates and Maintenance
```bash
# Update specific wiki
./bluespice-deploy-wiki --wiki-name=<wiki-name> --run-update

# Restart shared services
docker compose -f shared/docker-compose.yml restart
```

## 🔍 Troubleshooting Guide

### Common Issues and Solutions

#### Database Connection Problems
**Symptoms**: Wiki cannot connect to database
**Solutions**:
1. Verify shared services are running: `docker ps`
2. Test database health: `docker exec bluespice-database mysql -u root -e "SELECT 1;"`
3. Re-initialize shared services: `./setup-shared-services`

#### SSL Certificate Issues
**Symptoms**: SSL certificate not issued or expired
**Solutions**:
1. Confirm DNS points to your server
2. Check Let's Encrypt rate limits
3. Verify email address validity
4. Review proxy logs: `docker logs bluespice-proxy`

#### Container Startup Failures
**Symptoms**: Containers fail to start or crash
**Solutions**:
1. Check available disk space: `df -h`
2. Review container logs: `docker logs <container-name>`
3. Verify network connectivity: `docker network ls`
4. Restart Docker daemon if necessary

### Log Locations
- **Application Logs**: `docker logs <container-name>`
- **Shared Services**: `docker compose -f shared/docker-compose.yml logs`
- **Individual Wiki**: `docker compose -f ../wikis/<wiki-name>/docker-compose.yml logs`

## 🔒 Security Features

### Built-in Security Measures
- **🔐 Auto-Generated Passwords**: Secure database credentials
- **🛡️ SSL/TLS Encryption**: Modern security policies and protocols
- **📁 Proper Permissions**: Secure file and directory ownership
- **🌐 Network Isolation**: Services communicate through isolated Docker networks
- **🔑 Credential Management**: Secure storage of sensitive configuration

### Security Best Practices
- Regularly update Docker images and base system
- Monitor container logs for suspicious activity
- Use strong, unique passwords for all services
- Keep SSL certificates current and valid
- Backup configuration and data regularly

## 📚 Backup and Recovery

### Backup Strategy
```bash
# Database Backup
docker exec bluespice-database mysqldump -u root -p<password> --all-databases > backup.sql

# File System Backup
tar -czf wiki-backup.tar.gz /opt/bluespice/<wiki-name>/

# Configuration Backup
cp -r /core/wikis/<wiki-name>/.env /backup/location/
```

### Recovery Process
1. Restore database from backup
2. Restore file system data
3. Restore configuration files
4. Redeploy wiki instance

## 📈 Scaling and Performance

### Multi-Wiki Management
- Each wiki operates independently
- Shared resources reduce overhead
- Individual scaling per wiki
- Isolated update cycles

### Performance Optimization
- Enable caching services
- Optimize database settings
- Monitor resource usage
- Scale shared services as needed

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Test** thoroughly in a development environment
5. **Push** to the branch (`git push origin feature/amazing-feature`)
6. **Open** a Pull Request

### Development Guidelines
- Follow existing code style and patterns
- Include documentation for new features
- Test changes with multiple wiki configurations
- Update this README if adding new functionality

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support and Resources

### Getting Help
- **Documentation Issues**: Check this README and inline code comments
- **Technical Problems**: Review troubleshooting section above
- **Bug Reports**: Open an issue with detailed logs and configuration
- **Feature Requests**: Submit enhancement requests via GitHub issues

### Useful Resources
- [BlueSpice MediaWiki Documentation](https://en.wiki.bluespice.com/)
- [Docker Compose Reference](https://docs.docker.com/compose/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)

### Community
- **Issues**: Report bugs and request features
- **Discussions**: Share experiences and ask questions
- **Wiki**: Additional documentation and examples

---

## 🙏 Acknowledgments

- **BlueSpice Team**: For creating excellent MediaWiki software
- **Docker Community**: For revolutionizing application deployment
- **Let's Encrypt**: For providing free SSL certificates
- **MediaWiki Foundation**: For the underlying wiki platform

---

*Built with ❤️ for the MediaWiki community*
