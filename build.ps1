# Release build for ARPG Movement. Invoked via build.cmd patch|minor|major:
# bumps the version in manifest.json and mmapi_mod_declare, then zips
# momi-mod/arpg_movement into dist/ARPGMovement-<version>.zip (folder at zip
# root, as Nexus/MOMI expect). Does not compile-check — run the MOMI installer
# once before releasing.
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('patch', 'minor', 'major')]
    [string]$Bump
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$modDir = Join-Path $root 'momi-mod\arpg_movement'
$manifestPath = Join-Path $modDir 'manifest.json'
$gmlPath = Join-Path $modDir 'gml\ArpgMovement.gml'

$cur = (Get-Content -Raw $manifestPath | ConvertFrom-Json).version
if ($cur -notmatch '^\d+\.\d+\.\d+$') { throw "manifest.json: unexpected version '$cur'" }
$maj, $min, $pat = $cur.Split('.') | ForEach-Object { [int]$_ }

switch ($Bump) {
    'patch' { $pat++ }
    'minor' { $min++; $pat = 0 }
    'major' { $maj++; $min = 0; $pat = 0 }
}
$new = "$maj.$min.$pat"

# Plain text replaces (not a JSON round-trip) so formatting survives;
# UTF8 without BOM so the GML's em dashes do too.
$enc = New-Object System.Text.UTF8Encoding($false)

$text = [IO.File]::ReadAllText($manifestPath)
$bumped = [regex]::Replace($text, '(?m)^(\s*)"version":\s*"[^"]*"', ('${1}"version": "' + $new + '"'))
if ($bumped -eq $text) { throw "manifest.json: version line not found" }
[IO.File]::WriteAllText($manifestPath, $bumped, $enc)

$text = [IO.File]::ReadAllText($gmlPath)
$bumped = [regex]::Replace($text, 'mmapi_mod_declare\("arpg_movement",\s*"[^"]*"\)', ('mmapi_mod_declare("arpg_movement", "' + $new + '")'))
if ($bumped -eq $text) { throw "ArpgMovement.gml: mmapi_mod_declare(...) not found" }
[IO.File]::WriteAllText($gmlPath, $bumped, $enc)

$distDir = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $distDir | Out-Null
$zip = Join-Path $distDir "ARPGMovement-$new.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $modDir -DestinationPath $zip

Write-Host "Version: $cur -> $new"
Write-Host "Package: $zip"
