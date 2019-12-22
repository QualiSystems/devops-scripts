Set-ExecutionPolicy Bypass -Scope Process -Force;

# Reroute TEMP to a local location
New-Item $env:ALLUSERSPROFILE\choco-cache -ItemType Directory -Force
$env:TEMP = "$env:ALLUSERSPROFILE\choco-cache"

$chocolateyNetworkPath = "\\qsnas1\Storage\devops\chocolatey\chocolatey.0.10.15.nupkg"
$localChocolateyPackageFilePath = Join-Path $env:TEMP 'chocolatey.nupkg'
$ChocoInstallPath = "$($env:SystemDrive)\ProgramData\Chocolatey\bin"
$env:ChocolateyInstall = "$($env:SystemDrive)\ProgramData\Chocolatey"
$env:Path += ";$ChocoInstallPath"
$DebugPreference = 'Continue';

function Install-ChocolateyFromPackage {
    param ([string]$chocolateyPackageFilePath = '')

    if ($chocolateyPackageFilePath -eq $null -or $chocolateyPackageFilePath -eq '') {
        throw "You must specify a local package to run the local install."
    }

    if (!(Test-Path($chocolateyPackageFilePath))) {
        throw "No file exists at $chocolateyPackageFilePath"
    }

    $chocTempDir = Join-Path $env:TEMP "chocolatey"
    $tempDir = Join-Path $chocTempDir "chocInstall"
    if (![System.IO.Directory]::Exists($tempDir)) { [System.IO.Directory]::CreateDirectory($tempDir) }
    $file = Join-Path $tempDir "chocolatey.zip"
    Copy-Item $chocolateyPackageFilePath $file -Force

    # unzip the package
    Write-Output "Extracting $file to $tempDir..."
    Expand-Archive -Path "$file" -DestinationPath "$tempDir" -Force

    # Call Chocolatey install
    Write-Output 'Installing chocolatey on this machine'
    $toolsFolder = Join-Path $tempDir "tools"
    $chocInstallPS1 = Join-Path $toolsFolder "chocolateyInstall.ps1"

    & $chocInstallPS1

    Write-Output 'Ensuring chocolatey commands are on the path'
    $chocInstallVariableName = 'ChocolateyInstall'
    $chocoPath = [Environment]::GetEnvironmentVariable($chocInstallVariableName)
    if ($chocoPath -eq $null -or $chocoPath -eq '') {
        $chocoPath = 'C:\ProgramData\Chocolatey'
    }

    $chocoExePath = Join-Path $chocoPath 'bin'

    if ($($env:Path).ToLower().Contains($($chocoExePath).ToLower()) -eq $false) {
        $env:Path = [Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine);
    }

    Write-Output 'Ensuring chocolatey.nupkg is in the lib folder'
    $chocoPkgDir = Join-Path $chocoPath 'lib\chocolatey'
    $nupkg = Join-Path $chocoPkgDir 'chocolatey.nupkg'
    if (!(Test-Path $nupkg)) {
        Write-Output 'Copying chocolatey.nupkg is in the lib folder'
        if (![System.IO.Directory]::Exists($chocoPkgDir)) { [System.IO.Directory]::CreateDirectory($chocoPkgDir); }
        Copy-Item "$file" "$nupkg" -Force -ErrorAction SilentlyContinue
    }
}

# Idempotence - do not install Chocolatey if it is already installed
if (!(Test-Path $ChocoInstallPath)) {
    # download the package to the local path
    if (!(Test-Path $localChocolateyPackageFilePath)) {
        Copy-Item $chocolateyNetworkPath $localChocolateyPackageFilePath
    }

    # Install Chocolatey
    Install-ChocolateyFromPackage $localChocolateyPackageFilePath

    choco source remove --name="'chocolatey'"
    choco source add --name="'internal_server'" --source="'\\qsnas1\Storage\devops\chocolatey'" --priority="'1'"
}