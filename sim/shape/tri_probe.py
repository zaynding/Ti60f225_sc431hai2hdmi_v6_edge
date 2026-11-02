import numpy as np, cv2, math
from shapegen import *
from shape_int import *
def sobel_edges(img, thr, blur):
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float32)
    if blur: g = cv2.GaussianBlur(g, (0,0), blur)
    gx = cv2.Sobel(g, cv2.CV_32F, 1, 0, ksize=3); gy = cv2.Sobel(g, cv2.CV_32F, 0, 1, ksize=3)
    return (np.abs(gx) + np.abs(gy)) > thr
rng = np.random.default_rng(2)
for mode, thr, blur in [('sobel',160,1.5),('sobel',400,2.0),('sobel',64,2.0),('canny',0,0)]:
    print(mode, thr, blur)
    for kind in ['triangle','circle','square']:
        res=[]
        for t in range(10):
            size = rng.uniform(150, 230); rot = rng.uniform(0, 2*math.pi)
            img = render([(kind, W/2, H/2, size, rot, 1.0)], 'plain', seed=t)
            e = edges(img) if mode=='canny' else sobel_edges(img, thr, blur)
            m = analyse(crop_edges(e))
            # include regions the area filter would have removed
            lab_regs = regions(dilate3(pool4(crop_edges(e))))
            res.append([(c, round(I1/2**24,5), s['M'], (s['xmax']-s['xmin']+1)*(s['ymax']-s['ymin']+1)) for c,I1,el,s in m])
        print(' ', kind, [r[0] if r else None for r in res])
