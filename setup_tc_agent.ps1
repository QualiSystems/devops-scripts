param (
    [string]$UserName,
    [string]$Password,
    [switch]$DebugMode
)

$ErrorActionPreference = if ($DebugMode) { 'Inquire' } else { 'Stop' }

function Log([string]$message) {    
    Write-Host $message
    if ($DebugMode) {
        Read-Host 'Press enter to continue...'
    }
}

function Install-ChocolateyPackage() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$packageName,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)]$installationArguments)

    choco install -y $packageName @installationArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install chocolatey package $packageName. Exit code: $LASTEXITCODE"
    }
}

function Invoke-Executable([string]$filePath, [string[]]$argumentList = $null) {
    if ($null -eq $argumentList) {
        $process = Start-Process -FilePath $filePath -Wait -NoNewWindow -PassThru
    }
    else {
        $process = Start-Process -FilePath $filePath -Wait -NoNewWindow -ArgumentList $argumentList -PassThru
    }

    $exitCode = $process.ExitCode
    if ($exitCode -ne 0) {
        throw "Failed to install $filePath. Exit code: $exitCode"
    }
}
function Invoke-MsiInstaller([string]$installerPath) {
    Invoke-Executable -filePath 'msiexec.exe' -argumentList '/i', $installerPath, '/passive', '/norestart'
}

$now = Get-Date
$setupScriptsFolder = Join-Path -Path $Env:ALLUSERSPROFILE -ChildPath 'TcAgentSetup'
$logPath = "$setupScriptsFolder\tc_agent_setup_log-$($now.Month)-$($now.Day)-$($now.Hour)-$($now.Minute)-$($now.Second)-$($now.Millisecond).txt"

Write-Host "Writing transcript to $logPath"
Start-Transcript -Path $logPath

try {
    $secureStringPwd = $Password | ConvertTo-SecureString -AsPlainText -Force
    $userCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $secureStringPwd
    $networkInstallersPath = '\\qsnas1\Storage\devops\unattended'

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
    & "$networkInstallersPath\installChocolatey.ps1"

    Log 'Installing chocolatey packages'
    Install-ChocolateyPackage vcredist-all
    Install-ChocolateyPackage googlechrome
    Install-ChocolateyPackage 7zip
    Install-ChocolateyPackage everything
    Install-ChocolateyPackage sql-server-2017 --params="'/IsoPath:$networkInstallersPath\en_sql_server_2017_developer_x64_dvd_11296168.iso'"
    Install-ChocolateyPackage nodejs-lts
    Install-ChocolateyPackage python2 --params 'PrependPath=1'
    Install-ChocolateyPackage vcpython27
    Install-ChocolateyPackage python3 --params 'PrependPath=1'
    Install-ChocolateyPackage jdk8
    Install-ChocolateyPackage ruby.portable

    Log 'Installing ASPNet MVC 4'
    Invoke-Executable -filePath "$networkInstallersPath\AspNetMVC4Setup.exe" -argumentList '/Passive', '/NoRestart'

    Log 'Installing Visual Studio 2013 build tools'
    Invoke-Executable -filePath "$networkInstallersPath\BuildTools_Full_2013.exe" -argumentList '/Passive', '/NoRestart'

    Log 'Installing Visual Studio 2015 build tools'
    Invoke-Executable "$networkInstallersPath\BuildTools_Full_2015.exe" -argumentList '/Passive', '/NoRestart'

    Log 'Installing Visual Studio 2017'
    $vs2017InstallerPath = "$networkInstallersPath\VS2017Layout\vs_Enterprise.exe"
    Invoke-Executable -filePath $vs2017InstallerPath

    Log 'Installing Visual Studio 2013 Team Explorer'
    Invoke-Executable -filePath "$networkInstallersPath\vs_teamExplorer.exe" -argumentList '/Passive', '/NoRestart'

    Log 'Installing TFS power tools 2013'
    Invoke-MsiInstaller "`"$networkInstallersPath\Team Foundation Server 2013 Power Tools.msi`""

    Log 'Installing Wix 3.5'
    Invoke-MsiInstaller "`"$networkInstallersPath\Wix35.msi`""

    Log 'Installing VMware SDK'
    Invoke-Executable -filePath "$networkInstallersPath\VMware-vix-1.11.2-591240.exe" -argumentList '/s', '/v/qn'

    Log 'Installing VMware PowerCLI'
    Invoke-Executable -filePath "$networkInstallersPath\VMware-PowerCLI-5.5.0-1295336.exe" -argumentList '/s', '/v/qn'
    
    Log 'Installing Citrix XenServer Tools'
    $citrixVmToolsSetupAtCDPath = 'D:\Setup.exe'
    if (Test-Path $citrixVmToolsSetupAtCDPath) {
        Invoke-Executable -filePath $citrixVmToolsSetupAtCDPath -argumentList '/passive', '/norestart'
    }
    else {
        Invoke-MsiInstaller "`"$networkInstallersPath\managementagentx64.msi`""
    }

    Log 'Adding paths to the path environment variable'
    $pathRegisteryKey = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    $currentPath = (Get-ItemProperty -Path $pathRegisteryKey -Name 'PATH').Path
    $newPath = $currentPath + ';C:\Program Files (x86)\Microsoft Team Foundation Server 2013 Power Tools\'
    Set-ItemProperty -Path $pathRegisteryKey -Name 'PATH' -Value $newPath

    Log 'Setting evironment variables'
    [System.Environment]::SetEnvironmentVariable('UseCommandLineService', 'True', [System.EnvironmentVariableTarget]::Machine)

    Log 'Activating Windows'
    $computer = $Env:ComputerName
    $agentInfoText = Get-Content "$networkInstallersPath\setup_info.json"
    $agentInfo = $agentInfoText | ConvertFrom-Json 
    $activationKey = $agentInfo.ActivationKey
    $service = get-wmiObject -query 'select * from SoftwareLicensingService' -computername $computer
    $service.InstallProductKey($activationKey)
    $service.RefreshLicenseStatus()

    Log 'Downloading TeamCity build agent'
    $tcAgentArchivePath = Join-Path $env:Temp -ChildPath 'buildAgent.zip'
    $buildAgentPath = 'C:\BuildAgent'

    Invoke-RestMethod -Method Get http://tc/update/buildAgent.zip -OutFile $tcAgentArchivePath
    Expand-Archive $tcAgentArchivePath -DestinationPath $buildAgentPath

    Log 'Downloading latest QsBuild artifacts from TeamCity'
    $qsbuildArchivePath = Join-Path $Env:Temp -ChildPath 'qsbuild.zip'
    $qsAgentSpyFolder = "$($Env:Temp)\QsAgentSpy"
    Invoke-RestMethod -Method Get "http://tc/httpAuth/app/rest/builds/count:1,pinned:true,buildType:Trunk_Tools_QsBuild/artifacts/content/QsBuild.zip" -Credential $userCredentials -OutFile $qsbuildArchivePath
    Expand-Archive $qsbuildArchivePath -DestinationPath $qsAgentSpyFolder

    $javaHomePath = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    $jrePath = "$javaHomePath\jre"

    $agentConfiguration = 
    @"
serverUrl=http\://tc
name=$computer
workDir=C\:\\BuildAgent\\work
tempDir=C\:\\BuildAgent\\temp
systemDir=C\:\\BuildAgent\\system
ownPort=9090
env.TEAMCITY_JRE=$jrePath
"@

    Log "Writing agent config file - $agentConfiguration"
    New-Item -Path "$buildAgentPath\conf\" -Name 'buildAgent.properties' -Type 'file' -Value $agentConfiguration -Force

    Log 'Running agent maintenance'
    $qsBuildExePath = Join-Path -Path $qsAgentSpyFolder -ChildPath 'QsBuild.exe'
    Invoke-Executable -filePath $qsBuildExePath -argumentList '/RunnerType=AgentMaintenance', '/Verbosity=Max', '/IsTeamCity=false', '/SolutionRoot=NONE', '/BuildId=0', "/TriggeredBy=$UserName", '/SkipScreenResolution=true', '/SkipAntiVirus=true', '/SkipDisablingAgent=true'
}
catch {
    Log "An exception was raised: $_"
    if (-not $DebugMode) {
        Read-Host 'Press enter to continue'
    }
}
finally {
    Stop-Transcript
}