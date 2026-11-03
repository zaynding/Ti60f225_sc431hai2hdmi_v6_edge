"""Run with: python -m unittest discover -s sim/loader -p test_jtag_host.py -v"""
import contextlib
import importlib.util
import io
from pathlib import Path
import struct
import unittest
from unittest.mock import patch, PropertyMock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('loader', ROOT / 'tools/jtag_load_demo.py')
loader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(loader)


class HostTests(unittest.TestCase):
    def test_connect_initializes_gpio_with_actual_installed_pyftdi(self):
        # Exercise Jtag.__init__, including the Efinity-specific configure
        # implementation. Replace only hardware access, keeping FTDI constants.
        from pyftdi.ftdi import Ftdi
        with patch.object(Ftdi, 'open_mpsse_from_url') as opened, \
             patch.object(Ftdi, 'write_data') as sent, \
             patch.object(Ftdi, 'is_connected', new_callable=PropertyMock, return_value=True), \
             patch.object(Ftdi, 'close'):
            j = loader.Jtag('ftdi://test/2', 12e6)
            opened.assert_called_once()
            # Preserve upstream's default: GPIO low, TCK/TDI/TMS as outputs.
            sent.assert_any_call(bytearray((Ftdi.SET_BITS_LOW, 0, 0x0B)))
            j.close()

    def test_done_scan_flushes_actual_pyftdi_buffer_and_leaves_update(self):
        # Use the installed pyftdi TAP/MPSSE implementation with only USB replaced.
        # Previously the final DONE remained in _write_buff until the next read.
        from pyftdi.bits import BitSequence
        from pyftdi.jtag import JtagEngine

        class UsbRecorder:
            is_connected = True
            def __init__(self):
                self.writes = []
            def write_data(self, data):
                self.writes.append(bytes(data))

        j = loader.Jtag.__new__(loader.Jtag)
        j.BitSequence = BitSequence
        j.eng = JtagEngine()
        usb = UsbRecorder()
        j.eng._ctrl._ftdi = usb
        j.ir = loader.IR_USER1
        j.write_scan(loader.scan_bytes(loader.CMD_DONE, 3))
        self.assertTrue(usb.writes, 'DONE was buffered instead of sent to USB')
        self.assertFalse(j.eng._ctrl._write_buff)
        self.assertEqual(str(j.eng._sm.state()), 'run_test_idle')

    def test_main_waits_for_done_to_cross_clock_domains(self):
        class Board:
            def __init__(self, *_):
                self.held = False
                self.acked = 0
                self.done_reads = None
                self.slots = 0
            def idcode(self):
                return 0x10660A79
            def write_scan(self, data):
                h, _ = struct.unpack('<II', data[:8])
                cmd, n = h & 255, h >> 8
                if cmd == loader.CMD_HOLD:
                    self.held = True
                elif cmd == loader.CMD_WRITE:
                    self.acked += n
                elif cmd == loader.CMD_DONE:
                    self.done_reads = 0
            def status(self):
                if self.done_reads is not None:
                    self.done_reads += 1
                    if self.done_reads >= 3:
                        self.held = False
                        self.slots = 3
                return dict(grant=self.held, hold=self.held, slots=self.slots, acked=self.acked,
                            busy=False, overrun=False, count_err=False, bresp_err=False,
                            watchdog=False, magic=0xA55A)
            def close(self):
                pass

        with patch.object(loader, 'Jtag', Board), patch.object(loader.time, 'sleep'), \
             patch.object(loader.sys, 'argv', ['loader', '--url', 'ftdi://test/2']), \
             contextlib.redirect_stdout(io.StringIO()) as output:
            loader.main()
        self.assertIn('OK: saved frame 1', output.getvalue())


if __name__ == '__main__':
    unittest.main()
