import numpy as np, sys, math
import fitgold as fg
idx = int(sys.argv[1])
v = int(open('../build/fit/fit_in.memh').read().split()[idx], 16)
cls = int(open('../build/fit/fit_cls.txt').read().splitlines()[idx].split()[0])
exec(open('fitcheck.py').read().split("bad = 0")[0].split("recs = []")[0])
def unpack(v):
    g = lambda lo, w: (v >> lo) & ((1 << w) - 1)
    s = dict(M=g(0,16), sx=g(16,24), sy=g(40,25), sxx=g(65,32), syy=g(97,32), sxy=g(129,32), xmin=g(161,8), xmax=g(169,8), ymin=g(177,9), ymax=g(186,9))
    s['ext'] = [(g(196+17*k, 8), g(196+17*k+8, 9)) for k in range(8)]
    return s
exp = fg.expected(unpack(v), cls)
lines = [l.split() for l in open('../build/fit/draw_out.txt') if l.strip()]
img = np.zeros((len(lines), 1920), np.uint8)
for y, l in enumerate(lines):
    for p, t in enumerate(l[:960]):
        val = int(t, 16)
        for k in range(2):
            px = (val >> (24*k)) & 0xffffff
            r, g, b = (px >> 16) & 255, (px >> 8) & 255, px & 255
            img[y, 2*p+k] = 1 if (r, g, b) not in ((0x30,0x30,0x30),) and not (r == g == b) else 0
left = img[:, :960].astype(bool)
print('lines', len(lines), 'drawn px left panel', int(left.sum()), 'right panel', int(img[:, 960:].sum()))
if exp['kind'] == 'ell':
    ys, xs = np.nonzero(left)
    dx = xs - exp['cx']; dy = ys - exp['cy']
    u = exp['c']*dx + exp['s']*dy; vv = exp['c']*dy - exp['s']*dx
    r = np.sqrt((u/exp['a'])**2 + (vv/exp['b'])**2)
    d = np.abs(r - 1) * min(exp['a'], exp['b'])
    per = math.pi * (3*(exp['a']+exp['b']) - math.sqrt((3*exp['a']+exp['b'])*(exp['a']+3*exp['b'])))
    print('expected perimeter %.0f px, drawn %d px (%.2fx), distance to ideal ellipse: mean %.2f max %.2f' % (per, len(xs), len(xs)/per, d.mean() if len(d) else -1, d.max() if len(d) else -1))
