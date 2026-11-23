$ErrorActionPreference = 'Stop'
$output = Join-Path $PSScriptRoot 'build/cpp-tests'
New-Item -ItemType Directory -Path $output -Force | Out-Null
foreach ($test in Get-ChildItem (Join-Path $PSScriptRoot 'test') -Filter '*.cpp') {
  $executable = Join-Path $output ($test.BaseName + '.exe')
  & clang++ -std=c++20 -Wall -Wextra -Werror $test.FullName -o $executable
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & $executable
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  Write-Output "$($test.BaseName) passed"
}
