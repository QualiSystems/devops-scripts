<#
.SYNOPSIS
    Creates an on premise layout of visual studio for use in TeamCity agents
.DESCRIPTION
    Usage:
    https://docs.microsoft.com/en-us/visualstudio/install/create-a-network-installation-of-visual-studio?view=vs-2017
.EXAMPLE
    PS C:\> .\New-OfflineVS2017AgentInstallation.ps1 -VsEnterpriseExecutablePath 'D:\Downloads\vs_enterprise__1642780969.1551798146.exe' -LayoutDestinationPath 'D:\Vs2017Layout'
    Creates a new offline layout that contains only the required workloads for TeamCity agents at 'D:\Vs2017Layout'
#>
[CmdletBinding()]
param (
    [Parameter()]
    [string]$VsEnterpriseExecutablePath,
    [Parameter()]
    [string]$LayoutDestinationPath
)

Start-Process -FilePath $VsEnterpriseExecutablePath -NoNewWindow -PassThru -ArgumentList `
                    '--layout D:\VSLayout',
                    '--lang en-US'
                    '--add Microsoft.VisualStudio.Workload.ManagedDesktop',
                    '--add Microsoft.VisualStudio.Workload.NativeDesktop',
                    '--add Microsoft.VisualStudio.Workload.Universal',
                    '--add Microsoft.VisualStudio.Workload.NetWeb',
                    '--add Microsoft.VisualStudio.Workload.Node',
                    '--add Microsoft.VisualStudio.Workload.VisualStudioExtension',
                    '--add Microsoft.VisualStudio.Workload.NetCoreTools',
                    '--add microsoft.net.componentgroup.targetingpacks.common',
                    '--add microsoft.visualstudio.component.entityframework',
                    '--add microsoft.visualstudio.component.intellitrace.frontend',
                    '--add microsoft.visualstudio.component.debugger.justintime',
                    '--add microsoft.visualstudio.component.liveunittesting',
                    '--add microsoft.net.componentgroup.4.7.developertools',
                    '--add microsoft.net.componentgroup.4.7.1.developertools',
                    '--add microsoft.visualstudio.component.wcf.tooling',
                    '--add microsoft.visualstudio.componentgroup.architecturetools.managed',
                    '--add microsoft.visualstudio.component.vc.diagnostictools',
                    '--add microsoft.visualstudio.component.vc.cmake.project',
                    '--add microsoft.visualstudio.component.vc.atlmfc',
                    '--add microsoft.visualstudio.component.vc.cli.support',
                    '--add microsoft.visualstudio.component.windows10sdk.17134',
                    '--add microsoft.visualstudio.component.windows10sdk.15063.desktop',
                    '--add microsoft.visualstudio.component.cloudexplorer',
                    '--add microsoft.visualstudio.component.webdeploy',
                    '--add microsoft.netcore.componentgroup.web',
                    '--add microsoft.visualstudio.component.git',
                    '--add microsoft.visualstudio.component.typescript.2.3',
                    '--add microsoft.visualstudio.component.typescript.2.2',
                    '--add microsoft.visualstudio.component.typescript.2.8'