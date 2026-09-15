$ErrorActionPreference = 'Stop'
$rootPath = $PSScriptRoot
$compilerPath = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compilerPath)) {
    $compilerPath = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $compilerPath)) { throw '.NET Framework C# compiler is unavailable.' }
# Windows PowerShell 5.1 requires a BOM to reliably read Korean script strings.
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
Get-ChildItem -LiteralPath $rootPath -Filter '*.ps1' -Recurse | ForEach-Object {
    $scriptText = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($_.FullName, $scriptText, $utf8Bom)
}
$arguments = @('/nologo','/target:winexe','/platform:anycpu','/optimize+','/codepage:65001',
    '/reference:System.dll','/reference:System.Core.dll','/reference:System.Drawing.dll',
    '/reference:System.Windows.Forms.dll','/reference:System.Web.Extensions.dll',
    "/out:$rootPath\EthernetHelper.exe", "/win32manifest:$rootPath\app.manifest")
if (Test-Path -LiteralPath "$rootPath\app.ico") { $arguments += "/win32icon:$rootPath\app.ico" }
$arguments += "$rootPath\EthernetHelper.cs"
& $compilerPath @arguments
if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $LASTEXITCODE" }
Write-Output "Built $rootPath\EthernetHelper.exe"
