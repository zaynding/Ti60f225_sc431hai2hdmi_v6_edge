import numpy as np, cv2, sys
sig=float(sys.argv[1]); NFR=8; W,H=200,80
rng=np.random.default_rng(7)
base=np.full((H,W),215.0); cv2.circle(base,(45,40),26,60,-1,cv2.LINE_AA); cv2.rectangle(base,(95,18),(150,62),70,-1); cv2.line(base,(160,10),(195,70),90,2,cv2.LINE_AA)
base=cv2.GaussianBlur(base,(0,0),1.0)
with open('sim/build/algo/noisy.memh','w') as f:
    for k in range(NFR):
        g=np.clip(base+rng.normal(0,sig,base.shape),0,255).astype(np.uint8)
        for y in range(H):
            for p in range(W//2): f.write('%02x%02x\n'%(g[y,2*p+1],g[y,2*p]))
