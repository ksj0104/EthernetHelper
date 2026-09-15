$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'build.ps1')
$resultPath = Join-Path $env:TEMP ('EthernetHelper-selftest-' + [guid]::NewGuid().ToString('N') + '.txt')
$process = Start-Process -FilePath (Join-Path $PSScriptRoot 'EthernetHelper.exe') -ArgumentList @('--self-test', ('"' + $resultPath + '"')) -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw 'Executable self-test failed.' }
Get-Content -LiteralPath $resultPath -Encoding UTF8
$downloadPath = Join-Path $PSScriptRoot 'downloads'
New-Item -ItemType Directory -Path $downloadPath -Force | Out-Null
$zipPath = Join-Path $downloadPath 'EthernetHelper-Windows.zip'
$files = @('EthernetHelper.exe', 'Engine.ps1', 'README.md') | ForEach-Object { Join-Path $PSScriptRoot $_ }
Compress-Archive -LiteralPath $files -DestinationPath $zipPath -Force
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $downloadPath 'SHA256SUMS.txt'), "$hash  EthernetHelper-Windows.zip`n", [Text.Encoding]::ASCII)
Write-Output "Packaged $zipPath"
