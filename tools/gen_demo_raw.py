#!/usr/bin/env python3
"""Turn the two demo photos into DDR "RAW frames" that the board's own pipeline can consume.

The FPGA stores camera frames as 1920x1080 8-bit Bayer RAW, 16 pixels per 128-bit DDR word, and the
read side streams every word MSB-byte first.  The debayer expects (after its own white-balance gain):

    even frame line :  x even = G , x odd = B
    odd  frame line :  x even = R , x odd = G          (R/B gains are 2.0 / 2.02, G is 1.0)

So this script
  1. fits each photo into the centre 960x1080 window that the display shows (screw: zoomed crop,
     caliper: whole width), replicating the border outward so no artificial edges appear,
  2. divides R and B by the sensor white-balance gains so the displayed colours are right again,
  3. mosaics the result, and
  4. reorders the bytes to the DDR layout (byte-reversed inside every 16-byte word).

Outputs (in --out): frame1.raw / frame2.raw (2,073,600 bytes each, DDR byte order),
frame1_preview.png / frame2_preview.png (what the 960x1080 panel should look like), and
frameN.stream (same mosaic in raster order, only with --streams, used by the simulation).
"""
import argparse
import os
import sys

import cv2
import numpy as np

W, H = 1920, 1080
CROP_X0, CROP_W = 480, 960          # displayed window (display_split_2px: CROP_X_PAIR=240, CROP_PAIRS=480)
GAIN_R, GAIN_G, GAIN_B = 512 / 256.0, 256 / 256.0, 517 / 256.0   # top-level fixed WB gains (Q8.8)


def load(path):
    img = cv2.imread(path, cv2.IMREAD_COLOR)
    if img is None:
        sys.exit("cannot read image: " + path)
    return img


def resize(img, w, h):
    interp = cv2.INTER_AREA if w < img.shape[1] else cv2.INTER_CUBIC
    return cv2.resize(img, (w, h), interpolation=interp)


def fit_cover(img, cx):
    """Full-height window of aspect CROP_W:H centred on column cx, scaled to CROP_W x H."""
    ih, iw = img.shape[:2]
    ww = int(round(ih * CROP_W / H))
    x0 = int(np.clip(cx - ww // 2, 0, max(iw - ww, 0)))
    return resize(img[:, x0:x0 + ww], CROP_W, H)


def fit_contain(img):
    """Whole image scaled to the window width, centred vertically, border rows replicated."""
    ih, iw = img.shape[:2]
    nh = int(round(ih * CROP_W / iw))
    small = resize(img, CROP_W, nh)
    top = (H - nh) // 2
    return np.pad(small, ((top, H - nh - top), (0, 0), (0, 0)), mode="edge")


def build_frame(panel_bgr):
    """960x1080 panel -> 1920x1080 frame by replicating the outer columns."""
    return np.pad(panel_bgr, ((0, 0), (CROP_X0, W - CROP_X0 - CROP_W), (0, 0)), mode="edge")


def mosaic(frame_bgr):
    b, g, r = (frame_bgr[..., i].astype(np.float32) for i in range(3))
    r = np.clip(np.rint(r / GAIN_R), 0, 255)
    g = np.clip(np.rint(g / GAIN_G), 0, 255)
    b = np.clip(np.rint(b / GAIN_B), 0, 255)
    raw = np.empty((H, W), np.uint8)
    raw[0::2, 0::2] = g[0::2, 0::2]     # even line, even x : G
    raw[0::2, 1::2] = b[0::2, 1::2]     # even line, odd  x : B
    raw[1::2, 0::2] = r[1::2, 0::2]     # odd  line, even x : R
    raw[1::2, 1::2] = g[1::2, 1::2]     # odd  line, odd  x : G
    return raw


def to_ddr(raw):
    """raster byte stream -> DDR image: reverse the 16 bytes of every 128-bit word."""
    return np.ascontiguousarray(raw.reshape(-1, 16)[:, ::-1]).reshape(-1)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument("--img1", default=os.path.join(root, "demo_images", "frame1_screw.jpg"))
    ap.add_argument("--img2", default=os.path.join(root, "demo_images", "frame2_caliper.jpg"))
    ap.add_argument("--cx1", type=int, default=900, help="screw: source column to centre the zoomed crop on")
    ap.add_argument("--fit1", choices=["cover", "contain"], default="cover")
    ap.add_argument("--fit2", choices=["cover", "contain"], default="contain")
    ap.add_argument("--cx2", type=int, default=500, help="used when --fit2 cover")
    ap.add_argument("--out", default=os.path.join(root, "demo_raw"))
    ap.add_argument("--streams", action="store_true", help="also write frameN.stream (raster order, for sim/loader/tb_debayer_demo)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    jobs = [("frame1", a.img1, a.fit1, a.cx1), ("frame2", a.img2, a.fit2, a.cx2)]
    for name, path, fit, cx in jobs:
        img = load(path)
        panel = fit_cover(img, cx) if fit == "cover" else fit_contain(img)
        frame = build_frame(panel)
        raw = mosaic(frame)
        assert raw.size == W * H
        to_ddr(raw).tofile(os.path.join(a.out, name + ".raw"))
        if a.streams:
            raw.tofile(os.path.join(a.out, name + ".stream"))
        cv2.imwrite(os.path.join(a.out, name + "_preview.png"), panel)
        print("%s: %s (%s) -> %d bytes" % (name, os.path.basename(path), fit, raw.size))


if __name__ == "__main__":
    main()
