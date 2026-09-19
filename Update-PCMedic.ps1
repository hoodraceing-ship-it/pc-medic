#Requires -Version 5.1
[CmdletBinding()]
param([int]$ParentPid = 0,[switch]$ForceCheck)
$ErrorActionPreference = 'Stop'
$repo='hoodraceing-ship-it/PC-Medic';$api="https://api.github.com/repos/$repo/releases/latest";$appDir=$PSScriptRoot
$stateDir=Join-Path $env:ProgramData 'PCMedic';$stateFile=Join-Path $stateDir 'update-state.json';$logDir=Join-Path $stateDir 'Logs'
New-Item -ItemType Directory -Path $stateDir,$logDir -Force|Out-Null
$logFile=Join-Path $logDir 'updater.log'
function Write-UpdateLog([string]$Message){Add-Content $logFile ("{0:u} {1}" -f (Get-Date),$Message) -Encoding UTF8}
function Show-Info([string]$Message,[string]$Title='PC Medic Update'){Add-Type -AssemblyName PresentationFramework;[System.Windows.MessageBox]::Show($Message,$Title,'OK','Information')|Out-Null}
function Get-LocalVersion{$line=Get-Content (Join-Path $appDir 'VERSION.txt') -First 1;$m=[regex]::Match($line,'\d+\.\d+\.\d+');if(-not $m.Success){throw 'Installed version could not be determined.'};[version]$m.Value}
try{
 if(-not $ForceCheck -and(Test-Path $stateFile)){try{$s=Get-Content $stateFile -Raw|ConvertFrom-Json;if([datetime]$s.LastCheck -gt(Get-Date).AddHours(-24)){exit 0}}catch{}}
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$headers=@{'User-Agent'='PC-Medic-Updater';'Accept'='application/vnd.github+json'}
 $release=Invoke-RestMethod -Uri $api -Headers $headers -TimeoutSec 12
 @{LastCheck=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content $stateFile -Encoding UTF8
 $local=Get-LocalVersion;$remote=[version](([string]$release.tag_name).TrimStart('v','V'));Write-UpdateLog "Installed $local; latest $remote."
 if($remote -le $local){if($ForceCheck){Show-Info "PC Medic $local is already up to date."};exit 0}
 $zipAsset=$release.assets|Where-Object name -match '\.zip$'|Select-Object -First 1;$hashAsset=$release.assets|Where-Object name -match '\.(sha256|sha256\.txt)$'|Select-Object -First 1
 if(-not $zipAsset -or -not $hashAsset){throw "Release $remote is missing the ZIP or SHA-256 checksum asset."}
 Add-Type -AssemblyName PresentationFramework
 if([System.Windows.MessageBox]::Show("PC Medic $remote is available.`n`n$($release.name)`n`nInstall it now? PC Medic will close and reopen automatically.",'PC Medic Update','YesNo','Information') -ne 'Yes'){exit 0}
 $tempRoot=Join-Path $env:TEMP ('PCMedic-Update-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $tempRoot -Force|Out-Null
 $zipPath=Join-Path $tempRoot $zipAsset.name;$hashPath=Join-Path $tempRoot $hashAsset.name
 Invoke-WebRequest $zipAsset.browser_download_url -Headers $headers -OutFile $zipPath -UseBasicParsing;Invoke-WebRequest $hashAsset.browser_download_url -Headers $headers -OutFile $hashPath -UseBasicParsing
 $expected=([regex]::Match((Get-Content $hashPath -Raw),'(?i)\b[a-f0-9]{64}\b')).Value.ToLowerInvariant();$actual=(Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
 if(-not $expected -or $actual -ne $expected){throw 'The update checksum does not match. Nothing was installed.'}
 $extract=Join-Path $tempRoot 'extracted';Expand-Archive $zipPath $extract -Force
 $source=Get-ChildItem $extract -Directory -Recurse|Where-Object {Test-Path (Join-Path $_.FullName 'PCMedic.ps1')}|Select-Object -First 1 -ExpandProperty FullName
 if(-not $source){throw 'The update package does not contain PC Medic.'}
 $apply=Join-Path $tempRoot 'Apply-PCMedicUpdate.ps1'
 $applyText="`$ErrorActionPreference='Stop'`r`nif($ParentPid -gt 0){Wait-Process -Id $ParentPid -Timeout 15 -ErrorAction SilentlyContinue}`r`nStart-Sleep -Milliseconds 800`r`nCopy-Item -Path '$($source.Replace("'","''"))\*' -Destination '$($appDir.Replace("'","''"))' -Recurse -Force`r`nStart-Process (Join-Path `$env:WINDIR 'System32\wscript.exe') -ArgumentList ('`"'+(Join-Path '$($appDir.Replace("'","''"))' 'PCMedic.vbs')+'`"')"
 Set-Content $apply $applyText -Encoding UTF8;Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$apply+'"'))
 if($ParentPid -gt 0){Stop-Process -Id $ParentPid -Force -ErrorAction SilentlyContinue}
}catch{Write-UpdateLog $_.Exception.ToString();if($ForceCheck){Show-Info ("The update check could not be completed.`n`n"+$_.Exception.Message+"`n`nNo files were changed.") 'PC Medic Update Error'};exit 1}
