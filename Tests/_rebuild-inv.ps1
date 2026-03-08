# Load the module
. "$PSScriptRoot\..\Modules\AppBuilder.ps1"

$sourceDir = "$env:USERPROFILE\.bildsyps\builds\inventory-mgr22\source"

if (-not (Test-Path $sourceDir)) {
    Write-Host "ERROR: Source directory not found: $sourceDir" -ForegroundColor Red
    exit 1
}

Write-Host "=== Running Repair-TauriSource ===" -ForegroundColor Cyan
Repair-TauriSource -SourceDir $sourceDir
Write-Host "=== Repair complete ===" -ForegroundColor Green

Write-Host ""
Write-Host "=== Starting cargo tauri build ===" -ForegroundColor Cyan
$tauriRoot = Join-Path $sourceDir 'src-tauri'
$buildLog = Join-Path $env:TEMP 'inv-mgr-build.log'
$buildErr = Join-Path $env:TEMP 'inv-mgr-build-err.log'

$proc = Start-Process cargo -ArgumentList @('tauri', 'build') `
    -WorkingDirectory $tauriRoot -Wait -NoNewWindow -PassThru `
    -RedirectStandardOutput $buildLog -RedirectStandardError $buildErr

Write-Host ""
Write-Host "=== Build exit code: $($proc.ExitCode) ===" -ForegroundColor $(if ($proc.ExitCode -eq 0) { 'Green' } else { 'Red' })

if ($proc.ExitCode -ne 0) {
    Write-Host ""
    Write-Host "=== Last 50 lines of stderr ===" -ForegroundColor Yellow
    Get-Content $buildErr -Tail 50
}
else {
    Write-Host ""
    Write-Host "=== Last 10 lines of stdout ===" -ForegroundColor Green
    Get-Content $buildLog -Tail 10
}
