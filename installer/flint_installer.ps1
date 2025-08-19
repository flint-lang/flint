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
$WrapperPath = Join-Path $FlintRoot "flintc.cmd"
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

function Find-WindowsExeAsset($releaseObj) {
    if (-not $releaseObj) { return $null }
    foreach ($asset in $releaseObj.assets) {
        $name = $asset.name.ToLower()
        # match exact exe or files that contain 'windows' and end with exe
        if ($name -eq "flintc.exe" -or ($name -like "*windows*.exe") -or ($name -like "*-win*.exe")) {
            return $asset.browser_download_url
        }
    }
    # fallback: if only one exe exists, return it
    $exeAssets = $releaseObj.assets | Where-Object { $_.name -like "*.exe" }
    if ($exeAssets.Count -eq 1) { return $exeAssets[0].browser_download_url }
    return $null
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
            $assetUrl = "https://github.com/$RepoOwner/$RepoName/releases/download/$resolvedTag/flintc.exe"
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

if (-not $assetUrl) {
    if (-not $release) {
        Write-Host "Could not find release for '$Version' via GitHub API." -ForegroundColor Yellow
        if ($Version -ne "latest") {
            # attempt to download by naive URL style (fallback)
            Write-Host "Attempting naive URL download path for $Version ..."
            $assetUrl = "https://github.com/$RepoOwner/$RepoName/releases/download/$Version/flintc.exe"
        } else {
            Write-ErrExit "No release found and cannot continue."
        }
    } else {
        # if we have a release object (from tags endpoint), try to find explicit exe asset first
        $resolvedTag = $release.tag_name
        $assetUrl = Find-WindowsExeAsset $release
        if (-not $assetUrl) {
            Write-Host "No Windows .exe asset found automatically. Trying a likely name..."
            $assetUrl = "https://github.com/$RepoOwner/$RepoName/releases/download/$resolvedTag/flintc.exe"
        }
        $Version = $resolvedTag  # normalize version to the canonical tag
    }
}

$targetDir = Join-Path $VersionsDir $Version
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
$exePath = Join-Path $targetDir "flintc.exe"

if ((Test-Path $exePath) -and (-not $Force)) {
    Write-Host "flintc.exe for version '$Version' already exists at $exePath. Use -Force to re-download."
} else {
    Write-Host "Downloading flintc ($Version) ..."
    try {
        # GitHub may require a User-Agent header
        $headers = @{ "User-Agent" = "flint_installer" }
        Invoke-WebRequest -Uri $assetUrl -OutFile $exePath -Headers $headers -UseBasicParsing
    } catch {
        Write-ErrExit "Download failed: $($_.Exception.Message)"
    }

    # Ensure executable bit and existence
    if (-not (Test-Path $exePath)) {
        Write-ErrExit "downloaded file missing after download."
    } else {
        Write-Host "Downloaded to $exePath"
    }
}

# Create wrapper (flintc.cmd) in $FlintRoot
$wrapperText = @"
@echo off
REM flintc wrapper - chooses project pinned > user pinned > newest cached
setlocal

set FLINT_ROOT=%LOCALAPPDATA%\Flint
set VERSIONS_DIR=%FLINT_ROOT%\versions
set PROJECT_PIN_FILE=%CD%\.flint\version
set USER_PIN_FILE=%FLINT_ROOT%\active_version

REM 1) project pinned
if exist "%PROJECT_PIN_FILE%" (
    set /p VER=<"%PROJECT_PIN_FILE%"
) else if exist "%USER_PIN_FILE%" (
    set /p VER=<"%USER_PIN_FILE%"
) else (
    REM pick newest directory under versions
    for /f "delims=" %%v in ('dir /b /ad "%VERSIONS_DIR%" ^| sort') do set VER=%%v
)

if "%VER%"=="" (
    echo No flint version found in %FLINT_ROOT%\versions. Please run installer.
    exit /b 2
)

set EXE="%FLINT_ROOT%\versions\%VER%\flintc.exe"
if not exist %EXE% (
    echo Requested flint version %VER% not present at %EXE%
    exit /b 3
)

REM Execute the real binary and forward arguments
"%FLINT_ROOT%\versions\%VER%\flintc.exe" %*
endlocal
"@

# write wrapper
$wrapperText | Out-File -FilePath $WrapperPath -Encoding ascii -Force
Write-Host "Wrapper created at $WrapperPath"

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

Write-Host "Installation complete. You can now run 'flintc' from a new terminal (or use full path to the wrapper)."
Write-Host "To pin a version per-project, create a file '.flint\\version' containing the tag (e.g. $Version) in your project root."
Write-Host "To set a user default active version, write the version tag to: $ActiveVersionFile"

