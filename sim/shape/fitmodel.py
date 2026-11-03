"""Float golden model of the 'draw the best-fitting ideal outline' stage.
Input: one hole region (set of 4x4-pixel cells) + class.  Output: outline geometry in crop pixel coordinates.
circle / ellipse : centre + covariance eigen-decomposition (moments)
square/rect/triangle : max-area polygon (4/3 vertices) among the 8 directional extreme cells, then every side is
                      pushed outwards by  d_i = K0 + K1*(|nx|+|ny|)  (the hole is the shape eroded by the 3x3 dilated edge ring)."""
import numpy as np, math, cv2
from scipy import ndimage as ndi
from itertools import combinations
from shapegen import *
import shape_int as si

K0, K1, KE = 4.0, 2.0, 5.0         # calibrated below

def region_cells(e_crop):
    m = si.dilate3(si.pool4(e_crop))
    lab, n = ndi.label(~m, structure=ndi.generate_binary_structure(2, 1))
    h, w = m.shape; out = []
    ys, xs = np.mgrid[0:h, 0:w]
    for l in range(1, n+1):
        sel = lab == l
        x = xs[sel]; y = ys[sel]
        M = len(x)
        if x.min()==0 or y.min()==0 or x.max()==w-1 or y.max()==h-1: continue
        if M < si.MMIN or M > si.MMAX: continue
        if (x.max()-x.min()+1)*(y.max()-y.min()+1) < si.BMIN: continue
        out.append((x, y))
    return out

DIRS = [(1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)]
def extremes(x, y):
    pts = []
    for dx, dy in DIRS:
        p = x*dx + y*dy
        i = int(np.argmax(p))               # first max in scan order (cells are in raster order)
        pts.append((4*x[i]+2.0, 4*y[i]+2.0))
    return pts

def poly_area(p):
    p = np.array(p); x, y = p[:,0], p[:,1]
    return 0.5*abs(np.dot(x, np.roll(y,-1)) - np.dot(y, np.roll(x,-1)))

def order_ccw(p, c):
    return sorted(p, key=lambda q: math.atan2(q[1]-c[1], q[0]-c[0]))

def best_polygon(pts, n):
    u = list(dict.fromkeys(pts))
    c = np.mean(np.array(u), 0)
    best, ba = None, -1
    for comb in combinations(u, n):
        o = order_ccw(list(comb), c); a = poly_area(o)
        if a > ba: ba, best = a, o
    return best

def offset_polygon(poly, k0=None, k1=None):
    k0 = K0 if k0 is None else k0; k1 = K1 if k1 is None else k1
    n = len(poly); c = np.mean(np.array(poly), 0)
    lines = []
    for i in range(n):
        p, q = np.array(poly[i]), np.array(poly[(i+1) % n])
        d = q - p; L = math.hypot(*d)
        nrm = np.array([d[1], -d[0]])/L      # candidate normal
        if np.dot(nrm, p - c) < 0: nrm = -nrm   # outward
        off = k0 + k1*(abs(nrm[0]) + abs(nrm[1]))
        lines.append((nrm, np.dot(nrm, p) + off))
    verts = []
    for i in range(n):
        n1, c1 = lines[i-1]; n2, c2 = lines[i]
        A = np.array([n1, n2]); b = np.array([c1, c2])
        verts.append(np.linalg.solve(A, b))
    return np.array(verts)

def fit_ellipse(x, y, ke=None):
    ke = KE if ke is None else ke
    cx = x.mean(); cy = y.mean()
    X = np.stack([x - cx, y - cy]); C = (X @ X.T)/len(x)*16.0       # cell units -> px^2
    w, v = np.linalg.eigh(C)                                         # ascending
    a = 2*math.sqrt(max(w[1], 1e-6)) + ke; b = 2*math.sqrt(max(w[0], 1e-6)) + ke
    ang = math.atan2(v[1,1], v[0,1])
    return (4*cx+2.0, 4*cy+2.0), a, b, ang

def outline_mask(kind, x, y, shape=(H, CROP_W), k0=None, k1=None, ke=None):
    m = np.zeros(shape, np.uint8)
    if kind in ('circle', 'ellipse'):
        (cx, cy), a, b, ang = fit_ellipse(x, y, ke)
        if kind == 'circle': a = b = (a + b)/2
        cv2.ellipse(m, (int(round(cx)), int(round(cy))), (int(round(a)), int(round(b))), math.degrees(ang), 0, 360, 255, 1)
    else:
        n = 3 if kind == 'triangle' else 4
        poly = best_polygon(extremes(x, y), n)
        v = offset_polygon(poly, k0, k1)
        cv2.polylines(m, [np.round(v).astype(np.int32).reshape(-1,1,2)], True, 255, 1)
    return m > 0

def truth_boundary(kind, cx, cy, size, rot, aspect):
    img = np.zeros((H, W, 3), np.uint8)
    draw_shape(img, kind, cx, cy, size, rot, (255,255,255), aspect)
    t = (img[:,:,0] > 127)[:, CROP_X0:CROP_X0+CROP_W]
    return t & ~ndi.binary_erosion(t)

def boundary_error(fit, truth):
    dt_t = ndi.distance_transform_edt(~truth)
    dt_f = ndi.distance_transform_edt(~fit)
    return float(dt_t[fit].mean()), float(dt_t[fit].max()), float(dt_f[truth].mean()), float(dt_f[truth].max())

def make_cases(n, seed, saw=8, noise=3.0):
    rng = np.random.default_rng(seed); cases = []
    kinds = ['circle','ellipse','square','rect','triangle']
    for t in range(n):
        kind = kinds[t % 5]
        size = rng.uniform(160, 260); rot = rng.uniform(0, 2*math.pi)
        asp = rng.uniform(1.3, 2.0) if kind in ('ellipse','rect') else (rng.choice([1.0, 1.4]) if kind == 'triangle' else 1.0)
        cx = W/2 + rng.uniform(-120, 120); cy = H/2 + rng.uniform(-100, 100)
        cases.append((kind, cx, cy, size, rot, asp, seed*1000+t))
    return cases

def evaluate(cases, k0=None, k1=None, ke=None, verbose=False):
    res = {}
    for kind, cx, cy, size, rot, asp, sd in cases:
        img = render([(kind, cx, cy, size, rot, asp)], 'plain', seed=sd, saw_amp=8)
        e = crop_edges(edges(img))
        regs = region_cells(e)
        if not regs: res.setdefault(kind, []).append(None); continue
        x, y = max(regs, key=lambda r: len(r[0]))
        f = outline_mask(kind, x, y, k0=k0, k1=k1, ke=ke)
        tb = truth_boundary(kind, cx, cy, size, rot, asp)
        res.setdefault(kind, []).append(boundary_error(f, tb))
    return res

if __name__ == '__main__':
    cases = make_cases(40, 1)
    r = evaluate(cases)
    for k, v in r.items():
        vv = [a for a in v if a]
        print(k, 'n', len(vv), 'mean dist fit->truth %.2f  max %.2f   truth->fit mean %.2f max %.2f' % tuple(np.mean(vv, 0)))
