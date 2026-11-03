"""Extract the actual card glyphs; generate FPGA ROMs and camera-like test maps.

Usage: python tools/gen_digit_card.py --pdf PATH [--vectors]
Needs Poppler pdftoppm, numpy, Pillow, OpenCV. Does not change the source PDF.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from itertools import permutations

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def glyphs(page):
    ink = (np.asarray(page.convert('L')) < 128).astype('uint8')
    n, _, stats, _ = cv2.connectedComponentsWithStats(ink)
    objects = [tuple(map(int, s)) for s in stats[1:] if s[4] > 1000]
    top = sorted([s for s in objects if s[1] < ink.shape[0] // 2], key=lambda s: s[0])
    lower = sorted([s for s in objects if s[1] > ink.shape[0] // 2], key=lambda s: s[0])
    if len(top) != 3 or len(lower) != 3:
        raise ValueError('Expected page 1 to contain 7 + 2 above 9 - 4')
    boxes = top + lower
    return {key: Image.fromarray(255 * ink[y:y+h, x:x+w])
            for key, (x, y, w, h, _) in zip(['7', '+', '2', '9', '-', '4'], boxes)}, boxes


def normalize(image, size=(32, 64)):
    # Nearest bin-center sampling, also used by the hardware DDA.
    a = np.asarray(image)
    w, h = size
    xs = ((2*np.arange(w)+1)*a.shape[1] // (2*w)).astype(int)
    ys = ((2*np.arange(h)+1)*a.shape[0] // (2*h)).astype(int)
    return (a[ys[:, None], xs] >= 128).astype('uint8')


def row_word(bits):
    return int(''.join(str(int(v)) for v in bits), 2)


def write_map(path, roi):
    a = np.asarray(roi.convert('L'), dtype=np.uint16)
    avg = a.reshape(270, 4, 240, 4).sum(axis=(1, 3)) // 16
    threshold = (int(avg.min()) + int(avg.max())) // 2
    bits = (avg < threshold).astype('uint8')
    path.write_text(''.join(f'{int(v)}\n' for v in bits.flat), encoding='ascii')
    return bits


def nearest_components(bits, templates):
    n, _, stats, _=cv2.connectedComponentsWithStats(bits,connectivity=8)
    candidates=[]
    for x,y,w,h,area in stats[1:]:
        crop=Image.fromarray(bits[y:y+h,x:x+w]*255)
        sampled=normalize(crop)
        candidates.append({'box':[int(x),int(x+w-1),int(y),int(y+h-1)],
                           'scores':[int(np.count_nonzero(sampled!=t)) for t in templates]})
    if len(candidates)<3:
        return [],0
    assignment=min(permutations(range(len(candidates)),3),
                   key=lambda ids:min(candidates[ids[0]]['scores'][0],candidates[ids[0]]['scores'][3])+
                       candidates[ids[1]]['scores'][1]+candidates[ids[2]]['scores'][2])
    left=candidates[assignment[0]]['scores']
    return [candidates[i]['box'] for i in assignment],(5 if left[3]<left[0] else 7)


def span_rom(gs):
    """Vector polygon scanlines with 12-bit horizontal and 8-bit vertical interpolation."""
    words=[]
    for char in ['7','+','2','5']:
        ink=(np.asarray(gs[char])>127).astype('uint8')
        contours,_=cv2.findContours(ink,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
        contour=max(contours,key=cv2.contourArea)
        polygon=cv2.approxPolyDP(contour,0.75 if char in '7+' else 0.35,True)[:,0,:].astype(float)
        rows=[]
        for row in range(128):
            y=np.clip(row*(ink.shape[0]-1)/127,0.00001,ink.shape[0]-1.00001)
            intersections=[]
            for p,q in zip(polygon,np.roll(polygon,-1,axis=0)):
                if (p[1]<=y<q[1]) or (q[1]<=y<p[1]):
                    intersections.append(p[0]+(y-p[1])*(q[0]-p[0])/(q[1]-p[1]))
            intersections.sort()
            intervals=list(zip(intersections[::2],intersections[1::2]))
            if not intervals or len(intervals)>2:
                raise ValueError(f'Unexpected polygon scanline {char} row {row}: {intervals}')
            # Rightmost interval always occupies slot 1 (the continuous spine).
            right=intervals[-1]
            left=intervals[0] if len(intervals)==2 else (right[0],right[0])
            edges=[*left,*right]
            coords=[max(0,min(4095,round(x*4095/(ink.shape[1]-1)))) for x in edges]
            packed=sum(x<<(12*i) for i,x in enumerate(coords))
            packed|=(int(len(intervals)==2)<<48)|(1<<49)
            rows.append(packed)
        words.extend(rows[r]|(rows[min(r+1,127)]<<50) for r in range(128))
    (ROOT/'digit_standard_spans.mem').write_text(''.join(f'{w:025x}\n' for w in words),encoding='ascii')


def generate_vectors(page, gs, out):
    out.mkdir(parents=True, exist_ok=True)
    scenes = []
    # Real card, including its unrelated lower 9 - 4 row.
    for name, width, pos, angle, low, high, expected in [
        ('card', 700, (130, 16), 0, 0, 255, 1),
        ('smaller', 520, (88, 125), 0, 0, 255, 1),
        ('rotated', 700, (115, 10), 4, 0, 255, 1),
        ('dim', 700, (130, 16), 0, 25, 135, 1),
        ('low_contrast', 700, (130, 16), 0, 100, 115, 1),
    ]:
        roi = Image.new('L', (960, 1080), 255)
        card = page.resize((width, round(page.height*width/page.width)), Image.Resampling.LANCZOS)
        if angle:
            card = card.rotate(angle, Image.Resampling.BICUBIC, expand=True, fillcolor=255)
        roi.paste(card, pos)
        roi = roi.point(lambda p: round(low+(high-low)*p/255))
        scenes.append((name, roi, expected))

    def expression(text, x=100, y=200, height=240):
        roi = Image.new('L', (960, 1080), 255)
        for ch in text:
            glyph = gs[ch]
            hh = round(height*(.16 if ch=='-' else .74)) if ch in '+-' else height
            ww = round(hh*glyph.width/glyph.height)
            g = Image.eval(glyph, lambda p: 255-p).resize((ww, hh), Image.Resampling.LANCZOS)
            roi.paste(g, (x, y+(height-hh)//2))
            x += ww+45
        return roi

    # The permissive mode ranks the nearest assignment, without rejecting an
    # imperfect sign/digit or imposing left-to-right order.
    for name, expr, expected in [('missing_plus','72',0),('minus','7-2',1),
                                 ('wrong_left','9+2',1),('wrong_right','7+4',1),
                                 ('wrong_order','2+7',1),('separate','7+2',1)]:
        scenes.append((name, expression(expr), expected))
    blank = Image.new('L', (960,1080),255)
    scenes.append(('blank', blank, 0))
    noise = np.asarray(expression('7+2')).copy()
    rng = np.random.default_rng(72)
    yy = rng.integers(0,1080,1000); xx = rng.integers(0,960,1000)
    noise[yy,xx] = 0
    scenes.append(('noise',Image.fromarray(noise),1))
    # Rotate the whole expression independently of the page layout.
    scenes.append(('tilt_minus4',expression('7+2').rotate(-4,Image.Resampling.BICUBIC,fillcolor=255),1))
    scenes.append(('small_characters',expression('7+2',height=40),1))
    # Same three glyphs, deliberately violating the removed old geometry gates.
    loose=Image.new('L',(960,1080),255)
    for char,x,y,w,h in [('7',8,120,100,140),('+',410,500,40,100),('2',750,80,150,300)]:
        loose.paste(Image.eval(gs[char],lambda p:255-p).resize((w,h),Image.Resampling.LANCZOS),(x,y))
    scenes.append(('different_sizes_and_rows',loose,1))
    scenes.append(('touch_border',expression('7+2',x=0,y=0,height=160),1))
    scenes.append(('rotated10',expression('7+2').rotate(10,Image.Resampling.BICUBIC,fillcolor=255),1))
    # A real white 5 card completely covers the printed 7; + and 2 stay put.
    covered=scenes[0][1].copy();covered.paste(255,(160,144,365,416))
    five=Image.eval(gs['5'],lambda p:255-p)
    five=five.resize((round(240*five.width/five.height),240),Image.Resampling.LANCZOS)
    covered.paste(five,(186,160))
    covered_moved=Image.new('L',(960,1080),255);covered_moved.paste(covered,(64,24))
    scenes.extend([
        ('covered5',covered,1),('five_expression',expression('5+2'),1),
        ('covered5_dim',covered.point(lambda p:round(20+120*p/255)),1),
        ('covered5_moved',covered_moved,1),
        ('covered5_tilt',covered.rotate(4,Image.Resampling.BICUBIC,fillcolor=255),1),
        ('five_small',expression('5+2',height=40),1)])
    manifest = []
    templates=[normalize(gs[c]) for c in ['7','+','2','5']]
    for i, (name, roi, expected) in enumerate(scenes):
        bits=write_map(out/f'scene{i}.mem', roi)
        assigned,lhs=nearest_components(bits,templates)
        if bool(assigned)!=bool(expected):
            raise AssertionError(f'Source fixture component count differs: {name}')
        roi.save(out/f'{name}.png')
        if name == 'card':
            pixels=np.asarray(roi,dtype=np.uint16)
            pairs=pixels[:,0::2] | (pixels[:,1::2]<<8)
            (out/'card_gray2.mem').write_text(''.join(f'{int(p):04x}\n' for p in pairs.flat),encoding='ascii')
            moved=Image.new('L',(960,1080),255);moved.paste(roi,(64,24));moved.save(out/'card_moved.png')
            write_map(out/'card_moved.mem',moved)
            ma=np.asarray(moved,dtype=np.uint16)
            mp=ma[:,0::2]|(ma[:,1::2]<<8)
            (out/'card_moved_gray2.mem').write_text(''.join(f'{int(p):04x}\n' for p in mp.flat),encoding='ascii')
        if name=='covered5_moved':
            ma=np.asarray(roi,dtype=np.uint16);mp=ma[:,0::2]|(ma[:,1::2]<<8)
            (out/'card5_moved_gray2.mem').write_text(''.join(f'{int(p):04x}\n' for p in mp.flat),encoding='ascii')
            write_map(out/'card5_moved.mem',roi)
        manifest.append({'scene':i,'name':name,'expected':expected,'boxes':assigned,'lhs':lhs,'result':lhs+2 if assigned else 0})
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    (out/'expected.mem').write_text(''.join(f'{s[2]}\n' for s in scenes),encoding='ascii')
    (out/'expected_lhs.mem').write_text(''.join(f'{m["lhs"]:x}\n' for m in manifest),encoding='ascii')
    (out/'expected_result.mem').write_text(''.join(f'{m["result"]:02x}\n' for m in manifest),encoding='ascii')
    for name,index,shift in [('x0',0,8),('x1',1,8),('y0',2,9),('y1',3,9)]:
        (out/f'expected_{name}.mem').write_text(''.join(
            format(sum(box[index]<<(shift*k) for k,box in enumerate(m['boxes'])),f'0{6 if shift==8 else 7}x')+'\n' for m in manifest),encoding='ascii')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pdf', type=Path, default=ROOT/'assets'/'digit_recognition_card.pdf')
    parser.add_argument('--vectors', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as td:
        prefix = Path(td)/'card'
        subprocess.run(['pdftoppm','-f','1','-l','1','-singlefile','-scale-to','1600',
                        '-png',str(args.pdf),str(prefix)],check=True)
        page = Image.open(prefix.with_suffix('.png')).convert('L')
        gs, boxes = glyphs(page)
        five_prefix=Path(td)/'five'
        subprocess.run(['pdftoppm','-f','8','-l','8','-singlefile','-scale-to','1600',
                        '-png',str(args.pdf),str(five_prefix)],check=True)
        five_page=np.asarray(Image.open(five_prefix.with_suffix('.png')).convert('L'))
        _,_,stats,_=cv2.connectedComponentsWithStats((five_page<128).astype('uint8'))
        x,y,w,h,_=max(stats[1:],key=lambda s:s[4])
        gs['5']=Image.fromarray(255*(five_page[y:y+h,x:x+w]<128).astype('uint8'))
        span_rom(gs)
        templates = [normalize(gs[c]) for c in ['7','+','2','5']]
        words = [sum(int(templates[k][r,c])<<k for k in range(4)) for r in range(64) for c in range(32)]
        (ROOT/'digit_7p2_templates.mem').write_text(''.join(f'{v:x}\n' for v in words),encoding='ascii')
        nine = normalize(gs['9'],(44,64))
        (ROOT/'digit_result9.mem').write_text(''.join(f'{row_word(r):011x}\n' for r in nine),encoding='ascii')
        seven=normalize(gs['7'],(44,64))
        (ROOT/'digit_results.mem').write_text(''.join(f'{row_word(r):011x}\n' for r in np.concatenate([nine,seven])),encoding='ascii')
        info = {'source_sha256':hashlib.sha256(args.pdf.read_bytes()).hexdigest(),
                'source_page':1,'glyph_order':['7','+','2','9','-','4'],
                'rendered_boxes_xywha':boxes,'template_size':[32,64],
                'template_word_order':'2048 x 4 bits, addr={y[5:0],x[4:0]}, bits={5,2,+,7}',
                'five_source_page':8,'rendering_glyph_order':['7','+','2','5']}
        if args.vectors:
            info['scenes']=generate_vectors(page,gs,ROOT/'sim'/'digits'/'vectors')
        (ROOT/'sim'/'digits').mkdir(parents=True,exist_ok=True)
        (ROOT/'sim'/'digits'/'templates.json').write_text(json.dumps(info,indent=2),encoding='utf-8')
        preview = Image.new('RGB',(4*160,320),'white')
        for k, t in enumerate(templates):
            preview.paste(Image.fromarray(255-255*t).resize((160,320),Image.Resampling.NEAREST),(160*k,0))
        preview.save(ROOT/'sim'/'digits'/'templates.png')
        print(json.dumps(info,indent=2))


if __name__ == '__main__':
    main()
