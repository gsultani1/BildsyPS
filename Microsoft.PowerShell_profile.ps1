# ============= Microsoft.PowerShell_profile.ps1 =============
# The fact that this works is proof that God loves PowerShell developers
# Profile load timing
$global:ProfileLoadStart = Get-Date
$global:ProfileTimings = @{}
$global:BildsyPSVersion = '1.4.1'

# Safe Mode - report errors but continue loading
trap {
    Write-Host "Error loading PowerShell profile: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkRed
    continue
}

# Ensure Rust/Cargo is on PATH if installed
$cargobin = Join-Path $env:USERPROFILE '.cargo\bin'
if ((Test-Path $cargobin) -and $env:PATH -notmatch [regex]::Escape($cargobin)) {
    $env:PATH = "$cargobin;$env:PATH"
}

# Keep UTF-8 and predictable output
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8
$ErrorActionPreference = "Stop"
Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineOption -HistorySearchCursorMovesToEnd

# ===== PowerShell Profile =====
# Suppress startup noise
if ($Host.UI.RawUI.WindowTitle) { Clear-Host }

# ===== BildsyPS Home (user data, separate from module install path) =====
$global:BildsyPSHome = "$env:USERPROFILE\.bildsyps"
$global:BildsyPSModulePath = $PSScriptRoot

function Initialize-BildsyPSHome {
    # Create the ~/.bildsyps directory tree on first run
    $dirs = @(
        $global:BildsyPSHome
        "$global:BildsyPSHome\config"
        "$global:BildsyPSHome\data"
        "$global:BildsyPSHome\logs"
        "$global:BildsyPSHome\logs\sessions"
        "$global:BildsyPSHome\plugins"
        "$global:BildsyPSHome\plugins\Config"
        "$global:BildsyPSHome\skills"
        "$global:BildsyPSHome\aliases"
    )
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }

    # First-run migration: copy old files to new locations if they exist
    $migrated = @()
    $oldRoot = $PSScriptRoot

    # Config/.env -> ~/.bildsyps/config/.env
    $oldEnv = "$oldRoot\Config\.env"
    $newEnv = "$global:BildsyPSHome\config\.env"
    if ((Test-Path $oldEnv) -and -not (Test-Path $newEnv)) {
        Copy-Item $oldEnv $newEnv -Force
        $migrated += ".env"
    }

    # ChatConfig.json -> ~/.bildsyps/config/ChatConfig.json
    $oldChat = "$oldRoot\ChatConfig.json"
    $newChat = "$global:BildsyPSHome\config\ChatConfig.json"
    if ((Test-Path $oldChat) -and -not (Test-Path $newChat)) {
        Copy-Item $oldChat $newChat -Force
        $migrated += "ChatConfig.json"
    }

    # ToolPreferences.json -> ~/.bildsyps/config/ToolPreferences.json
    $oldTP = "$oldRoot\ToolPreferences.json"
    $newTP = "$global:BildsyPSHome\config\ToolPreferences.json"
    if ((Test-Path $oldTP) -and -not (Test-Path $newTP)) {
        Copy-Item $oldTP $newTP -Force
        $migrated += "ToolPreferences.json"
    }

    # UserSkills.json -> ~/.bildsyps/skills/UserSkills.json
    $oldSkills = "$oldRoot\UserSkills.json"
    $newSkills = "$global:BildsyPSHome\skills\UserSkills.json"
    if ((Test-Path $oldSkills) -and -not (Test-Path $newSkills)) {
        Copy-Item $oldSkills $newSkills -Force
        $migrated += "UserSkills.json"
    }

    # UserAliases.ps1 -> ~/.bildsyps/aliases/UserAliases.ps1
    $oldAliases = "$oldRoot\UserAliases.ps1"
    $newAliases = "$global:BildsyPSHome\aliases\UserAliases.ps1"
    if ((Test-Path $oldAliases) -and -not (Test-Path $newAliases)) {
        Copy-Item $oldAliases $newAliases -Force
        $migrated += "UserAliases.ps1"
    }

    # NaturalLanguageMappings.json -> ~/.bildsyps/data/NaturalLanguageMappings.json
    $oldNL = "$oldRoot\NaturalLanguageMappings.json"
    $newNL = "$global:BildsyPSHome\data\NaturalLanguageMappings.json"
    if ((Test-Path $oldNL) -and -not (Test-Path $newNL)) {
        Copy-Item $oldNL $newNL -Force
        $migrated += "NaturalLanguageMappings.json"
    }

    # ~/Documents/ChatLogs/ -> ~/.bildsyps/logs/sessions/
    $oldLogs = "$env:USERPROFILE\Documents\ChatLogs"
    $newLogs = "$global:BildsyPSHome\logs\sessions"
    if ((Test-Path $oldLogs) -and (Get-ChildItem $oldLogs -Filter "*.json" -ErrorAction SilentlyContinue).Count -gt 0) {
        $existingNew = (Get-ChildItem $newLogs -Filter "*.json" -ErrorAction SilentlyContinue).Count
        if ($existingNew -eq 0) {
            Copy-Item "$oldLogs\*.json" $newLogs -Force -ErrorAction SilentlyContinue
            $migrated += "ChatLogs ($(( Get-ChildItem $newLogs -Filter '*.json' -ErrorAction SilentlyContinue).Count) sessions)"
        }
    }

    # ~/Documents/ChatLogs/AIExecutionLog.json -> ~/.bildsyps/logs/AIExecutionLog.json
    $oldExecLog = "$env:USERPROFILE\Documents\ChatLogs\AIExecutionLog.json"
    $newExecLog = "$global:BildsyPSHome\logs\AIExecutionLog.json"
    if ((Test-Path $oldExecLog) -and -not (Test-Path $newExecLog)) {
        Copy-Item $oldExecLog $newExecLog -Force
        $migrated += "AIExecutionLog.json"
    }

    # Plugins/ -> ~/.bildsyps/plugins/ (user plugin files only, skip bundled examples)
    $oldPlugins = "$oldRoot\Plugins"
    if (Test-Path $oldPlugins) {
        $userPlugins = Get-ChildItem "$oldPlugins\*.ps1" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '_Example*' -and $_.Name -notlike '_Pomodoro*' -and $_.Name -notlike '_QuickNotes*' }
        foreach ($p in $userPlugins) {
            $dest = Join-Path "$global:BildsyPSHome\plugins" $p.Name
            if (-not (Test-Path $dest)) {
                Copy-Item $p.FullName $dest -Force
                $migrated += "Plugin: $($p.Name)"
            }
        }
        # Plugin configs
        $oldPConfig = "$oldPlugins\Config"
        if (Test-Path $oldPConfig) {
            Get-ChildItem "$oldPConfig\*.json" -ErrorAction SilentlyContinue | ForEach-Object {
                $dest = Join-Path "$global:BildsyPSHome\plugins\Config" $_.Name
                if (-not (Test-Path $dest)) {
                    Copy-Item $_.FullName $dest -Force
                }
            }
        }
    }

    if ($migrated.Count -gt 0) {
        Write-Host "`n[BildsyPS] Migrated $($migrated.Count) item(s) to $global:BildsyPSHome" -ForegroundColor Cyan
        foreach ($m in $migrated) {
            Write-Host "  - $m" -ForegroundColor DarkCyan
        }
        Write-Host "  Old files left in place (safe to remove manually).`n" -ForegroundColor DarkGray
    }
}

Initialize-BildsyPSHome

# ===== Bundled Module Loading =====
# PowerShell charges ~250-350ms per dot-source operation. With 39 modules, that's
# ~12s of structural overhead. Fix: concatenate all modules into a single string,
# create one [scriptblock], and dot-source it once.
$global:ModulesPath = "$PSScriptRoot\Modules"
$global:DebugModuleLoading = $false

$_bundleSw = [System.Diagnostics.Stopwatch]::StartNew()
$_bundleContent = [System.Text.StringBuilder]::new(512KB)

# IntentAliasSystem sub-modules (normally cascaded via dot-source)
$_intentSubModules = @(
    'IntentRegistry.ps1', 'IntentActions.ps1', 'IntentActionsSystem.ps1',
    'WorkflowEngine.ps1', 'IntentRouter.ps1', 'AgentTools.ps1', 'AgentLoop.ps1'
)

# All modules to bundle (in dependency order)
$_allModules = @(
    'ConfigLoader.ps1', 'PlatformUtils.ps1', 'SecurityUtils.ps1',
    'SecretScanner.ps1', 'CommandValidation.ps1',
    'SystemUtilities.ps1', 'ArchiveUtils.ps1', 'DockerTools.ps1', 'DevTools.ps1',
    'NaturalLanguage.ps1', 'ResponseParser.ps1',
    'DocumentTools.ps1', 'SafetySystem.ps1', 'TerminalTools.ps1',
    'NavigationUtils.ps1', 'PackageManager.ps1', 'WebTools.ps1',
    'ProductivityTools.ps1', 'MCPClient.ps1',
    'BrowserAwareness.ps1', 'CodeArtifacts.ps1',
    'FzfIntegration.ps1', 'PersistentAliases.ps1', 'ProfileHelp.ps1',
    'ToastNotifications.ps1', 'FolderContext.ps1', 'ChatStorage.ps1', 'ChatSession.ps1'
)

# Inject $PSScriptRoot so modules that reference it for paths resolve correctly
[void]$_bundleContent.AppendLine("`$PSScriptRoot = `"$($global:ModulesPath)`"")

# Read and concatenate all main modules with per-module timing wrappers
foreach ($mod in $_allModules) {
    $modPath = Join-Path $global:ModulesPath $mod
    if (Test-Path $modPath) {
        [void]$_bundleContent.AppendLine("`$_modSw = [System.Diagnostics.Stopwatch]::StartNew()")
        [void]$_bundleContent.AppendLine([System.IO.File]::ReadAllText($modPath))
        [void]$_bundleContent.AppendLine("`$_modSw.Stop(); `$global:ProfileTimings['$mod'] = `$_modSw.ElapsedMilliseconds")
    }
}

# IntentAliasSystem: inline the parent + all 7 sub-modules
$_iasPath = Join-Path $global:ModulesPath 'IntentAliasSystem.ps1'
if (Test-Path $_iasPath) {
    [void]$_bundleContent.AppendLine("`$_modSw = [System.Diagnostics.Stopwatch]::StartNew()")
    $iasContent = [System.IO.File]::ReadAllText($_iasPath)
    $iasContent = $iasContent -replace '\. "\$PSScriptRoot\\[^"]+"', '# (inlined below)'
    [void]$_bundleContent.AppendLine($iasContent)
    foreach ($sub in $_intentSubModules) {
        $subPath = Join-Path $global:ModulesPath $sub
        if (Test-Path $subPath) {
            [void]$_bundleContent.AppendLine([System.IO.File]::ReadAllText($subPath))
        }
    }
    [void]$_bundleContent.AppendLine("`$_modSw.Stop(); `$global:ProfileTimings['IntentAliasSystem.ps1'] = `$_modSw.ElapsedMilliseconds")
}

# ChatProviders
$_cpPath = Join-Path $global:ModulesPath 'ChatProviders.ps1'
if (Test-Path $_cpPath) {
    [void]$_bundleContent.AppendLine("`$_modSw = [System.Diagnostics.Stopwatch]::StartNew()")
    [void]$_bundleContent.AppendLine([System.IO.File]::ReadAllText($_cpPath))
    [void]$_bundleContent.AppendLine("`$_modSw.Stop(); `$global:ProfileTimings['ChatProviders.ps1'] = `$_modSw.ElapsedMilliseconds")
}

# UserSkills
$_usPath = Join-Path $global:ModulesPath 'UserSkills.ps1'
if (Test-Path $_usPath) {
    [void]$_bundleContent.AppendLine("`$_modSw = [System.Diagnostics.Stopwatch]::StartNew()")
    [void]$_bundleContent.AppendLine([System.IO.File]::ReadAllText($_usPath))
    [void]$_bundleContent.AppendLine("`$_modSw.Stop(); `$global:ProfileTimings['UserSkills.ps1'] = `$_modSw.ElapsedMilliseconds")
}

# PluginLoader
$_plPath = Join-Path $global:ModulesPath 'PluginLoader.ps1'
if (Test-Path $_plPath) {
    [void]$_bundleContent.AppendLine("`$_modSw = [System.Diagnostics.Stopwatch]::StartNew()")
    [void]$_bundleContent.AppendLine([System.IO.File]::ReadAllText($_plPath))
    [void]$_bundleContent.AppendLine("`$_modSw.Stop(); `$global:ProfileTimings['PluginLoader.ps1'] = `$_modSw.ElapsedMilliseconds")
}

# Execute the entire bundle as a single scriptblock (1 parse + 1 execute)
. ([scriptblock]::Create($_bundleContent.ToString()))

$_bundleSw.Stop()
$global:ProfileTimings['_BUNDLE_TOTAL'] = $_bundleSw.ElapsedMilliseconds

# Cleanup
Remove-Variable -Name '_bundleContent', '_bundleSw', '_allModules', '_intentSubModules', '_iasPath', '_cpPath', '_usPath', '_plPath' -ErrorAction SilentlyContinue



# ===== Deferred Module Loading =====
# Modules below are loaded on first use to reduce profile startup time.
# Each stub dot-sources the real module in its own scope so loaded functions
# shadow the stub locally, then the recursive call resolves to the real implementation.
# On subsequent calls the stub re-dot-sources (fast — file is in OS page cache).
$global:DeferredLoaded = @{}

# --- VisionTools.ps1 stubs ---
function Invoke-Vision {
    if (-not $global:DeferredLoaded['VisionTools.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\VisionTools.ps1"; $sw.Stop(); $global:ProfileTimings['VisionTools.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['VisionTools.ps1'] = $true } else { . "$global:ModulesPath\VisionTools.ps1" }
    Invoke-Vision @args
}
function Send-ImageToAI {
    if (-not $global:DeferredLoaded['VisionTools.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\VisionTools.ps1"; $sw.Stop(); $global:ProfileTimings['VisionTools.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['VisionTools.ps1'] = $true } else { . "$global:ModulesPath\VisionTools.ps1" }
    Send-ImageToAI @args
}
function Test-VisionSupport {
    if (-not $global:DeferredLoaded['VisionTools.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\VisionTools.ps1"; $sw.Stop(); $global:ProfileTimings['VisionTools.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['VisionTools.ps1'] = $true } else { . "$global:ModulesPath\VisionTools.ps1" }
    Test-VisionSupport @args
}
function Capture-Screenshot {
    if (-not $global:DeferredLoaded['VisionTools.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\VisionTools.ps1"; $sw.Stop(); $global:ProfileTimings['VisionTools.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['VisionTools.ps1'] = $true } else { . "$global:ModulesPath\VisionTools.ps1" }
    Capture-Screenshot @args
}
Set-Alias vision Invoke-Vision -Force

# --- OCRTools.ps1 stubs ---
function Invoke-OCRFile {
    if (-not $global:DeferredLoaded['OCRTools.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\OCRTools.ps1"; $sw.Stop(); $global:ProfileTimings['OCRTools.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['OCRTools.ps1'] = $true } else { . "$global:ModulesPath\OCRTools.ps1" }
    Invoke-OCRFile @args
}
function Invoke-OCR {
    if (-not $global:DeferredLoaded['OCRTools.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\OCRTools.ps1"; $sw.Stop(); $global:ProfileTimings['OCRTools.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['OCRTools.ps1'] = $true } else { . "$global:ModulesPath\OCRTools.ps1" }
    Invoke-OCR @args
}
function ConvertFrom-PDF {
    if (-not $global:DeferredLoaded['OCRTools.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\OCRTools.ps1"; $sw.Stop(); $global:ProfileTimings['OCRTools.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['OCRTools.ps1'] = $true } else { . "$global:ModulesPath\OCRTools.ps1" }
    ConvertFrom-PDF @args
}
Set-Alias ocr Invoke-OCRFile -Force

# --- AppBuilder.ps1 stubs ---
function New-AppBuild {
    if (-not $global:DeferredLoaded['AppBuilder.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\AppBuilder.ps1"; $sw.Stop(); $global:ProfileTimings['AppBuilder.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['AppBuilder.ps1'] = $true } else { . "$global:ModulesPath\AppBuilder.ps1" }
    New-AppBuild @args
}
function Update-AppBuild {
    if (-not $global:DeferredLoaded['AppBuilder.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\AppBuilder.ps1"; $sw.Stop(); $global:ProfileTimings['AppBuilder.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['AppBuilder.ps1'] = $true } else { . "$global:ModulesPath\AppBuilder.ps1" }
    Update-AppBuild @args
}
function Get-AppBuilds {
    if (-not $global:DeferredLoaded['AppBuilder.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\AppBuilder.ps1"; $sw.Stop(); $global:ProfileTimings['AppBuilder.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['AppBuilder.ps1'] = $true } else { . "$global:ModulesPath\AppBuilder.ps1" }
    Get-AppBuilds @args
}
function Remove-AppBuild {
    if (-not $global:DeferredLoaded['AppBuilder.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\AppBuilder.ps1"; $sw.Stop(); $global:ProfileTimings['AppBuilder.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['AppBuilder.ps1'] = $true } else { . "$global:ModulesPath\AppBuilder.ps1" }
    Remove-AppBuild @args
}
Set-Alias builds Get-AppBuilds -Force
Set-Alias rebuild Update-AppBuild -Force

# --- AgentHeartbeat.ps1 stubs ---
function Get-HeartbeatStatus {
    if (-not $global:DeferredLoaded['AgentHeartbeat.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\AgentHeartbeat.ps1"; $sw.Stop(); $global:ProfileTimings['AgentHeartbeat.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['AgentHeartbeat.ps1'] = $true } else { . "$global:ModulesPath\AgentHeartbeat.ps1" }
    Get-HeartbeatStatus @args
}
function Show-AgentTaskList {
    if (-not $global:DeferredLoaded['AgentHeartbeat.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\AgentHeartbeat.ps1"; $sw.Stop(); $global:ProfileTimings['AgentHeartbeat.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['AgentHeartbeat.ps1'] = $true } else { . "$global:ModulesPath\AgentHeartbeat.ps1" }
    Show-AgentTaskList @args
}
function Add-AgentTask {
    if (-not $global:DeferredLoaded['AgentHeartbeat.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\AgentHeartbeat.ps1"; $sw.Stop(); $global:ProfileTimings['AgentHeartbeat.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['AgentHeartbeat.ps1'] = $true } else { . "$global:ModulesPath\AgentHeartbeat.ps1" }
    Add-AgentTask @args
}
function Invoke-AgentHeartbeat {
    if (-not $global:DeferredLoaded['AgentHeartbeat.ps1']) { $sw = [System.Diagnostics.Stopwatch]::StartNew(); . "$global:ModulesPath\AgentHeartbeat.ps1"; $sw.Stop(); $global:ProfileTimings['AgentHeartbeat.ps1 (deferred)'] = $sw.ElapsedMilliseconds; $global:DeferredLoaded['AgentHeartbeat.ps1'] = $true } else { . "$global:ModulesPath\AgentHeartbeat.ps1" }
    Invoke-AgentHeartbeat @args
}
Set-Alias heartbeat Get-HeartbeatStatus -Force
Set-Alias heartbeat-tasks Show-AgentTaskList -Force

function Show-ProfileTimings {
    <#
    .SYNOPSIS
    Display profile module load times, ranked slowest-first.
    #>
    $total = ($global:ProfileTimings.Values | Measure-Object -Sum).Sum
    Write-Host "`n  Profile Module Load Times (total: ${total}ms)" -ForegroundColor Cyan
    Write-Host "  $('-' * 50)" -ForegroundColor DarkGray
    $global:ProfileTimings.GetEnumerator() |
    Sort-Object Value -Descending |
    ForEach-Object {
        $pct = if ($total -gt 0) { [math]::Round($_.Value / $total * 100, 1) } else { 0 }
        $color = if ($_.Value -gt 100) { 'Yellow' } elseif ($_.Value -gt 50) { 'DarkYellow' } else { 'Gray' }
        Write-Host ("  {0,-35} {1,5}ms  ({2}%)" -f $_.Key, $_.Value, $pct) -ForegroundColor $color
    }
    Write-Host ""
}

# ===== Module Reload Functions =====
function Update-IntentAliases {
    . "$global:ModulesPath\IntentAliasSystem.ps1" -ErrorAction SilentlyContinue
    # Re-merge user skills and plugins since reloading core wipes the global hashtables
    $global:LoadedUserSkills = [ordered]@{}
    Import-UserSkills -Quiet
    $global:LoadedPlugins = [ordered]@{}
    Import-BildsyPSPlugins -Quiet
    Write-Host "Intent aliases reloaded (skills + plugins re-merged)." -ForegroundColor Green
}
Set-Alias reload-intents Update-IntentAliases -Force

function Update-UserSkills {
    Unregister-UserSkills
    Import-UserSkills
}
Set-Alias reload-skills Update-UserSkills -Force

function Update-ChatProviders {
    . "$global:ModulesPath\ChatProviders.ps1" -ErrorAction SilentlyContinue
    Write-Host "Chat providers reloaded." -ForegroundColor Green
}
Set-Alias reload-providers Update-ChatProviders -Force

function Update-BildsyPSPlugins {
    # Unregister all current plugin contributions, then re-load from disk
    foreach ($pName in @($global:LoadedPlugins.Keys)) {
        Unregister-BildsyPSPlugin -Name $pName
    }
    Import-BildsyPSPlugins
}
Set-Alias reload-plugins Update-BildsyPSPlugins -Force

function Update-AllModules {
    . "$global:ModulesPath\IntentAliasSystem.ps1" -ErrorAction SilentlyContinue
    . "$global:ModulesPath\ChatProviders.ps1" -ErrorAction SilentlyContinue
    if (Test-Path $global:ModulesPath) {
        Get-ChildItem "$global:ModulesPath\*.ps1" | ForEach-Object {
            . $_.FullName -ErrorAction SilentlyContinue
        }
    }
    # Re-merge plugins after core reload
    $global:LoadedPlugins = [ordered]@{}
    Import-BildsyPSPlugins
    Write-Host "All modules reloaded." -ForegroundColor Green
}
Set-Alias reload-all Update-AllModules -Force

# ===== Prompt with Style =====
function Prompt {
    $path = (Get-Location).Path.Replace($env:USERPROFILE, '~')
    Write-Host ("[" + (Get-Date -Format "HH:mm:ss") + "] ") -ForegroundColor DarkCyan -NoNewline
    Write-Host ("PS ") -ForegroundColor Cyan -NoNewline
    Write-Host $path -ForegroundColor Yellow -NoNewline
    return "> "
}

# ===== Lazy Module Loading =====
$global:LazyModules = @{
    'Terminal-Icons' = $false
    'posh-git'       = $false
    'ThreadJob'      = $false
}

function Import-LazyModule {
    param([string]$Name)
    if (-not $global:LazyModules[$Name]) {
        $loadTime = Measure-Command {
            Import-Module $Name -ErrorAction SilentlyContinue
        }
        $global:LazyModules[$Name] = $true
        Write-Host "Loaded $Name ($([math]::Round($loadTime.TotalMilliseconds))ms)" -ForegroundColor DarkGray
    }
}

function Enable-TerminalIcons {
    if (-not $global:LazyModules['Terminal-Icons']) {
        Import-LazyModule 'Terminal-Icons'
    }
}

function Enable-PoshGit {
    if (-not $global:LazyModules['posh-git']) {
        if (Test-Path .git -ErrorAction SilentlyContinue) {
            Import-LazyModule 'posh-git'
        }
    }
}

function Enable-ThreadJob {
    if (-not $global:LazyModules['ThreadJob']) {
        Import-LazyModule 'ThreadJob'
    }
}

# Aliases to trigger lazy loading
function lz { Enable-TerminalIcons; Get-ChildItem @args | Format-Table -AutoSize }
function gst { Enable-PoshGit; git status @args }

# ===== Profile Reload =====
Set-Alias reload ". $PROFILE" -Force

# ===== Startup Secret Scan =====
if (Get-Command Invoke-StartupSecretScan -ErrorAction SilentlyContinue) {
    Invoke-StartupSecretScan
}

# ===== Startup Message =====
$global:ProfileLoadTime = (Get-Date) - $global:ProfileLoadStart
Write-Host "`nPowerShell $($PSVersionTable.PSVersion) on $env:COMPUTERNAME" -ForegroundColor Green
Write-Host "Profile loaded in $([math]::Round($global:ProfileLoadTime.TotalMilliseconds))ms | Session: $($global:SessionId)" -ForegroundColor DarkGray
Write-Host "Type 'tips' for quick reference, 'profile-timing' for load details" -ForegroundColor DarkGray
