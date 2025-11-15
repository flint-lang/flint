<#
  flint_installer.ps1
  Usage:
    # Install latest (default behaviour):
    .\flint_installer.ps1

    # Install latest explicitly:
    .\flint_installer.ps1 -Version latest

    # Install a specific tag:
    .\flint_installer.ps1 -Version v0.1.6-core

    # Force download a release even if it might already be downloaded
    .\flint_installer.ps1 -Version v0.1.6-core -Force
#>

param(
  [Parameter(Mandatory=$false)]
  [string]$Version = "latest",

  [switch]$Force  # set to force download even if already cached
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Config
$RepoOwner = "flint-lang"
$RepoName  = "flintc"
$FlintRoot = Join-Path $env:LOCALAPPDATA "Flint"
$VersionsDir = Join-Path $FlintRoot "Versions"
$FlintcLink = Join-Path $FlintRoot "flintc.exe"
$FlsLink = Join-Path $FlintRoot "fls.exe"
$ActiveVersionFile = Join-Path $FlintRoot "active_version"

function Write-ErrExit($msg, [int]$code = 1) {
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit $code
}

function Get-ReleaseObjectByTag([string]$tag) {
    # If 'latest', use the latest releases endpoint
    $ua = @{ "User-Agent" = "flint_installer" }
    try {
        if ($tag -eq "latest") {
            $url = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
            return Invoke-RestMethod -Uri $url -Headers $ua -UseBasicParsing
        } else {
            $url = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/tags/$tag"
            return Invoke-RestMethod -Uri $url -Headers $ua -UseBasicParsing
        }
    } catch {
        Write-Host "Failed to query GitHub releases: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

function Find-WindowsExeAsset($releaseObj, $exeName) {
    if (-not $releaseObj) { return $null }
    foreach ($asset in $releaseObj.assets) {
        $name = $asset.name.ToLower()
        $searchName = $exeName.ToLower()
        # match exact exe or files that contain 'windows' and the exe name
        if ($name -eq $searchName -or ($name -like "*windows*$searchName") -or ($name -like "*-win*$searchName")) {
            return $asset.browser_download_url
        }
    }
    # fallback: if asset with exact name exists, return it
    $exeAssets = $releaseObj.assets | Where-Object { $_.name.ToLower() -eq $exeName.ToLower() }
    if ($exeAssets.Count -eq 1) { return $exeAssets[0].browser_download_url }
    return $null
}

function Download-Binary($binaryName, $assetUrl, $targetDir, $resolvedTag) {
    $exePath = Join-Path $targetDir $binaryName
    
    if ((Test-Path $exePath) -and (-not $Force)) {
        Write-Host "$binaryName for version '$resolvedTag' already exists at $exePath. Use -Force to re-download."
        return $exePath
    } else {
        Write-Host "Downloading $binaryName ($resolvedTag) ..."
        try {
            # GitHub may require a User-Agent header
            $headers = @{ "User-Agent" = "flint_installer" }
            Invoke-WebRequest -Uri $assetUrl -OutFile $exePath -Headers $headers -UseBasicParsing
        } catch {
            Write-Host "Warning: Download failed for $binaryName : $($_.Exception.Message)" -ForegroundColor Yellow
            return $null
        }

        # Ensure executable bit and existence
        if (-not (Test-Path $exePath)) {
            Write-Host "Warning: $binaryName file missing after download." -ForegroundColor Yellow
            return $null
        } else {
            Write-Host "Downloaded to $exePath"
            return $exePath
        }
    }
}

function Create-HardLink($sourcePath, $linkPath, $binaryName) {
    # Remove existing link/file if present
    if (Test-Path $linkPath) {
        Remove-Item $linkPath -Force
        Write-Host "Removed existing $binaryName at $linkPath"
    }

    try {
        New-Item -ItemType HardLink -Path $linkPath -Target $sourcePath -Force -ErrorAction Stop | Out-Null
        Write-Host "Created hard link for $binaryName at $linkPath" -ForegroundColor Green
        return $true
    } catch {
        Write-Host ("Failed to create hard link for {0}: {1}" -f $binaryName, $_.Exception.Message) -ForegroundColor Yellow
        return $false
    }
}

# create directories
New-Item -ItemType Directory -Path $VersionsDir -Force | Out-Null

# resolve version -> release object / asset url
if ($Version -eq "latest") {
    Write-Host "Resolving latest release from GitHub (via releases list)..."
    $ua = @{ "User-Agent" = "flint_installer" }
    try {
        $listUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases"
        $releases = Invoke-RestMethod -Uri $listUrl -Headers $ua -UseBasicParsing
        if ($releases -and $releases.Count -gt 0) {
            # take the first element's tag_name
            $resolvedTag = ($releases | Select-Object -First 1).tag_name
            Write-Host "Resolved latest tag: $resolvedTag"
            $assetUrlFlintc = "https://github.com/$RepoOwner/$RepoName/releases/download/$resolvedTag/flintc.exe"
            $assetUrlFls = "https://github.com/$RepoOwner/$RepoName/releases/download/$resolvedTag/fls.exe"
            $Version = $resolvedTag
        } else {
            Write-Host "No releases returned from list endpoint." -ForegroundColor Yellow
            # fallback to the older API call
            $release = Get-ReleaseObjectByTag $Version
        }
    } catch {
        Write-Host "Failed to query releases list: $($_.Exception.Message)" -ForegroundColor Yellow
        # fallback to the older API call
        $release = Get-ReleaseObjectByTag $Version
    }
} else {
    $release = Get-ReleaseObjectByTag $Version
}

if (-not $assetUrlFlintc -or -not $assetUrlFls) {
    if (-not $release) {
        Write-Host "Could not find release for '$Version' via GitHub API." -ForegroundColor Yellow
        if ($Version -ne "latest") {
            # attempt to download by naive URL style (fallback)
            Write-Host "Attempting naive URL download path for $Version ..."
            $assetUrlFlintc = "https://github.com/$RepoOwner/$RepoName/releases/download/$Version/flintc.exe"
            $assetUrlFls = "https://github.com/$RepoOwner/$RepoName/releases/download/$Version/fls.exe"
        } else {
            Write-ErrExit "No release found and cannot continue."
        }
    } else {
        # if we have a release object (from tags endpoint), try to find explicit exe assets
        $resolvedTag = $release.tag_name
        $assetUrlFlintc = Find-WindowsExeAsset $release "flintc.exe"
        $assetUrlFls = Find-WindowsExeAsset $release "fls.exe"
        
        if (-not $assetUrlFlintc) {
            Write-Host "No Windows .exe asset found automatically for flintc. Trying a likely name..."
            $assetUrlFlintc = "https://github.com/$RepoOwner/$RepoName/releases/download/$resolvedTag/flintc.exe"
        }
        
        if (-not $assetUrlFls) {
            Write-Host "No Windows .exe asset found automatically for fls. Trying a likely name..."
            $assetUrlFls = "https://github.com/$RepoOwner/$RepoName/releases/download/$resolvedTag/fls.exe"
        }
        
        $Version = $resolvedTag  # normalize version to the canonical tag
    }
}

$targetDir = Join-Path $VersionsDir $Version
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

# Download both binaries
$flintcPath = Download-Binary "flintc.exe" $assetUrlFlintc $targetDir $Version
$flsPath = Download-Binary "fls.exe" $assetUrlFls $targetDir $Version

# Check if at least one binary was downloaded successfully
if (-not $flintcPath -and -not $flsPath) {
    Write-ErrExit "Failed to download both binaries. Installation cannot continue."
}

# Create links for both binaries
if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

# Persist active version file
$Version | Out-File -FilePath $ActiveVersionFile -Encoding ascii -Force -NoNewline

# Create hard links for both binaries (so `flintc.exe` and `fls.exe` are available under $FlintRoot)
$linkSuccessCount = 0

if ($flintcPath) {
    $sourceFlintc = $flintcPath
    if (Create-HardLink $sourceFlintc $FlintcLink "flintc") { $linkSuccessCount++ }
}

if ($flsPath) {
    $sourceFls = $flsPath
    if (Create-HardLink $sourceFls $FlsLink "fls") { $linkSuccessCount++ }
}

if ($linkSuccessCount -eq 0) {
    Write-ErrExit "Failed to create any hard links. Installation incomplete."
}

# Add $FlintRoot to User PATH if missing
function Add-ToUserPathIfMissing($dir) {
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $userPath) { $userPath = "" }
    # case-insensitive check
    $paths = $userPath -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    if ($paths -notcontains $dir) {
        $newPath = if ($userPath -eq "") { $dir } else { "$userPath;$dir" }
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Host "Added $dir to user PATH. You may need to restart your shell for changes to take effect."
        return $true
    } else {
        Write-Host "$dir already on user PATH"
        return $false
    }
}

Add-ToUserPathIfMissing $FlintRoot

Write-Host "`nInstallation complete!" -ForegroundColor Green
if ($flintcPath) {
    Write-Host "- flintc is available via 'flintc' command"
}
if ($flsPath) {
    Write-Host "- fls is available via 'fls' command"
}
Write-Host "`nYou may need to restart your terminal for PATH changes to take effect."
Write-Host "To pin a version per-project, create a file '.flint\version' containing the tag (e.g. $Version) in your project root."
Write-Host "To set a user default active version, write the version tag to: $ActiveVersionFile"