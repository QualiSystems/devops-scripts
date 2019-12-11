#Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/QualiSystems/devops-scripts/master/initial_tc_agent_setup.ps1'))

param (
    [string]$UserName = 'buser',
    [string]$Password,
    [string]$ServerName
)

function Log([string]$message) {    
    Write-Host $message
}

function Convert-ToClearText([securestring]$secureString) {
    $passwordBSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($passwordBSTR)    
}

function Set-AutoLogon([string]$domainName, [string]$userName, [SecureString]$password) {
    $autoLogonRegistryKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    $passwordInClearText = Convert-ToClearText $password

    Set-ItemProperty -Path $autoLogonRegistryKey -Name "AutoAdminLogon" -Value "1"	
    Set-ItemProperty -Path $autoLogonRegistryKey -Name "DefaultDomainName" -Value $domainName	
    Set-ItemProperty -Path $autoLogonRegistryKey -Name "DefaultUserName" -Value $userName
    Set-ItemProperty -Path $autoLogonRegistryKey -Name "DefaultPassword" -Value $passwordInClearText
}

function Set-ScriptToRunOnBoot([string]$scriptContent, [string]$scriptArguments) {
    $registryKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    $registryEntry = "SetupTCAgent"
    $guid = (New-Guid).ToString('n')
    $setupScriptName = "TCAgentSetup_$guid.ps1"
    $setupScriptPath = Join-Path $Env:Temp -ChildPath $setupScriptName
    
    New-Item -Force -Path $Env:Temp -Name $setupScriptName -ItemType "file" -Value $setupScriptContent
    $command = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File '$setupScriptPath' $scriptArguments"
    Set-ItemProperty -Path $registryKey -Name $registryEntry -Value $command
}

function Restart {
    Log "Restarting"
    Restart-Computer -Force    
}

function Set-SetupScriptToRunOnBoot([string]$userName, [SecureString]$password) {    
    $passwordInClearText = Convert-ToClearText $password
    $setupScriptName = 'setup_tc_agent.ps1'    
    $setupScriptContent = (New-Object System.Net.WebClient).DownloadString("https://raw.githubusercontent.com/QualiSystems/devops-scripts/master/$setupScriptName")    

    Set-ScriptToRunOnBoot $setupScriptContent "-UserName '$userName' -Password '$passwordInClearText'"
}

function New-Credentials([string]$userName, [string]$password) {
    $secureStringPwd = $password | ConvertTo-SecureString -AsPlainText -Force 
    return New-Object System.Management.Automation.PSCredential -ArgumentList $userName, $secureStringPwd
}

$domain = 'qualisystems'
$fullDomainUserName = "$domain\$UserName"

if ([string]::IsNullOrEmpty($Password)) {
    $userCredentials = Get-Credential -UserName $fullDomainUserName -Message "Please enter $UserName password"
    $firstRun = $true
}
else {
    $userCredentials = New-Credentials -userName $UserName -password $Password
    $firstRun = $false
}

if ([string]::IsNullOrEmpty($ServerName)) {
    $ServerName = Read-Host 'Server Name'
}

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
Set-TimeZone -Id "Israel Standard Time"

Log "Disabling Firewall"
Set-NetFirewallProfile -All -Enabled False -Verbose

Log 'Enabling samba version 1.0'
Install-WindowsFeature -Name "FS-SMB1"

Log "Disabling server manager at startup"
Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask

if ($firstRun) {
    Write-Host 'Renaming computer'
    Rename-Computer -NewName $ServerName
    $content = (New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/QualiSystems/devops-scripts/master/initial_tc_agent_setup.ps1')
    $clearTextPassword = Convert-ToClearText $userCredentials.Password
    Set-AutoLogon $domain $UserName $userCredentials.Password
    Set-ScriptToRunOnBoot -scriptContent $content -scriptArguments "-User '$UserName' -Password '$clearTextPassword' -ServerName '$ServerName'"
    Restart
}

Log 'Joining Domain'
Add-Computer -ComputerName 'localhost' -DomainName "$domain.local" -DomainCredential $userCredentials -Force

Log "Adding $UserName to administrators group"
Invoke-DscResource -Name Group -ModuleName PSDesiredStateConfiguration -Property @{GroupName = 'Administrators'; ensure = 'present'; MembersToInclude = @($fullDomainUserName) } -Method Set

Log "Setting auto logon for $UserName"
Set-AutoLogon $domain $UserName $userCredentials.Password
Set-SetupScriptToRunOnBoot $UserName $userCredentials.Password

Restart