# ===== FolderContext.ps1 =====
# Folder awareness — gives the AI a compact snapshot of the current directory
# Token-budget-aware: respects context limits, truncates intelligently

# ===== Configuration =====
$global:FolderContextMaxFiles = 50       # Max files to list per directory
$global:FolderContextMaxDepth = 2        # Max depth for tree view
$global:FolderContextMaxTokens = 800     # Max tokens to spend on folder context
$global:FolderContextAutoUpdate = $false # Auto-update on directory change

function Get-FolderContext {
    <#
    .SYNOPSIS
    Build a compact, token-budget-aware snapshot of the current directory for AI context injection.
    Returns a string suitable for inclusion in a system prompt or chat message.
    .PARAMETER Path
    Directory to snapshot. Defaults to current directory.
    .PARAMETER MaxTokens
    Approximate token budget for the output. Defaults to $global:FolderContextMaxTokens.
    .PARAMETER IncludeGitStatus
    Include git status if the directory is a git repo.
    .PARAMETER IncludeFileContents
    Include content previews for small text files.
    #>
    param(
        [string]$Path = (Get-Location).Path,
        [int]$MaxTokens = $global:FolderContextMaxTokens,
        [switch]$IncludeGitStatus,
        [switch]$IncludeFileContents
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $usedTokens = 0

    # Returns $true if added, $false if budget exceeded
    $tryAdd = {
        param([string]$Text)
        $t = [math]::Ceiling($Text.Length / 4)
        if ($usedTokens + $t -le $MaxTokens) {
            $lines.Add($Text)
            $usedTokens += $t
            return $true
        }
        return $false
    }

    # Header
    & $tryAdd "=== Current Directory: $Path ===" | Out-Null

    # Git repo detection
    $isGitRepo = Test-Path (Join-Path $Path '.git')
    if (-not $isGitRepo) {
        $check = $Path
        while ($check -and $check -ne (Split-Path $check -Parent)) {
            if (Test-Path (Join-Path $check '.git')) { $isGitRepo = $true; break }
            $check = Split-Path $check -Parent
        }
    }
    if ($isGitRepo) { & $tryAdd "Git repo: yes" | Out-Null }

    # Git status (compact)
    if ($IncludeGitStatus -and $isGitRepo) {
        try {
            $branch = git -C $Path rev-parse --abbrev-ref HEAD 2>$null
            if ($branch) { & $tryAdd "Branch: $branch" | Out-Null }

            $status = git -C $Path status --short 2>$null
            if ($status) {
                $statusLines = $status -split "`n" | Where-Object { $_ -match '\S' }
                $changed = $statusLines.Count
                if ($changed -gt 0) {
                    & $tryAdd "Modified files ($changed):" | Out-Null
                    foreach ($s in $statusLines | Select-Object -First 10) {
                        & $tryAdd "  $s" | Out-Null
                    }
                    if ($changed -gt 10) { & $tryAdd "  ... and $($changed - 10) more" | Out-Null }
                }
                else {
                    & $tryAdd "Working tree: clean" | Out-Null
                }
            }
        }
        catch {}
    }

    # File listing — grouped by type, token-aware
    try {
        $items = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^\.(git|vs|idea|cache)$' } |
        Sort-Object { $_.PSIsContainer } -Descending |
        Sort-Object Name

        $dirs = @($items | Where-Object { $_.PSIsContainer })
        $files = @($items | Where-Object { -not $_.PSIsContainer })

        # Directories
        if ($dirs.Count -gt 0) {
            & $tryAdd "" | Out-Null
            & $tryAdd "Directories ($($dirs.Count)):" | Out-Null
            $shown = 0
            foreach ($d in $dirs | Select-Object -First $global:FolderContextMaxFiles) {
                $childCount = try { (Get-ChildItem $d.FullName -ErrorAction SilentlyContinue).Count } catch { '?' }
                if (& $tryAdd "  $($d.Name)/  ($childCount items)") { $shown++ }
                else { break }
            }
            if ($dirs.Count -gt $shown) { & $tryAdd "  ... and $($dirs.Count - $shown) more dirs" | Out-Null }
        }

        # Files — grouped by extension
        if ($files.Count -gt 0) {
            & $tryAdd "" | Out-Null
            & $tryAdd "Files ($($files.Count)):" | Out-Null

            $byExt = $files | Group-Object Extension | Sort-Object Name
            foreach ($group in $byExt) {
                $ext = if ($group.Name) { $group.Name } else { '(no ext)' }
                $names = $group.Group | ForEach-Object {
                    $size = if ($_.Length -gt 1MB) { "$([math]::Round($_.Length/1MB, 1))MB" }
                    elseif ($_.Length -gt 1KB) { "$([math]::Round($_.Length/1KB, 0))KB" }
                    else { "$($_.Length)B" }
                    "$($_.Name) ($size)"
                }
                $line = "  $ext`: $($names -join ', ')"
                if (-not (& $tryAdd $line)) { break }
            }
        }

        # Notable files
        $notable = @('README.md', 'README.txt', '.env', '.env.example', 'package.json',
            'requirements.txt', 'Makefile', 'Dockerfile', 'docker-compose.yml',
            'pyproject.toml', 'Cargo.toml', 'go.mod', '*.sln', '*.csproj',
            'Microsoft.PowerShell_profile.ps1')
        $found = @()
        foreach ($pattern in $notable) {
            $match = $files | Where-Object { $_.Name -like $pattern }
            if ($match) { $found += $match.Name }
        }
        if ($found.Count -gt 0) {
            & $tryAdd "" | Out-Null
            & $tryAdd "Notable: $($found -join ', ')" | Out-Null
        }

        # File content previews for small key files
        if ($IncludeFileContents) {
            $previewFiles = $files | Where-Object {
                $_.Length -lt 4KB -and
                $_.Extension -in @('.md', '.txt', '.json', '.yaml', '.yml', '.toml', '.env', '.gitignore')
            } | Select-Object -First 3

            foreach ($f in $previewFiles) {
                try {
                    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
                    if ($content) {
                        $preview = $content.Trim()
                        if ($preview.Length -gt 300) { $preview = $preview.Substring(0, 300) + '...' }
                        & $tryAdd "" | Out-Null
                        & $tryAdd "--- $($f.Name) ---" | Out-Null
                        & $tryAdd $preview | Out-Null
                    }
                }
                catch {}
            }
        }

    }
    catch {
        & $tryAdd "  (Could not read directory: $($_.Exception.Message))" | Out-Null
    }

    & $tryAdd "" | Out-Null
    & $tryAdd "=== End Directory Context ===" | Out-Null

    return $lines -join "`n"
}

function Invoke-FolderContextUpdate {
    <#
    .SYNOPSIS
    Inject current folder context into the active chat session.
    Replaces any previous folder context message rather than appending.
    #>
    param(
        [string]$Path = (Get-Location).Path,
        [switch]$IncludeGitStatus,
        [switch]$IncludeFileContents,
        [switch]$Silent
    )

    $ctx = Get-FolderContext -Path $Path -IncludeGitStatus:$IncludeGitStatus -IncludeFileContents:$IncludeFileContents

    # Remove any previous folder context injection (sentinel + the assistant ack after it)
    $sentinel = '[FOLDER_CONTEXT]'
    if ($global:ChatSessionHistory -and $global:ChatSessionHistory.Count -gt 0) {
        $filtered = [System.Collections.Generic.List[object]]::new()
        $skipNext = $false
        foreach ($msg in $global:ChatSessionHistory) {
            if ($skipNext) {
                $skipNext = $false
                continue  # skip the assistant ack that follows the sentinel
            }
            if ($msg.role -eq 'user' -and $msg.content.StartsWith($sentinel)) {
                $skipNext = $true
                continue  # skip the sentinel message itself
            }
            $filtered.Add($msg)
        }
        $global:ChatSessionHistory = $filtered.ToArray()
    }

    # Inject as a user/assistant exchange so it works for all providers
    $global:ChatSessionHistory += @{ role = 'user'; content = "$sentinel`n$ctx" }
    $global:ChatSessionHistory += @{ role = 'assistant'; content = "Got it. I can see you're in $Path. I'll use this directory context to help you." }

    if (-not $Silent) {
        $fileCount = (Get-ChildItem $Path -Force -ErrorAction SilentlyContinue).Count
        Write-Host "  Folder context loaded: $Path ($fileCount items)" -ForegroundColor DarkCyan
    }

    return $ctx
}

function Show-FolderContext {
    <#
    .SYNOPSIS
    Display the current folder context (what the AI sees).
    #>
    param([switch]$IncludeGitStatus, [switch]$IncludeFileContents)
    $ctx = Get-FolderContext -IncludeGitStatus:$IncludeGitStatus -IncludeFileContents:$IncludeFileContents
    Write-Host $ctx -ForegroundColor Gray
}

# ===== Directory Change Watcher =====
# Overrides the built-in Set-Location to optionally auto-update folder context
$global:FolderContextEnabled = $false

function Enable-FolderAwareness {
    <#
    .SYNOPSIS
    Enable automatic folder context updates when you change directories.
    #>
    $global:FolderContextEnabled = $true
    Write-Host "Folder awareness enabled. Context will update on 'cd'." -ForegroundColor Green
}

function Disable-FolderAwareness {
    $global:FolderContextEnabled = $false
    Write-Host "Folder awareness disabled." -ForegroundColor DarkGray
}

# Wrap Set-Location to auto-update folder context when enabled
$global:OriginalSetLocation = $null
function Set-LocationWithContext {
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [string]$Path,
        [switch]$PassThru,
        [switch]$StackName
    )
    if ($Path) {
        Microsoft.PowerShell.Management\Set-Location -Path $Path -ErrorAction Stop
    }
    else {
        Microsoft.PowerShell.Management\Set-Location
    }
    if ($global:FolderContextEnabled -and $global:ChatSessionHistory -and $global:ChatSessionHistory.Count -gt 0) {
        Invoke-FolderContextUpdate -Silent
    }
}

Set-Alias -Name cd -Value Set-LocationWithContext -Force -Option AllScope -Scope Global

Write-Verbose "FolderContext loaded: Get-FolderContext, Invoke-FolderContextUpdate, Show-FolderContext, Enable-FolderAwareness"
