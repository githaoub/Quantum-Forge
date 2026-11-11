"""Normalise a supplied gamepass badge into a 512 RGBA PNG.

AI image generators hand back RGB. The "transparent" checkerboard they draw is
painted pixels, not alpha, so pasting one into the store row produces a flag
square around the disc. This walks the border-connected background, keys it out,
clamps a circle so a stray speck cannot drag the crop square, and rescales the
disc to the same diameter ratio the procedural badges use.

    python scripts/prepare_gamepass_art.py --src path/to/source.jpg \\
        --dst assets/generated/gamepasses/auto_vent.png

Deterministic: no randomness, no fonts, no timestamps. Same input bytes give
the same output bytes.
"""

from __future__ import annotations

import argparse
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "assets" / "generated" / "gamepasses"

FINAL = 512
# Diameter as a fraction of the canvas, matching generate_gamepass_icons.py's
# DISC_R = 0.470. A set with drifting margins reads as sloppy at 48px.
DISC_RATIO = 0.94

# The checkerboard is neutral and mid-to-bright, but it is not two flat tones:
# a photographed or re-encoded source carries a gradient across it. Measured on
# the auto_vent source, corner samples were 206, 160, 203, 158, so the
# brightness floor is 115. The ink ring's min channel is around 15, which is
# what stops the flood at the disc edge.
SAT_MAX = 26
BRIGHT_MIN = 115


def background_mask(rgb: np.ndarray) -> np.ndarray:
    a = rgb.astype(np.int16)
    sat = a.max(axis=2) - a.min(axis=2)
    return (sat <= SAT_MAX) & (a.min(axis=2) >= BRIGHT_MIN)


def border_connected(mask: np.ndarray) -> np.ndarray:
    """4-connected flood from every border pixel, restricted to `mask`.

    Deliberately not `ImageDraw.floodfill`: that function still exists in
    Pillow 13 but returns without filling anything, so the key silently becomes
    a no-op and the checkerboard ships. Measured: it reported 0 pixels filled on
    a mask where a BFS found 388,118. A silent no-op in a keying step is worse
    than a crash, because the output still looks like an image.
    """
    h, w = mask.shape
    seen = np.zeros((h, w), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    for x in range(w):
        for y in (0, h - 1):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))

    while queue:
        y, x = queue.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    return seen


def ink_ring_radius(rgb: np.ndarray) -> float | None:
    """Radius of the outermost dark contour, in source pixels.

    Not every generator returns a disc on a checkerboard. `x2_star_matter` came
    back as a disc sitting on a dotted grey plate inside a white margin, so the
    background key removed only the white band and left the plate behind the
    circle. The disc's own ink contour is the thing to cut at, and it is the
    outermost radius whose whole circumference is dark.

    Returns None when no ring clears the threshold, so the caller can fall back
    to the radius-percentile clamp instead of cutting a hole in the art.
    """
    h, w = rgb.shape[:2]
    lum = 0.2126 * rgb[:, :, 0] + 0.7152 * rgb[:, :, 1] + 0.0722 * rgb[:, :, 2]
    cy, cx = h / 2, w / 2
    dist = np.hypot(np.arange(w)[None, :] - cx, np.arange(h)[:, None] - cy)

    bins = np.rint(dist).astype(np.int32).ravel()
    counts = np.bincount(bins)
    darks = np.bincount(bins, weights=(lum.ravel() < 80).astype(np.float64))
    with np.errstate(invalid="ignore", divide="ignore"):
        fraction = np.where(counts > 0, darks / np.maximum(counts, 1), 0.0)

    span = np.arange(fraction.size)
    usable = (span >= int(min(w, h) * 0.15)) & (span < min(w, h) // 2 - 1)
    if not usable.any():
        return None

    solid = usable & (fraction >= 0.55)
    if not solid.any():
        return None
    ring = int(span[solid].max())

    # Walk back out over the ring's anti-aliased outer edge.
    edge = ring
    while edge + 1 < fraction.size and fraction[edge + 1] >= 0.25:
        edge += 1
    return float(edge) + 2.0


def key_out(src: Path, ring_clamp: bool = False) -> tuple[Image.Image, dict[str, float | int | tuple[int, ...] | str]]:
    img = Image.open(src).convert("RGB")
    w, h = img.size
    rgb = np.asarray(img)

    candidate = background_mask(rgb)
    bg = border_connected(candidate)
    alpha = np.where(bg, 0, 255).astype(np.uint8)

    # Radial clamp. One isolated checkerboard speck that JPEG noise cut off from
    # the rest of the background survived the flood on the first pass and pulled
    # the crop square from 980 to 1070, shrinking the disc by 9%.
    ys, xs = np.nonzero(alpha > 24)
    if ys.size == 0:
        raise SystemExit(f"nothing survived keying in {src}")
    cx, cy = xs.mean(), ys.mean()
    dist = np.hypot(np.arange(w)[None, :] - cx, np.arange(h)[:, None] - cy)

    clamp_mode = "percentile"
    if ring_clamp:
        ring = ink_ring_radius(rgb)
        if ring is not None:
            r99 = ring
            clamp_mode = f"ink-ring r={ring:.0f}"
        else:
            r99 = float(np.percentile(dist[alpha > 24], 99.5))
    else:
        r99 = float(np.percentile(dist[alpha > 24], 99.5))

    outside = dist > r99 * (1.0 if clamp_mode.startswith("ink-ring") else 1.004)
    removed = int(((alpha > 0) & outside).sum())
    alpha[outside] = 0

    feathers = Image.fromarray(alpha, mode="L").filter(ImageFilter.GaussianBlur(1.1))
    rgba = img.copy()
    rgba.putalpha(feathers)

    a = np.asarray(feathers)
    ys, xs = np.nonzero(a > 24)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    diameter = max(x1 - x0 + 1, y1 - y0 + 1)
    side = int(round(diameter / DISC_RATIO))

    left = int(round(cx - side / 2))
    top = int(round(cy - side / 2))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    box = (left, top, left + side, top + side)
    if box[0] >= 0 and box[1] >= 0 and box[2] <= w and box[3] <= h:
        patch = rgba.crop(box)
        canvas.paste(patch, (0, 0), patch)
    else:
        canvas.paste(rgba, (-left, -top), rgba)

    stats = {
        "src_w": w,
        "src_h": h,
        "bg_pct": round(float(bg.mean()) * 100, 1),
        "r99": round(r99, 1),
        "clamp": clamp_mode,
        "removed": removed,
        "bbox": (int(x0), int(y0), int(x1), int(y1)),
        "diameter": int(diameter),
        "crop": int(side),
        "centre": (round(cx), round(cy)),
    }
    return canvas.resize((FINAL, FINAL), Image.Resampling.LANCZOS), stats


def report(img: Image.Image) -> None:
    arr = np.asarray(img).astype(np.float32)
    alpha = arr[:, :, 3]
    lum = 0.2126 * arr[:, :, 0] + 0.7152 * arr[:, :, 1] + 0.0722 * arr[:, :, 2]
    inside = alpha > 40
    vals = lum[inside]
    corners = [tuple(int(v) for v in arr[y, x]) for x, y in ((0, 0), (FINAL - 1, 0), (0, FINAL - 1), (FINAL - 1, FINAL - 1))]
    print(f"  corners {corners}")
    print(f"  alpha bbox {img.getbbox()} opaque {inside.mean() * 100:.1f}%")
    print(
        f"  lum p50={np.percentile(vals, 50):.0f} p95={np.percentile(vals, 95):.0f} "
        f"max={vals.max():.0f} share>120={(vals > 120).mean() * 100:.1f}%"
    )
    # The store draws badges at 48 design px on a 0.719 canvas, so 34.5 real px.
    for target in (48, 35):
        s = np.asarray(img.resize((target, target), Image.Resampling.LANCZOS)).astype(np.float32)
        keep = s[:, :, 3] > 40
        sl = (0.2126 * s[:, :, 0] + 0.7152 * s[:, :, 1] + 0.0722 * s[:, :, 2])[keep]
        print(f"  {target}px p50={np.percentile(sl, 50):.0f} share>120={(sl > 120).mean() * 100:.1f}%")


def size_strip(img: Image.Image, path: Path) -> None:
    tiles = []
    for target in (64, 48, 35):
        small = img.resize((target, target), Image.Resampling.LANCZOS)
        zoom = small.resize((target * 6, target * 6), Image.Resampling.NEAREST)
        cell = Image.new("RGBA", (zoom.width, zoom.height), (32, 34, 42, 255))
        cell.alpha_composite(zoom)
        tiles.append(cell)
    gap = 18
    width = sum(t.width for t in tiles) + gap * (len(tiles) - 1)
    height = max(t.height for t in tiles)
    sheet = Image.new("RGBA", (width, height), (32, 34, 42, 255))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, height - t.height))
        x += t.width + gap
    sheet.convert("RGB").save(path)
    print(f"  wrote {path.relative_to(REPO_ROOT)}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True, type=Path, help="source image, RGB with a baked checkerboard")
    ap.add_argument("--dst", type=Path, help="output PNG (default assets/generated/gamepasses/<stem>.png)")
    ap.add_argument("--no-preview", action="store_true", help="skip the 64/48/35 size strip")
    ap.add_argument(
        "--ring-clamp",
        action="store_true",
        help="cut at the disc's own ink contour instead of the alpha percentile. "
        "Use when the generator drew the disc on a patterned plate rather than a plain checkerboard.",
    )
    args = ap.parse_args(argv)

    src = args.src if args.src.is_absolute() else (REPO_ROOT / args.src)
    if not src.is_file():
        return int(bool(sys.stderr.write(f"missing source: {src}\n")) or 1)

    dst = args.dst or (OUT_DIR / f"{src.stem.lower().replace('-', '_')}.png")
    if not dst.is_absolute():
        dst = REPO_ROOT / dst
    dst.parent.mkdir(parents=True, exist_ok=True)

    print(f"{src.name}: {Image.open(src).size[0]}x{Image.open(src).size[1]} {Image.open(src).format}")
    img, stats = key_out(src, ring_clamp=args.ring_clamp)
    print(
        f"  keyed {stats['bg_pct']}% background | clamp={stats['clamp']} r={stats['r99']} "
        f"removed {stats['removed']} stray px\n"
        f"  disc bbox {stats['bbox']} diameter={stats['diameter']} crop={stats['crop']} centre={stats['centre']}"
    )

    img.save(dst)
    print(f"  wrote {dst.relative_to(REPO_ROOT)} {dst.stat().st_size} bytes")
    report(img)
    if not args.no_preview:
        size_strip(img, dst.with_name(f"_{dst.stem}_at_size.png"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
