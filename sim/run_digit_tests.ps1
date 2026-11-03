param(
    [string]$ModelSimDir='D:/ModelSim/modelsim_ase/win32aloem',
    [string]$Python='python'
)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectDir
$testDir=Join-Path $PSScriptRoot 'build/digits'
$libraryDir=Join-Path $testDir 'work'
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
foreach($exeName in @('vlib.exe','vlog.exe','vsim.exe')) {
    if(!(Test-Path -LiteralPath (Join-Path $ModelSimDir $exeName))) { throw "Missing ModelSim executable: $exeName" }
}
& $Python tools/gen_digit_card.py --vectors
if($LASTEXITCODE) { throw 'Card template/vector generation failed' }
& $Python sim/digits/check_video.py --prepare
if($LASTEXITCODE) { throw 'Video oracle generation failed' }
if(!(Test-Path -LiteralPath $libraryDir)) { & "$ModelSimDir/vlib.exe" $libraryDir }
if($LASTEXITCODE) { throw 'ModelSim library creation failed' }
$sources=@(
    'rtl/simple_dual_port_ram.v','rtl/frame_buffer_V3/bank_switch.v',
    'rtl_custom/key_sl.v','rtl_custom/ui_ctrl.v',
    'rtl_custom/line_buffer_3x3_2px.v','rtl_custom/line_buffer_3x3_2px_p.v',
    'rtl_custom/sort9_net.v','rtl_custom/median_switch_2px.v','rtl_custom/gaussian3x3_2px.v',
    'rtl_custom/sobel3x3_2px.v','rtl_custom/nms3x3_2px.v','rtl_custom/edge_link_2px.v',
    'rtl_custom/auto_thr_2px.v','rtl_custom/threshold_compare.v','rtl_custom/edge_algo_2px.v',
    'rtl_custom/despeckle_2px.v','rtl_custom/display_split_2px.v',
    'rtl_custom/digit_capture_2px.v','rtl_custom/digit_match_7p2.v',
    'rtl_custom/digit_outline_2px.v','rtl_custom/digit_result_overlay_2px.v','rtl_custom/digit_result_control.v',
    'sim/tb_ui_menu.sv','sim/tb_bank_switch_freeze.v','sim/tb_display_split_2px.v',
    'sim/tb_digit_match.sv','sim/tb_digit_capture.sv','sim/tb_digit_pipeline.sv','sim/tb_digit_video.sv','sim/tb_digit_live_result.sv','sim/tb_digit_result_control.sv','sim/tb_digit_answer_pixels.sv'
)
& "$ModelSimDir/vlog.exe" -sv -work $libraryDir @sources
if($LASTEXITCODE) { throw 'RTL compilation failed' }
$tests=@('tb_ui_menu','tb_bank_switch_freeze','tb_display_split_2px','tb_digit_match','tb_digit_capture','tb_digit_pipeline','tb_digit_live_result','tb_digit_result_control','tb_digit_answer_pixels','tb_digit_video')
foreach($testName in $tests) {
    $logPath=Join-Path $testDir "$testName.log"
    & "$ModelSimDir/vsim.exe" -c -quiet -lib $libraryDir $testName -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' -l $logPath
    if($LASTEXITCODE) { throw "Simulation failed: $testName ($logPath)" }
    if(!(Select-String -LiteralPath $logPath -Pattern 'PASS' -Quiet)) { throw "No PASS result: $testName" }
}
& $Python sim/digits/check_video.py
if($LASTEXITCODE) { throw 'Independent video pixel verification failed' }
Write-Host 'PASS: all digit recognition, video, UI, and existing frame/display regression checks.'
