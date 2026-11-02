import numpy as np, math, os, cv2
from shapegen import *
from shape_int import *
out = '../build/shape'; os.makedirs(out, exist_ok=True)
def pack(s):
    return s['M'] | (s['sx'] << 16) | (s['sy'] << 40) | (s['sxx'] << 65) | (s['syy'] << 97) | (s['sxy'] << 129) \
        | (s['xmin'] << 161) | (s['xmax'] << 169) | (s['ymin'] << 177) | (s['ymax'] << 186)
def write_frame(k, e_full, label):
    with open(f'{out}/frame{k}.memh', 'w') as f:
        for y in range(H):
            by = np.packbits(e_full[y].astype(np.uint8), bitorder='little')
            f.write('%0480x\n' % int.from_bytes(by.tobytes(), 'little'))
    res = analyse(e_full[:, CROP_X0:CROP_X0 + CROP_W])
    with open(f'{out}/exp{k}.memh', 'w') as f:
        for c, I1, el, s in res: f.write('%049x\n' % pack(s))
    with open(f'{out}/cls{k}.memh', 'w') as f:
        for c, I1, el, s in res: f.write('%x\n' % c)
    print(label, [(CLS[c], s['M'], (s['xmax']-s['xmin']+1)*(s['ymax']-s['ymin']+1)) for c, I1, el, s in res])
# big triangle + circle (both above the 1/12 bounding-box gate)
write_frame(0, edges(render([('circle', W/2-150, 330, 170, 0, 1), ('triangle', W/2+30, 780, 290, 0.3, 1)], 'plain', seed=1, saw_amp=8)), 'scene0')
# ellipse passes; small square (box < 1/12) and small triangle are filtered out
write_frame(1, edges(render([('ellipse', W/2, 330, 260, 0.8, 1.6), ('square', W/2-250, 850, 110, 0.4, 1), ('triangle', W/2+250, 880, 120, 0.1, 1)], 'plain', seed=2)), 'scene1')
# rectangle + triangle on the wood texture
write_frame(2, edges(render([('rect', W/2, 320, 230, 0.2, 1.7), ('triangle', W/2, 800, 260, 3.5, 1)], 'wood', seed=3)), 'scene2')
