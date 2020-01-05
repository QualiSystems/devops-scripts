param (
    [string]$UserName = 'buser',
    [string]$Password,
    [switch]$DebugMode,
    [string]$CallingScript = 'init.ps1',
    [string]$SetupScriptsFolder = $null
)

$ErrorActionPreference = if ($DebugMode) { 'Inquire' } else { 'Stop' }

function Log([string]$message) {
    Write-Host $message
    if ($DebugMode) {
        Read-Host 'Press enter to continue'
    }
}

function Convert-ToClearText([securestring]$secureString) {
    $passwordBSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($passwordBSTR)    
}

function Set-AutoLogon([string]$userName, [SecureString]$password, [string]$domainName) {
    $autoLogonRegistryKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $passwordInClearText = Convert-ToClearText $password

    Log "Setting AutoAdminLogon - user: $userName domain; $domainName"

    Set-ItemProperty -Path $autoLogonRegistryKey -Name 'AutoAdminLogon' -Value '1'
    Set-ItemProperty -Path $autoLogonRegistryKey -Name 'DefaultUserName' -Value $userName
    Set-ItemProperty -Path $autoLogonRegistryKey -Name 'DefaultPassword' -Value $passwordInClearText
    if (-not [string]::IsNullOrEmpty($domainName)) {
        Set-ItemProperty -Path $autoLogonRegistryKey -Name 'DefaultDomainName' -Value $domainName
    }
}

function New-ScriptFromUrl([string]$url) {
    $guid = (New-Guid).ToString('n')
    $setupScriptName = "TCAgentSetup_$guid.ps1"
    $scriptContent = (New-Object System.Net.WebClient).DownloadString($url)

    return New-Item -Force -Path $SetupScriptsFolder -Name $setupScriptName -ItemType 'file' -Value $scriptContent
}

function Set-ScriptToRunOnBoot([string]$scriptUrl, [string]$scriptArguments) {
    $registryKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    $registryEntry = 'SetupTCAgent'
    $setupScriptPath = New-ScriptFromUrl $scriptUrl
    
    $command = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File $setupScriptPath $scriptArguments"

    Log "Setting script to run on boot: $command"
    Set-ItemProperty -Path $registryKey -Name $registryEntry -Value $command
}

function Restart {
    Log 'Restarting'
    Restart-Computer -Force
    exit 0
}

function Set-SetupScriptToRunOnBoot([string]$userName, [SecureString]$password) {    
    $passwordInClearText = Convert-ToClearText $password    
    $arguments = "-UserName $userName -Password $passwordInClearText"
    if ($DebugMode) {
        $arguments = "$arguments -DebugMode"
    }

    Set-ScriptToRunOnBoot 'https://raw.githubusercontent.com/QualiSystems/devops-scripts/master/setup_tc_agent.ps1' $arguments
}

function New-Credentials([string]$userName, [string]$password) {
    $secureStringPwd = $password | ConvertTo-SecureString -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential -ArgumentList $userName, $secureStringPwd
}

if ([String]::IsNullOrEmpty($SetupScriptsFolder)) {
    $SetupScriptsFolder = Join-Path -Path $Env:ALLUSERSPROFILE -ChildPath 'TcAgentSetup'
    New-Item -ItemType Directory -Path $SetupScriptsFolder -Force
    Write-Host "SetupScriptsFolder created at $SetupScriptsFolder"
}

$domain = 'qualisystems'
$fullDomainUserName = "$domain\$UserName"
$firstRun = [string]::IsNullOrEmpty($Password)

if ($firstRun) {
    $localUserCredentials = Get-Credential -UserName $Env:USERNAME -Message "Please enter $($Env:USERNAME) password"
    $domainUserCredentials = Get-Credential -UserName $fullDomainUserName -Message "Please enter $UserName password"
    $ServerName = Read-Host 'Server Name'

    Log 'Installing Nuget package provider'
    Install-PackageProvider -Name NuGet -Force -Confirm:$False

    @('ComputerManagementDsc',
        'xNetworking',
        'xRemoteDesktopAdmin',
        'DSCR_PowerPlan') | foreach {
        if ((Get-Module $_ -list) -eq $null) { 
            Log "Installing $_"; Install-Module $_ -Force -Confirm:$False
        }
    }

    Log 'Setting the time zone'
    Set-TimeZone -Id 'Israel Standard Time'

    Log 'Disabling Firewall'
    Set-NetFirewallProfile -All -Enabled False -Verbose

    Log 'Enabling samba version 1.0'
    Install-WindowsFeature -Name 'FS-SMB1'

    Log 'Disabling server manager at startup'
    Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask

    Write-Host 'Renaming computer'
    Rename-Computer -NewName $ServerName
        
    $domainUserTextPassword = Convert-ToClearText $domainUserCredentials.Password
    Set-AutoLogon $Env:USERNAME $localUserCredentials.Password
    
    $arguments = "-UserName $UserName -Password $domainUserTextPassword"
    if ($DebugMode) {
        $arguments = "$arguments -DebugMode"
    }

    Set-ScriptToRunOnBoot -scriptUrl "https://raw.githubusercontent.com/QualiSystems/devops-scripts/master/$CallingScript" -scriptArguments $arguments

    return
}

$domainUserCredentials = New-Credentials -userName $fullDomainUserName -password $Password

Log 'Joining Domain'
Add-Computer -ComputerName 'localhost' -DomainName "$domain.local" -DomainCredential $domainUserCredentials -Force

Log "Adding $UserName to administrators group"
Invoke-DscResource -Name Group -ModuleName PSDesiredStateConfiguration -Property @{GroupName = 'Administrators'; ensure = 'present'; MembersToInclude = @($fullDomainUserName) } -Method Set