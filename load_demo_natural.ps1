# Descriptive entrypoint for the current gray-tabletop, soft-shadow demo photos.
param([string]$EfinityHome = $(if ($env:EFINITY_HOME) { $env:EFINITY_HOME } else { 'C:\Efinity\2026.1' }),
      [string[]]$ExtraArgs = @())
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'load_demo_shadowfree.ps1') -EfinityHome $EfinityHome -ExtraArgs $ExtraArgs
