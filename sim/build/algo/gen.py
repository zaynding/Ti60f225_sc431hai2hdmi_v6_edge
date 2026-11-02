import numpy as np, cv2
W,H=200,80
im=np.full((H,W),215.0)
cv2.circle(im,(45,40),26,60,-1,cv2.LINE_AA)
cv2.rectangle(im,(95,18),(150,62),70,-1)
cv2.line(im,(160,10),(195,70),90,2,cv2.LINE_AA)
rng=np.random.default_rng(1)
im=cv2.GaussianBlur(im,(0,0),1.0)+rng.normal(0,2.5,im.shape)
g=np.clip(im,0,255).astype(np.uint8)
cv2.imwrite('sim/build/algo/img.png',g)
with open('sim/build/algo/img.memh','w') as f:
    for y in range(H):
        for p in range(W//2): f.write('%02x%02x\n'%(g[y,2*p+1],g[y,2*p]))
