# Azure DevOps Repository Backup and Recovery Guide

## Business Overview

This document provides a comprehensive guide for recovering Azure DevOps repositories from backups. The backup and restore system ensures business continuity by maintaining complete copies of all Git repositories in Azure Blob Storage.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Backup Process Overview](#backup-process-overview)
3. [Recovery Scenarios](#recovery-scenarios)
4. [Step-by-Step Recovery Procedures](#step-by-step-recovery-procedures)
5. [Recovery Checklist](#recovery-checklist)
6. [Post-Recovery Verification](#post-recovery-verification)
7. [Contact Information](#contact-information)

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
- Restore entire organization structure
- Restore individual projects
- Restore specific repositories
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

### Scenario 1: Complete Organization Recovery

**When to Use:**
- Entire Azure DevOps organization was deleted
- Migration to a new organization
- Disaster recovery situation

**What Gets Restored:**
- All projects
- All repositories within each project
- Complete repository structure

**Time Estimate:** [e.g., 2-4 hours depending on number of repositories]

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

**Time Estimate:** [e.g., 30-60 minutes per project]

---

### Scenario 3: Individual Repository Recovery

**When to Use:**
- Single repository was deleted
- Repository needs to be restored to different location
- Point-in-time recovery for specific repository

**What Gets Restored:**
- Selected repository only
- Can restore to different organization/project
- Can restore specific backup date

**Time Estimate:** [e.g., 5-15 minutes per repository]

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

### Recovery Procedure: Scenario 1 - Complete Organization Recovery

#### Step 1: Prepare Recovery Environment

1. Open PowerShell as Administrator
2. Navigate to the script directory
3. Verify Azure connection:
   ```powershell
   Connect-AzAccount
   Get-AzContext
   ```

**[SCREENSHOT PLACEHOLDER: Azure login and context verification]**

#### Step 2: Launch Restore Script

1. Run the restore script:
   ```powershell
   .\restoreRepos.ps1
   ```

**[SCREENSHOT PLACEHOLDER: Script startup screen]**

#### Step 3: Configure Storage Connection

1. Enter Azure Resource Group name: `[Your Resource Group]`
2. Enter Storage Account name: `[Your Storage Account]`
3. Enter Container name (default: `repobackups`)

**[SCREENSHOT PLACEHOLDER: Storage configuration prompts]**

#### Step 4: Review Available Backups

The script will display a table of all available backups organized by project and repository.

**[SCREENSHOT PLACEHOLDER: Backup listing table]**

Review the list to confirm:
- All expected projects are listed
- Latest backup dates are recent
- Repository counts match expectations

#### Step 5: Select Recovery Scenario

1. When prompted, select option **1** (Full Organization Restore)
2. Review the summary of repositories to be restored

**[SCREENSHOT PLACEHOLDER: Scenario selection and summary]**

#### Step 6: Configure Target Organization

1. Enter target Azure DevOps organization URL:
   ```
   https://dev.azure.com/YourOrganization
   ```
2. Choose authentication method:
   - Option Y: Use SYSTEM_ACCESSTOKEN environment variable
   - Option N: Enter Personal Access Token manually

**[SCREENSHOT PLACEHOLDER: Organization configuration]**

#### Step 7: Confirm and Execute

1. Review the restore summary:
   - Number of repositories to restore
   - Target organization
   - Backup dates to be used
2. Type **Y** to confirm and proceed

**[SCREENSHOT PLACEHOLDER: Confirmation prompt]**

#### Step 8: Monitor Recovery Progress

The script will:
- Create projects as needed (with confirmation prompts)
- Create repositories as needed
- Download and restore each repository
- Display progress for each operation

**[SCREENSHOT PLACEHOLDER: Recovery progress output]**

#### Step 9: Handle Existing Resources

If projects or repositories already exist:
- **Projects**: Script will prompt to create (Y/N)
- **Repositories**: Options will be:
  - **(S)kip**: Skip this repository
  - **(O)verwrite**: Replace existing repository (destructive)
  - **(A)bort**: Cancel entire restore operation

**[SCREENSHOT PLACEHOLDER: Conflict resolution prompts]**

#### Step 10: Verify Recovery Summary

At completion, review the summary:
- Total repositories processed
- Successful restores
- Failed restores (if any)

**[SCREENSHOT PLACEHOLDER: Recovery summary]**

---

### Recovery Procedure: Scenario 2 - Project Recovery

#### Step 1-3: Same as Scenario 1

Follow Steps 1-3 from Complete Organization Recovery.

#### Step 4: Select Project to Restore

1. Review the list of available projects
2. Note the project index number
3. When prompted, select option **2** (Project Restore)
4. Enter the project number to restore

**[SCREENSHOT PLACEHOLDER: Project selection]**

#### Step 5: Specify Target Project Name

1. Enter target project name:
   - Can be same as source project name
   - Can be a new project name
   - Example: If source is "LegacyProject", target can be "NewProject"

**[SCREENSHOT PLACEHOLDER: Target project name prompt]**

#### Step 6-10: Complete Recovery

Follow Steps 6-10 from Complete Organization Recovery, but note:
- Only repositories from the selected project will be restored
- All repositories will be restored to the specified target project

---

### Recovery Procedure: Scenario 3 - Individual Repository Recovery

#### Step 1-3: Same as Scenario 1

Follow Steps 1-3 from Complete Organization Recovery.

#### Step 4: Select Repository

1. Review the backup table
2. Note the repository key (format: X.Y, e.g., 1.3)
3. When prompted, select option **3** (Repository Restore)
4. Enter the repository key (e.g., `1.3`)

**[SCREENSHOT PLACEHOLDER: Repository key selection]**

#### Step 5: Select Backup Date

1. Review available backup dates for the repository
2. Select backup date:
   - Option 1: Latest backup (recommended)
   - Other options: Specific historical date
3. Enter the number corresponding to your choice

**[SCREENSHOT PLACEHOLDER: Backup date selection]**

#### Step 6: Configure Target Location

1. Enter target project name (can be different from source)
2. Enter target repository name (can be different from source)
3. Enter target organization URL (can be different from source)

**[SCREENSHOT PLACEHOLDER: Target configuration]**

#### Step 7-10: Complete Recovery

Follow Steps 7-10 from Complete Organization Recovery.

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

**[SCREENSHOT PLACEHOLDER: Repository list in Azure DevOps]**

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

**[SCREENSHOT PLACEHOLDER: Git branch/tag verification]**

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

- **Full Organization**: 2-4 hours (depends on repository count)
- **Single Project**: 30-60 minutes
- **Single Repository**: 5-15 minutes

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

