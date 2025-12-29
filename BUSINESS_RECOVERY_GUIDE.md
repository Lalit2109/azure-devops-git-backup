# Azure DevOps Repository Backup and Recovery Guide

## Business Overview

This document provides a comprehensive guide for recovering Azure DevOps repositories from backups. The backup and restore system ensures business continuity by maintaining complete copies of all Git repositories in Azure Blob Storage.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Backup Process Overview](#backup-process-overview)
3. [Recovery Scenarios](#recovery-scenarios)
4. [Common Recovery Steps](#common-recovery-steps)
5. [Step-by-Step Recovery Procedures](#step-by-step-recovery-procedures)
6. [Recovery Checklist](#recovery-checklist)
7. [Post-Recovery Verification](#post-recovery-verification)
8. [Contact Information](#contact-information)

---

## Introduction

### What is This System?

Our Azure DevOps Repository Backup and Recovery system automatically creates daily backups of all Git repositories, storing them securely in Azure Blob Storage. These backups include:

- All code branches
- All tags and releases
- Complete commit history
- All repository metadata

### Why Do We Need This?

**Business Impact of Data Loss:**
- Loss of code repositories can halt development work
- Recreating lost code can take weeks or months
- Customer deliverables may be delayed
- Compliance and audit requirements

**Recovery Capabilities:**
- Restore individual repositories (most common)
- Restore entire projects
- Restore complete organization structure
- Restore to different organizations (for disaster recovery)

---

## Backup Process Overview

### How Backups Work

1. **Automated Daily Backups**
   - Runs automatically every day
   - Backs up all repositories in the organization
   - Stores backups in Azure Blob Storage
   - Maintains backup history (configurable retention period)

2. **Backup Storage**
   - Location: Azure Blob Storage
   - Organization: By Project and Repository
   - Format: Compressed ZIP files
   - Retention: [Specify your retention policy, e.g., 90 days]

3. **Backup Verification**
   - Each backup includes a manifest file
   - Logs track all backup operations
   - Failed backups are logged for investigation

### Backup Schedule

- **Frequency**: Daily
- **Time**: [Specify backup time, e.g., 2:00 AM]
- **Duration**: Varies by repository size (typically 30-60 minutes)
- **Monitoring**: Automated alerts for backup failures

---

## Recovery Scenarios

### Scenario 1: Individual Repository Recovery ⭐ (Tested)

**When to Use:**
- Single repository was deleted
- Repository needs to be restored to different location
- Point-in-time recovery for specific repository

**What Gets Restored:**
- Selected repository only
- Can restore to different organization/project
- Can restore specific backup date

**Time Estimate:** 5-15 minutes per repository

---

### Scenario 2: Project Recovery

**When to Use:**
- A project was accidentally deleted
- Project needs to be restored to a new name
- Project migration between organizations

**What Gets Restored:**
- All repositories within the selected project
- Can restore to a new project name
- Repository names remain the same

**Time Estimate:** 30-60 minutes per project

**Note:** Uses same steps as Scenario 1, but restores all repositories in a project automatically.

---

### Scenario 3: Complete Organization Recovery

**When to Use:**
- Entire Azure DevOps organization was deleted
- Migration to a new organization
- Disaster recovery situation

**What Gets Restored:**
- All projects
- All repositories within each project
- Complete repository structure

**Time Estimate:** 2-4 hours depending on number of repositories

**Note:** Uses same steps as Scenario 1, but restores all projects and repositories automatically.

---

## Common Recovery Steps

The following steps are common to all recovery scenarios and are detailed in Scenario 1 below:

1. **Prepare Recovery Environment** (Steps 1-4)
   - Open PowerShell
   - Verify Azure connection
   - Launch restore script
   - Configure storage connection
   - Review available backups

2. **Configure Target Organization** (Step 9)
   - Enter target Azure DevOps organization URL
   - Choose authentication method

3. **Monitor and Complete Recovery** (Steps 10-13)
   - Confirm and execute
   - Monitor recovery progress
   - Handle existing resources
   - Verify recovery summary

**Scenarios 2 and 3 will reference these common steps and only detail their unique selection steps.**

---

## Step-by-Step Recovery Procedures

### Prerequisites

Before starting any recovery procedure, ensure you have:

- [ ] Access to Azure Portal
- [ ] Access to Azure DevOps (target organization)
- [ ] PowerShell installed (version 5.1 or later)
- [ ] Required permissions (see below)
- [ ] Personal Access Token (PAT) with appropriate permissions
- [ ] Recovery script (`restoreRepos.ps1`)
- [ ] Storage account details (Resource Group, Storage Account Name)

**Required Permissions:**
- Azure Storage: Contributor or Storage Blob Data Contributor
- Azure DevOps: Code (Read & Write), Project and Team (Read & Write)

---

### Recovery Procedure: Scenario 1 - Individual Repository Recovery ⭐

*This is the most common scenario and has been fully tested. Scenarios 2 and 3 follow similar steps but with different selection processes.*

#### Step 1: Prepare Recovery Environment

1. Open PowerShell as Administrator
2. Navigate to the script directory
3. Verify Azure connection:
   ```powershell
   Connect-AzAccount
   Get-AzContext
   ```

![Azure login and context verification](screenshots/azure-login-verification.png)

#### Step 2: Launch Restore Script

1. Run the restore script:
   ```powershell
   .\restoreRepos.ps1
   ```

![Script startup screen](screenshots/script-startup.png)

#### Step 3: Configure Storage Connection

1. Enter Azure Resource Group name: `[Your Resource Group]`
2. Enter Storage Account name: `[Your Storage Account]`
3. Enter Container name (default: `repobackups`)

![Storage configuration prompts](screenshots/storage-configuration.png)

#### Step 4: Review Available Backups

The script will display a table of all available backups organized by project and repository.

![Backup listing table](screenshots/backup-listing-table.png)

Review the list to confirm:
- All expected projects are listed
- Latest backup dates are recent
- Repository counts match expectations

#### Step 5: Select Recovery Scenario

1. When prompted, select option **3** (Repository Restore)
2. The script will display the scenario selection menu

![Scenario selection menu](screenshots/scenario-selection.png)

#### Step 6: Select Repository

1. Review the backup table displayed earlier
2. Note the repository key (format: X.Y, e.g., 1.3)
3. Enter the repository key when prompted (e.g., `1.3`)

![Repository key selection](screenshots/repository-key-selection.png)

#### Step 7: Select Backup Date

1. Review available backup dates for the repository
2. Select backup date:
   - Option 1: Latest backup (recommended)
   - Other options: Specific historical date
3. Enter the number corresponding to your choice

![Backup date selection](screenshots/backup-date-selection.png)

#### Step 8: Configure Target Location

1. Enter target project name (can be different from source):
   ```
   [Enter target project name or press Enter for default]
   ```
2. Enter target repository name (can be different from source):
   ```
   [Enter target repository name or press Enter for default]
   ```
3. Enter target organization URL (can be different from source):
   ```
   https://dev.azure.com/YourOrganization
   ```

![Target configuration](screenshots/target-configuration.png)

#### Step 9: Configure Authentication

1. Choose authentication method:
   - Option Y: Use SYSTEM_ACCESSTOKEN environment variable
   - Option N: Enter Personal Access Token manually
2. If entering manually, provide your PAT token

![Organization configuration](screenshots/organization-configuration.png)

#### Step 10: Confirm and Execute

1. Review the restore summary:
   - Repository to be restored
   - Source and target locations
   - Backup date to be used
2. Type **Y** to confirm and proceed

![Confirmation prompt](screenshots/confirmation-prompt.png)

#### Step 11: Monitor Recovery Progress

The script will:
- Create project if needed (with confirmation prompt)
- Create repository if needed
- Download backup from Azure Storage
- Extract and restore repository
- Display progress for each operation

![Recovery progress output](screenshots/recovery-progress.png)

#### Step 12: Handle Existing Resources

If projects or repositories already exist:
- **Projects**: Script will prompt to create (Y/N)
- **Repositories**: Options will be:
  - **(S)kip**: Skip this repository
  - **(O)verwrite**: Replace existing repository (destructive)
  - **(A)bort**: Cancel entire restore operation

![Conflict resolution prompts](screenshots/conflict-resolution.png)

#### Step 13: Verify Recovery Summary

At completion, review the summary:
- Total repositories processed
- Successful restores
- Failed restores (if any)

![Recovery summary](screenshots/recovery-summary.png)

---

### Recovery Procedure: Scenario 2 - Project Recovery

*This scenario follows the same steps as Scenario 1, but with different selection process. Steps 1-4 and 9-13 are identical to Scenario 1.*

#### Steps 1-4: Common Steps

Follow **Steps 1-4** from Scenario 1 (Individual Repository Recovery):
- Prepare Recovery Environment
- Launch Restore Script
- Configure Storage Connection
- Review Available Backups

#### Step 5: Select Recovery Scenario

1. When prompted, select option **2** (Project Restore)

**[SCREENSHOT PLACEHOLDER: Project scenario selection]**

#### Step 6: Select Project to Restore

1. Review the list of available projects displayed in the backup table
2. Note the project index number (e.g., 1, 2, 3)
3. Enter the project number to restore

**[SCREENSHOT PLACEHOLDER: Project selection prompt]**

#### Step 7: Specify Target Project Name

1. Enter target project name:
   - Can be same as source project name (press Enter)
   - Can be a new project name
   - Example: If source is "LegacyProject", target can be "NewProject"

**[SCREENSHOT PLACEHOLDER: Target project name prompt]**

#### Steps 8-13: Common Steps

Follow **Steps 9-13** from Scenario 1:
- Configure Authentication
- Confirm and Execute
- Monitor Recovery Progress
- Handle Existing Resources
- Verify Recovery Summary

**Note:** The script will automatically restore all repositories within the selected project to the specified target project.

---

### Recovery Procedure: Scenario 3 - Complete Organization Recovery

*This scenario follows the same steps as Scenario 1, but restores all projects automatically. Steps 1-4 and 9-13 are identical to Scenario 1.*

#### Steps 1-4: Common Steps

Follow **Steps 1-4** from Scenario 1 (Individual Repository Recovery):
- Prepare Recovery Environment
- Launch Restore Script
- Configure Storage Connection
- Review Available Backups

#### Step 5: Select Recovery Scenario

1. When prompted, select option **1** (Full Organization Restore)

**[SCREENSHOT PLACEHOLDER: Full organization scenario selection]**

#### Step 6: Review Restore Summary

1. The script will display a summary showing:
   - Total number of projects to restore
   - Total number of repositories to restore
   - Target organization
2. Review the summary carefully

**[SCREENSHOT PLACEHOLDER: Full organization restore summary]**

#### Steps 7-13: Common Steps

Follow **Steps 9-13** from Scenario 1:
- Configure Target Organization and Authentication
- Confirm and Execute
- Monitor Recovery Progress
- Handle Existing Resources
- Verify Recovery Summary

**Note:** The script will automatically:
- Restore all projects found in backups
- Restore all repositories within each project
- Create projects and repositories as needed
- Use the latest backup for each repository

---

## Recovery Checklist

Use this checklist for any recovery operation:

### Pre-Recovery

- [ ] Verify backup exists in Azure Blob Storage
- [ ] Confirm target organization/project access
- [ ] Verify PAT token has required permissions
- [ ] Test Azure connection
- [ ] Review recovery scenario requirements
- [ ] Notify stakeholders of recovery operation
- [ ] Schedule maintenance window if needed

### During Recovery

- [ ] Monitor script output for errors
- [ ] Respond to prompts (project creation, conflicts)
- [ ] Document any issues encountered
- [ ] Note any skipped repositories

### Post-Recovery

- [ ] Verify all expected repositories are restored
- [ ] Check repository contents (branches, tags)
- [ ] Verify commit history is intact
- [ ] Test repository access for team members
- [ ] Update documentation if project/repo names changed
- [ ] Notify team of recovery completion
- [ ] Review recovery logs for any warnings

---

## Post-Recovery Verification

### Verification Steps

1. **Repository Count Verification**
   - Log into Azure DevOps
   - Navigate to each restored project
   - Count repositories and compare with expected count

![Repository list in Azure DevOps](screenshots/repository-list-azure-devops.png)

2. **Repository Content Verification**
   - Clone a sample repository
   - Verify branches exist:
     ```bash
     git branch -a
     ```
   - Verify tags exist:
     ```bash
     git tag
     ```
   - Check commit history:
     ```bash
     git log --oneline
     ```

![Git branch/tag verification](screenshots/git-branch-tag-verification.png)

3. **Team Access Verification**
   - Verify team members can access repositories
   - Test clone operations
   - Verify permissions are correct

4. **Integration Verification**
   - If repositories have CI/CD pipelines, verify they still work
   - Check any external integrations
   - Verify webhooks if applicable

### Verification Checklist

- [ ] All expected repositories are present
- [ ] Repository names match expectations
- [ ] All branches are present
- [ ] All tags are present
- [ ] Commit history is complete
- [ ] Team members can access repositories
- [ ] Permissions are correctly set
- [ ] CI/CD pipelines function correctly (if applicable)

---

## Important Notes

### ⚠️ Warnings

1. **Overwrite Operations**: Choosing to overwrite existing repositories will **permanently delete** current content. Use with extreme caution.

2. **Organization Differences**: When restoring to a different organization, ensure:
   - Target organization has sufficient capacity
   - Team members have access to target organization
   - Any integrations are updated

3. **Project Name Changes**: If restoring to a new project name:
   - Update all documentation
   - Notify all team members
   - Update CI/CD pipeline references
   - Update any external integrations

### ⏱️ Time Estimates

- **Single Repository**: 5-15 minutes ✅ (Tested)
- **Single Project**: 30-60 minutes
- **Full Organization**: 2-4 hours (depends on repository count)

*Note: Times may vary based on repository sizes and network conditions.*

### 📞 Escalation

If you encounter issues during recovery:

1. **Check Logs**: Review script output and log files
2. **Verify Permissions**: Ensure all required permissions are in place
3. **Contact IT Support**: [Insert contact information]
4. **Emergency Contact**: [Insert emergency contact]

---

## Contact Information

### Technical Support

- **Primary Contact**: [Name/Email]
- **Backup Administrator**: [Name/Email]
- **Azure DevOps Admin**: [Name/Email]

### Emergency Contacts

- **After Hours**: [Contact Information]
- **Critical Issues**: [Contact Information]

### Documentation

- **Script Repository**: [GitHub/Internal Repository URL]
- **Technical Documentation**: [Link to README.md]
- **Azure Portal**: [Link]

---

## Appendix

### A. Common Error Messages and Solutions

| Error Message | Solution |
|--------------|----------|
| "Failed to connect to Azure Storage" | Verify Azure authentication and storage account details |
| "Repository already exists" | Choose Skip, Overwrite, or Abort option |
| "Git push failed" | Verify PAT token has Write permissions |
| "Project creation failed" | Verify PAT token has Project creation permissions |

### B. Recovery Time Objectives (RTO)

- **Critical Repositories**: [e.g., 1 hour]
- **Standard Repositories**: [e.g., 4 hours]
- **Archive Repositories**: [e.g., 24 hours]

### C. Recovery Point Objectives (RPO)

- **Maximum Data Loss**: [e.g., 24 hours] (based on daily backup schedule)

---

**Document Version**: 1.0  
**Last Updated**: [Date]  
**Next Review Date**: [Date]

---

*This document should be reviewed and updated quarterly or after any significant changes to the backup/recovery system.*
