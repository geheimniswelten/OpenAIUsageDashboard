[CmdletBinding()]
param(
    [string]$DelphiBin = "${env:ProgramFiles(x86)}\Embarcadero\Studio\37.0\bin",
    [string]$ResourceCompiler = '',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '_bin')
)

$ErrorActionPreference = 'Stop'
if (-not $ResourceCompiler) {
    $sdkCompiler = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\rc.exe" `
        -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $sdkCompiler) { throw 'Windows SDK rc.exe not found. Set -ResourceCompiler to its full path.' }
    $ResourceCompiler = $sdkCompiler.FullName
}
$compiler = Join-Path $DelphiBin 'dcc64.exe'
foreach ($tool in @($ResourceCompiler, $compiler)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Compiler not found: $tool. Set -DelphiBin to your Delphi bin directory."
    }
}
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
$dcuPath = Join-Path $PSScriptRoot '_dcu\Win64_Release'
New-Item -ItemType Directory -Force -Path $outputPath, $dcuPath | Out-Null
$resourceOutput = Join-Path $dcuPath 'OpenAIUsageDashboard.res'

Push-Location $PSScriptRoot
try {
    # Direct dcc builds do not regenerate the IDE-managed project resource.
    # Always compile the current MAINICON, manifest and version information.
    # BRCC32 rewrites the group metadata of these 32-bit icons to 24-bit.
    # The Windows SDK compiler preserves the source ICO metadata and alpha.
    & $ResourceCompiler /nologo /fo $resourceOutput 'OpenAIUsageDashboard.rc'
    if ($LASTEXITCODE -ne 0) { throw "Resource compilation failed ($LASTEXITCODE)." }
    Copy-Item -LiteralPath $resourceOutput -Destination (Join-Path $PSScriptRoot 'OpenAIUsageDashboard.RES') -Force

    & $compiler -B -Q --codepage:65001 '-$O+' '-$D-' '-$L-' `
        '-NSSystem;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win;Bde' `
        "-N0$dcuPath" "-E$outputPath" 'OpenAIUsageDashboard.dpr'
    if ($LASTEXITCODE -ne 0) { throw "Win64 compilation failed ($LASTEXITCODE)." }
    Write-Output (Join-Path $outputPath 'OpenAIUsageDashboard.exe')
}
finally {
    Pop-Location
}
