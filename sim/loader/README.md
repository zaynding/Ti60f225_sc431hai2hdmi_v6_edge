# sim/loader

ModelSim (vlog/vsim from `D:\ModelSim\modelsim_ase\win32aloem`), run from this directory:

```
python ../../tools/gen_demo_raw.py --streams                 # also writes the raster-order *.stream files
cp ../../demo_raw/frame1.stream .                            # tb_debayer_demo reads frame1.stream
vlib work && vlog -sv -work work ../../rtl/debayer/*.v ../../rtl_custom/jtag_demo_loader.v tb_*.sv
vsim -c -lib work tb_debayer_demo -do "run -all; quit -f"    # -> debayer_out.txt
python ../../tools/check_debayer_out.py debayer_out.txt ../../demo_raw/frame1_preview.png out.png
vsim -c -lib work tb_jtag_demo_loader -do "run -all; quit -f"                       # PASS: jtag_demo_loader test passed
python ../../tools/jtag_load_demo.py --emit-test scan_write.bin; cp ../../demo_raw/frame1.raw .
vsim -c -lib work tb_jtag_file_scan -do "run -all; quit -f"                         # PASS: script scan bytes accepted ...
```

`../tb_bank_switch_freeze.v` (compile together with `rtl/frame_buffer_V3/bank_switch.v`) covers the preload marking.

## Saved-slot addressing and host completion regressions

Run from the project root:

```powershell
python -m unittest discover -s sim/loader -p test_jtag_host.py -v
./sim/loader/run_frame_buffer_slots.ps1
```

The host tests use the installed pyftdi TAP/MPSSE implementation with USB replaced by a recorder to check that DONE is flushed and leaves UPDATE_DR, and a simulated board to reproduce delayed DONE status (`acked=259200`, `grant/hold=True`, `slots=0`). The host must poll until the slots are valid and the bus has been released.

The connection test also exercises the real installed `JtagEngine.configure` with hardware calls mocked. Efinity's fork accepts `init=None` but accesses `init.val` before checking for None. The loader supplies an empty GPIO initializer only when this parameter is supported, retaining the default low GPIO values and JTAG output directions. All three tests pass under both Anaconda and Efinity Python; no vendor library files are modified.

The RTL test instantiates the actual `frame_buffer -> ddr_buffer -> bank_switch` hierarchy with the same geometry as `checker0`, and checks every AXI read address for four complete 2,073,600-byte RAW frames, including 4K boundaries and final bursts. Before the parameter-forwarding fix it reads slot 2 from `0x027E9200` instead of the loader's `0x023F4A00`; the standalone bank-switch test cannot expose this hierarchy error. The test supplies frame length/start signals and an AXI responder; it does not simulate physical DDR or HDMI pixels.
