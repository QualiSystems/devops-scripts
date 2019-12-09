#Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/QualiSystems/devops-scripts/master/initial_tc_agent_setup.ps1'))

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

function Set-SetupScriptToRunOnBoot([string]$userName, [SecureString]$password) {
    $registryKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    $registryEntry = "SetupTCAgent"
    $passwordInClearText = Convert-ToClearText $password
    $setupScriptName = 'setup_tc_agent.ps1'
    $setupScriptPath = Join-Path $Env:Temp -ChildPath $setupScriptName
    
    $setupScriptContent = (New-Object System.Net.WebClient).DownloadString("https://raw.githubusercontent.com/QualiSystems/devops-scripts/master/$setupScriptName")
    
    New-Item -Force -Path $Env:Temp -Name $setupScriptName -ItemType "file" -Value $setupScriptContent
    $command = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File $setupScriptPath -UserName $userName -Password $passwordInClearText"
    Set-ItemProperty -Path $registryKey -Name $registryEntry -Value $command
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

$domain = 'qualisystems'
$domainUserName = 'buser'
$fullDomainUserName = "$domain\$domainUserName"
$userCredentials = Get-Credential -UserName $fullDomainUserName -Message "Please enter $domainUserName password"

Log 'Setting the time zone'
Set-TimeZone -Id "Israel Standard Time"

Log "Disabling Firewall"
Set-NetFirewallProfile -All -Enabled False -Verbose

Log 'Enabling samba version 1.0'
Install-WindowsFeature -Name "FS-SMB1"

$serverName = Read-Host 'Server Name'

Log 'Joining Domain'
Add-Computer -DomainName "$domain.local" -ComputerName 'localhost' -NewName $serverName -Credential $userCredentials

Log "Adding $domainUserName to administrators group"
Invoke-DscResource -Name Group -ModuleName PSDesiredStateConfiguration -Property @{GroupName = 'Administrators'; ensure = 'present'; MembersToInclude = @($fullDomainUserName) } -Method Set

Log "Disabling server manager at startup"
Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask

Log "Setting auto logon for $domainUserName"
Set-AutoLogon $domain $domainUserName $userCredentials.Password
Set-SetupScriptToRunOnBoot $domainUserName $userCredentials.Password

Log "Restarting"
Restart-Computer -Force