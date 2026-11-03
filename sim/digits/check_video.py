"""Independent raster oracle for interpolated standard outlines and live video."""
from pathlib import Path
import argparse
import json
import cv2
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'sim'/'build'/'digits'


def standard_mask(boxes,width=960,height=1080,x_offset=0,full_width=None,lhs=7):
    canvas=np.zeros((height,full_width or width),np.uint8)
    words=[int(w,16) for w in (ROOT/'digit_standard_spans.mem').read_text().split()]
    for glyph,(x0,x1,y0,y1) in enumerate(boxes):
        left=x_offset+4*x0;top=4*y0;ww=4*(x1-x0+1);hh=4*(y1-y0+1)
        for dy in range(hh):
            yy=top+dy
            if yy<0 or yy>=height:
                continue
            phase=((2*dy+1)<<14)//hh
            row,fraction=divmod(phase,256)
            atlas=3 if glyph==0 and lhs==5 else glyph
            word=words[128*atlas+row]
            lo=word&((1<<50)-1);hi=word>>50
            if (lo>>48)!=(hi>>48):
                lo=hi if fraction>=128 else lo
                hi=lo
            flags=lo>>48
            endpoints=[]
            for edge in range(4):
                a=(lo>>(12*edge))&4095;b=(hi>>(12*edge))&4095
                interpolated=a+((b-a)*fraction//256)
                endpoints.append(left+((interpolated*ww)>>12))
            for interval in range(2):
                if flags&(1<<interval):
                    low,high=endpoints[2*interval:2*interval+2]
                    canvas[yy,max(0,low):min(canvas.shape[1],high+1)]=1
    edge=cv2.morphologyEx(canvas,cv2.MORPH_GRADIENT,np.ones((3,3),np.uint8))
    return cv2.dilate(edge,np.ones((5,5),np.uint8))


def reference(moved=True,lhs=5):
    name=('covered5_moved' if moved else 'covered5') if lhs==5 else ('card_moved' if moved else 'card')
    roi=np.asarray(Image.open(ROOT/f'sim/digits/vectors/{name}.png').convert('L'))
    scenes=json.loads((ROOT/'sim/digits/vectors/manifest.json').read_text())
    boxes=next(m['boxes'] for m in scenes if m['name']==('covered5_moved' if moved else 'covered5')) if lhs==5 else scenes[0]['boxes']
    if moved and lhs!=5:
        boxes=[[x0+16,x1+16,y0+6,y1+6] for x0,x1,y0,y1 in boxes]
    full=standard_mask(boxes,x_offset=480,full_width=1920,lhs=lhs)
    return roi,full[:,480:1440],boxes,full


def write_pairs(path,mask):
    pairs=mask[:,::2]|(mask[:,1::2]<<1)
    path.write_text(''.join(f'{int(b):x}\n' for b in pairs.flat),encoding='ascii')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--prepare',action='store_true')
    args=parser.parse_args()
    roi,mask,boxes,full=reference()
    components,_=cv2.connectedComponents(mask,connectivity=8)
    assert components-1==3, f'Standard outlines contain disconnected dots or joined glyphs: {components-1}'
    if args.prepare:
        write_pairs(OUT/'outline_expected.mem',full)
        small=standard_mask([(2,3,4,9),(6,7,6,7),(10,11,4,9)],width=64,height=64,x_offset=32,full_width=128)
        write_pairs(OUT/'pipeline_expected.mem',small)
        print('Prepared standard-vector, six-pixel contour and movement oracles')
        return
    raw=bytes.fromhex((OUT/'video.hex').read_text(encoding='ascii'))
    assert len(raw)==1920*1080*3, f'Incomplete video frame: {len(raw)} bytes'
    image=np.frombuffer(raw,np.uint8).reshape(1080,960,2,3)[:,:,::-1,::-1].reshape(1080,1920,3)
    green=(image[:,:,0]==0)&(image[:,:,1]==255)&(image[:,:,2]==0)
    status=np.zeros((1080,960),bool);status[72:108,8:208]=1
    result_x=boxes[2][1]*4+20;result_y=min(boxes[0][2],boxes[2][2])*4
    if result_x+144>960:
        result_x=boxes[0][0]*4
        bottom=max(boxes[0][3],boxes[2][3])*4+20
        result_y=bottom if bottom+128<960 else max(8,result_y-144)
    badge=np.zeros_like(status);badge[result_y:result_y+128,result_x:result_x+144]=1
    excluded=status|badge
    for panel in range(2):
        actual=green[:,960*panel:960*(panel+1)]
        bad=np.count_nonzero((actual!=mask.astype(bool))&~excluded)
        assert bad==0, f'Panel {panel} standard outline mismatch: {bad} pixels'
    untouched=(mask==0)&~excluded
    assert np.array_equal(image[:,:960][untouched],np.repeat(roi[:,:,None],3,axis=2)[untouched]), 'Live moving colour image mismatch'
    original=np.asarray(Image.open(ROOT/'sim/digits/vectors/card.png').convert('L'))
    assert np.count_nonzero(original!=roi)>10000, 'Movement fixture must actually move'
    assert not green[650:,:960].any(), 'Unrelated lower 9 - 4 was outlined'
    nine_words=[int(w,16) for w in (ROOT/'digit_results.mem').read_text().split()][64:128]
    nine=np.array([[(word>>(43-x))&1 for x in range(44)] for word in nine_words],dtype=bool).repeat(2,0).repeat(2,1)
    assert np.array_equal(green[result_y:result_y+128,result_x+56:result_x+144],nine), 'Computed result 7 mismatch'
    Image.fromarray(image).save(OUT/'video_preview.png')
    Image.fromarray(image[:600]).save(OUT/'video_preview_top.png')
    stats={'resolution':[1920,1080],'contour_pixels':int(mask.sum()),'pixel_mismatches':0,
           'outline_components':3,
           'camera_frozen':False,'target_motion_pixels':[64,24],'computed_expression':'5+2=7',
           'input_sequence':'7+2 -> opaque white 5 card covering 7 -> 5+2',
           'result_delay_frames_default':18,'result_delay_frames_hd_fixture':1,
           'rendering':'interpolated standard polygon contours, about 6 pixels',
           'boxes':boxes}
    (OUT/'video_verification.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
    print(json.dumps(stats,indent=2))


if __name__=='__main__':
    main()
