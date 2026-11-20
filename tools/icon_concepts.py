#!/usr/bin/env python3
"""Render four store-icon concepts from the game's own vector shapes.

  python3 tools/icon_concepts.py            -> store/taptap/icon_concepts/icon_<A-D>_{1024,512}.png
                                               + sheet.png (full size + phone-size preview in a rounded mask)

Shapes follow the in-game drawing code: the player ship (scripts/player.gd _draw), the
NEON HYDRA head and hex plates (scripts/enemy.gd boss5) and the round enemy bullets.
Everything is drawn at 2048 px with additive neon glow, then downsampled.
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "store" / "taptap" / "icon_concepts"
S = 2048

CYAN = (90, 242, 255)
PINK = (255, 80, 190)
GOLD = (255, 209, 51)
ORANGE = (255, 128, 50)
WHITE = (235, 255, 255)
RED = (255, 77, 51)
HULL = (15, 30, 51)


# ---------- helpers ----------
def gradient(c0, c1, centre=(0.5, 0.5), radius=0.75):
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S
    d = np.sqrt((x - centre[0]) ** 2 + (y - centre[1]) ** 2) / radius
    t = np.clip(d, 0, 1)[..., None] ** 1.2
    img = np.array(c0, np.float32) * (1 - t) + np.array(c1, np.float32) * t
    return img


def grid(img, step=256, colour=(60, 110, 170), alpha=0.10, width=6, offset=(0, 0)):
    layer = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(layer)
    for i in range(-2, S // step + 3):
        x = i * step + offset[0]
        y = i * step + offset[1]
        d.line([(x, 0), (x, S)], fill=255, width=width)
        d.line([(0, y), (S, y)], fill=255, width=width)
    m = np.asarray(layer, np.float32)[..., None] / 255 * alpha
    return img * (1 - m) + np.array(colour, np.float32) * m


class Light:
    """An additive neon layer: draw shapes, then bloom() adds them with glow."""

    def __init__(self):
        self.im = Image.new("RGB", (S, S), (0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def poly(self, pts, outline, width, fill=None):
        if fill is not None:
            self.d.polygon(pts, fill=fill)
        self.d.line(pts + [pts[0]], fill=outline, width=width, joint="curve")
        for p in pts:  # round the corners
            r = width / 2
            self.d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=outline)

    def circle(self, c, r, fill=None, outline=None, width=0):
        self.d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=fill, outline=outline, width=width)

    def line(self, a, b, colour, width):
        self.d.line([a, b], fill=colour, width=width)
        for p in (a, b):
            r = width / 2
            self.d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=colour)


def bloom(base, light: Light, strength=1.0):
    L = np.asarray(light.im, np.float32)
    out = base + L
    for r, k in ((10, 0.9), (34, 0.75), (110, 0.6)):
        out += np.asarray(light.im.filter(ImageFilter.GaussianBlur(r)), np.float32) * k * strength
    return out


def occlude(base, pts_or_circle, colour):
    """Paint an opaque dark shape onto the base (hull fills sit under the glow)."""
    im = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    if isinstance(pts_or_circle, tuple) and len(pts_or_circle) == 2 and isinstance(pts_or_circle[1], (int, float)):
        (c, r) = pts_or_circle
        d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=colour)
    else:
        d.polygon(pts_or_circle, fill=colour)
    return np.asarray(im, np.float32)


def rot(pts, ang, centre):
    ca, sa = math.cos(ang), math.sin(ang)
    return [(centre[0] + x * ca - y * sa, centre[1] + x * sa + y * ca) for x, y in pts]


def ship_pts(c, r, ang):
    # player.gd: (r+6,0), (-0.7r, 0.95r), (-0.35r, 0), (-0.7r, -0.95r); r+6 ~ 1.4r at icon scale
    return rot([(r * 1.35, 0), (-r * 0.75, r * 0.98), (-r * 0.32, 0), (-r * 0.75, -r * 0.98)], ang, c)


def draw_ship(base, light, c, r, ang, colour=CYAN, stroke=None):
    stroke = stroke or max(8, int(r * 0.13))
    pts = ship_pts(c, r, ang)
    base = occlude(base, pts, HULL)
    light.poly(pts, colour, stroke)
    light.circle(c, r * 0.17, fill=WHITE)
    return base


def bullet(light, c, r, colour):
    light.circle(c, r, fill=tuple(int(v * 0.55) for v in colour))
    light.circle(c, r * 0.62, fill=colour)
    light.circle(c, r * 0.32, fill=(255, 255, 255))


def tonemap(arr):
    """Scale over-bright pixels back instead of clipping each channel, so neon keeps its hue
    (per-channel clipping turns every bright stroke white); a little white core remains."""
    m = arr.max(axis=2, keepdims=True)
    scaled = arr * np.minimum(1.0, 255.0 / np.maximum(m, 1e-3))
    return 0.8 * scaled + 0.2 * np.clip(arr, 0, 255)


def finish(arr, name):
    img = Image.fromarray(np.clip(tonemap(arr), 0, 255).astype(np.uint8))
    # gentle vignette
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S
    v = 1 - 0.35 * np.clip(np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2) / 0.72, 0, 1) ** 2
    img = Image.fromarray(np.clip(np.asarray(img, np.float32) * v[..., None], 0, 255).astype(np.uint8))
    OUT.mkdir(parents=True, exist_ok=True)
    big = img.resize((1024, 1024), Image.LANCZOS)
    big.save(OUT / f"icon_{name}_1024.png", optimize=True)
    img.resize((512, 512), Image.LANCZOS).save(OUT / f"icon_{name}_512.png", optimize=True)
    return big


# ---------- concepts ----------
def concept_a():
    """Hero close-up: the ship fills the frame, firing a twin stream to the corner."""
    base = gradient((22, 70, 110), (4, 8, 26), centre=(0.42, 0.58), radius=0.85)
    base = grid(base, step=340, alpha=0.10, offset=(60, 120))
    L = Light()
    ang = -math.pi / 4
    c = (S * 0.43, S * 0.58)
    # bullet stream to the top-right corner
    for i, t in enumerate((0.0, 1.0, 2.0)):
        p = (c[0] + (900 + t * 300) * math.cos(ang), c[1] + (900 + t * 300) * math.sin(ang))
        bullet(L, p, 70 - i * 10, CYAN)
    # dash streak behind
    for k, w in ((1.0, 70), (1.6, 40)):
        a = (c[0] - 330 * math.cos(ang), c[1] - 330 * math.sin(ang))
        b = (c[0] - (330 + 520 * k) * math.cos(ang), c[1] - (330 + 520 * k) * math.sin(ang))
        L.line(a, b, (20, 70, 90), w)
    # one magenta enemy shot for colour contrast
    bullet(L, (S * 0.80, S * 0.80), 92, PINK)
    base = draw_ship(base, L, c, 560, ang, stroke=78)
    return finish(bloom(base, L, 1.05), "A")


def concept_b():
    """Boss duel: the gold NEON HYDRA's head looms from the top-right, the cyan ship answers."""
    base = gradient((52, 18, 72), (6, 4, 20), centre=(0.66, 0.34), radius=0.9)
    base = grid(base, step=300, colour=(120, 80, 170), alpha=0.07)
    L = Light()
    face = math.radians(135)  # pointing down-left at the ship
    hc = (S * 0.66, S * 0.34)
    R = 560
    # three body plates trailing off the top-right corner
    for i, (dist, sr) in enumerate(((820, 300), (1260, 260), (1660, 230))):
        sp = (hc[0] - dist * math.cos(face), hc[1] - dist * math.sin(face))
        hexp = [(sp[0] + sr * math.cos(face + k * math.pi / 3), sp[1] + sr * math.sin(face + k * math.pi / 3)) for k in range(6)]
        base = occlude(base, hexp, (34, 27, 6))
        L.poly(hexp, tuple(int(v * 0.75) for v in GOLD), 46)
        L.circle(sp, 44, fill=tuple(int(v * 0.8) for v in GOLD))
    # head (enemy.gd boss5 polygon, a little broader)
    hd = rot([(R * 1.3, 0), (R * 0.55, R * 0.95), (-R * 0.8, R * 0.85), (-R * 0.5, 0), (-R * 0.8, -R * 0.85), (R * 0.55, -R * 0.95)], face, hc)
    base = occlude(base, hd, (44, 34, 6))
    L.poly(hd, GOLD, 80)
    for s in (-1, 1):
        # fangs: thick hooked mandibles curling toward the snout
        pts = rot([(R * 1.05, s * R * 0.50), (R * 1.50, s * R * 0.50), (R * 1.78, s * R * 0.14)], face, hc)
        L.line(pts[0], pts[1], GOLD, 92)
        L.line(pts[1], pts[2], GOLD, 92)
        eye = rot([(R * 0.28, s * R * 0.42)], face, hc)[0]
        L.circle(eye, 96, fill=RED)
        L.circle(eye, 40, fill=(255, 235, 210))
    # the player: smaller, bright, aiming into the jaws, shots in flight
    sc = (S * 0.22, S * 0.79)
    aim = math.atan2(hc[1] - sc[1], hc[0] - sc[0])
    for t in (0.30, 0.43):
        bullet(L, (sc[0] + (hc[0] - sc[0]) * t, sc[1] + (hc[1] - sc[1]) * t), 58, CYAN)
    base = draw_ship(base, L, sc, 235, aim, stroke=58)
    return finish(bloom(base, L, 1.0), "B")


def concept_c():
    """Emblem: the ship inside a bold hexagonal arena ring, bullets orbiting the ring."""
    base = gradient((40, 30, 90), (5, 6, 24), centre=(0.5, 0.5), radius=0.75)
    L = Light()
    c = (S / 2, S / 2 + 20)
    ring_r = 760
    hexp = [(c[0] + ring_r * math.cos(math.pi / 6 + k * math.pi / 3), c[1] + ring_r * math.sin(math.pi / 6 + k * math.pi / 3)) for k in range(6)]
    L.poly(hexp, PINK, 70)
    inner = [(c[0] + (ring_r - 150) * math.cos(math.pi / 6 + k * math.pi / 3), c[1] + (ring_r - 150) * math.sin(math.pi / 6 + k * math.pi / 3)) for k in range(6)]
    L.poly(inner, (90, 30, 80), 22)
    # orbiting bullets at three vertices
    for k in (0, 2, 4):
        bullet(L, hexp[k], 96, CYAN)
    base = draw_ship(base, L, (c[0], c[1] + 0.3 * 430), 430, -math.pi / 2, stroke=72)
    return finish(bloom(base, L, 1.0), "C")


def concept_d():
    """Bullet storm: the ship at the eye of a spiral of enemy fire, mid-dash."""
    base = gradient((16, 26, 60), (3, 4, 16), centre=(0.5, 0.5), radius=0.8)
    L = Light()
    c = (S * 0.5, S * 0.52)
    # two-arm spiral of bullets, growing outward
    for arm, col in ((0, PINK), (math.pi, ORANGE)):
        for i in range(7):
            t = i / 6
            a = arm + 0.6 + t * 2.6
            r = 520 + t * 640
            bullet(L, (c[0] + r * math.cos(a), c[1] + r * math.sin(a)), 60 + t * 60, col)
    # dash after-images
    ang = -math.pi / 3
    for k, f in ((1.4, 0.20),):
        off = (-k * 170 * math.cos(ang), -k * 170 * math.sin(ang))
        ghost = ship_pts((c[0] + off[0], c[1] + off[1]), 330, ang)
        L.poly(ghost, tuple(int(v * f) for v in CYAN), 44)
    base = draw_ship(base, L, c, 330, ang, stroke=60)
    return finish(bloom(base, L, 1.0), "D")


def sheet(icons):
    """Full-size previews on top; below, each icon masked and shrunk to phone sizes."""
    W, cell = 4 * 420 + 50, 420
    out = Image.new("RGB", (W, 760), (24, 26, 34))
    d = ImageDraw.Draw(out)
    for i, (name, im) in enumerate(icons):
        x = 30 + i * cell
        out.paste(im.resize((380, 380), Image.LANCZOS), (x, 30))
        d.text((x, 420), f"{name}", fill=(220, 220, 220))
        for j, sz in enumerate((168, 96, 48)):
            small = im.resize((sz, sz), Image.LANCZOS)
            m = Image.new("L", (sz, sz), 0)
            ImageDraw.Draw(m).rounded_rectangle([0, 0, sz - 1, sz - 1], radius=int(sz * 0.22), fill=255)
            xx = x + [0, 190, 300][j]
            out.paste(small, (xx, 460 + (168 - sz) // 2), m)
    out.save(OUT / "sheet.png")


if __name__ == "__main__":
    icons = [("A", concept_a()), ("B", concept_b()), ("C", concept_c()), ("D", concept_d())]
    sheet(icons)
    print("written to", OUT)
