param (
    [string]$UserName,
    [string]$Password
)

function Log([string]$message) {    
    Write-Host $message
}

$secureStringPwd = $Password | ConvertTo-SecureString -AsPlainText -Force 
$userCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $secureStringPwd

Log 'Enabling RDP'
Invoke-DscResource -Name xRemoteDesktopAdmin -ModuleName xRemoteDesktopAdmin -Property  @{Ensure = 'Present'; UserAuthentication = 'Secure' } -Method Set

Log 'Disabling UAC'
Invoke-DscResource -Name Registry -ModuleName PSDesiredStateConfiguration -Property  @{Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; ValueType = 'Dword'; Ensure = 'present'; ValueData = @('0'); ValueName = 'EnableLUA' } -Method Set

Log 'Setting power plan'
Invoke-DscResource -Name cPowerPlanSetting -ModuleName DSCR_PowerPlan -Property  @{planGuid = 'Active'; SettingGuid = 'STANDBYIDLE'; Value = 0; AcDc = 'Both' } -Method Set

Log 'Enabling file sharing'
Invoke-DscResource -Name xfirewall -ModuleName xNetworking -Property  @{name = 'File and Printer Sharing (SMB-In)'; ensure = 'Present'; enabled = 'True' } -Method Set
Invoke-DscResource -Name xfirewall -ModuleName xNetworking -Property  @{name = 'File and Printer Sharing (NB-Session-In)'; ensure = 'Present'; enabled = 'True' } -Method Set

Log 'Enabling PowerShell remoting'
Enable-PSRemoting

Log 'Installing chocolatey pacakge manager'
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

Log 'Installing chocolatey packages'
choco install -y googlechrome 7zip everything
choco install -y sql-server-2017
choco install -y nodejs
choco install -y python2
choco install -y vcpython27
choco install -y python3
choco install -y jdk8

$networkInstallersPath = "\\qsnas1\Storage\devops\TC_Agent_Automation"

Log 'Installing ASPNet MVC 4'
Start-Process -FilePath "$networkInstallersPath\AspNetMVC4Setup.exe" -Wait -NoNewWindow -ArgumentList '/Passive', '/NoRestart'

Log 'Installing Visual Studio 2013 build tools'
Start-Process -FilePath "$networkInstallersPath\BuildTools_Full_2013.exe" -Wait -NoNewWindow -ArgumentList '/Passive', '/NoRestart'

Log 'Installing Visual Studio 2015 build tools'
Start-Process -FilePath "$networkInstallersPath\BuildTools_Full_2015.exe" -Wait -NoNewWindow -ArgumentList '/Passive', '/NoRestart'

Log 'Installing Visual Studio 2017'
$vs2017InstallerPath = "$networkInstallersPath\vs_Enterprise.exe"
Start-Process -FilePath $vs2017InstallerPath -Wait -NoNewWindow -ArgumentList '--update', '--passive', '--wait', '--norestart'
Start-Process -FilePath $vs2017InstallerPath -Wait -NoNewWindow -ArgumentList '--config', "`"$networkInstallersPath\.vsconfig`"", '--passive', '--wait', '--norestart', '--nocache'

Log 'Installing Visual Studio 2013 Team Explorer'
Start-Process -FilePath "$networkInstallersPath\vs_teamExplorer.exe" -Wait -NoNewWindow -ArgumentList '/Passive', '/NoRestart'

Log 'Installing TFS power tools 2013'
Start-Process -FilePath "msiexec.exe" -Wait -NoNewWindow -ArgumentList '/i',"`"$networkInstallersPath\Team Foundation Server 2013 Power Tools.msi`"",'/passive','/norestart'

Log 'Installing Wix 3.5'
Start-Process -FilePath "msiexec.exe" -Wait -NoNewWindow -ArgumentList '/i',"`"$networkInstallersPath\Wix35.msi`"",'/passive','/norestart'

Log 'Installing VMware SDK'
Start-Process -FilePath "$networkInstallersPath\VMware-vix-1.11.2-591240.exe" -Wait -NoNewWindow -ArgumentList '/s', '/v/qn'

Log 'Installing VMware PowerCLI'
Start-Process -FilePath "$networkInstallersPath\VMware-PowerCLI-5.5.0-1295336.exe" -Wait -NoNewWindow -ArgumentList '/s', '/v/qn'

Log 'Setting evironment variables'
# $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
[System.Environment]::SetEnvironmentVariable('UseCommandLineService', 'True', [System.EnvironmentVariableTarget]::Machine)
# [System.Environment]::SetEnvironmentVariable('Path', $currentPath + 'C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer' , [System.EnvironmentVariableTarget]::Machine)

Log 'Activating Windows'
$computer = $Env:ComputerName
$key = Read-Host -Prompt "Please Enter Windows Activation Key"
$service = get-wmiObject -query "select * from SoftwareLicensingService" -computername $computer
$service.InstallProductKey($key)
$service.RefreshLicenseStatus()

Log "Downloading TeamCity build agent"
$tcAgentArchivePath = Join-Path $env:Temp -ChildPath 'buildAgent.zip'
$buildAgentPath = 'C:\BuildAgent'

Invoke-RestMethod -Method Get http://tc/update/buildAgent.zip -OutFile $tcAgentArchivePath
Expand-Archive $tcAgentArchivePath -DestinationPath $buildAgentPath

Log "Downloading latest QsBuild artifacts from TeamCity"
$qsbuildArchivePath = Join-Path $Env:Temp -ChildPath 'qsbuild.zip'
$qsAgentSpyFolder = "$($Env:Temp)\QsAgentSpy"
Invoke-RestMethod -Method Get "http://tc/httpAuth/app/rest/builds/count:1,pinned:true,buildType:Trunk_Tools_QsBuild/artifacts/content/QsBuild.zip" -Credential $userCredentials -OutFile $qsbuildArchivePath
Expand-Archive $qsbuildArchivePath -DestinationPath $qsAgentSpyFolder

$javaHomePath = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
$jrePath = "$javaHomePath\jre"
$serverName = [System.Environment]::MachineName

$agentConfiguration = 
@"
serverUrl=http\://tc
name=$serverName
workDir=C\:\\BuildAgent\\work
tempDir=C\:\\BuildAgent\\temp
systemDir=C\:\\BuildAgent\\system
ownPort=9090
env.TEAMCITY_JRE=$jrePath
"@

New-Item -Path "$buildAgentPath\conf\" -Name 'buildAgent.properties' -Type 'file' -Value $agentConfiguration -Force

Log "Running agent maintenance"
$qsBuildExePath = Join-Path -Path $qsAgentSpyFolder -ChildPath 'QsBuild.exe'
Start-Process -FilePath $qsBuildExePath -Wait -NoNewWindow -ArgumentList '/RunnerType=AgentMaintenance', '/Verbosity=Max', '/IsTeamCity=false', '/SolutionRoot=NONE', '/BuildId=0', "/TriggeredBy=$UserName", '/SkipScreenResolution=true', '/SkipAntiVirus=true', '/DisableMinutes=15'