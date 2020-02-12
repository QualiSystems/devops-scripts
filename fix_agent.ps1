$ErrorActionPreference = 'Stop'

function Invoke-Executable([string]$filePath, [string[]]$argumentList) {
    $process = Start-Process -FilePath $filePath -Wait -NoNewWindow -PassThru -ArgumentList $argumentList
    $exitCode = $process.ExitCode
    if ($exitCode -ne 0) {
        throw "$filePath failed. Exit code: $exitCode"
    }
}

$devopsPath = "\\qsnas1\Storage\devops"

# make sure choclatey source is the network share
Write-Host -ForegroundColor Blue 'Configuring chocolatey to use the network share as a source for packages'
choco source remove --name="'chocolatey'"
choco source add --name="'internal_server'" --source="'$devopsPath\chocolatey'" --priority="'1'"

#replace python 2 and python 3 64 bit installations with the 32 bit installations
Write-Host -ForegroundColor Blue 'Replacing Python 64 bit installation with the 32 bit installation'
choco uninstall -y python2
choco uninstall -y python3
choco install -y python2 --params 'PrependPath=1' --forcex86
choco install -y python3 --params 'PrependPath=1' --forcex86

# enable sql server's tcp protocol to enable remote access
Write-Host -ForegroundColor Blue 'Enabling SQL server TCP protocol'
Import-Module 'sqlps'
$wmi = New-Object 'Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer'
$uri = "ManagedComputer[@Name='$($Env:ComputerName)']/ServerInstance[@Name='MSSQLSERVER']/ServerProtocol[@Name='Tcp']"
$tcp = $wmi.GetSmoObject($uri)
$tcp.IsEnabled = $true
$tcp.Alter()
Restart-Service -Name MSSQLSERVER

# install azure functions core tools
Write-Host -ForegroundColor Blue 'Installing Azure functions core tools npm package'
Invoke-Executable -filePath 'npm.cmd' -argumentList 'install', '-g', 'azure-functions-core-tools'

# fix visual studio installation if needed
if (-not $(Test-Path 'C:\Program Files (x86)\Microsoft SDKs\Azure\Storage Emulator')) {
    Write-Host -ForegroundColor Blue 'Storage emulator is not installed. Repairing the Visual Studio installation.'
    $arguments = 'repair',
                 "--layoutPath ""$devopsPath\unattended\VS2017Layout""",
                 '--installPath "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise"',
                 '--passive',
                 '--norestart'

    Invoke-Executable -filePath 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vs_installer.exe' -argumentList $arguments
}