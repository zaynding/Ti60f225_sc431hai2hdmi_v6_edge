import numpy as np, cv2, sys
lines=[l.split() for l in open('../build/shape/fit_draw.txt') if l.strip()]
H=len(lines); img=np.zeros((H,1920,3),np.uint8)
for y,l in enumerate(lines):
    for p,t in enumerate(l[:960]):
        v=int(t,16)
        for k in range(2):
            px=(v>>(24*k))&0xffffff; img[y,2*p+k]=(px&255,(px>>8)&255,(px>>16)&255)
cv2.imwrite('../build/shape/fit_draw.png', img)
print(img.shape, 'colored px', int(((img[:,:,0]!=img[:,:,1])|(img[:,:,1]!=img[:,:,2])).sum()))
