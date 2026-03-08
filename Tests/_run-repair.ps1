$r = Invoke-Pester -Path './Tests/AppBuilder.Tests.ps1' -PassThru -Output Normal
foreach ($f in $r.Failed) {
    Write-Host "FAIL: $($f.ExpandedPath)"
    Write-Host "  ERR: $($f.ErrorRecord.Exception.Message)"
    Write-Host ""
}
Write-Host "Passed: $($r.PassedCount) Failed: $($r.FailedCount) Skipped: $($r.SkippedCount)"
if ($r.Containers | Where-Object { $_.Result -eq 'Failed' }) {
    Write-Host "CONTAINER FAILURES:"
    $r.Containers | Where-Object { $_.Result -eq 'Failed' } | ForEach-Object {
        Write-Host "  $($_.Item): $($_.ErrorRecord.Exception.Message)"
    }
}
