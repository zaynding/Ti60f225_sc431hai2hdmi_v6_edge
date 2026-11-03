# Load the latest natural gray-tabletop photos with soft shadows into slots 1/2.
# Uses the same Efinity Python / FTDI setup as load_demo.ps1.
param([string]$EfinityHome = $(if ($env:EFINITY_HOME) { $env:EFINITY_HOME } else { 'C:\Efinity\2026.1' }),
      [string[]]$ExtraArgs = @())
$ErrorActionPreference = 'Stop'
$loaderArgs = @('--raw1', (Join-Path $PSScriptRoot 'demo_raw_natural_v3/frame1.raw'),
                '--raw2', (Join-Path $PSScriptRoot 'demo_raw_natural_v3/frame2.raw')) + $ExtraArgs
$previousPythonHome = $env:PYTHONHOME
try {
    & (Join-Path $PSScriptRoot 'load_demo.ps1') -EfinityHome $EfinityHome -ExtraArgs $loaderArgs
} finally {
    $env:PYTHONHOME = $previousPythonHome
}
