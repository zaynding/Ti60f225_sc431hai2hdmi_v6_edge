# Preloads the two demo pictures (saved frame 1 / 2) over JTAG after the bitstream has been downloaded.
# Close the Efinity Programmer first (only one program can own the FTDI channel).
param([string]$EfinityHome = $(if ($env:EFINITY_HOME) { $env:EFINITY_HOME } else { 'C:\Efinity\2026.1' }),
      [string[]]$ExtraArgs = @())
Set-Location $PSScriptRoot
$py = Join-Path $EfinityHome 'python311\bin\python.exe'
if (-not (Test-Path $py)) { throw "Efinity python not found: $py  (pass -EfinityHome <path>)" }
$env:PYTHONHOME = Join-Path $EfinityHome 'python311'
& $py tools\jtag_load_demo.py @ExtraArgs
if ($LASTEXITCODE) { throw 'demo load failed' }
