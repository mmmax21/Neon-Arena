#!/usr/bin/env python3
"""Finish the TapTap store images from tests/key_art.gd renders and capture frames.

Usage: python3 tools/store_art.py <keyart-dir> <capture-dir> <out-dir>

keyart-dir: raw_wide.png (3840x2160), raw_square.png (2880x2880), raw_tall.png (1200x1800),
            raw_icon.png (1024x1024) from tests/key_art.gd (tiles stitched by this script).
capture-dir: frames/NNNNN.jpg and shot_*.png from tests/store_capture.gd.

Adds a bloom pass and the NEON ARENA title (the game's bundled Noto Sans SC, SIL OFL),
then writes every size the TapTap store asks for. Promo images carry no text but the title.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "fonts" / "NotoSansSC-Medium.subset.otf"
TITLE = "NEON ARENA"
CYAN = (90, 242, 255)
PINK = (255, 90, 190)
MAX_BYTES = 2_000_000  # mini-game material limit per image


def stitch(keyart: Path, name: str) -> Image.Image:
    raw = keyart / f"raw_{name}.png"
    meta = keyart / f"raw_{name}_tiles.json"
    if meta.exists():
        d = json.loads(meta.read_text())
        img = Image.new("RGB", tuple(d["size"]))
        for x, y, p in d["tiles"]:
            img.paste(Image.open(p).convert("RGB"), (int(x), int(y)))
        return img
    return Image.open(raw).convert("RGB")


def bloom(img: Image.Image, strength=0.9) -> Image.Image:
    """Screen-blend blurred copies over the image: the neon glow the engine draws by hand."""
    w, h = img.size
    out = img
    for div, amount in ((24, 0.55), (60, 0.45)):
        small = img.resize((max(1, w // 8), max(1, h // 8)), Image.BILINEAR)
        glow = small.filter(ImageFilter.GaussianBlur(w / div / 8)).resize((w, h), Image.BILINEAR)
        glow = Image.eval(glow, lambda v, a=amount * strength: min(255, int(v * a * 1.6)))
        out = ImageChops.screen(out, glow)
    return out


def vignette(img: Image.Image, amount=0.45) -> Image.Image:
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((-w * 0.25, -h * 0.25, w * 1.25, h * 1.25), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(min(w, h) * 0.18))
    dark = Image.new("RGB", (w, h), (3, 3, 10))
    return Image.composite(img, Image.blend(img, dark, amount), mask)


def title_layer(size, text_h: int, centre, tracking=0.12, max_w=None):
    """Returns an RGBA layer with the neon title centred at `centre`, cap height ~text_h,
    shrunk if needed so letters plus glow fit within max_w (default: 90% of the width)."""
    w, h = size
    max_w = max_w or w * 0.9
    while True:
        font = ImageFont.truetype(str(FONT), int(text_h * 1.38))
        advances = [font.getlength(c) for c in TITLE]
        spacing = text_h * tracking
        total = sum(advances) + spacing * (len(TITLE) - 1)
        if total + text_h * 0.5 <= max_w or text_h < 8:
            break
        text_h = int(text_h * 0.94)
    stroke = max(2, text_h // 22)
    x0 = centre[0] - total / 2
    y0 = centre[1]

    def draw_text(fill, stroke_fill=None, sw=0, offset=(0, 0)):
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        x = x0 + offset[0]
        for c, adv in zip(TITLE, advances):
            d.text((x, y0 + offset[1]), c, font=font, fill=fill, anchor="lm",
                   stroke_width=sw, stroke_fill=stroke_fill or fill)
            x += adv + spacing
        return layer

    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # Wide soft glows: magenta shadow below-right, cyan halo all round.
    for color, blur, alpha, off in ((PINK, text_h * 0.35, 150, (text_h * 0.05, text_h * 0.07)),
                                     (CYAN, text_h * 0.45, 170, (0, 0)),
                                     (CYAN, text_h * 0.15, 220, (0, 0))):
        g = draw_text(color + (alpha,), sw=stroke * 2, offset=off).filter(ImageFilter.GaussianBlur(blur))
        base = Image.alpha_composite(base, g)
    # Crisp letters: cyan rim, near-white core.
    base = Image.alpha_composite(base, draw_text(CYAN + (255,), sw=stroke))
    base = Image.alpha_composite(base, draw_text((225, 255, 255, 255), sw=max(1, stroke // 3)))
    return base


def with_title(img: Image.Image, text_h: int, centre, scrim_h=None) -> Image.Image:
    img = img.convert("RGBA")
    if scrim_h:
        # Gentle darkening behind the title so bullets don't fight the letters.
        w, h = img.size
        scrim = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(scrim)
        top = int(centre[1] - scrim_h / 2)
        for i in range(int(scrim_h)):
            a = int(110 * (1 - abs(i - scrim_h / 2) / (scrim_h / 2)) ** 0.7)
            d.line([(0, top + i), (w, top + i)], fill=a)
        img = Image.composite(Image.new("RGBA", img.size, (4, 4, 12, 255)), img, scrim)
    return Image.alpha_composite(img, title_layer(img.size, text_h, centre)).convert("RGB")


def save_jpg(img: Image.Image, path: Path, limit=MAX_BYTES):
    for q in (93, 90, 87, 84, 80, 75):
        img.save(path, "JPEG", quality=q, optimize=True, progressive=True)
        if path.stat().st_size <= limit:
            return q
    return q


def main():
    keyart, capture, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    report = {}

    # 16:9 promo (1920x1080) and the 460x215 PC cover cut from the same art.
    wide = vignette(bloom(stitch(keyart, "wide"))).resize((1920, 1080), Image.LANCZOS)
    promo = with_title(wide, 118, (960, 128), scrim_h=230)
    report["promo_16x9_1920x1080.jpg"] = save_jpg(promo, out / "promo_16x9_1920x1080.jpg")
    cover = wide.crop((0, 60, 1920, 60 + 897)).resize((460, 215), Image.LANCZOS)
    cover = with_title(cover, 34, (230, 36), scrim_h=64)
    report["cover_460x215.jpg"] = save_jpg(cover, out / "cover_460x215.jpg")

    # 1:1 promo (1440x1440), same scene re-framed.
    square = vignette(bloom(stitch(keyart, "square"))).resize((1440, 1440), Image.LANCZOS)
    report["promo_1x1_1440x1440.jpg"] = save_jpg(with_title(square, 128, (720, 150), scrim_h=250),
                                                out / "promo_1x1_1440x1440.jpg")

    # 600x900 vertical PC cover.
    tall = vignette(bloom(stitch(keyart, "tall"))).resize((600, 900), Image.LANCZOS)
    report["cover_600x900.jpg"] = save_jpg(with_title(tall, 62, (300, 70), scrim_h=130),
                                          out / "cover_600x900.jpg")

    # Icon: concept C ("neon emblem") from tools/icon_concepts.py; run that first.
    # Square corners, dark navy (not black/white/transparent), no text.
    icon = Image.open(out / "icon_concepts" / "icon_C_1024.png").convert("RGB")
    icon.resize((512, 512), Image.LANCZOS).save(out / "icon_512.png", optimize=True)
    icon.save(out / "icon_1024.png", optimize=True)

    # Transparent title logo for PC pages (1280 wide).
    logo = title_layer((2000, 420), 150, (1000, 210), max_w=1900)
    logo = logo.crop(logo.getbbox())
    logo.thumbnail((1280, 720), Image.LANCZOS)
    if logo.width < 1280:
        logo = logo.resize((1280, round(logo.height * 1280 / logo.width)), Image.LANCZOS)
    logo.save(out / "logo_1280.png", optimize=True)

    # Screenshots: real 1920x1080 gameplay, in store order.
    picks = [("frames", 60), ("frames", 420), ("shot", "countdown"), ("frames", 2400),
             ("shot", "beacon_grid"), ("shot", "hydra"), ("shot", "cards")]
    for i, (kind, key) in enumerate(picks, 1):
        src = capture / ("frames/%05d.jpg" % key if kind == "frames" else f"shot_{key}.png")
        img = Image.open(src).convert("RGB")
        report[f"screenshot_{i}.jpg"] = save_jpg(img, out / f"screenshot_{i}.jpg")

    for p in sorted(out.iterdir()):
        if p.suffix in (".jpg", ".png"):
            with Image.open(p) as im:
                print(f"{p.name:28s} {im.size[0]}x{im.size[1]:<6d} {p.stat().st_size / 1e6:5.2f} MB"
                      + (f"  q{report[p.name]}" if p.name in report else ""))


if __name__ == "__main__":
    main()
