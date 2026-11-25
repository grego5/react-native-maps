function Get-AdbPath {
    $name = if ($IsWindows) { 'adb.exe' } else { 'adb' }
    foreach ($sdk in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)) {
        if ($sdk) {
            $path = Join-Path $sdk "platform-tools/$name"
            if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
        }
    }
    $command = Get-Command adb -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
}

function Get-OnlineDevices([string]$Adb) {
    $devices = & $Adb devices
    if ($LASTEXITCODE -ne 0) { throw 'ADB device discovery failed.' }
    foreach ($line in $devices) {
        if ($line -match '^(\S+)\s+device\s*$') { $Matches[1] }
    }
}
