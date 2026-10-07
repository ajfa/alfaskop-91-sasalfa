# start-9030.ps1 [stop] - the Univac 90/30 side: fresh disks, U9030 with its windows hidden, IPL, and console.py
# running ims.con (OS/3, ICAM and IMS on the line of the A91). With A91_SAS_LOG naming the sas.txt that run-a91.sh
# writes (\\wsl.localhost\Ubuntu-22.04\home\<user>\alfaskop-91-sasalfa\run\live\sas.txt), ICAM starts once the A91
# has picked SAS2.1; without it, at once.
# Stops only what it started: python running this folder's console.py or relay.py, and U9030 by its pid file.
param([string]$Action = 'start')
$ErrorActionPreference = 'Stop'
$d = $PSScriptRoot
Set-Location $d
function Stop-Mine {
	Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
		Where-Object { $_.CommandLine -match 'console\.py ims\.con|relay\.py 127\.0\.0\.1:9036' } |
		ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
	& "$d/u9030ctl.ps1" stop | Out-Null
}
Stop-Mine
if ($Action -eq 'stop') { 'stopped'; return }
Copy-Item "$d/disks/REL042.8418", "$d/disks/LNS001.8418" "$d/run-u9030/Data" -Force
Remove-Item console.log, console.cmd -ErrorAction SilentlyContinue
& "$d/u9030ctl.ps1" start
$c = Start-Process -FilePath python -ArgumentList 'console.py', 'ims.con' -WorkingDirectory $d -WindowStyle Hidden -PassThru
Start-Sleep 3
& "$d/u9030ctl.ps1" ipl
"console $($c.Id)"
