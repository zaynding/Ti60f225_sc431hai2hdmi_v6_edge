"""Synthetic scenes for shape recognition: filled shapes on plain / textured backgrounds,
camera-like noise, optional sawtooth geometry error, then cv2.Canny -> edge map."""
import numpy as np, cv2, math

W, H = 1920, 1080
CROP_X0, CROP_W = 480, 960          # displayed crop (source x 480..1439)

def regular_polygon(cx, cy, r, n, rot):
    return np.array([[cx + r*math.cos(rot + 2*math.pi*k/n), cy + r*math.sin(rot + 2*math.pi*k/n)] for k in range(n)])

def draw_shape(img, kind, cx, cy, size, rot, color, aspect=1.0):
    """size = characteristic radius in px (circumradius for polygons, semi-major for ellipse)."""
    if kind == 'circle':
        cv2.circle(img, (int(cx), int(cy)), int(size), color, -1, cv2.LINE_AA)
    elif kind == 'ellipse':
        cv2.ellipse(img, (int(cx), int(cy)), (int(size), int(size/aspect)), math.degrees(rot), 0, 360, color, -1, cv2.LINE_AA)
    elif kind == 'square':
        p = regular_polygon(cx, cy, size, 4, rot + math.pi/4)
        cv2.fillConvexPoly(img, np.round(p*16).astype(np.int32), color, cv2.LINE_AA, 4)
    elif kind == 'rect':
        a, b = size, size/aspect
        c, s = math.cos(rot), math.sin(rot)
        p = np.array([[cx + x*c - y*s, cy + x*s + y*c] for x, y in [(-a,-b),(a,-b),(a,b),(-a,b)]])
        cv2.fillConvexPoly(img, np.round(p*16).astype(np.int32), color, cv2.LINE_AA, 4)
    elif kind == 'triangle':
        p = regular_polygon(cx, cy, size, 3, rot)
        # aspect != 1 -> stretch along rot axis (isosceles/scalene look)
        if aspect != 1.0:
            c, s = math.cos(rot), math.sin(rot)
            q = p - [cx, cy]
            u = q[:,0]*c + q[:,1]*s; v = -q[:,0]*s + q[:,1]*c
            v = v/aspect
            p = np.stack([cx + u*c - v*s, cy + u*s + v*c], 1)
        cv2.fillConvexPoly(img, np.round(p*16).astype(np.int32), color, cv2.LINE_AA, 4)

def render(shapes, bg='plain', seed=0, saw_amp=0, saw_period=40, noise=3.0, contrast=60):
    rng = np.random.default_rng(seed)
    if bg == 'plain':
        img = np.full((H, W, 3), 225, np.uint8)
    else:  # wood-like texture
        base = rng.normal(0, 1, (H//8, W//8)).astype(np.float32)
        base = cv2.resize(base, (W, H), interpolation=cv2.INTER_CUBIC)
        stripes = np.sin(np.arange(H)[:, None]/9.0 + 4*base)[:, :, None]*18
        img = np.clip(150 + stripes + np.array([20, 0, -25]), 0, 255).astype(np.uint8)
    for (kind, cx, cy, size, rot, aspect) in shapes:
        col = tuple(int(c) for c in rng.integers(30, 90, 3)) if bg == 'plain' else (40, 60, 200)
        draw_shape(img, kind, cx, cy, size, rot, col, aspect)
    if saw_amp:
        out = np.empty_like(img)
        for y in range(H):
            sh = int(round(saw_amp * ((y % saw_period) / saw_period - 0.5)))
            out[y] = np.roll(img[y], sh, axis=0)
        img = out
    img = np.clip(img.astype(np.float32) + rng.normal(0, noise, img.shape), 0, 255).astype(np.uint8)
    return img

def edges(img, lo=40, hi=90):
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    g = cv2.GaussianBlur(g, (3, 3), 0)
    return cv2.Canny(g, lo, hi) > 0

def crop_edges(e):
    return e[:, CROP_X0:CROP_X0 + CROP_W]
