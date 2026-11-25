[CmdletBinding()]
param(
    [string]$Device,
    [ValidateRange(1, 30)]
    [int]$BackgroundSeconds = 3
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-adb.ps1')

$adb = Get-AdbPath
if (-not $adb) { throw 'ADB was not found. Set ANDROID_HOME or add adb to PATH.' }
$online = @(Get-OnlineDevices $adb)
if (-not $Device) {
    if ($online.Count -ne 1) { throw 'Connect one Android device or pass -Device to choose an online device.' }
    $Device = $online[0]
} elseif ($Device -notin $online) {
    throw "Device '$Device' is not online."
}

$package = 'com.maps.example'
$processBefore = & $adb -s $Device shell pidof $package
if ($LASTEXITCODE -ne 0 -or -not $processBefore) { throw 'Open the example and wait for the map before running the lifecycle check.' }

& $adb -s $Device shell input keyevent KEYCODE_HOME
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Start-Sleep -Seconds $BackgroundSeconds

$launch = & $adb -s $Device shell am start -W -n "$package/.MainActivity"
if ($LASTEXITCODE -ne 0 -or $launch -match 'Error:|Exception') { throw "Could not resume $package." }
$processAfter = & $adb -s $Device shell pidof $package
if ($LASTEXITCODE -ne 0 -or $processAfter -ne $processBefore) { throw 'The example process did not survive backgrounding.' }
Write-Output 'The example resumed in the same process. On the device, verify the map renders and responds to pan and drag.'
