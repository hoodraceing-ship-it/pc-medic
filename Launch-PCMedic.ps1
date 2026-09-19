#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$logRoot = Join-Path $env:ProgramData 'PCMedic\Logs'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$logFile = Join-Path $logRoot ('Startup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try {
    & (Join-Path $PSScriptRoot 'PCMedic.ps1')
} catch {
    $details = @(
        'PC Medic could not start.'
        ''
        ('Time: ' + (Get-Date))
        ('PowerShell: ' + $PSVersionTable.PSVersion)
        ('Windows: ' + [Environment]::OSVersion.VersionString)
        ''
        $_.Exception.ToString()
        ''
        $_.ScriptStackTrace
    ) -join [Environment]::NewLine
    Set-Content -Path $logFile -Value $details -Encoding UTF8
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("PC Medic could not start.`n`nThe error has been saved here:`n$logFile`n`nThe log will open after you click OK.",'PC Medic startup error','OK','Error') | Out-Null
    Start-Process notepad.exe -ArgumentList ('"{0}"' -f $logFile)
}
