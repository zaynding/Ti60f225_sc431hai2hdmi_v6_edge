#!/usr/bin/env python3
"""Rebuild the RGB image produced by tb_debayer_demo and compare it with the source photo panel.
usage: check_debayer_out.py debayer_out.txt frameN_preview.png [dump.png]
The display wiring is  HDMI R = debayer 'b' field, HDMI B = debayer 'r' field (see ti60f225_oob_top.v)."""
import sys
import cv2
import numpy as np

W, H, CROP_X0, CROP_W = 1920, 1080, 480, 960
lines, cur = [], None
for ln in open(sys.argv[1]):
    ln = ln.strip()
    if ln == "L":
        cur = []
        lines.append(cur)
    elif ln:
        cur.append(int(ln, 16))
print("lines captured:", len(lines), "pairs/line:", len(lines[0]) if lines else 0)
n = min(len(l) for l in lines)
v = np.array([l[:n] for l in lines], dtype=np.uint64)      # (lines, pairs)
def field(shift): return ((v >> np.uint64(shift)) & np.uint64(0xFF)).astype(np.uint8)
# datax2 = {b_hi,g_hi,r_hi, b_lo,g_lo,r_lo}
r_lo, g_lo, b_lo = field(0), field(8), field(16)
r_hi, g_hi, b_hi = field(24), field(32), field(40)
def interleave(lo, hi):
    out = np.empty((lo.shape[0], lo.shape[1] * 2), np.uint8)
    out[:, 0::2] = lo; out[:, 1::2] = hi
    return out
rc, gc, bc = interleave(r_lo, r_hi), interleave(g_lo, g_hi), interleave(b_lo, b_hi)
disp_bgr = np.dstack([rc, gc, bc])          # display B = code r, G = g, R = code b  -> BGR order = (r, g, b)
if len(sys.argv) > 3:
    cv2.imwrite(sys.argv[3], disp_bgr[:, CROP_X0:CROP_X0 + CROP_W])
ref = cv2.imread(sys.argv[2]).astype(np.float32)           # 1080 x 960 panel, BGR
best = None
for dy in range(-3, 4):
    for dx in range(-3, 4):
        y0, y1 = max(0, dy) + 8, 1080 - 8 - max(0, -dy)
        got = disp_bgr[:, CROP_X0 + dx:CROP_X0 + dx + CROP_W].astype(np.float32)
        if got.shape[1] != CROP_W: continue
        # output line k corresponds to source line k+dy
        a = got[y0 - dy:y1 - dy] if dy else got[y0:y1]
        b = ref[y0:y1]
        a = a[:b.shape[0]]
        e = np.abs(a - b)[:, 8:-8].mean(axis=(0, 1))
        if best is None or e.sum() < best[0]:
            best = (e.sum(), dy, dx, e)
print("best shift dy=%d dx=%d  mean abs err (B,G,R) = %s" % (best[1], best[2], np.round(best[3], 2)))
# swapped-channel hypothesis, for diagnosis
sw = disp_bgr[..., ::-1]
