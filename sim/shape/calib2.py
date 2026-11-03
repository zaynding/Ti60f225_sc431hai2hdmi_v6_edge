import numpy as np, itertools
exec(open('calib.py').read().split("print('ellipse/circle KE')")[0])
print('KE fine', [(ke, round(score(('circle','ellipse'), ke=ke)[0],2)) for ke in (6.5,7,7.5,8,8.5)])
best=None
for k0,k1 in itertools.product(np.arange(4,10.5,1.0), np.arange(0,5.5,1.0)):
    s=score(('square','rect','triangle'),k0=k0,k1=k1)
    if best is None or s[0]<best[0]: best=(round(s[0],2),k0,k1)
print('best polygon', best)
k0,k1=best[1],best[2]
for kind in ('circle','ellipse','square','rect','triangle'):
    errs=[]
    for kd,x,y,tb in data:
        if kd!=kind: continue
        f=outline_mask(kd,x,y,k0=k0,k1=k1,ke=7.5); a,b,c,d=boundary_error(f,tb); errs.append((a,max(b,d)))
    e=np.array(errs); print(kind,'mean %.2f  worst-case max %.2f  n=%d'%(e[:,0].mean(),e[:,1].max(),len(e)))
