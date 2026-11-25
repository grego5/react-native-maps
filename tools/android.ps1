[CmdletBinding()]
param(
    [switch]$Release,
    [switch]$Emulator,
    [string]$Device,
    [ValidateRange(1, 65535)]
    [int]$Port = 8088
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-adb.ps1')

if ($Release -and $Device) { throw 'Release mode builds the APK only. Omit -Device.' }
$example = Join-Path $PSScriptRoot '../example'
$abi = if ($Emulator) { 'x86_64' } else { 'arm64-v8a' }
$variant = if ($Release) { 'release' } else { 'debug' }
$task = if ($Release) { ':app:assembleRelease' } else { ':app:assembleDebug' }
$gradlew = if ($IsWindows) { './gradlew.bat' } else { './gradlew' }

Push-Location -LiteralPath $example
try {
    # Install a fresh archive so npm cannot reuse an older copy of the local dependency.
    $packDir = [IO.Directory]::CreateTempSubdirectory('react-native-maps-')
    try {
        & npm pack 'file:..' --pack-destination $packDir.FullName --silent
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        $archive = Get-ChildItem -LiteralPath $packDir.FullName -File -Filter '*.tgz'
        & npm install --no-save --install-links --no-audit --no-fund "react-native-maps@file:$($archive.FullName)"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } finally {
        Get-ChildItem -LiteralPath $packDir.FullName -File | Remove-Item
        Remove-Item -LiteralPath $packDir.FullName
    }

    & npx expo prebuild --platform android --no-install
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Set-Location -LiteralPath 'android'
    & $gradlew $task "-PreactNativeArchitectures=$abi"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $apk = (Resolve-Path -LiteralPath "app/build/outputs/apk/$variant/app-$variant.apk").Path
    Write-Output "Built APK: $apk"
} finally {
    Pop-Location
}

if ($Release) { return }
$adb = Get-AdbPath
if (-not $adb) {
    if ($Device) { throw 'ADB was not found. Set ANDROID_HOME or add adb to PATH.' }
    Write-Output 'ADB was not found. APK built without installation.'
    return
}
$candidates = @(Get-OnlineDevices $adb | Where-Object { ($_ -match '^emulator-\d+$') -eq [bool]$Emulator })
if ($Device -and $Device -notin $candidates) { throw "Device '$Device' is offline or does not match the selected build mode." }
if (-not $Device) {
    if ($candidates.Count -eq 0) {
        Write-Output 'No matching online device. APK built without installation.'
        return
    }
    if ($candidates.Count -gt 1) { throw 'Multiple matching devices are online. Pass -Device to choose one.' }
    $Device = $candidates[0]
}

$deviceAbi = & $adb -s $Device shell getprop ro.product.cpu.abi
if ($LASTEXITCODE -ne 0 -or ([string]$deviceAbi).Trim() -ne $abi) {
    throw "Device '$Device' does not report the built ABI '$abi'."
}
& $adb -s $Device install -r $apk
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

try {
    $metro = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/status" -TimeoutSec 2 -NoProxy
} catch {
    Write-Output "Installed on '$Device'. Start Metro with npm run start, then open the development client."
    return
}
if ($metro.Content -notmatch 'packager-status:running') {
    Write-Output "Installed on '$Device'. Metro is unavailable on port $Port."
    return
}

& $adb -s $Device reverse "tcp:$Port" "tcp:$Port"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$metroUrl = [Uri]::EscapeDataString("http://127.0.0.1:$Port")
& $adb -s $Device shell am start -W -a android.intent.action.VIEW -n 'com.maps.example/.MainActivity' -d "exp+react-native-maps-example://expo-development-client/?url=$metroUrl"
exit $LASTEXITCODE
