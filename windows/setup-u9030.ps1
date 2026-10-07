# setup-u9030.ps1 [-App dir] [-Data dir] - prepare run-u9030\ from an installed Univac 90/30 emulator (U9030 by
# Steve Boyd): U9030.exe, sasalfa.cfg, pristine copies of the IMS disks in disks\, and a U9030Console.exe that exits
# at once, because U9030 starts its console client and that client would take the console port console.py uses.
param(
	[string]$App = (Join-Path ${env:ProgramFiles(x86)} 'Univac 9030 Emulator'),
	[string]$Data = (Join-Path $env:ProgramData 'Univac 9030 Emulator\Data'))
$ErrorActionPreference = 'Stop'
$run = Join-Path $PSScriptRoot 'run-u9030'
$disks = Join-Path $PSScriptRoot 'disks'
New-Item -ItemType Directory -Force (Join-Path $run 'Data'), $disks | Out-Null
Copy-Item (Join-Path $App 'U9030.exe') $run
Copy-Item (Join-Path $PSScriptRoot 'sasalfa.cfg') $run
Copy-Item (Join-Path $Data 'REL042.8418'), (Join-Path $Data 'LNS001.8418') $disks
$stub = Join-Path $run 'U9030Console.exe'
Remove-Item $stub -ErrorAction SilentlyContinue
powershell.exe -NoProfile -Command "Add-Type -TypeDefinition 'public static class NoConsole { public static void Main() { } }' -OutputAssembly '$stub' -OutputType WindowsApplication"
if (-not (Test-Path $stub)) { throw 'could not build U9030Console.exe' }
"ready: $run"
