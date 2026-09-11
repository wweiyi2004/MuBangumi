param([Parameter(Mandatory = $true)][string]$ArchivePath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows_package_safety.ps1')
Assert-WindowsPackageArchive $ArchivePath
Write-Output "Windows package contains runtime files only: $ArchivePath"
