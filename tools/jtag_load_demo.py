#!/usr/bin/env python3
"""Load the two demo pictures into saved-frame slots 1 and 2 of the running Ti60 design over JTAG.

Run it AFTER the bitstream is downloaded (close the Efinity Programmer first - only one program can own the
FTDI JTAG channel).  It talks to rtl_custom/jtag_demo_loader.v through the USER1 instruction; the FPGA freezes the
camera frame writer, takes over the DDR write channel, writes demo_raw/frame1.raw + frame2.raw to the DDR regions
of slot 1 / slot 2, gives the channel back, marks the slots valid and switches the display to slot 1.

    python tools/jtag_load_demo.py                 (needs pyftdi: Efinity's own python311 already has it)
    python tools/jtag_load_demo.py --url ftdi://0x0403:0x6010/2 --freq 15e6
    python tools/jtag_load_demo.py --status        (only print the loader status)

Without the board:  --emit-test FILE  writes the exact DR byte stream of one WRITE scan (used by the ModelSim test bench).
"""
import argparse
import inspect
import os
import struct
import sys
import time
from types import SimpleNamespace

SAVED_BASE = 0x0200_0000                 # bank_switch.v: SAVED_BASE_ADDR
FRAME_LEN = 960 * 1080 * 32 // 8 + 0x200  # bank_switch.v: FRAME_LEN (slot pitch)
FRAME_BYTES = 1920 * 1080                # 8-bit Bayer RAW, one frame
WORD = 16                                # DDR AXI word = 128 bit

CMD_STATUS, CMD_HOLD, CMD_WRITE, CMD_DONE, CMD_CLEAR = 0, 1, 2, 3, 4
IR_USER1 = 0b01000                       # Titanium TAP, 5-bit IR (pgm/efx_pgm/device_utils.py EFX_TI_INSTR)
IR_IDCODE = 0b00011
CHUNK_WORDS = 2048                       # 32 KiB per DR scan (one MPSSE command is limited to 64 KiB)

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)


def slot_addr(i):
    return SAVED_BASE + i * FRAME_LEN


def header(cmd, n, addr):
    """64-bit scan header, LSB first: cmd[7:0] n[31:8] addr[63:32]  (little-endian bytes = LSB-first bit order)"""
    return struct.pack("<II", (cmd & 0xFF) | ((n & 0xFFFFFF) << 8), addr & 0xFFFFFFFF)


def scan_bytes(cmd, n=0, addr=0, payload=b""):
    assert len(payload) == n * WORD if cmd == CMD_WRITE else True
    return header(cmd, n, addr) + payload


def decode_status(st):
    return {
        "grant": bool(st & 1), "hold": bool(st >> 1 & 1), "overrun": bool(st >> 2 & 1),
        "count_err": bool(st >> 3 & 1), "bresp_err": bool(st >> 4 & 1), "busy": bool(st >> 5 & 1),
        "watchdog": bool(st >> 6 & 1), "slots": st >> 8 & 0xF, "acked": st >> 16 & 0xFFFFFFFF,
        "magic": st >> 48 & 0xFFFF,
    }


class Jtag:
    def __init__(self, url, freq):
        try:
            from pyftdi.bits import BitSequence
            from pyftdi.jtag import JtagEngine
        except ImportError:
            sys.exit("pyftdi is missing.  Use Efinity's python:  <efinity>/python311/bin/python.exe tools/jtag_load_demo.py"
                     "   (or: pip install pyftdi)")
        self.BitSequence = BitSequence
        self.eng = JtagEngine(trst=False, frequency=freq)
        # Efinity's pyftdi adds init=None but dereferences init.val/init.dir
        # before checking for None. Supply its empty/default GPIO initializer;
        # upstream pyftdi only accepts url, so leave that call unchanged.
        if "init" in inspect.signature(self.eng.configure).parameters:
            self.eng.configure(url, init=SimpleNamespace(val="", dir=""))
        else:
            self.eng.configure(url)
        self.eng.reset()
        self.ir = None

    def close(self):
        self.eng.close()

    def set_ir(self, code):
        if self.ir != code:
            self.eng.write_ir(self.BitSequence(code, length=5))
            self.ir = code

    def idcode(self):
        self.set_ir(IR_IDCODE)
        v = self.eng.read_dr(32)
        self.ir = None
        return int(v)

    def write_scan(self, data):
        """Shift `data` (bytes, byte 0 first, LSB first) into the USER1 DR."""
        self.set_ir(IR_USER1)
        self.eng.write_dr(self.BitSequence(bytes_=data))
        # write_dr only queues the transition to UPDATE_DR. Leave UPDATE so
        # the RTL samples it, then send the buffered MPSSE commands now.
        # Otherwise DONE may not reach the FPGA until the next status read.
        self.eng.go_idle()
        self.eng.sync()

    def status(self):
        """64-bit scan with a STATUS header; the status word is shifted out meanwhile."""
        self.set_ir(IR_USER1)
        out = self.BitSequence(bytes_=header(CMD_STATUS, 0, 0))
        self.eng.change_state("shift_dr")
        rd = self.eng.shift_register(out)
        self.eng.change_state("update_dr")
        self.eng.go_idle()
        self.eng.sync()
        v = 0
        for i, b in enumerate(bytes(rd.tobytes(msby=True))):    # first bit received = bit 0 of byte 0
            v |= b << (8 * i)
        return decode_status(v)


def autodetect_url(port):
    from pyftdi.ftdi import Ftdi
    devs = Ftdi.list_devices()
    if not devs:
        sys.exit("no FTDI device found (is the board powered / USB cable plugged in / Efinity Programmer closed?)")
    desc = devs[0][0]
    return "ftdi://0x%04x:0x%04x/%d" % (desc.vid, desc.pid, port)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", help="pyftdi URL; default: first FTDI device, interface --port")
    ap.add_argument("--port", type=int, default=2, help="FTDI interface carrying JTAG (Ti60F225 kit: 2 = channel B)")
    ap.add_argument("--freq", type=float, default=12e6, help="TCK frequency (default 12 MHz)")
    ap.add_argument("--raw1", default=os.path.join(root, "demo_raw", "frame1.raw"))
    ap.add_argument("--raw2", default=os.path.join(root, "demo_raw", "frame2.raw"))
    ap.add_argument("--status", action="store_true", help="only print the loader status")
    ap.add_argument("--emit-test", metavar="FILE", help="write one WRITE scan (3 words of raw1 -> slot 1) and exit")
    a = ap.parse_args()

    if a.emit_test:
        data = open(a.raw1, "rb").read(3 * WORD)
        open(a.emit_test, "wb").write(scan_bytes(CMD_WRITE, 3, slot_addr(0), data))
        print("wrote", a.emit_test)
        return

    url = a.url or autodetect_url(a.port)
    print("JTAG:", url, "@ %.1f MHz" % (a.freq / 1e6))
    j = Jtag(url, a.freq)
    held = False
    try:
        idc = j.idcode()
        print("IDCODE: 0x%08x%s" % (idc, "" if (idc & 0xFFF) in (0xA79, 0xEF3) else "   (not an Efinix device?)"))
        st = j.status()
        if st["magic"] != 0xA55A:
            sys.exit("loader not found in this bitstream (status magic 0x%04x).  Program the new bitstream first." % st["magic"])
        print("loader status:", st)
        if a.status:
            return

        frames = []
        for p in (a.raw1, a.raw2):
            with open(p, "rb") as raw_file:
                d = raw_file.read()
            if len(d) != FRAME_BYTES:
                sys.exit("%s: expected %d bytes, got %d" % (p, FRAME_BYTES, len(d)))
            frames.append(d)

        t0 = time.time()
        held = True
        j.write_scan(scan_bytes(CMD_HOLD))
        print("camera writes frozen, waiting for the DDR write channel ...")
        for _ in range(400):
            st = j.status()
            if st["grant"]:
                break
            time.sleep(0.02)
        else:
            sys.exit("no grant from the FPGA (status %s)" % st)

        total = 0
        for i, d in enumerate(frames):
            base = slot_addr(i)
            words = len(d) // WORD
            print("slot %d: %d bytes -> DDR 0x%08x" % (i + 1, len(d), base))
            w = 0
            while w < words:
                n = min(CHUNK_WORDS, words - w)
                j.write_scan(scan_bytes(CMD_WRITE, n, base + w * WORD, d[w * WORD:(w + n) * WORD]))
                w += n
                total += n
                if (w // CHUNK_WORDS) % 16 == 0 or w == words:
                    st = j.status()
                    if st["overrun"] or st["count_err"] or st["bresp_err"]:
                        sys.exit("loader error: %s" % st)
                    sys.stdout.write("\r  %3d %%" % (100 * w // words))
                    sys.stdout.flush()
            print()

        for _ in range(100):
            st = j.status()
            if st["acked"] == total and not st["busy"]:
                break
            time.sleep(0.01)
        if st["acked"] != total or st["overrun"] or st["count_err"] or st["bresp_err"]:
            sys.exit("write verification failed: %s (expected %d words)" % (st, total))
        j.write_scan(scan_bytes(CMD_DONE, 0b0011))
        # Status is synchronised through two TCK registers, and slot marking
        # follows bus release in core_clk. A single scan can still report the
        # state before DONE; wait for both the valid bits and released bus.
        deadline = time.monotonic() + 2.0
        while True:
            st = j.status()
            if (st["magic"] != 0xA55A or st["overrun"] or st["count_err"]
                    or st["bresp_err"] or st["watchdog"]):
                sys.exit("loader error after DONE: %s" % st)
            if (st["slots"] & 3 == 3 and not st["grant"] and not st["hold"]
                    and not st["busy"] and st["acked"] == total):
                break
            if time.monotonic() >= deadline:
                sys.exit("DONE did not release the bus / mark slots valid: %s" % st)
            time.sleep(0.01)
        held = False
        print("done in %.1f s, loader status:" % (time.time() - t0), st)
        print("OK: saved frame 1 = screw, saved frame 2 = caliper.  Display switches to frame 1.")
    finally:
        if held:                                    # error path: give the DDR bus / camera writer back
            try:
                j.write_scan(scan_bytes(CMD_DONE, 0))
            except Exception:
                pass
        j.close()


if __name__ == "__main__":
    main()
