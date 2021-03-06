#Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/QualiSystems/devops-scripts/master/agent.ps1'))

param (
    [string]$UserName = 'buser',
    [string]$Password,
    [switch]$DebugMode
)

function Log([string]$message) {
    Write-Host $message
    if ($DebugMode) {
        Read-Host 'Press enter to continue'
    }
}

function New-InitScript {
    $guid = (New-Guid).ToString('n')
    $initScriptName = "InitMachine_$guid.ps1"
    $scriptContent = (New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/QualiSystems/devops-scripts/master/init.ps1')

    return New-Item -Force -Path $setupScriptsFolder -Name $initScriptName -ItemType 'file' -Value $scriptContent
}

$now = Get-Date
$setupScriptsFolder = Join-Path -Path $Env:ALLUSERSPROFILE -ChildPath 'TcAgentSetup'
New-Item -ItemType Directory -Path $setupScriptsFolder -Force
$logPath = "$setupScriptsFolder\tc_agent_setup_log-$($now.Month)-$($now.Day)-$($now.Hour)-$($now.Minute)-$($now.Second)-$($now.Millisecond).txt"

Write-Host "Writing transcript to $logPath"
Start-Transcript -Path $logPath

try {
    
    $initScriptItem = New-InitScript
    . $initScriptItem.FullName -UserName $UserName -Password $Password -DebugMode:$DebugMode -CallingScript 'agent.ps1'

    Restart
}
catch {
    Log "An exception was raised: $_"
    if(-not $DebugMode) {
        Read-Host 'Press enter to continue'
    }
    exit 2
}
finally {
    Stop-Transcript
}