$ErrorActionPreference = 'Stop'
# Read-only inventory through the exact argument builder used by the GUI.
$testRoot = Join-Path $env:TEMP ('EthernetHelper downloaded test ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
Expand-Archive -LiteralPath (Join-Path $PSScriptRoot 'downloads\EthernetHelper-Windows.zip') -DestinationPath $testRoot
$engine = Join-Path $testRoot 'Engine.ps1'
Set-Content -LiteralPath $engine -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII
$policyBefore = Get-ExecutionPolicy -List | ConvertTo-Json -Compress
$assembly = [Reflection.Assembly]::LoadFile((Join-Path $testRoot 'EthernetHelper.exe'))
$output = Join-Path $testRoot 'inventory result.json'
$arguments = [EthernetHelper.Program]::EngineArguments($engine, 'Inventory', $null, $output)
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Run-Inventory([string]$Arguments) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $ps
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardError = $true
    $info.StandardErrorEncoding = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    $process = [Diagnostics.Process]::Start($info)
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ExitCode=$process.ExitCode;Error=$stderr}
}
$old = Run-Inventory ($arguments.Replace('-ExecutionPolicy Bypass', '-ExecutionPolicy RemoteSigned'))
if ($old.ExitCode -eq 0 -or (Test-Path -LiteralPath $output) -or $old.Error -notmatch 'UnauthorizedAccess|PSSecurityException') {
    throw 'Expected the old launch to reproduce download signature blocking.'
}
Write-Output 'PASS: old launch reproduces downloaded-file blocking.'
$fixed = Run-Inventory $arguments
if ($fixed.ExitCode -ne 0 -or !(Test-Path -LiteralPath $output)) { throw ('Fixed launch failed: ' + $fixed.Error) }
$result = Get-Content -LiteralPath $output -Encoding UTF8 -Raw | ConvertFrom-Json
if (!$result.ok -or $result.status -ne 'inventory') { throw 'Inventory did not succeed.' }
if ((Get-Content -LiteralPath $engine -Stream Zone.Identifier -Raw) -notmatch 'ZoneId=3') { throw 'Download marker was unexpectedly removed.' }
if ((Get-ExecutionPolicy -List | ConvertTo-Json -Compress) -ne $policyBefore) { throw 'Parent execution policies changed.' }
Write-Output 'PASS: packaged app launch produces valid inventory with download marker intact and policies unchanged.'
Write-Output 'Only read-only Inventory was invoked; no repair or restore was performed.'
