import numpy as np, math
import fitgold as fg
recs = []
for line, cl in zip(open('../build/fit/fit_in.memh'), open('../build/fit/fit_cls.txt')):
    v = int(line, 16); c, k = cl.split(); recs.append((v, int(c), k))
# rebuild stats from the packed record (so the golden sees exactly what the RTL saw)
def unpack(v):
    g = lambda lo, w: (v >> lo) & ((1 << w) - 1)
    s = dict(M=g(0,16), sx=g(16,24), sy=g(40,25), sxx=g(65,32), syy=g(97,32), sxy=g(129,32), xmin=g(161,8), xmax=g(169,8), ymin=g(177,9), ymax=g(186,9))
    s['ext'] = [(g(196+17*k, 8), g(196+17*k+8, 9)) for k in range(8)]
    return s
def sx(v, bits): return v - (1 << bits) if v >> (bits-1) else v
bad = 0; worst = {}
for (v, c, k), line in zip(recs, open('../build/fit/fit_out.txt')):
    kind, cyc, par = line.split(); kind = int(kind); par = int(par, 16)
    assert kind == c, (kind, c)
    exp = fg.expected(unpack(v), c)
    if exp['kind'] == 'ell':
        g = lambda lo, w: (par >> lo) & ((1 << w) - 1)
        got = dict(cx=g(0,12)/4, cy=g(12,13)/4, a=g(25,14)/16, b=g(39,14)/16, c=sx(g(53,16),16)/16384, s=sx(g(69,16),16)/16384,
                   ia=g(85,18)/2**20, ib=g(103,18)/2**20)
        err = dict(cx=abs(got['cx']-exp['cx']), cy=abs(got['cy']-exp['cy']), a=abs(got['a']-exp['a']), b=abs(got['b']-exp['b']),
                   c=abs(got['c']-exp['c']), s=abs(got['s']-exp['s']), ia=abs(got['ia']-1/exp['a'])*exp['a'], ib=abs(got['ib']-1/exp['b'])*exp['b'])
        # an exact circle has an undefined axis direction: compare the rotation-invariant part only
        if c == 1: err['c'] = err['s'] = 0
        tol = dict(cx=0.4, cy=0.4, a=0.35, b=0.35, c=0.02, s=0.02, ia=0.01, ib=0.01)
        for key in err:
            worst[(('ell'), key)] = max(worst.get(('ell', key), 0), err[key])
            if err[key] > tol[key]: bad += 1; print('ELL MISMATCH', k, key, got, exp)
    else:
        got = []
        for e in range(4):
            q = (par >> (59*e)) & ((1 << 59) - 1)
            got.append((sx(q & 0xffff,16)/16384, sx((q >> 16) & 0xffff,16)/16384, sx(q >> 32, 27)/16384))
        used = []
        for nx_, ny_, c_ in got:
            m_ = math.hypot(nx_, ny_)
            if m_ > 0.1: used.append(((nx_/m_, ny_/m_), c_/m_))
        elines = exp['lines']
        if len(used) != len(elines): bad += 1; print('POLY edge count', k, len(used), len(elines)); continue
        for (nx, ny, c0) in elines:
            m = min(max(abs(u[0][0]-nx), abs(u[0][1]-ny), abs(u[1]-c0)/50.0) for u in used)
            md = min(abs(u[1]-c0) + 100*max(abs(u[0][0]-nx), abs(u[0][1]-ny)) for u in used)   # px near the shape
            worst[('poly', 'line')] = max(worst.get(('poly','line'), 0), md)
            if md > 1.2: bad += 1; print('POLY MISMATCH', k, (nx, ny, c0), used)
print('worst deviations', {f'{a}.{b}': round(v, 4) for (a, b), v in worst.items()})
print('records', len(recs), 'mismatches', bad)
