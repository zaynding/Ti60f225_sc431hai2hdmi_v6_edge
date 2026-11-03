$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location $root
$lib = Join-Path $root 'work_frame_slots'
if (-not (Test-Path -LiteralPath $lib)) { & vlib $lib }
$sources = @('frame_buffer', 'ddr_buffer', 'bank_switch', 'ddr_rd_buffer', 'ddr_wr_buffer',
    'DC_FIFO', 'rst_n_piple', 'vid_rx_align_v1', 'frame_info_det', 'ser2par_v1',
    'par2ser_parse', 'vid_par2ser', 'data_tx') |
    ForEach-Object { Join-Path $root "rtl/frame_buffer_V3/$_.v" }
& vlog -sv -work $lib @sources (Join-Path $PSScriptRoot 'tb_frame_buffer_slots.sv')
if ($LASTEXITCODE) { throw 'ModelSim compile failed' }
$simOutput = & vsim -c -onfinish stop -l (Join-Path $lib 'slots.transcript.log') -lib $lib tb_frame_buffer_slots -do 'run -all; quit -f'
$simOutput
if ($LASTEXITCODE -or -not ($simOutput -match 'PASS: frame_buffer hierarchy')) {
    throw 'Frame-buffer slot regression failed (PASS marker required)'
}
