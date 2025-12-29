# Azure DevOps Repository Backup and Restore

A comprehensive PowerShell solution for backing up and restoring Azure DevOps Git repositories to/from Azure Blob Storage.

## 📋 Overview

This repository provides enterprise-grade backup and restore capabilities for Azure DevOps Git repositories:

- **backupRepos.ps1**: Automated backup script that creates complete repository backups (all branches, tags, refs) to Azure Blob Storage
- **restoreRepos.ps1**: Interactive restore script supporting three recovery scenarios with flexible target options

## ✨ Features

### Backup Script
- ✅ **Complete Repository Backup**: Mirror clone preserves all branches, tags, and refs
- ✅ **Hierarchical Storage**: Organized by `ProjectName/RepositoryName/YYYY-MM-DD.zip`
- ✅ **Automatic Discovery**: Discovers all repositories in an organization
- ✅ **Retention Policies**: Configurable backup retention (default: 365 days)
- ✅ **Manifest Generation**: JSON manifest tracks all backup operations
- ✅ **Comprehensive Logging**: Detailed logs with timestamps and error tracking
- ✅ **Error Recovery**: Continues processing even if individual repositories fail

### Restore Script
- ✅ **Three Recovery Scenarios**:
  1. **Full Organization Restore**: Restore entire organization structure
  2. **Project Restore**: Restore all repositories from a project (can use new project name)
  3. **Repository Restore**: Restore individual repository (can restore to different org/project)
- ✅ **Interactive Interface**: User-friendly prompts with table-formatted backup listings
- ✅ **Flexible Targets**: Restore to same or different organizations/projects
- ✅ **Backup Selection**: Choose latest backup or select specific date
- ✅ **Automatic Creation**: Creates missing projects and repositories as needed
- ✅ **Conflict Handling**: Options to skip, overwrite, or abort when repositories exist

## 🚀 Quick Start

### Prerequisites

1. **PowerShell 5.1+**
2. **Git** (must be in PATH)
3. **Azure PowerShell Modules**:
   ```powershell
   Install-Module -Name Az.Storage -Scope CurrentUser -Force
   Install-Module -Name VSTeam -Scope CurrentUser -Force
   ```
4. **Azure Authentication**:
   ```powershell
   Connect-AzAccount
   ```

### Installation

1. Clone or download this repository
2. Ensure prerequisites are installed
3. Authenticate to Azure and Azure DevOps

### Basic Usage

#### Backup All Repositories

```powershell
.\backupRepos.ps1 `
    -ResourceGroupName "rg-backups" `
    -StorageAccountName "stbackups001" `
    -AzureDevOpsAccount "https://dev.azure.com/YourOrganization" `
    -AccessToken "your-pat-token"
```

#### Restore (Interactive)

```powershell
.\restoreRepos.ps1 `
    -ResourceGroupName "rg-backups" `
    -StorageAccountName "stbackups001"
```

## 📖 Detailed Documentation

### Backup Script Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `ResourceGroupName` | Yes | - | Azure Resource Group containing storage account |
| `StorageAccountName` | Yes | - | Azure Storage Account name |
| `ContainerName` | No | `repobackups` | Blob Storage container name |
| `RetentionDays` | No | `365` | Days to retain backups (0 = keep forever) |
| `LogPath` | No | `.\backup-YYYY-MM-DD.log` | Log file path |
| `AzureDevOpsAccount` | No | Uses existing VSTeam config | Organization URL |
| `AccessToken` | No | `$env:SYSTEM_ACCESSTOKEN` | Personal Access Token |
| `ProjectName` | No | - | Filter: backup only this project |
| `RepositoryName` | No | - | Filter: backup only this repository |

### Restore Scenarios

#### Scenario 1: Full Organization Restore
Restores all projects and repositories from backup to target organization. Creates projects and repositories as needed.

**Use Case**: Complete organization recovery after deletion or migration to new organization.

#### Scenario 2: Project Restore
Restores all repositories from a specific project. Allows specifying a new target project name while keeping repository names the same.

**Use Case**: Project recovery or project migration with new name.

#### Scenario 3: Repository Restore
Restores a single repository. Can restore to different organization, project, or with different repository name.

**Use Case**: Individual repository recovery or repository migration.

### Storage Structure

Backups are stored hierarchically in Azure Blob Storage:

```
repobackups/
├── backup-manifest.json          # Latest backup manifest
├── backup-manifest-2024-01-15.json  # Historical manifests
├── ProjectA/
│   ├── Repository1/
│   │   ├── 2024-01-15.zip
│   │   ├── 2024-01-16.zip
│   │   └── 2024-01-17.zip
│   └── Repository2/
│       └── 2024-01-17.zip
└── ProjectB/
    └── Repository3/
        └── 2024-01-17.zip
```

## 🔐 Security

### Required Permissions

**Azure Storage**:
- Contributor or Storage Blob Data Contributor role

**Azure DevOps PAT Token**:
- **Backup**: Code (Read)
- **Restore**: Code (Read & Write), Project and Team (Read & Write)

### Security Best Practices

1. **Never commit PAT tokens** to version control
2. **Use Azure Key Vault** for token storage in production
3. **Rotate PAT tokens** regularly
4. **Use least-privilege** permissions
5. **Enable Azure Storage encryption**
6. **Use private endpoints** for production storage access

## 📝 Examples

### Scheduled Daily Backup

Create a Windows Scheduled Task:

```powershell
# Run daily at 2 AM
.\backupRepos.ps1 `
    -ResourceGroupName "rg-backups" `
    -StorageAccountName "stbackups001" `
    -RetentionDays 90 `
    -LogPath "C:\Logs\backup-$(Get-Date -Format 'yyyy-MM-dd').log"
```

### Restore Specific Repository to Different Organization

```powershell
.\restoreRepos.ps1 `
    -ResourceGroupName "rg-backups" `
    -StorageAccountName "stbackups001"

# Interactive prompts:
# 1. Select Scenario 3 (Repository Restore)
# 2. Choose repository from table
# 3. Select backup date
# 4. Enter target organization URL
# 5. Enter target project name
```

### Backup Specific Project Only

```powershell
.\backupRepos.ps1 `
    -ResourceGroupName "rg-backups" `
    -StorageAccountName "stbackups001" `
    -ProjectName "MyProject"
```

## 🐛 Troubleshooting

### Common Issues

**"Git is not installed or not in PATH"**
- Install Git and ensure it's in system PATH
- Verify: `git --version`

**"Failed to connect to Azure Storage"**
- Verify Azure authentication: `Get-AzContext`
- Check storage account name and resource group
- Ensure proper permissions

**"Failed to retrieve repositories"**
- Verify PAT token is valid and not expired
- Check token has required scopes
- Verify organization URL format

**"Git push failed during restore"**
- Verify PAT token has Code (Write) permissions
- Check target repository exists or can be created
- Ensure project permissions allow repository creation

**"Collection was modified; enumeration operation may not execute"**
- This has been fixed in the latest version
- Ensure you're using the latest script version

### Debug Mode

Enable verbose output for detailed debugging:

```powershell
.\backupRepos.ps1 -Verbose ...
.\restoreRepos.ps1 -Verbose ...
```

## 📊 Logging

Both scripts generate comprehensive logs:

- **Backup Script**: Creates timestamped log files (`backup-YYYY-MM-DD.log`)
- **Restore Script**: Console output with color-coded messages + log file

Log levels:
- **INFO**: General information (white)
- **SUCCESS**: Successful operations (green)
- **WARNING**: Warnings (yellow)
- **ERROR**: Errors (red)

## 💰 Storage Costs

Consider Azure Blob Storage tiers based on access patterns:

- **Hot Tier**: Best for frequent restores (higher cost, instant access)
- **Cool Tier**: Lower cost for infrequent access (30-day minimum)
- **Archive Tier**: Lowest cost (requires rehydration before access)

**Recommendation**: Use Hot tier for recent backups, move older backups to Cool/Archive tier.

## 🔄 Best Practices

1. **Schedule Regular Backups**: Daily backups recommended for production
2. **Test Restores**: Periodically test restore procedures
3. **Monitor Logs**: Set up alerts for backup failures
4. **Retention Policy**: Balance retention period with storage costs
5. **Document Recovery Procedures**: Maintain runbooks for your team
6. **Version Control**: Keep scripts in version control

## 📄 License

This project is provided as-is for backup and restore operations. Use at your own risk.

## 🤝 Contributing

Contributions are welcome! Please ensure:
- Code follows PowerShell best practices
- Error handling is comprehensive
- Logging is detailed
- Documentation is updated

## 📞 Support

For issues or questions:
1. Check the troubleshooting section
2. Review script logs for detailed error messages
3. Verify all prerequisites are installed
4. Ensure proper Azure and Azure DevOps permissions

## 📚 Additional Resources

- [Azure DevOps REST API Documentation](https://docs.microsoft.com/en-us/rest/api/azure/devops/)
- [Azure Blob Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/blobs/)
- [VSTeam PowerShell Module](https://github.com/DarqueWarrior/vsteam)
- [Azure PowerShell Module](https://docs.microsoft.com/en-us/powershell/azure/)

---

**Version**: 2.0  
**Last Updated**: 2024
