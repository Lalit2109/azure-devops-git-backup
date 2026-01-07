<#
.SYNOPSIS
    Restores Azure DevOps Git repositories from Azure Blob Storage backups.

.DESCRIPTION
    This script restores Git repositories from Azure Blob Storage backups to Azure DevOps.
    Supports three restore scenarios:
    1. Full organization restore - restores all projects/repos from backup
    2. Project restore - restores all repos from a specific project (can use new project name)
    3. Repository restore - restores a specific repository (can restore to different org/project)

.PARAMETER ResourceGroupName
    Azure Resource Group name containing the storage account.

.PARAMETER StorageAccountName
    Azure Storage Account name.

.PARAMETER ContainerName
    Azure Blob Storage container name. Default: "repobackups"

.PARAMETER LogPath
    Path to log file. Default: ".\restore-$(Get-Date -Format 'yyyy-MM-dd').log"

.PARAMETER AzureDevOpsAccount
    Target Azure DevOps organization URL.

.PARAMETER AccessToken
    Azure DevOps Personal Access Token. If not provided, will prompt for input.

.EXAMPLE
    .\restoreRepos.ps1

.EXAMPLE
    .\restoreRepos.ps1 -ResourceGroupName "<ResourceGroupName>" -StorageAccountName "<StorageAccountName>"

.NOTES
    Requires: VSTeam PowerShell module, Az.Storage module, Git
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory = $false)]
    [string]$ContainerName = "repobackups",
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\restore-$(Get-Date -Format 'yyyy-MM-dd').log",
    
    [Parameter(Mandatory = $false)]
    [string]$AzureDevOpsAccount,
    
    [Parameter(Mandatory = $false)]
    [string]$AccessToken
)

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Use string formatting to avoid quote issues - PowerShell best practice
    $logMessage = "{0} [LOG] [{1}] {2}" -f $timestamp, $Level, $Message
    
    # Write to console with colors - standard PowerShell Write-Host
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage }
    }
    
    # Write to log file if LogPath is defined
    if ($LogPath) {
        try {
            Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
        } catch {
            # If log file write fails, continue without logging
        }
    }
}

function Read-UserInput {
    param(
        [string]$Prompt,
        [switch]$AsSecureString
    )
    
    Write-Host ""
    Write-Host ">>> [INPUT] $Prompt" -ForegroundColor Cyan
    if ($AsSecureString) {
        return Read-Host -AsSecureString
    } else {
        return Read-Host
    }
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..." "INFO"
    
    $prerequisites = @{
        "Git" = "git"
        "VSTeam Module" = "VSTeam"
        "Az.Storage Module" = "Az.Storage"
    }
    
    $allPresent = $true
    
    foreach ($prereq in $prerequisites.GetEnumerator()) {
        if ($prereq.Value -eq "git") {
            try {
                $null = git --version 2>&1
                Write-Log "$($prereq.Key) is installed" "SUCCESS"
            } catch {
                Write-Log "$($prereq.Key) is not installed or not in PATH" "ERROR"
                $allPresent = $false
            }
        } else {
            $module = Get-Module -ListAvailable -Name $prereq.Value
            if ($module) {
                Write-Log "$($prereq.Key) module is installed" "SUCCESS"
            } else {
                Write-Log "$($prereq.Key) module is not installed" "ERROR"
                $allPresent = $false
            }
        }
    }
    
    return $allPresent
}

function Install-RequiredModules {
    Write-Log "Installing required PowerShell modules..." "INFO"
    
    try {
        if (-not (Get-Module -ListAvailable -Name VSTeam)) {
            Write-Log "Installing VSTeam module..." "INFO"
            Install-Module -Name VSTeam -Scope CurrentUser -Force -ErrorAction Stop
        }
        
        if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
            Write-Log "Installing Az.Storage module..." "INFO"
            Install-Module -Name Az.Storage -Scope CurrentUser -Force -ErrorAction Stop
        }
        
        Import-Module VSTeam -ErrorAction Stop
        Import-Module Az.Storage -ErrorAction Stop
        
        Write-Log "Modules installed and imported successfully" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed to install/import modules: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Get-AvailableBackups {
    param(
        [object]$StorageContext,
        [string]$ContainerName
    )
    
    Write-Log "Scanning storage account for available backups..." "INFO"
    
    try {
        $allBlobs = Get-AzStorageBlob -Container $ContainerName -Context $StorageContext | 
            Where-Object { $_.Name -like "*/*/*.zip" -and $_.Name -notlike "backup-manifest*" }
        
        $backupStructure = @{}
        
        foreach ($blob in $allBlobs) {
            # Parse blob path: ProjectName/RepositoryName/YYYY-MM-DD.zip
            $parts = $blob.Name.Split('/')
            if ($parts.Count -ge 3) {
                $projectName = $parts[0]
                $repoName = $parts[1]
                $fileName = $parts[-1]
                $dateString = $fileName.Replace('.zip', '')
                
                if (-not $backupStructure.ContainsKey($projectName)) {
                    $backupStructure[$projectName] = @{}
                }
                
                if (-not $backupStructure[$projectName].ContainsKey($repoName)) {
                    $backupStructure[$projectName][$repoName] = @()
                }
                
                $backupInfo = @{
                    Date = $dateString
                    BlobName = $blob.Name
                    SizeMB = [math]::Round($blob.Length / 1MB, 2)
                    LastModified = $blob.LastModified
                }
                
                # Check if this backup already exists (by blob name) to avoid duplicates
                $existingBackup = $backupStructure[$projectName][$repoName] | Where-Object { $_.BlobName -eq $blob.Name }
                if (-not $existingBackup) {
                    $backupStructure[$projectName][$repoName] += $backupInfo
                }
            }
        }
        
        # Sort backups by date for each repo
        foreach ($project in $backupStructure.Keys) {
            foreach ($repo in @($backupStructure[$project].Keys)) {
                $backupStructure[$project][$repo] = @($backupStructure[$project][$repo] | 
                    Sort-Object { [DateTime]::ParseExact($_.Date, 'yyyy-MM-dd', $null) } -Descending)
            }
        }
        
        Write-Log "Found $($backupStructure.Count) projects with backups" "SUCCESS"
        return $backupStructure
    } catch {
        Write-Log "Failed to scan backups: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Get-LatestBackupDate {
    param(
        [array]$Backups
    )
    
    if ($Backups.Count -eq 0) {
        return $null
    }
    
    # Backups are already sorted by date descending
    return $Backups[0].Date
}

function Select-RestoreScenario {
    Write-Log "========================================" "INFO"
    Write-Log "Restore Scenario Selection" "INFO"
    Write-Log "========================================" "INFO"
    Write-Log "1. Full Organization Restore - Restore all projects/repos from backup" "INFO"
    Write-Log "2. Project Restore - Restore all repos from a specific project" "INFO"
    Write-Log "3. Repository Restore - Restore a specific repository" "INFO"
    Write-Log "========================================" "INFO"
    
    $choice = ""
    while ($choice -notin @("1", "2", "3")) {
        $choice = Read-UserInput -Prompt "Select restore scenario (1, 2, or 3)"
        if ($choice -notin @("1", "2", "3")) {
            Write-Log "Invalid choice. Please enter 1, 2, or 3." "WARNING"
        }
    }
    
    return [int]$choice
}

function Display-AvailableBackups {
    param(
        [hashtable]$BackupStructure,
        [hashtable]$ProjectNameMapping = @{},
        [hashtable]$RepoNameMapping = @{}
    )
    
    Write-Log "========================================" "INFO"
    Write-Log "Available Backups" "INFO"
    Write-Log "========================================" "INFO"
    
    $projectIndex = 1
    $repoIndexMap = @{}
    $tableData = @()
    
    foreach ($project in ($BackupStructure.Keys | Sort-Object)) {
        # Use original project name if available
        $displayProjectName = if ($ProjectNameMapping.ContainsKey($project)) { $ProjectNameMapping[$project] } else { $project }
        
        $repoIndex = 1
        foreach ($repo in ($BackupStructure[$project].Keys | Sort-Object)) {
            $backups = @($BackupStructure[$project][$repo])
            $latest = Get-LatestBackupDate -Backups $backups
            $latestBackupObj = $backups | Where-Object { 
                $backupDate = if ($_.GetType().Name -eq 'Hashtable') { $_.Date } else { $_.Date }
                $backupDate -eq $latest
            } | Select-Object -First 1
            
            if ($latestBackupObj) {
                # Handle both hashtable and PSCustomObject - try multiple access methods
                if ($latestBackupObj.GetType().Name -eq 'Hashtable' -or $latestBackupObj.GetType().Name -eq 'OrderedDictionary') {
                    $latestSize = if ($latestBackupObj.ContainsKey('SizeMB')) { $latestBackupObj['SizeMB'] } else { 0 }
                } else {
                    $latestSize = if ($latestBackupObj.PSObject.Properties['SizeMB']) { $latestBackupObj.SizeMB } else { 0 }
                }
            } else {
                $latestSize = 0
            }
            
            # Get original repository name if available
            $mappingKey = "$project|$repo"
            $displayRepoName = if ($RepoNameMapping.ContainsKey($mappingKey)) { 
                $RepoNameMapping[$mappingKey].OriginalRepository 
            } else { 
                $repo 
            }
            
            $key = "$projectIndex.$repoIndex"
            $repoIndexMap[$key] = @{
                Project = $project  # Keep sanitized for blob lookup
                Repository = $repo   # Keep sanitized for blob lookup
                DisplayProject = $displayProjectName  # Original name for display
                DisplayRepository = $displayRepoName  # Original name for display
            }
            
            $tableData += [PSCustomObject]@{
                Key = $key
                Project = $displayProjectName
                Repository = $displayRepoName
                LatestBackup = $latest
                Size = if ($latestSize -gt 0) { "$latestSize MB" } else { "N/A" }
                TotalBackups = $backups.Count
            }
            
            $repoIndex++
        }
        
        $projectIndex++
    }
    
    # Display as table
    if ($tableData.Count -gt 0) {
        Write-Host ""
        $tableOutput = $tableData | Format-Table -AutoSize | Out-String
        Write-Host $tableOutput
        # Also log to file (split by lines)
        $tableOutput -split "`n" | ForEach-Object {
            if ($_.Trim() -ne "") {
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $logMessage = "{0} [INFO] {1}" -f $timestamp, $_
                if ($LogPath) {
                    try {
                        Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
                    } catch {
                        # If log file write fails, continue without logging
                    }
                }
            }
        }
        Write-Host ""
    } else {
        Write-Log "No backups found" "WARNING"
    }
    
    Write-Log "========================================" "INFO"
    
    return $repoIndexMap
}

function Select-BackupDate {
    param(
        [array]$Backups,
        [string]$ProjectName,
        [string]$RepoName
    )
    
    if ($Backups.Count -eq 1) {
        Write-Log "Only one backup available: $($Backups[0].Date)" "INFO"
        return $Backups[0].Date
    }
    
    Write-Log "Available backups for $($ProjectName)/$($RepoName):" "INFO"
    for ($i = 0; $i -lt $Backups.Count; $i++) {
        $backup = $Backups[$i]
        $marker = if ($i -eq 0) { " (Latest)" } else { "" }
        Write-Log "  [$($i + 1)] $($backup.Date) - $($backup.SizeMB) MB$marker" "INFO"
    }
    
    $choice = ""
    while ($choice -eq "" -or ([int]$choice -lt 1 -or [int]$choice -gt $Backups.Count)) {
        $choice = Read-UserInput -Prompt "Select backup date (1-$($Backups.Count), default: 1 for latest)"
        if ($choice -eq "") {
            $choice = "1"
        }
        if ([int]$choice -lt 1 -or [int]$choice -gt $Backups.Count) {
            Write-Log "Invalid choice. Please enter a number between 1 and $($Backups.Count)." "WARNING"
            $choice = ""
        }
    }
    
    return $Backups[[int]$choice - 1].Date
}

function Get-BackupBlob {
    param(
        [object]$StorageContext,
        [string]$ContainerName,
        [string]$BlobName,
        [string]$LocalPath
    )
    
    if ([string]::IsNullOrWhiteSpace($BlobName)) {
        Write-Log "Error: BlobName is empty or null. Cannot download backup." "ERROR"
        return $false
    }
    
    Write-Log "Downloading backup: $BlobName" "INFO"
    
    try {
        Get-AzStorageBlobContent -Blob $BlobName -Container $ContainerName -Context $StorageContext -Destination $LocalPath -Force -ErrorAction Stop
        Write-Log "Backup downloaded successfully" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed to download backup: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Get-OriginalNamesFromManifest {
    param(
        [object]$StorageContext,
        [string]$ContainerName
    )
    
    Write-Log "Reading manifest to get original repository and project names..." "INFO"
    
    try {
        # Try to get the latest manifest
        $manifestBlob = Get-AzStorageBlob -Blob "backup-manifest.json" -Container $ContainerName -Context $StorageContext -ErrorAction SilentlyContinue
        if (-not $manifestBlob) {
            Write-Log "Manifest not found. Will use names from blob paths." "WARNING"
            return @{}, @{}
        }
        
        $tempManifestPath = Join-Path $env:TEMP "manifest-$(Get-Date -Format 'yyyyMMddHHmmss').json"
        Get-AzStorageBlobContent -Blob "backup-manifest.json" -Container $ContainerName -Context $StorageContext -Destination $tempManifestPath -Force -ErrorAction Stop
        
        $manifestContent = Get-Content $tempManifestPath -Raw | ConvertFrom-Json
        Remove-Item $tempManifestPath -Force -ErrorAction SilentlyContinue
        
        # Create mapping: sanitized blob path -> original names
        $repoNameMapping = @{}
        $projectNameMapping = @{}
        
        foreach ($repo in $manifestContent.Repositories) {
            if ($repo.Status -eq "Success" -and $repo.BlobPath) {
                # Extract sanitized project/repo from BlobPath (format: ProjectName/RepositoryName/YYYY-MM-DD.zip)
                $pathParts = $repo.BlobPath.Split('/')
                if ($pathParts.Count -ge 2) {
                    $sanitizedProject = $pathParts[0]
                    $sanitizedRepo = $pathParts[1]
                    $mappingKey = "$sanitizedProject|$sanitizedRepo"
                    
                    # Decode URL-encoded names from manifest (e.g., My%20Repo -> My Repo, My%25%25Repo -> My%%Repo)
                    $decodedProject = $repo.Project
                    $decodedRepository = $repo.Repository
                    
                    try {
                        if (-not [string]::IsNullOrWhiteSpace($repo.Project)) {
                            $decodedProject = [System.Uri]::UnescapeDataString($repo.Project)
                        }
                    } catch {
                        # If decoding fails, use original value
                        Write-Log "Could not decode project name '$($repo.Project)', using as-is" "WARNING"
                    }
                    
                    try {
                        if (-not [string]::IsNullOrWhiteSpace($repo.Repository)) {
                            $decodedRepository = [System.Uri]::UnescapeDataString($repo.Repository)
                        }
                    } catch {
                        # If decoding fails, use original value
                        Write-Log "Could not decode repository name '$($repo.Repository)', using as-is" "WARNING"
                    }
                    
                    # Store repository mapping with decoded names
                    $repoNameMapping[$mappingKey] = @{
                        OriginalProject = $decodedProject
                        OriginalRepository = $decodedRepository
                    }
                    
                    # Store project mapping (sanitized -> original decoded)
                    if (-not $projectNameMapping.ContainsKey($sanitizedProject)) {
                        $projectNameMapping[$sanitizedProject] = $decodedProject
                    }
                }
            }
        }
        
        Write-Log "Found $($repoNameMapping.Count) repository name mappings and $($projectNameMapping.Count) project name mappings in manifest" "SUCCESS"
        return @{
            RepoMapping = $repoNameMapping
            ProjectMapping = $projectNameMapping
        }
    } catch {
        Write-Log "Could not read manifest for original names: $($_.Exception.Message)" "WARNING"
        return @{
            RepoMapping = @{}
            ProjectMapping = @{}
        }
    }
}

function Get-AuthenticatedUrl {
    param(
        [string]$Url,
        [string]$AccessToken
    )
    
    if ([string]::IsNullOrWhiteSpace($Url)) {
        throw "URL cannot be empty"
    }
    
    if ([string]::IsNullOrWhiteSpace($AccessToken)) {
        throw "AccessToken cannot be empty"
    }
    
    # Handle URLs that may already have credentials (e.g., https://orgname@dev.azure.com/...)
    # Find the @ symbol or the first / after https://
    $schemeEnd = $Url.IndexOf('://') + 3
    if ($schemeEnd -lt 3) {
        throw "Invalid URL format: $Url"
    }
    
    $atIndex = $Url.IndexOf('@', $schemeEnd)
    $firstSlashIndex = $Url.IndexOf('/', $schemeEnd)
    
    if ($atIndex -gt 0 -and ($firstSlashIndex -lt 0 -or $atIndex -lt $firstSlashIndex)) {
        # URL has existing credentials (e.g., orgname@), remove them
        $urlAfterAt = $Url.Substring($atIndex + 1)
        $authenticatedUrl = "https://$AccessToken@$urlAfterAt"
    } else {
        # No existing credentials, add token after scheme
        $urlAfterScheme = $Url.Substring($schemeEnd)
        $authenticatedUrl = "https://$AccessToken@$urlAfterScheme"
    }
    
    return $authenticatedUrl
}

function Create-ProjectIfNeeded {
    param(
        [string]$ProjectName,
        [string]$OrgUrl,
        [string]$AccessToken
    )
    
    try {
        # Check if project exists
        $existingProject = $null
        try {
            $existingProject = Get-VSTeamProject -Name $ProjectName -ErrorAction Stop
        } catch {
            # Project doesn't exist or error occurred - this is expected for new projects
            $existingProject = $null
        }
        
        if ($existingProject) {
            Write-Log "Project '$ProjectName' already exists" "INFO"
            return $true
        }
        
        # Ask for confirmation
        Write-Log "Project '$ProjectName' does not exist" "WARNING"
        $confirm = Read-UserInput -Prompt "Create new project '$ProjectName'? (Y/N)"
        if ($confirm -ne "Y" -and $confirm -ne "y") {
            Write-Log "Project creation cancelled by user" "WARNING"
            return $false
        }
        
        # Create project
        Write-Log "Creating project '$ProjectName'..." "INFO"
        $newProject = Add-VSTeamProject -Name $ProjectName -Description "Restored from backup" -ErrorAction Stop
        Write-Log "Project '$ProjectName' created successfully" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed to create project '$ProjectName': $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Create-RepositoryIfNeeded {
    param(
        [string]$ProjectName,
        [string]$RepositoryName,
        [string]$OrgUrl,
        [string]$AccessToken
    )
    
    try {
        # Check if repository exists
        $existingRepo = $null
        try {
            $existingRepo = Get-VSTeamGitRepository -ProjectName $ProjectName -Name $RepositoryName -ErrorAction Stop
        } catch {
            # Repository doesn't exist or error occurred - this is expected for new repositories
            $existingRepo = $null
        }
        
        if ($existingRepo) {
            Write-Log "Repository '$RepositoryName' already exists in project '$ProjectName'" "WARNING"
            $action = Read-UserInput -Prompt "Repository exists. Options: (S)kip, (O)verwrite, (A)bort [Default: Skip]"
            if ($action -eq "" -or $action -eq "S" -or $action -eq "s") {
                Write-Log "Skipping repository restore" "INFO"
                return $null
            } elseif ($action -eq "A" -or $action -eq "a") {
                throw "Restore aborted by user"
            } elseif ($action -eq "O" -or $action -eq "o") {
                Write-Log "Will overwrite existing repository" "WARNING"
                return $existingRepo
            } else {
                Write-Log "Invalid choice. Skipping repository." "WARNING"
                return $null
            }
        }
        
        # Create repository
        Write-Log "Creating repository '$RepositoryName' in project '$ProjectName'..." "INFO"
        $newRepo = Add-VSTeamGitRepository -ProjectName $ProjectName -Name $RepositoryName -ErrorAction Stop
        Write-Log "Repository '$RepositoryName' created successfully" "SUCCESS"
        return $newRepo
    } catch {
        Write-Log "Failed to create repository '$RepositoryName': $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Restore-Repository {
    param(
        [object]$StorageContext,
        [string]$ContainerName,
        [string]$BlobName,
        [string]$TargetRepoUrl,
        [string]$AccessToken
    )
    
    $tempDir = Join-Path $env:TEMP "restore-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $zipPath = Join-Path $tempDir "backup.zip"
    $extractPath = Join-Path $tempDir "extracted"
    
    try {
        # Create temp directory
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
        
        # Download backup
        if (-not (Get-BackupBlob -StorageContext $StorageContext -ContainerName $ContainerName -BlobName $BlobName -LocalPath $zipPath)) {
            throw "Failed to download backup"
        }
        
        # Extract backup
        Write-Log "Extracting backup..." "INFO"
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force -ErrorAction Stop
        
        # Find the .git directory (should be the only directory in extracted folder)
        $gitDirs = Get-ChildItem -Path $extractPath -Directory -Filter "*.git"
        if ($gitDirs.Count -eq 0) {
            # Try to find any directory
            $gitDirs = Get-ChildItem -Path $extractPath -Directory
        }
        
        if ($gitDirs.Count -eq 0) {
            throw "No repository directory found in backup"
        }
        
        $repoPath = $gitDirs[0].FullName
        
        # Validate it's a git repository
        Push-Location $repoPath
        try {
            $gitCheck = git rev-parse --git-dir 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Extracted directory is not a valid git repository"
            }
        } finally {
            Pop-Location
        }
        
        Write-Log "Repository structure validated" "SUCCESS"
        
        # Construct authenticated URL
        $authenticatedUrl = Get-AuthenticatedUrl -Url $TargetRepoUrl -AccessToken $AccessToken
        
        # Push to target repository
        Write-Log "Pushing repository to target..." "INFO"
        Push-Location $repoPath
        try {
            $pushOutput = & git push --mirror $authenticatedUrl 2>&1
            $exitCode = $LASTEXITCODE
            
            if ($exitCode -ne 0) {
                $errorDetails = $pushOutput | Out-String
                throw "Git push failed with exit code $exitCode. Output: $errorDetails"
            }
            
            Write-Log "Repository restored successfully" "SUCCESS"
        } finally {
            Pop-Location
        }
        
        return $true
    } catch {
        Write-Log "Failed to restore repository: $($_.Exception.Message)" "ERROR"
        return $false
    } finally {
        # Cleanup
        if (Test-Path $tempDir) {
            Write-Log "Cleaning up temporary files..." "INFO"
            Remove-Item -Recurse -Force -Path $tempDir -ErrorAction SilentlyContinue
        }
    }
}

#endregion

#region Main Script

try {
    Write-Log "========================================" "INFO"
    Write-Log "Azure DevOps Repository Restore Script" "INFO"
    Write-Log "========================================" "INFO"
    Write-Log "Start time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    
    # Check prerequisites
    if (-not (Test-Prerequisites)) {
        Write-Log "Some prerequisites are missing. Attempting to install modules..." "WARNING"
        if (-not (Install-RequiredModules)) {
            throw "Failed to install required modules. Please install manually."
        }
    }
    
    # Import modules
    Import-Module VSTeam -ErrorAction Stop
    Import-Module Az.Storage -ErrorAction Stop
    
    # Get storage account details
    if (-not $ResourceGroupName -or -not $StorageAccountName -or -not $ContainerName) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor DarkGray
        Write-Host "Azure Storage Configuration" -ForegroundColor White
        Write-Host "========================================" -ForegroundColor DarkGray
        Write-Host ""
    }
    
    if (-not $ResourceGroupName) {
        $ResourceGroupName = Read-UserInput -Prompt "Enter Azure Resource Group name"
    }
    
    if (-not $StorageAccountName) {
        $StorageAccountName = Read-UserInput -Prompt "Enter Azure Storage Account name"
    }
    
    if (-not $ContainerName) {
        $ContainerName = Read-UserInput -Prompt "Enter Container name (default: repobackups)"
        if ($ContainerName -eq "") {
            $ContainerName = "repobackups"
        }
    }
    
    # Connect to Azure Storage
    Write-Log "Connecting to Azure Storage Account: $StorageAccountName" "INFO"
    try {
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
        $storageContext = $storageAccount.Context
        Write-Log "Successfully connected to storage account" "SUCCESS"
    } catch {
        throw "Failed to connect to Azure Storage Account: $($_.Exception.Message)"
    }
    
    # Check container exists
    Write-Log "Checking container: $ContainerName" "INFO"
    $container = Get-AzStorageContainer -Name $ContainerName -Context $storageContext -ErrorAction SilentlyContinue
    if (-not $container) {
        throw "Container '$ContainerName' does not exist in storage account"
    }
    
    # Get available backups
    $backupStructure = Get-AvailableBackups -StorageContext $storageContext -ContainerName $ContainerName
    
    if ($backupStructure.Count -eq 0) {
        Write-Log "No backups found in storage account" "WARNING"
        exit 0
    }
    
    # Get original names from manifest
    $nameMappings = Get-OriginalNamesFromManifest -StorageContext $storageContext -ContainerName $ContainerName
    $repoNameMapping = $nameMappings.RepoMapping
    $projectNameMapping = $nameMappings.ProjectMapping
    
    # Display available backups
    $repoIndexMap = Display-AvailableBackups -BackupStructure $backupStructure -ProjectNameMapping $projectNameMapping -RepoNameMapping $repoNameMapping
    
    # Select restore scenario
    $scenario = Select-RestoreScenario
    
    # Get target Azure DevOps details
    if (-not $AzureDevOpsAccount) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor DarkGray
        Write-Host "Azure DevOps Configuration" -ForegroundColor White
        Write-Host "========================================" -ForegroundColor DarkGray
        Write-Host ""
        $AzureDevOpsAccount = Read-UserInput -Prompt "Enter target Azure DevOps organization URL (e.g., https://dev.azure.com/YourOrganization)"
    }
    
    # Get Personal Access Token
    if (-not $AccessToken) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor DarkGray
        Write-Host "Authentication" -ForegroundColor White
        Write-Host "========================================" -ForegroundColor DarkGray
        Write-Host ""
        $secureToken = Read-UserInput -Prompt "Enter Azure DevOps Personal Access Token" -AsSecureString
        if ($secureToken -and $secureToken -is [SecureString]) {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
            try {
                $AccessToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            } finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            }
        } else {
            throw "Failed to read Personal Access Token."
        }
    } else {
        # AccessToken was provided as parameter, convert if SecureString
        if ($AccessToken -is [SecureString]) {
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AccessToken)
            try {
                $AccessToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            } finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            }
        }
    }
    
    if (-not $AccessToken -or ($AccessToken -is [string] -and $AccessToken.Trim() -eq "")) {
        throw "AccessToken is required. Please provide a valid Azure DevOps Personal Access Token."
    }
    
    # Configure Azure DevOps connection
    Write-Log "Configuring Azure DevOps account: $AzureDevOpsAccount" "INFO"
    try {
        Set-VSTeamAccount -Account $AzureDevOpsAccount -Token $AccessToken -UseBearerToken -ErrorAction Stop
        Write-Log "Successfully connected to Azure DevOps" "SUCCESS"
    } catch {
        throw "Failed to connect to Azure DevOps: $($_.Exception.Message)"
    }
    
    # Process restore based on scenario
    $restoreList = @()
    $successCount = 0
    $failureCount = 0
    
    if ($scenario -eq 1) {
        # Scenario 1: Full Org Restore
        Write-Log "========================================" "INFO"
        Write-Log "Full Organization Restore" "INFO"
        Write-Log "========================================" "INFO"
        
        foreach ($project in ($backupStructure.Keys | Sort-Object)) {
            # Get original project name
            $originalProject = if ($projectNameMapping.ContainsKey($project)) { 
                $projectNameMapping[$project] 
            } else { 
                $project 
            }
            
            foreach ($repo in ($backupStructure[$project].Keys | Sort-Object)) {
                $backups = @($backupStructure[$project][$repo])
                $latestDate = Get-LatestBackupDate -Backups $backups
                $backupBlob = ($backups | Where-Object { $_.Date -eq $latestDate } | Select-Object -First 1)
                
                if (-not $backupBlob -or -not $backupBlob.BlobName) {
                    Write-Log "Warning: No backup found for $project/$repo with date $latestDate. Skipping." "WARNING"
                    continue
                }
                
                # Get original repository name from mapping
                $mappingKey = "$project|$repo"
                $originalRepo = $repo
                
                if ($repoNameMapping.ContainsKey($mappingKey)) {
                    $originalRepo = $repoNameMapping[$mappingKey].OriginalRepository
                }
                
                $restoreList += @{
                    SourceProject = $originalProject
                    SourceRepo = $originalRepo
                    TargetProject = $originalProject
                    TargetRepo = $originalRepo
                    BackupDate = $latestDate
                    BlobName = $backupBlob.BlobName
                }
            }
        }
        
        Write-Log "Will restore $($restoreList.Count) repositories" "INFO"
        $confirm = Read-UserInput -Prompt "Proceed with full restore? (Y/N)"
        if ($confirm -ne "Y" -and $confirm -ne "y") {
            Write-Log "Restore cancelled by user" "INFO"
            exit 0
        }
        
    } elseif ($scenario -eq 2) {
        # Scenario 2: Project Restore
        Write-Log "========================================" "INFO"
        Write-Log "Project Restore" "INFO"
        Write-Log "========================================" "INFO"
        
        # List projects with original names
        $projects = $backupStructure.Keys | Sort-Object
        Write-Log "Available projects:" "INFO"
        for ($i = 0; $i -lt $projects.Count; $i++) {
            $sanitizedProject = $projects[$i]
            $displayProjectName = if ($projectNameMapping.ContainsKey($sanitizedProject)) { 
                $projectNameMapping[$sanitizedProject] 
            } else { 
                $sanitizedProject 
            }
            Write-Log "  [$($i + 1)] $displayProjectName" "INFO"
        }
        
        $projectChoice = ""
        while ($projectChoice -eq "" -or ([int]$projectChoice -lt 1 -or [int]$projectChoice -gt $projects.Count)) {
            $projectChoice = Read-UserInput -Prompt "Select source project (1-$($projects.Count))"
            if ([int]$projectChoice -lt 1 -or [int]$projectChoice -gt $projects.Count) {
                Write-Log "Invalid choice. Please enter a number between 1 and $($projects.Count)." "WARNING"
                $projectChoice = ""
            }
        }
        
        $sourceProject = $projects[[int]$projectChoice - 1]
        $originalSourceProject = if ($projectNameMapping.ContainsKey($sourceProject)) { 
            $projectNameMapping[$sourceProject] 
        } else { 
            $sourceProject 
        }
        
        Write-Log "Selected source project: $originalSourceProject" "INFO"
        
        # Get target project name with default "<ProjectName> Restored"
        $defaultTargetProject = "$originalSourceProject Restored"
        $targetProject = Read-UserInput -Prompt "Enter target project name (can be new/different, default: $defaultTargetProject)"
        if ($targetProject -eq "") {
            $targetProject = $defaultTargetProject
        }
        
        # Build restore list for all repos in the project
        foreach ($repo in ($backupStructure[$sourceProject].Keys | Sort-Object)) {
            $backups = @($backupStructure[$sourceProject][$repo])
            $latestDate = Get-LatestBackupDate -Backups $backups
            $backupBlob = ($backups | Where-Object { $_.Date -eq $latestDate } | Select-Object -First 1)
            
            if (-not $backupBlob -or -not $backupBlob.BlobName) {
                Write-Log "Warning: No backup found for $sourceProject/$repo with date $latestDate. Skipping." "WARNING"
                continue
            }
            
            # Get original repository name from mapping
            $mappingKey = "$sourceProject|$repo"
            $originalRepo = $repo
            
            if ($repoNameMapping.ContainsKey($mappingKey)) {
                $originalRepo = $repoNameMapping[$mappingKey].OriginalRepository
                Write-Log "Using original repository name: $originalRepo (from blob: $repo)" "INFO"
            }
            
            $restoreList += @{
                SourceProject = $originalSourceProject
                SourceRepo = $originalRepo
                TargetProject = $targetProject
                TargetRepo = $originalRepo
                BackupDate = $latestDate
                BlobName = $backupBlob.BlobName
            }
        }
        
        Write-Log "Will restore $($restoreList.Count) repositories to project '$targetProject'" "INFO"
        $confirm = Read-UserInput -Prompt "Proceed with project restore? (Y/N)"
        if ($confirm -ne "Y" -and $confirm -ne "y") {
            Write-Log "Restore cancelled by user" "INFO"
            exit 0
        }
        
    } elseif ($scenario -eq 3) {
        # Scenario 3: Repository Restore
        Write-Log "========================================" "INFO"
        Write-Log "Repository Restore" "INFO"
        Write-Log "========================================" "INFO"
        
        # Select repository
        Write-Log "Enter repository key (e.g., 1.1, 2.3):" "INFO"
        $repoKey = Read-UserInput -Prompt "Repository key"
        
        if (-not $repoIndexMap.ContainsKey($repoKey)) {
            throw "Invalid repository key: $repoKey"
        }
        
        $selectedRepo = $repoIndexMap[$repoKey]
        $sourceProject = $selectedRepo.Project  # Sanitized for blob lookup
        $sourceRepo = $selectedRepo.Repository   # Sanitized for blob lookup
        
        # Get original names
        $originalSourceProject = if ($projectNameMapping.ContainsKey($sourceProject)) { 
            $projectNameMapping[$sourceProject] 
        } else { 
            $sourceProject 
        }
        
        $mappingKey = "$sourceProject|$sourceRepo"
        $originalSourceRepo = $sourceRepo
        if ($repoNameMapping.ContainsKey($mappingKey)) {
            $originalSourceRepo = $repoNameMapping[$mappingKey].OriginalRepository
        }
        
        Write-Log "Selected repository: $($originalSourceProject)/$($originalSourceRepo)" "INFO"
        
        # Select backup date
        $backups = @($backupStructure[$sourceProject][$sourceRepo])
        $backupDate = Select-BackupDate -Backups $backups -ProjectName $originalSourceProject -RepoName $originalSourceRepo
        $backupBlob = ($backups | Where-Object { $_.Date -eq $backupDate } | Select-Object -First 1)
        
        if (-not $backupBlob -or -not $backupBlob.BlobName) {
            throw "No backup found for $originalSourceProject/$originalSourceRepo with date $backupDate"
        }
        
        # Get target project
        $targetProject = Read-UserInput -Prompt "Enter target project name (can be different, default: $originalSourceProject)"
        if ($targetProject -eq "") {
            $targetProject = $originalSourceProject
        }
        
        # Get target repo name
        $targetRepo = Read-UserInput -Prompt "Enter target repository name (can be different, default: $originalSourceRepo)"
        if ($targetRepo -eq "") {
            $targetRepo = $originalSourceRepo
        }
        
        $restoreList += @{
            SourceProject = $originalSourceProject
            SourceRepo = $originalSourceRepo
            TargetProject = $targetProject
            TargetRepo = $targetRepo
            BackupDate = $backupDate
            BlobName = $backupBlob.BlobName
        }
    }
    
    # Execute restores
    Write-Log "========================================" "INFO"
    Write-Log "Starting Restore Operations" "INFO"
    Write-Log "========================================" "INFO"
    
    foreach ($restoreItem in $restoreList) {
        try {
            Write-Log "----------------------------------------" "INFO"
            Write-Log "Restoring: $($restoreItem.SourceProject)/$($restoreItem.SourceRepo) -> $($restoreItem.TargetProject)/$($restoreItem.TargetRepo)" "INFO"
            Write-Log "Backup date: $($restoreItem.BackupDate)" "INFO"
            
            # Create project if needed
            if (-not (Create-ProjectIfNeeded -ProjectName $restoreItem.TargetProject -OrgUrl $AzureDevOpsAccount -AccessToken $AccessToken)) {
                Write-Log "Skipping restore due to project creation failure" "WARNING"
                $failureCount++
                continue
            }
            
            # Create repository if needed (or get existing)
            $targetRepoObj = Create-RepositoryIfNeeded -ProjectName $restoreItem.TargetProject -RepositoryName $restoreItem.TargetRepo -OrgUrl $AzureDevOpsAccount -AccessToken $AccessToken
            
            if ($null -eq $targetRepoObj) {
                Write-Log "Skipping repository restore" "INFO"
                continue
            }
            
            # Get repository URL
            $targetRepoUrl = $targetRepoObj.RemoteUrl
            
            # Restore repository
            if (Restore-Repository -StorageContext $storageContext -ContainerName $ContainerName -BlobName $restoreItem.BlobName -TargetRepoUrl $targetRepoUrl -AccessToken $AccessToken) {
                $successCount++
                Write-Log "Successfully restored: $($restoreItem.TargetProject)/$($restoreItem.TargetRepo)" "SUCCESS"
            } else {
                $failureCount++
                Write-Log "Failed to restore: $($restoreItem.TargetProject)/$($restoreItem.TargetRepo)" "ERROR"
            }
            
        } catch {
            $failureCount++
            Write-Log "Error restoring $($restoreItem.SourceProject)/$($restoreItem.SourceRepo): $($_.Exception.Message)" "ERROR"
        }
    }
    
    # Summary
    Write-Log "========================================" "INFO"
    Write-Log "Restore Summary" "INFO"
    Write-Log "========================================" "INFO"
    Write-Log "Total repositories: $($restoreList.Count)" "INFO"
    Write-Log "Successful restores: $successCount" "SUCCESS"
    Write-Log "Failed restores: $failureCount" $(if ($failureCount -gt 0) { "ERROR" } else { "INFO" })
    Write-Log "End time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "========================================" "INFO"
    
    if ($failureCount -gt 0) {
        exit 1
    }
    
} catch {
    Write-Log "Fatal error: $($_.Exception.Message)" "ERROR"
    if ($_.ScriptStackTrace) {
        $stackTrace = $_.ScriptStackTrace.ToString()
        $stackTrace = $stackTrace -replace '"', "'"
        $stackTrace = $stackTrace -replace "`r`n", " | " -replace "`n", " | " -replace "`r", " | "
        Write-Log ("Stack trace: " + $stackTrace) "ERROR"
    }
    exit 1
}

#endregion
