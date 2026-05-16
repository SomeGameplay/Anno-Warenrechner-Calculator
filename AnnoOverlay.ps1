$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$calculatorPath = Join-Path $scriptDir 'anno-warenrechner\index.html'
$windowTitleNeedle = 'Anno Warenrechner'
$hotkeyText = 'Strg + Alt + R'

if (-not (Test-Path $calculatorPath)) {
    throw "Rechnerdatei nicht gefunden: $calculatorPath"
}

Add-Type -AssemblyName System.Windows.Forms

$nativeCode = @"
using System;
using System.Runtime.InteropServices;

public static class AnnoOverlayNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    public static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

Add-Type -TypeDefinition $nativeCode

$MOD_ALT = 0x0001
$MOD_CONTROL = 0x0002
$MOD_NOREPEAT = 0x4000
$VK_R = 0x52
$WM_HOTKEY = 0x0312
$HOTKEY_ID = 17011702

$SW_HIDE = 0
$SW_SHOW = 5
$SWP_SHOWWINDOW = 0x0040
$HWND_TOPMOST = [IntPtr](-1)

$overlayWidth = 1080
$overlayHeight = 940

function Get-EdgePath {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    $command = Get-Command 'msedge.exe' -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw 'Microsoft Edge wurde nicht gefunden. Das Overlay nutzt Edge im App-Modus.'
}

function Get-OverlayBounds {
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $width = [Math]::Min($overlayWidth, [Math]::Max(720, $workingArea.Width - 60))
    $height = [Math]::Min($overlayHeight, [Math]::Max(640, $workingArea.Height - 60))
    $x = [Math]::Max(0, $workingArea.Right - $width - 22)
    $y = [Math]::Max(0, $workingArea.Top + 22)

    return @{
        X = [int]$x
        Y = [int]$y
        Width = [int]$width
        Height = [int]$height
    }
}

function Find-OverlayWindow {
    param(
        [int]$Attempts = 1,
        [int]$DelayMs = 250
    )

    for ($i = 0; $i -lt $Attempts; $i++) {
        $process = Get-Process 'msedge' -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$windowTitleNeedle*" } |
            Select-Object -First 1

        if ($process) {
            return $process
        }

        if ($i -lt ($Attempts - 1)) {
            Start-Sleep -Milliseconds $DelayMs
        }
    }

    return $null
}

function Make-OverlayTopmost {
    param(
        [IntPtr]$Handle
    )

    $bounds = Get-OverlayBounds
    [AnnoOverlayNative]::SetWindowPos(
        $Handle,
        $HWND_TOPMOST,
        $bounds.X,
        $bounds.Y,
        $bounds.Width,
        $bounds.Height,
        $SWP_SHOWWINDOW
    ) | Out-Null
}

function Start-OverlayWindow {
    $existing = Find-OverlayWindow
    if ($existing) {
        Make-OverlayTopmost -Handle ([IntPtr]$existing.MainWindowHandle)
        return $existing
    }

    $edgePath = Get-EdgePath
    $uri = ([System.Uri](Resolve-Path $calculatorPath).Path).AbsoluteUri
    $bounds = Get-OverlayBounds

    $arguments = @(
        '--new-window',
        "--app=$uri",
        "--window-size=$($bounds.Width),$($bounds.Height)",
        "--window-position=$($bounds.X),$($bounds.Y)"
    )

    Start-Process -FilePath $edgePath -ArgumentList $arguments | Out-Null

    $window = Find-OverlayWindow -Attempts 35 -DelayMs 220
    if (-not $window) {
        throw 'Das Overlay-Fenster wurde gestartet, konnte aber nicht gefunden werden.'
    }

    Make-OverlayTopmost -Handle ([IntPtr]$window.MainWindowHandle)
    [AnnoOverlayNative]::SetForegroundWindow([IntPtr]$window.MainWindowHandle) | Out-Null
    return $window
}

function Toggle-OverlayWindow {
    $window = Find-OverlayWindow

    if (-not $window) {
        $window = Start-OverlayWindow
        return
    }

    $handle = [IntPtr]$window.MainWindowHandle

    if ([AnnoOverlayNative]::IsWindowVisible($handle)) {
        [AnnoOverlayNative]::ShowWindow($handle, $SW_HIDE) | Out-Null
    } else {
        [AnnoOverlayNative]::ShowWindow($handle, $SW_SHOW) | Out-Null
        Make-OverlayTopmost -Handle $handle
        [AnnoOverlayNative]::SetForegroundWindow($handle) | Out-Null
    }
}

# Rechner direkt öffnen.
Start-OverlayWindow | Out-Null

$modifiers = $MOD_CONTROL -bor $MOD_ALT -bor $MOD_NOREPEAT
$registered = [AnnoOverlayNative]::RegisterHotKey([IntPtr]::Zero, $HOTKEY_ID, $modifiers, $VK_R)

if (-not $registered) {
    throw "Hotkey $hotkeyText konnte nicht registriert werden. Er wird vermutlich schon von einer anderen App verwendet."
}

try {
    while ($true) {
        $message = New-Object 'AnnoOverlayNative+MSG'
        $result = [AnnoOverlayNative]::GetMessage([ref]$message, [IntPtr]::Zero, 0, 0)

        if ($result -le 0) {
            break
        }

        if ($message.message -eq $WM_HOTKEY -and $message.wParam.ToUInt32() -eq $HOTKEY_ID) {
            Toggle-OverlayWindow
        }
    }
}
finally {
    [AnnoOverlayNative]::UnregisterHotKey([IntPtr]::Zero, $HOTKEY_ID) | Out-Null
}
