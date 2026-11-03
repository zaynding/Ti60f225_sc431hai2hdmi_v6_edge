"""Golden for shape_fit: builds 332-bit region records exactly like shape_ccl, and the float expected outline parameters."""
import numpy as np, math, os, sys
from itertools import combinations
from shapegen import *
import shape_int as si
import fitmodel as fm

RTL_DIRS = [(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1),(0,-1),(1,-1)]
K0, K1, KE = 6.0, 3.0, 7.5

def stats(x, y):
    M = len(x); x = x.astype(np.int64); y = y.astype(np.int64)
    s = dict(M=M, sx=int(x.sum()), sy=int(y.sum()), sxx=int((x*x).sum()), syy=int((y*y).sum()), sxy=int((x*y).sum()),
             xmin=int(x.min()), xmax=int(x.max()), ymin=int(y.min()), ymax=int(y.max()))
    ext = []
    for dx, dy in RTL_DIRS:
        p = x*dx + y*dy; i = int(np.argmax(p)); ext.append((int(x[i]), int(y[i])))      # first max in raster order
    s['ext'] = ext
    return s

def pack(s):
    v = s['M'] | (s['sx'] << 16) | (s['sy'] << 40) | (s['sxx'] << 65) | (s['syy'] << 97) | (s['sxy'] << 129) \
        | (s['xmin'] << 161) | (s['xmax'] << 169) | (s['ymin'] << 177) | (s['ymax'] << 186)
    for k, (ex, ey) in enumerate(s['ext']): v |= (ex | (ey << 8)) << (196 + 17*k)
    return v

def expected(s, kind):
    ext = [(4*ex+2.0, 4*ey+2.0) for ex, ey in s['ext']]
    if kind in (1, 2):
        M = s['M']; cx = s['sx']/M; cy = s['sy']/M
        sxx = (s['sxx']/M - cx*cx)*16; syy = (s['syy']/M - cy*cy)*16; sxy = (s['sxy']/M - cx*cy)*16
        C = np.array([[sxx, sxy], [sxy, syy]]); w, v = np.linalg.eigh(C)
        a = 2*math.sqrt(max(w[1], 0)); b = 2*math.sqrt(max(w[0], 0))
        if kind == 1: a = b = (a+b)/2
        c, sn = v[0,1], v[1,1]
        if c < 0: c, sn = -c, -sn
        return dict(kind='ell', cx=4*cx+2.0, cy=4*cy+2.0, a=a+KE, b=b+KE, c=c, s=sn)
    n = 3 if kind == 5 else 4
    best, ba = None, -1
    for comb in combinations(range(8), n):
        P = [ext[i] for i in comb]
        if n == 3: area = (P[1][0]-P[0][0])*(P[2][1]-P[0][1]) - (P[2][0]-P[0][0])*(P[1][1]-P[0][1])
        else:      area = (P[2][0]-P[0][0])*(P[3][1]-P[1][1]) - (P[3][0]-P[1][0])*(P[2][1]-P[0][1])
        if area > ba: ba, best = area, P
    lines = []
    for e in range(n):
        p, q = best[e], best[(e+1) % n]; dx, dy = q[0]-p[0], q[1]-p[1]; L = math.hypot(dx, dy) or 1.0
        nx, ny = dy/L, -dx/L
        c = nx*p[0] + ny*p[1] + K0 + K1*(abs(nx)+abs(ny))
        lines.append((nx, ny, c))
    return dict(kind='poly', lines=lines)

def make_vectors(outdir, ncases=40, seed=21):
    cases = fm.make_cases(ncases, seed)
    recs = []
    for kind, cx, cy, size, rot, asp, sd in cases:
        img = render([(kind, cx, cy, size, rot, asp)], 'plain', seed=sd, saw_amp=8)
        e = crop_edges(edges(img))
        for x, y in fm.region_cells(e):
            s = stats(x, y); c, I1, el = si.classify_int(dict(M=s['M'], sx=s['sx'], sy=s['sy'], sxx=s['sxx'], syy=s['syy'], sxy=s['sxy']))
            if c == 0: continue
            recs.append((s, c, kind))
    os.makedirs(outdir, exist_ok=True)
    with open(f'{outdir}/fit_in.memh', 'w') as f:
        for s, c, k in recs: f.write('%083x\n' % pack(s))
    with open(f'{outdir}/fit_cls.txt', 'w') as f:
        for s, c, k in recs: f.write('%d %s\n' % (c, k))
    return recs

if __name__ == '__main__':
    recs = make_vectors('../build/fit')
    print(len(recs), 'records', {k: sum(1 for r in recs if r[1]==k) for k in range(1,6)})
