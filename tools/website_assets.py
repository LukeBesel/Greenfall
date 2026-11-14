#!/usr/bin/env python3
"""Regenerate the website images from game screenshots.

Usage (from the repo root):
    python3 tools/website_assets.py [--src /path/to/screenshots]

What it does
  * Reads the SHOTS list below (source screenshot, optional crop, alt text).
  * Writes website/assets/img/<name>.webp (max 1600 px wide, <= 250 KB)
    and website/assets/img/<name>-640.webp (thumbnail).
  * If <src>/steam/ exists (Steam capsules and store screenshots), every image
    in it is added: files with "capsule" or "header" in the name go to
    website/assets/steam/, the rest are appended to the gallery.
  * Builds the favicon set from a crop of Lumi's face, the Open Graph image,
    and website/assets/press/greenfall-screenshots.zip (JPEG, for press).
  * Rewrites the gallery between <!-- gallery:start --> and <!-- gallery:end -->
    in website/index.html so new shots appear without hand-editing HTML.

To change the images: edit SHOTS, re-run, check the site, commit.
Needs Pillow with WebP support (pip install pillow).
"""
from __future__ import annotations

import argparse
import html
import io
import re
import sys
import zipfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "website"
IMG = WEB / "assets" / "img"
STEAM_OUT = WEB / "assets" / "steam"
PRESS = WEB / "assets" / "press"
DEFAULT_SRC = ROOT / "screenshots"
if not (DEFAULT_SRC / "pk4_0.png").exists():  # main checkout has the PNGs; worktrees may not
    DEFAULT_SRC = Path("/home/user/Greenfall/screenshots")

MAX_W = 1600
THUMB_W = 640
MAX_BYTES = 250 * 1024
LETTERBOX = (0, 72, 1280, 648)  # cinematic frames: drop the black bars and the skip hint

# name, source (relative to --src), crop box or None, alt text, in_gallery
# Keep the gallery count at 11, 14, 17... so the 3-column grid (first shot 2x2) has no gaps.
SHOTS = [
    ("lumi-scoop", "pk4_0.png", None,
     "Lumi, a small white robot with big glowing blue eyes, fires a tractor beam at junk in a ruined town square", True),
    ("pickup-lasers", "pk5_0.png", None,
     "Lumi pulls bottles and cans out of the rubble with crackling pickup lasers", True),
    ("salvage-surge", "g2_surge.png", None,
     "A pillar of golden light marks a Salvage Surge hex where every piece of junk is worth triple", True),
    ("command-view", "g_command.png", None,
     "Command view: an overhead map of the district split into hexes, with robot crews assigned to clean and plant", True),
    ("survey-globe", "g_globe.png", None,
     "Lumi holds up a hologram of the planet showing how much of it has been reclaimed, next to a list of rocket destinations", True),
    ("future-city", "fut_day.png", None,
     "A restored street: clean paving, murals, string lights and bright towers rising out of the haze", True),
    ("future-night", "fut_night.png", None,
     "The restored town at night under rain, lit by a beacon and glowing signs", True),
    ("robot-crew", "g_robots.png", None,
     "Lumi at the home base with two little helper robots and a strip of cleaned road", False),
    ("robot-tiers", "robots_v2_it3_mk4.png", None,
     "Upgraded Mk IV robots with white shells, orange trim and teal tractor beams lifting a rusty crate", True),
    ("rocket-pad", "rocket/launch_1_pad_at_rest.png", LETTERBOX,
     "A sleek white rocket waits on a floating launch pad above a junk-filled plaza decorated with bunting", True),
    ("rocket-ignition", "rocket/launch_4_ignition.png", LETTERBOX,
     "Steam billows around the rocket as its engines ignite under the IGNITION sign", True),
    ("rocket-arrival", "rocket/arrive_3_aurora_exits.png", LETTERBOX,
     "Lumi steps off the rocket's landing ring at a new base", True),
    ("junk-street", "g_street.png", None,
     "A street buried in bags, bottles and paper in front of a faded noodle shop mural", False),
    # HUD-free crops for the hero slideshow (not in the gallery).
    ("hero-lumi", "pk4_0.png", (250, 190, 958, 588), "Lumi fires a tractor beam at junk", False),
    ("hero-surge", "g2_surge.png", (255, 190, 955, 584), "A Salvage Surge light pillar over a junk field", False),
]

FAVICON_CROP = ("pk4_0.png", (540, 345, 720, 525))
OG_CROP = ("pk4_0.png", (390, 190, 910, 590))


def fit_webp(im: Image.Image, width: int, path: Path, max_bytes: int = MAX_BYTES) -> int:
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    for q in (88, 84, 80, 76, 70, 65, 60, 55, 50):
        buf = io.BytesIO()
        im.save(buf, "WEBP", quality=q, method=6)
        if buf.tell() <= max_bytes:
            break
    path.write_bytes(buf.getvalue())
    return buf.tell()


def load(src: Path, rel: str, crop) -> Image.Image:
    im = Image.open(src / rel).convert("RGB")
    if crop:
        crop = (crop[0], crop[1], min(crop[2], im.width), min(crop[3], im.height))
        im = im.crop(crop)
    return im


def favicons(src: Path) -> None:
    rel, box = FAVICON_CROP
    face = load(src, rel, box)
    for size, name in ((32, "favicon-32.png"), (180, "apple-touch-icon.png"), (512, "icon-512.png")):
        out = face.resize((size, size), Image.LANCZOS)
        if name != "apple-touch-icon.png":  # round icon with transparent corners
            mask = Image.new("L", (size * 4, size * 4), 0)
            ImageDraw.Draw(mask).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
            out = out.convert("RGBA")
            out.putalpha(mask.resize((size, size), Image.LANCZOS))
        out.save(WEB / name if name != "icon-512.png" else WEB / "assets" / "brand" / name)
    face.resize((48, 48), Image.LANCZOS).save(WEB / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])


def og_image(src: Path) -> None:
    """1200x630 share card: wordmark and tagline on the left, Lumi on the right."""
    rel, box = OG_CROP
    W, H = 1200, 630
    card = Image.new("RGB", (W, H), (20, 17, 18))
    pic = load(src, rel, box)
    pic = pic.resize((H * pic.width // pic.height, H), Image.LANCZOS)
    x0 = W - pic.width
    left = Image.new("L", pic.size, 255)
    d = ImageDraw.Draw(left)
    for x in range(260):  # fade the left edge into the background
        d.line([(x, 0), (x, H)], fill=int(255 * x / 260))
    bottom = Image.new("L", pic.size, 255)
    d = ImageDraw.Draw(bottom)
    for y in range(120):  # and the bottom edge
        d.line([(0, H - 1 - y), (pic.width, H - 1 - y)], fill=int(255 * y / 120))
    fade = ImageChops.multiply(left, bottom)
    card.paste(pic, (x0, 0), fade)
    logo = WEB / "assets" / "brand" / "logo-1200.png"
    if logo.exists():
        lg = Image.open(logo).convert("RGBA")
        lg = lg.resize((520, round(lg.height * 520 / lg.width)), Image.LANCZOS)
        card.paste(lg, (64, 220), lg)
    d = ImageDraw.Draw(card)
    try:
        f = ImageFont.truetype("/usr/share/fonts/opentype/inter/InterDisplay-Light.otf", 40)
    except OSError:
        f = ImageFont.load_default()
    d.text((66, 320), "One small robot.", font=f, fill=(230, 230, 222))
    d.text((66, 370), "One very big cleanup.", font=f, fill=(158, 219, 168))
    d.line([(66, 448), (130, 448)], fill=(255, 179, 66), width=2)
    card.save(WEB / "assets" / "og-image.jpg", quality=86, optimize=True, progressive=True)


def gallery_html(items) -> str:
    rows = []
    for name, alt in items:
        a = html.escape(alt, quote=True)
        rows.append(
            f'        <li><a class="shot" href="assets/img/{name}.webp" data-lightbox>'
            f'<img src="assets/img/{name}-640.webp" alt="{a}" width="640" height="360" loading="lazy" decoding="async"></a></li>'
        )
    return "\n".join(rows)


def rewrite_gallery(items) -> None:
    index = WEB / "index.html"
    if not index.exists():
        return
    text = index.read_text()
    new = re.sub(r"<!-- gallery:start -->.*?<!-- gallery:end -->",
                 lambda m: "<!-- gallery:start -->\n" + gallery_html(items) + "\n<!-- gallery:end -->",
                 text, flags=re.S)
    if new != text:
        index.write_text(new)
        print("index.html gallery updated")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", type=Path, default=DEFAULT_SRC, help="screenshots folder")
    args = ap.parse_args()
    src: Path = args.src
    IMG.mkdir(parents=True, exist_ok=True)
    PRESS.mkdir(parents=True, exist_ok=True)

    shots = list(SHOTS)
    steam = src / "steam"
    if steam.is_dir():
        STEAM_OUT.mkdir(parents=True, exist_ok=True)
        for f in sorted(steam.iterdir()):
            if f.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp"):
                continue
            stem = re.sub(r"[^a-z0-9]+", "-", f.stem.lower()).strip("-")
            if "capsule" in stem or "header" in stem:
                im = Image.open(f).convert("RGBA" if f.suffix.lower() == ".png" else "RGB")
                fit_webp(im.convert("RGB"), MAX_W, STEAM_OUT / f"{stem}.webp")
                print(f"steam art  {stem}.webp")
            else:
                shots.append((f"steam-{stem}", f"steam/{f.name}", None,
                              "Greenfall store screenshot: " + f.stem.replace("_", " "), True))

    gallery, press = [], []
    for name, rel, crop, alt, in_gallery in shots:
        if not (src / rel).exists():
            print(f"missing    {rel} (skipped)", file=sys.stderr)
            continue
        im = load(src, rel, crop)
        big = fit_webp(im, MAX_W, IMG / f"{name}.webp")
        small = fit_webp(im, THUMB_W, IMG / f"{name}-640.webp", 60 * 1024)
        print(f"{name:18s} {im.width}x{im.height}  {big // 1024:4d} KB  thumb {small // 1024} KB")
        if in_gallery:
            gallery.append((name, alt))
            press.append((name, im))

    with zipfile.ZipFile(PRESS / "greenfall-screenshots.zip", "w", zipfile.ZIP_STORED) as z:
        for name, im in press:
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=85, optimize=True)
            z.writestr(f"greenfall-{name}.jpg", buf.getvalue())
        for logo in sorted((WEB / "assets" / "brand").glob("*")):
            z.write(logo, f"logo/{logo.name}")
    print(f"press zip  {(PRESS / 'greenfall-screenshots.zip').stat().st_size // 1024} KB")

    favicons(src)
    og_image(src)
    rewrite_gallery(gallery)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
