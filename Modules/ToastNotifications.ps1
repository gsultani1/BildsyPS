# ===== ToastNotifications.ps1 =====
# Windows toast notifications for BildsyPS events
# Gracefully degrades if BurntToast is not installed — never breaks the shell

$global:ShelixToastEnabled = $true   # Set to $false to silence all toasts
$global:ShelixToastProvider = $null  # 'BurntToast' | 'WinRT' | $null (auto-detect)

# ===== Provider Detection =====
function Initialize-ToastProvider {
    <#
    .SYNOPSIS
    Detect the best available toast provider. Called once at module load.
    Priority: BurntToast > Windows Runtime API > None
    #>
    if ($global:ShelixToastProvider) { return $global:ShelixToastProvider }

    # Try BurntToast
    if (Get-Module -Name BurntToast -ListAvailable -ErrorAction SilentlyContinue) {
        try {
            Import-Module BurntToast -ErrorAction Stop
            $global:ShelixToastProvider = 'BurntToast'
            return 'BurntToast'
        }
        catch {}
    }

    # Try Windows Runtime toast API directly (no module needed, PS 5.1+ on Win10/11)
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $global:ShelixToastProvider = 'WinRT'
        return 'WinRT'
    }
    catch {}

    $global:ShelixToastProvider = 'None'
    return 'None'
}

# ===== Core Toast Function =====
function Send-ShelixToast {
    <#
    .SYNOPSIS
    Send a Windows toast notification. Silently no-ops if no toast provider is available.
    .PARAMETER Title
    Notification title (bold, first line).
    .PARAMETER Message
    Notification body text.
    .PARAMETER Type
    Visual style: 'Success' (green), 'Error' (red), 'Info' (default), 'Warning' (yellow)
    .PARAMETER Sound
    Play a sound with the notification. Default: $false.
    #>
    param(
        [string]$Title = 'BildsyPS',
        [string]$Message = '',
        [ValidateSet('Success', 'Error', 'Info', 'Warning')]
        [string]$Type = 'Info',
        [switch]$Sound
    )

    if (-not $global:ShelixToastEnabled) { return }

    $provider = Initialize-ToastProvider

    # Prepend an emoji to the title based on type
    $prefix = switch ($Type) {
        'Success' { '✅ ' }
        'Error' { '❌ ' }
        'Warning' { '⚠️ ' }
        default { '🔔 ' }
    }
    $fullTitle = "$prefix$Title"

    switch ($provider) {
        'BurntToast' {
            try {
                $btParams = @{
                    Text  = @($fullTitle, $Message)
                    AppId = 'BildsyPS'
                }
                if (-not $Sound) { $btParams.Silent = $true }
                New-BurntToastNotification @btParams
            }
            catch {
                # BurntToast failed silently — don't crash the shell
            }
        }

        'WinRT' {
            try {
                $appId = 'BildsyPS'
                $template = [Windows.UI.Notifications.ToastTemplateType, Windows.UI.Notifications, ContentType = WindowsRuntime]::ToastText02
                $toastXml = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]::GetTemplateContent($template)

                $textNodes = $toastXml.GetElementsByTagName('text')
                $textNodes.Item(0).AppendChild($toastXml.CreateTextNode($fullTitle)) | Out-Null
                $textNodes.Item(1).AppendChild($toastXml.CreateTextNode($Message)) | Out-Null

                if (-not $Sound) {
                    $audioEl = $toastXml.CreateElement('audio')
                    $audioEl.SetAttribute('silent', 'true')
                    $toastXml.DocumentElement.AppendChild($audioEl) | Out-Null
                }

                $toast = [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]::new($toastXml)
                [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]::CreateToastNotifier($appId).Show($toast)
            }
            catch {
                # WinRT failed silently
            }
        }

        'None' {
            # No toast provider — silently no-op
        }
    }
}

# ===== Convenience Wrappers =====
function Send-SuccessToast {
    param([string]$Title = 'Done', [string]$Message = '')
    Send-ShelixToast -Title $Title -Message $Message -Type Success
}

function Send-ErrorToast {
    param([string]$Title = 'Error', [string]$Message = '')
    Send-ShelixToast -Title $Title -Message $Message -Type Error
}

function Send-InfoToast {
    param([string]$Title = 'BildsyPS', [string]$Message = '')
    Send-ShelixToast -Title $Title -Message $Message -Type Info
}

# ===== Install Helper =====
function Install-BurntToast {
    <#
    .SYNOPSIS
    Install the BurntToast module and enable toast notifications.
    #>
    Write-Host "Installing BurntToast..." -ForegroundColor Cyan
    try {
        Install-Module -Name BurntToast -Scope CurrentUser -Force -ErrorAction Stop
        Import-Module BurntToast -ErrorAction Stop
        $global:ShelixToastProvider = 'BurntToast'
        Write-Host "BurntToast installed. Toast notifications enabled." -ForegroundColor Green
        Send-ShelixToast -Title "BildsyPS" -Message "Toast notifications are now active." -Type Success
    }
    catch {
        Write-Host "Failed to install BurntToast: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Try: Install-Module BurntToast -Scope CurrentUser" -ForegroundColor Yellow
    }
}

# ===== Status =====
function Get-ToastStatus {
    <#
    .SYNOPSIS
    Show the current toast notification provider and status.
    #>
    $provider = Initialize-ToastProvider
    $enabled = $global:ShelixToastEnabled
    Write-Host "`n  Toast Notifications" -ForegroundColor Cyan
    Write-Host "  Provider : $provider" -ForegroundColor Gray
    Write-Host "  Enabled  : $enabled" -ForegroundColor Gray
    if ($provider -eq 'None') {
        Write-Host "  Tip: Run Install-BurntToast to enable rich notifications." -ForegroundColor DarkYellow
    }
}

# Auto-detect provider at load time (non-blocking)
$null = Initialize-ToastProvider

Write-Verbose "ToastNotifications loaded: Send-ShelixToast, Install-BurntToast, Get-ToastStatus"
