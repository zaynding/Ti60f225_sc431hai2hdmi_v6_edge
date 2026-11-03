import numpy as np, cv2
W,H=200,80
rng=np.random.default_rng(3)
def save(name,im):
    g=np.clip(im,0,255).astype(np.uint8)
    cv2.imwrite(f'sim/build/algo/{name}.png',g)
    with open(f'sim/build/algo/{name}.memh','w') as f:
        for y in range(H):
            for p in range(W//2): f.write('%02x%02x\n'%(g[y,2*p+1],g[y,2*p]))
# A: clean scene, high contrast shapes
im=np.full((H,W),215.0); cv2.circle(im,(45,40),26,60,-1,cv2.LINE_AA); cv2.rectangle(im,(95,18),(150,62),70,-1)
save('imgA',cv2.GaussianBlur(im,(0,0),1.0)+rng.normal(0,2.0,im.shape))
# B: heavy texture (wood-like stripes + noise)
yy=np.arange(H)[:,None]; xx=np.arange(W)[None,:]
im=140+40*np.sin(yy/1.7+0.3*np.sin(xx/9))+rng.normal(0,12,(H,W))
save('imgB',cv2.GaussianBlur(im,(0,0),0.7))
# C: low contrast soft scene
im=np.full((H,W),120.0); cv2.circle(im,(100,40),28,150,-1,cv2.LINE_AA)
save('imgC',cv2.GaussianBlur(im,(0,0),2.0)+rng.normal(0,1.5,im.shape))
