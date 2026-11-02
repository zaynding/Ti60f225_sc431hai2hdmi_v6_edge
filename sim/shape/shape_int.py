"""Bit-exact integer model of the RTL classifier plus region extraction used as golden."""
import numpy as np
from scipy import ndimage as ndi

MAP_W, MAP_H = 240, 270
MMIN, MMAX, BMIN = 600, 38880, 5400        # area gate in 4x4-cell units
MIN_AREA_DIV = 12             # region must occupy strictly more than 1/12 of the window
CLS = {0: 'none', 1: 'circle', 2: 'ellipse', 3: 'square', 4: 'rect', 5: 'triangle'}

# I1 * 2^24 windows
CIRC = (int(0.00600 * 2**24), int(0.00668 * 2**24))
QUAD = (int(0.00676 * 2**24), int(0.00760 * 2**24))
TRI  = (int(0.00850 * 2**24), int(0.01000 * 2**24))

def classify_int(s):
    M = s['M']
    M2 = M * M
    Cxx = M * s['sxx'] - s['sx'] * s['sx']
    Cyy = M * s['syy'] - s['sy'] * s['sy']
    Cxy = M * s['sxy'] - s['sx'] * s['sy']
    Vxx = (Cxx << 8) // M2
    Vyy = (Cyy << 8) // M2
    Vxy = (abs(Cxy) << 8) // M2
    if Cxy < 0: Vxy = -Vxy
    det = Vxx * Vyy - Vxy * Vxy
    if det < 0: det = 0
    I1 = (det << 8) // M2
    T = Vxx + Vyy
    D = (Vxx - Vyy) ** 2 + 4 * Vxy * Vxy
    elong = (D << 6) > T * T
    if CIRC[0] <= I1 <= CIRC[1]: c = 2 if elong else 1
    elif QUAD[0] <= I1 <= QUAD[1]: c = 4 if elong else 3
    elif TRI[0] <= I1 <= TRI[1]: c = 5
    else: c = 0
    return c, I1, elong

def pool4(e):
    h, w = e.shape
    return e.reshape(h // 4, 4, w // 4, 4).any(axis=(1, 3))

def dilate3(m):
    return ndi.binary_dilation(m, structure=np.ones((3, 3), bool), border_value=0)

def regions(m):
    """4-connected zero regions of dilated map, candidate (non-touching, area-gated) stats."""
    lab, n = ndi.label(~m, structure=ndi.generate_binary_structure(2, 1))
    h, w = m.shape
    ys, xs = np.mgrid[0:h, 0:w]
    out = []
    for l in range(1, n + 1):
        sel = lab == l
        M = int(sel.sum())
        x = xs[sel].astype(np.int64); y = ys[sel].astype(np.int64)
        touch = x.min() == 0 or y.min() == 0 or x.max() == w - 1 or y.max() == h - 1
        if touch or M < MMIN or M > MMAX: continue
        if (x.max() - x.min() + 1) * (y.max() - y.min() + 1) < BMIN: continue
        out.append(dict(M=M, sx=int(x.sum()), sy=int(y.sum()), sxx=int((x * x).sum()), syy=int((y * y).sum()),
                        sxy=int((x * y).sum()), xmin=int(x.min()), xmax=int(x.max()), ymin=int(y.min()), ymax=int(y.max())))
    return out

def analyse(e_crop):
    """e_crop: bool (1080, 960). Returns list of (class, stats)."""
    m = dilate3(pool4(e_crop))
    res = []
    for s in regions(m):
        c, I1, el = classify_int(s)
        res.append((c, I1, el, s))
    return res
