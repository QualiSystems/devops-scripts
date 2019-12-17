#Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/QualiSystems/devops-scripts/master/debug.ps1'))

$scriptName = 'agent.ps1'
$content = ((New-Object System.Net.WebClient).DownloadString("https://raw.githubusercontent.com/QualiSystems/devops-scripts/master/$scriptName"))
$initialScriptPath = Join-Path -Path $Env:TEMP -ChildPath $scriptName
New-Item -Path $initialScriptPath -Value $content

. $initialScriptPath -DebugMode