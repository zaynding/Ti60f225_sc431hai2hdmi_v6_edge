import numpy as np, itertools, pickle
from fitmodel import *
cases = make_cases(80, 11)
data = []
for kind, cx, cy, size, rot, asp, sd in cases:
    img = render([(kind, cx, cy, size, rot, asp)], 'plain', seed=sd, saw_amp=8)
    regs = region_cells(crop_edges(edges(img)))
    if not regs: continue
    x, y = max(regs, key=lambda r: len(r[0]))
    data.append((kind, x, y, truth_boundary(kind, cx, cy, size, rot, asp)))
print(len(data), 'usable cases')
def score(kinds, **kw):
    v = []
    for kind, x, y, tb in data:
        if kind not in kinds: continue
        f = outline_mask(kind, x, y, **kw)
        a, b, c, d = boundary_error(f, tb); v.append((a + c)/2)
    return float(np.mean(v)), len(v)
print('ellipse/circle KE')
for ke in (2, 3, 4, 5, 6, 7, 8): print(ke, score(('circle','ellipse'), ke=ke))
print('polygons K0,K1')
best = None
for k0, k1 in itertools.product((0, 1, 2, 3, 4, 5, 6), (0, 1, 2, 3, 4, 5)):
    s = score(('square','rect','triangle'), k0=k0, k1=k1)
    if best is None or s[0] < best[0]: best = (s[0], k0, k1)
print('best polygon', best)
for kd in (('square',), ('rect',), ('triangle',)):
    bb = None
    for k0, k1 in itertools.product((0, 1, 2, 3, 4, 5, 6), (0, 1, 2, 3, 4, 5)):
        s = score(kd, k0=k0, k1=k1)
        if bb is None or s[0] < bb[0]: bb = (round(s[0],2), k0, k1)
    print(kd, bb)
