@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
"$scripts = Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'powershell.exe' -or $_.Name -eq 'pwsh.exe') -and $_.CommandLine -like '*AnnoOverlay.ps1*' }; ^
foreach ($script in $scripts) { Stop-Process -Id $script.ProcessId -Force -ErrorAction SilentlyContinue }; ^
Get-Process msedge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*Anno Warenrechner*' } | ForEach-Object { $_.CloseMainWindow() | Out-Null }"
exit
