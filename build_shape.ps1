param([string]$Flow = 'compile',
      [string]$OutputDir = 'outflow_exposure_half',
      [string]$WorkDir = 'work_exposure_half',
      [string]$ProjectName = 'ti60f225_oob',
      [switch]$Help)
Set-Location $PSScriptRoot
$efinity = 'C:/Efinity/2026.1'
$env:EFINITY_HOME = $efinity
$env:PYTHONHOME = "$efinity/python311"
$env:EFXPT_HOME = "$efinity/pt"
$env:EFXPGM_HOME = "$efinity/pgm"
$env:EFXDBG_HOME = "$efinity/debugger"
$env:EFXIPM_HOME = "$efinity/ipm"
$env:EFXSVF_HOME = "$efinity/debugger/svf_player"
$env:EFXSERDESDBG_HOME = "$efinity/debugger/serdes_debug_tool"
$env:EFINITY_USER_DIR_INI = "$env:LOCALAPPDATA/efinity/user_dir.ini"
$env:PATH = "$efinity/bin;$efinity/python311/bin;$efinity/scripts;$env:PATH"
if ($Help) { & "$efinity/python311/bin/python.exe" "$efinity/scripts/efx_run.py" --help; exit }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
Copy-Item -LiteralPath debug_top.v -Destination "$WorkDir/debug_top.v" -Force
& "$efinity/python311/bin/python.exe" "$efinity/scripts/efx_run.py" $ProjectName --prj -f $Flow --output_dir $OutputDir --work_dir $WorkDir
if ($LASTEXITCODE) { throw 'Efinity build failed' }
