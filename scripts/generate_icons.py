#!/usr/bin/env python3
"""Generate every icon the game needs, locally, with no network and no Studio.

The blade catalogue is not duplicated here: this script parses
`src/shared/BladeRegistry.luau` and draws whatever it finds. Re-tier a blade or
add a new one and the icons follow without touching Python. If the parse finds
nothing it fails loudly instead of silently shipping an empty folder.

Everything is deterministic. No randomness, no fonts baked into assets, no
external downloads. Two runs on two machines produce byte-identical PNGs.

Outputs
-------
assets/generated/icons/*.png    one per asset key
assets/generated/index.json     key -> relative path, consumed by upload_assets.py
assets/generated/contact_sheet.png   review sheet, not shipped

Usage
-----
    python scripts/generate_icons.py
    python scripts/generate_icons.py --only blades --size 256
    python scripts/generate_icons.py --sheet-only
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path
from typing import Callable, Iterable, Sequence

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:  # pragma: no cover - operator error, not a code path
    sys.exit("Pillow is required. Run: pip install -r requirements.txt")


REPO_ROOT = Path(__file__).resolve().parent.parent
REGISTRY_PATH = REPO_ROOT / "src" / "shared" / "BladeRegistry.luau"
OUTPUT_DIR = REPO_ROOT / "assets" / "generated"
ICON_DIR = OUTPUT_DIR / "icons"

# Supersampling factor. Pillow's draw calls have no antialiasing, so everything
# is drawn large and downsampled once at the end. 4x is the point where more
# samples stop being visible at 512px.
SS = 4

WHITE = (255, 255, 255)
BLACK = (0, 0, 0)

# ---------------------------------------------------------------------------
# Luau parsing
# ---------------------------------------------------------------------------

BLADE_RE = re.compile(
    r'id\s*=\s*"([^"]+)",\s*'
    r'name\s*=\s*"([^"]+)",\s*'
    r'rarity\s*=\s*"([^"]+)",\s*'
    r'tier\s*=\s*(\d+),\s*'
    r'multiplier\s*=\s*([^,]+),\s*'
    r'cost\s*=\s*([^,]+),\s*'
    r'shape\s*=\s*"([^"]+)",\s*'
    r'material\s*=\s*"([^"]+)",\s*'
    r'aura\s*=\s*"([^"]+)",\s*'
    r'bladeColor\s*=\s*\{\s*([\d,\s]+?)\s*\},\s*'
    r'glowColor\s*=\s*\{\s*([\d,\s]+?)\s*\},\s*'
    r'gripColor\s*=\s*\{\s*([\d,\s]+?)\s*\}',
    re.S,
)

RARITY_RE = re.compile(
    r'(\w+)\s*=\s*\{\s*name\s*=\s*"(\w+)",\s*'
    r'index\s*=\s*(\d+),\s*'
    r'color\s*=\s*\{\s*([\d,\s]+?)\s*\}',
    re.S,
)


def _triplet(raw: str) -> tuple[int, int, int]:
    parts = [int(p) for p in raw.split(",") if p.strip()]
    if len(parts) != 3:
        raise ValueError(f"expected 3 colour channels, got {raw!r}")
    return (parts[0], parts[1], parts[2])


def load_registry(path: Path) -> tuple[list[dict], dict[str, dict]]:
    if not path.is_file():
        sys.exit(f"Blade catalogue not found: {path}")

    text = path.read_text(encoding="utf-8")

    blades = []
    for m in BLADE_RE.finditer(text):
        blades.append(
            {
                "id": m.group(1),
                "name": m.group(2),
                "rarity": m.group(3),
                "tier": int(m.group(4)),
                "shape": m.group(7),
                "material": m.group(8),
                "aura": m.group(9),
                "bladeColor": _triplet(m.group(10)),
                "glowColor": _triplet(m.group(11)),
                "gripColor": _triplet(m.group(12)),
            }
        )

    if not blades:
        sys.exit(
            f"Parsed 0 blades from {path}. The catalogue format changed and the "
            "regex in this script needs updating."
        )

    rarities: dict[str, dict] = {}
    for m in RARITY_RE.finditer(text):
        rarities[m.group(2)] = {
            "name": m.group(2),
            "index": int(m.group(3)),
            "color": _triplet(m.group(4)),
        }

    missing = sorted({b["rarity"] for b in blades} - set(rarities))
    if missing:
        sys.exit(f"Rarities used by blades but absent from RARITY_INFO: {missing}")

    return blades, rarities


# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------


def mix(a: Sequence[int], b: Sequence[int], t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return (
        int(round(a[0] + (b[0] - a[0]) * t)),
        int(round(a[1] + (b[1] - a[1]) * t)),
        int(round(a[2] + (b[2] - a[2]) * t)),
    )


def lighten(c: Sequence[int], t: float) -> tuple[int, int, int]:
    return mix(c, WHITE, t)


def darken(c: Sequence[int], t: float) -> tuple[int, int, int]:
    return mix(c, BLACK, t)


def vertical_gradient(size: int, top: Sequence[int], bottom: Sequence[int]) -> Image.Image:
    """Cheap two-stop vertical ramp. Built small then stretched, which is both
    faster and smoother than one draw call per row."""
    strips = 128
    small = Image.new("RGBA", (1, strips))
    px = small.load()
    for y in range(strips):
        c = mix(top, bottom, y / (strips - 1))
        px[0, y] = (c[0], c[1], c[2], 255)
    return small.resize((size, size), Image.BILINEAR)


def solid(size: int, colour: Sequence[int]) -> Image.Image:
    return Image.new("RGBA", (size, size), (colour[0], colour[1], colour[2], 255))


def star_points(
    cx: float, cy: float, outer: float, inner: float, points: int, rotation: float
) -> list[tuple[float, float]]:
    pts = []
    for i in range(points * 2):
        angle = rotation + i * math.pi / points
        radius = outer if i % 2 == 0 else inner
        pts.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return pts


def polygon_mask(size: int, pts: Iterable[tuple[float, float]]) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon([(int(round(x)), int(round(y))) for x, y in pts], fill=255)
    return mask


def paint_masked(
    base: Image.Image, mask: Image.Image, paint: Image.Image
) -> Image.Image:
    """Composite `paint` onto `base`, restricted to `mask`."""
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.paste(paint, (0, 0), mask)
    return Image.alpha_composite(base, layer)


def add_glow(
    base: Image.Image, mask: Image.Image, colour: Sequence[int], spread: float, alpha: int
) -> Image.Image:
    glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    tint = Image.new("RGBA", base.size, (colour[0], colour[1], colour[2], alpha))
    glow.paste(tint, (0, 0), mask)
    pad = max(2, int(base.size[0] * spread))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=pad))
    return Image.alpha_composite(base, glow)


def outline(
    img: Image.Image, pts: Sequence[tuple[float, float]], colour: tuple[int, int, int],
    alpha: int, width: int,
) -> None:
    pts = list(pts)
    if len(pts) < 2:
        return
    ImageDraw.Draw(img).line(
        [(int(round(x)), int(round(y))) for x, y in pts + [pts[0]]],
        fill=(colour[0], colour[1], colour[2], alpha),
        width=max(1, width),
    )


# ---------------------------------------------------------------------------
# Blade geometry
# ---------------------------------------------------------------------------
#
# One parametric spine per shape: p(t) = (cx + sweep * t^1.8, lerp(y_base, y_tip, t)).
# The outline is that spine offset by a width profile on both sides. Five sets of
# six numbers produce five distinct silhouettes, which is the same trick the
# in-engine 3D preview uses for its part chains.

SHAPE_PARAMS: dict[str, dict[str, float]] = {
    #                sweep  y_base y_tip  half_w taper haft  guard grip_w belly point
    "straight":   dict(sweep=0.00, y_base=0.62, y_tip=0.05, half_w=0.068, taper=0.66, haft=0.15, guard=0.10, grip_w=0.042, belly=0.02, point=1.05),
    "curved":     dict(sweep=0.11, y_base=0.62, y_tip=0.06, half_w=0.070, taper=0.58, haft=0.15, guard=0.10, grip_w=0.042, belly=0.12, point=1.20),
    "glaive":     dict(sweep=0.17, y_base=0.60, y_tip=0.07, half_w=0.058, taper=0.52, haft=0.24, guard=0.13, grip_w=0.038, belly=0.08, point=1.30),
    "scythe":     dict(sweep=0.33, y_base=0.38, y_tip=0.09, half_w=0.050, taper=0.22, haft=0.42, guard=0.07, grip_w=0.030, belly=0.00, point=1.10),
    "greatsword": dict(sweep=0.00, y_base=0.64, y_tip=0.04, half_w=0.096, taper=0.54, haft=0.14, guard=0.26, grip_w=0.048, belly=0.00, point=1.00),
}


def spine(t: float, p: dict[str, float], size: int) -> tuple[float, float]:
    x = 0.5 * size + p["sweep"] * size * (t ** 1.8)
    y = (p["y_base"] + (p["y_tip"] - p["y_base"]) * t) * size
    return x, y


def half_width(t: float, p: dict[str, float], size: int) -> float:
    base = p["half_w"] * size
    if t < p["taper"]:
        # A slight belly keeps thin blades from reading as rectangles. Wide
        # blades get none: a bulge on a greatsword turns the tip into a bullet.
        return base * (1.0 + p["belly"] * math.sin(math.pi * t))
    u = (t - p["taper"]) / (1.0 - p["taper"])
    # Exponent >= 1 makes the edges converge at a constant angle. Below 1 the
    # width lingers and the tip domes over, which is the classic knife-shaped
    # blob. This is the single number that decides "blade" vs "paddle".
    return base * max(0.0, (1.0 - u) ** p["point"])


def blade_outline(shape: str, size: int, samples: int = 110) -> list[tuple[float, float]]:
    p = SHAPE_PARAMS.get(shape) or SHAPE_PARAMS["straight"]
    left: list[tuple[float, float]] = []
    right: list[tuple[float, float]] = []

    for i in range(samples + 1):
        t = i / samples
        x, y = spine(t, p, size)
        x2, y2 = spine(min(1.0, t + 1e-3), p, size)
        dx, dy = x2 - x, y2 - y
        length = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / length, dx / length
        w = half_width(t, p, size)
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))

    return left + right[::-1]


def spine_offset(shape: str, size: int, fraction: float, samples: int = 110) -> list[tuple[float, float]]:
    """Points a fraction of the half-width to the lit side of the spine."""
    p = SHAPE_PARAMS.get(shape) or SHAPE_PARAMS["straight"]
    pts = []
    for i in range(samples + 1):
        t = i / samples
        x, y = spine(t, p, size)
        x2, y2 = spine(min(1.0, t + 1e-3), p, size)
        dx, dy = x2 - x, y2 - y
        length = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / length, dx / length
        w = half_width(t, p, size) * fraction
        pts.append((x + nx * w, y + ny * w))
    return pts


def render_blade(blade: dict, size: int) -> Image.Image:
    S = size * SS
    p = SHAPE_PARAMS.get(blade["shape"]) or SHAPE_PARAMS["straight"]
    blade_c = blade["bladeColor"]
    glow_c = blade["glowColor"]
    grip_c = blade["gripColor"]

    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    body_pts = blade_outline(blade["shape"], S)
    body_mask = polygon_mask(S, body_pts)

    # Grip / haft, drawn first so the blade sits in front of it.
    grip_w = p["grip_w"] * S
    grip_top = p["y_base"] * S
    grip_bottom = (p["y_base"] + p["haft"]) * S
    draw.rounded_rectangle(
        [0.5 * S - grip_w, grip_top, 0.5 * S + grip_w, grip_bottom],
        radius=grip_w * 0.55,
        fill=(grip_c[0], grip_c[1], grip_c[2], 255),
    )
    # Wrapping bands read as a grip at small sizes where texture would not.
    bands = 4
    for i in range(bands):
        by = grip_top + (grip_bottom - grip_top) * (0.12 + 0.22 * i)
        draw.line(
            [(0.5 * S - grip_w * 0.85, by), (0.5 * S + grip_w * 0.85, by)],
            fill=lighten(grip_c, 0.22) + (170,),
            width=max(2, int(S * 0.006)),
        )

    # Guard.
    guard_w = p["guard"] * S
    guard_h = S * 0.030
    draw.rounded_rectangle(
        [0.5 * S - guard_w, grip_top - guard_h * 0.5, 0.5 * S + guard_w, grip_top + guard_h * 0.5],
        radius=guard_h * 0.45,
        fill=darken(blade_c, 0.35) + (255,),
    )
    draw.rounded_rectangle(
        [0.5 * S - guard_w, grip_top - guard_h * 0.5, 0.5 * S + guard_w, grip_top],
        radius=guard_h * 0.45,
        fill=lighten(blade_c, 0.30) + (140,),
    )

    # Pommel.
    pommel_r = grip_w * 0.72
    draw.ellipse(
        [0.5 * S - pommel_r, grip_bottom - pommel_r * 0.9, 0.5 * S + pommel_r, grip_bottom + pommel_r],
        fill=lighten(grip_c, 0.35) + (255,),
    )

    # Glow behind the blade.
    img = add_glow(img, body_mask, glow_c, 0.055, 150)
    img = add_glow(img, body_mask, glow_c, 0.018, 110)

    # Blade body: vertical ramp, brighter at the tip.
    ramp = vertical_gradient(S, lighten(blade_c, 0.62), darken(blade_c, 0.42))
    img = paint_masked(img, body_mask, ramp)

    # Specular strip along the lit edge, clipped to the blade.
    sheen = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).line(
        [(int(round(x)), int(round(y))) for x, y in spine_offset(blade["shape"], S, 0.52)],
        fill=lighten(blade_c, 0.92) + (165,),
        width=max(2, int(S * 0.013)),
        joint="curve",
    )
    sheen = sheen.filter(ImageFilter.GaussianBlur(radius=S * 0.008))
    img = paint_masked(img, body_mask, sheen)

    # Contact shadow along the dark edge keeps the silhouette readable on glow.
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(edge).line(
        [(int(round(x)), int(round(y))) for x, y in spine_offset(blade["shape"], S, -0.86)],
        fill=darken(blade_c, 0.75) + (150,),
        width=max(2, int(S * 0.010)),
        joint="curve",
    )
    edge = edge.filter(ImageFilter.GaussianBlur(radius=S * 0.006))
    img = paint_masked(img, body_mask, edge)

    outline(img, body_pts, darken(blade_c, 0.62), 170, max(1, int(S * 0.0045)))

    # Aether motes climbing the blade: the only place shape == "aura" shows up
    # in a static icon, so it is deliberately restrained.
    aura = blade["aura"]
    if aura != "none":
        mote_count = {"spark": 5, "orbit": 7, "void": 9, "quantum": 11}.get(aura, 0)
        motes = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        md = ImageDraw.Draw(motes)
        for i in range(mote_count):
            t = 0.18 + 0.78 * (i / max(1, mote_count - 1))
            x, y = spine(t, p, S)
            side = 1 if i % 2 == 0 else -1
            w = half_width(t, p, S)
            mx = x + side * (w + S * 0.035)
            my = y - S * 0.01 * (i % 3)
            r = S * (0.008 if aura in ("spark", "orbit") else 0.011)
            md.ellipse([mx - r, my - r, mx + r, my + r], fill=glow_c + (235,))
        motes = motes.filter(ImageFilter.GaussianBlur(radius=S * 0.004))
        img = Image.alpha_composite(img, motes)

    return img.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Currency glyphs
# ---------------------------------------------------------------------------

SM_COLOR = (255, 196, 92)
AS_COLOR = (96, 226, 255)
QC_COLOR = (132, 255, 208)
UI_COLOR = (206, 224, 255)


def render_currency(kind: str, size: int) -> Image.Image:
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    c = {"sm": SM_COLOR, "as": AS_COLOR, "qc": QC_COLOR}[kind]

    if kind == "sm":
        pts = star_points(0.5 * S, 0.5 * S, 0.42 * S, 0.115 * S, 4, -math.pi / 2)
        mask = polygon_mask(S, pts)
        img = add_glow(img, mask, c, 0.075, 165)
        img = paint_masked(img, mask, vertical_gradient(S, lighten(c, 0.55), darken(c, 0.22)))
        outline(img, pts, darken(c, 0.45), 150, max(1, int(S * 0.006)))
        draw = ImageDraw.Draw(img)
        draw.ellipse(
            [0.5 * S - 0.075 * S, 0.5 * S - 0.075 * S, 0.5 * S + 0.075 * S, 0.5 * S + 0.075 * S],
            fill=lighten(c, 0.85) + (255,),
        )

    elif kind == "as":
        # Faceted kite: tall shard, hard shoulder, one bright facet.
        top = (0.5 * S, 0.06 * S)
        left = (0.26 * S, 0.42 * S)
        bottom = (0.5 * S, 0.95 * S)
        right = (0.74 * S, 0.42 * S)
        pts = [top, right, bottom, left]
        mask = polygon_mask(S, pts)
        img = add_glow(img, mask, c, 0.075, 165)
        img = paint_masked(img, mask, vertical_gradient(S, lighten(c, 0.60), darken(c, 0.30)))
        # Facet: the left half catches the light.
        facet = polygon_mask(S, [top, (0.5 * S, 0.42 * S), bottom, left])
        img = paint_masked(img, facet, solid(S, lighten(c, 0.50)))
        # Reset the facet's opacity so it reads as a facet, not a paint blob.
        soft = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        soft.paste(Image.new("RGBA", (S, S), lighten(c, 0.55) + (110,)), (0, 0), facet)
        img = Image.alpha_composite(img, soft)
        outline(img, pts, darken(c, 0.50), 170, max(1, int(S * 0.006)))
        draw = ImageDraw.Draw(img)
        draw.line(
            [(int(0.5 * S), int(0.06 * S)), (int(0.5 * S), int(0.95 * S))],
            fill=lighten(c, 0.85) + (190,),
            width=max(1, int(S * 0.005)),
        )

    else:  # qc
        cx = cy = 0.5 * S
        core_r = 0.20 * S
        ring_box = [cx - 0.40 * S, cy - 0.24 * S, cx + 0.40 * S, cy + 0.24 * S]
        ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        rd = ImageDraw.Draw(ring)
        rd.ellipse(ring_box, outline=c + (235,), width=max(2, int(S * 0.018)))
        ring = ring.filter(ImageFilter.GaussianBlur(radius=S * 0.006))
        img = Image.alpha_composite(img, ring)

        core_mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(core_mask).ellipse(
            [cx - core_r, cy - core_r, cx + core_r, cy + core_r], fill=255
        )
        img = add_glow(img, core_mask, c, 0.065, 190)
        img = paint_masked(img, core_mask, vertical_gradient(S, lighten(c, 0.65), darken(c, 0.20)))

        draw = ImageDraw.Draw(img)
        # Two counter-rotating ticks: reads as "quantum" rather than "circle".
        for angle in (0.4, math.pi + 0.4):
            x = cx + math.cos(angle) * 0.32 * S
            y = cy + math.sin(angle) * 0.19 * S
            r = 0.035 * S
            draw.ellipse([x - r, y - r, x + r, y + r], fill=WHITE + (230,))

    return img.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------------------
# UI glyphs
# ---------------------------------------------------------------------------


def render_ui(kind: str, size: int) -> Image.Image:
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    c = UI_COLOR
    stroke = max(2, int(S * 0.045))

    def ring(pts: Sequence[tuple[float, float]], colour: Sequence[int], width: int) -> None:
        ImageDraw.Draw(img).line(
            [(int(x), int(y)) for x, y in list(pts) + [pts[0]]],
            fill=(colour[0], colour[1], colour[2], 255),
            width=width,
            joint="curve",
        )

    if kind == "ui_forge":
        # Anvil: flat top, waisted body, single horn.
        pts = [
            (0.16 * S, 0.44 * S), (0.84 * S, 0.44 * S), (0.84 * S, 0.54 * S),
            (0.60 * S, 0.58 * S), (0.56 * S, 0.70 * S), (0.70 * S, 0.76 * S),
            (0.70 * S, 0.82 * S), (0.30 * S, 0.82 * S), (0.30 * S, 0.76 * S),
            (0.44 * S, 0.70 * S), (0.40 * S, 0.58 * S), (0.16 * S, 0.54 * S),
        ]
        mask = polygon_mask(S, pts)
        img = paint_masked(img, mask, solid(S, c))
        draw = ImageDraw.Draw(img)
        draw.rounded_rectangle(
            [0.14 * S, 0.86 * S, 0.86 * S, 0.92 * S], radius=S * 0.02, fill=darken(c, 0.35) + (255,)
        )
        # Hammer strike spark above the anvil.
        draw.line(
            [(0.50 * S, 0.08 * S), (0.50 * S, 0.26 * S)], fill=lighten(c, 0.5) + (255,), width=stroke
        )
        draw.line(
            [(0.36 * S, 0.15 * S), (0.64 * S, 0.30 * S)], fill=lighten(c, 0.5) + (230,), width=stroke
        )

    elif kind == "ui_drone":
        cx = cy = 0.5 * S
        hexagon = [
            (cx + math.cos(math.pi / 3 * i - math.pi / 6) * 0.22 * S,
             cy + math.sin(math.pi / 3 * i - math.pi / 6) * 0.22 * S)
            for i in range(6)
        ]
        ring(hexagon, c, stroke)
        for angle, radius, r in ((0.0, 0.40, 0.055), (2.1, 0.40, 0.045), (4.2, 0.40, 0.045)):
            x = cx + math.cos(angle) * radius * S
            y = cy + math.sin(angle) * radius * S
            draw.ellipse([x - r * S, y - r * S, x + r * S, y + r * S], fill=lighten(c, 0.3) + (255,))
        draw.ellipse([cx - 0.09 * S, cy - 0.09 * S, cx + 0.09 * S, cy + 0.09 * S], fill=c + (255,))
        # Tether lines suggest a lattice, which is the upgrade's name.
        for angle in (0.0, 2.1, 4.2):
            draw.line(
                [(int(cx), int(cy)),
                 (int(cx + math.cos(angle) * 0.22 * S), int(cy + math.sin(angle) * 0.22 * S))],
                fill=c + (110,),
                width=max(1, int(S * 0.012)),
            )

    elif kind == "ui_heat":
        pts = [
            (0.50 * S, 0.05 * S), (0.66 * S, 0.34 * S), (0.78 * S, 0.52 * S),
            (0.80 * S, 0.66 * S), (0.70 * S, 0.84 * S), (0.50 * S, 0.93 * S),
            (0.28 * S, 0.85 * S), (0.19 * S, 0.68 * S), (0.24 * S, 0.50 * S),
            (0.34 * S, 0.60 * S), (0.34 * S, 0.40 * S),
        ]
        mask = polygon_mask(S, pts)
        img = add_glow(img, mask, (255, 150, 60), 0.05, 150)
        img = paint_masked(img, mask, vertical_gradient(S, (255, 214, 120), (255, 96, 44)))
        outline(img, pts, (150, 50, 20), 140, max(1, int(S * 0.006)))
        # Inner core.
        draw = ImageDraw.Draw(img)
        draw.ellipse(
            [0.40 * S, 0.60 * S, 0.60 * S, 0.82 * S], fill=(255, 244, 200, 220)
        )

    elif kind == "ui_vent":
        for i in range(3):
            y = (0.30 + 0.20 * i) * S
            pts = [
                (0.20 * S, y), (0.50 * S, y - 0.13 * S), (0.80 * S, y),
                (0.80 * S, y + 0.07 * S), (0.50 * S, y - 0.06 * S), (0.20 * S, y + 0.07 * S),
            ]
            ImageDraw.Draw(img).polygon(
                [(int(x), int(y2)) for x, y2 in pts], fill=c + (255 - i * 45,)
            )

    elif kind == "ui_crit":
        pts = star_points(0.5 * S, 0.5 * S, 0.46 * S, 0.15 * S, 8, -math.pi / 2)
        mask = polygon_mask(S, pts)
        img = add_glow(img, mask, (255, 214, 120), 0.05, 160)
        img = paint_masked(img, mask, vertical_gradient(S, (255, 246, 210), (255, 170, 60)))
        outline(img, pts, (150, 80, 10), 150, max(1, int(S * 0.005)))

    elif kind == "ui_tech":
        nodes = [(0.50, 0.14), (0.20, 0.52), (0.80, 0.52), (0.34, 0.88), (0.66, 0.88)]
        links = [(0, 1), (0, 2), (1, 3), (2, 4), (3, 4)]
        for a, b in links:
            draw.line(
                [(int(nodes[a][0] * S), int(nodes[a][1] * S)),
                 (int(nodes[b][0] * S), int(nodes[b][1] * S))],
                fill=c + (140,),
                width=max(2, int(S * 0.022)),
            )
        for i, (nx, ny) in enumerate(nodes):
            r = (0.085 if i == 0 else 0.065) * S
            draw.ellipse(
                [nx * S - r, ny * S - r, nx * S + r, ny * S + r],
                fill=(lighten(c, 0.35) if i == 0 else c) + (255,),
            )

    elif kind == "ui_inventory":
        cells = [(0.16, 0.16), (0.54, 0.16), (0.16, 0.54), (0.54, 0.54)]
        for i, (cx, cy) in enumerate(cells):
            box = [cx * S, cy * S, (cx + 0.30) * S, (cy + 0.30) * S]
            if i == 0:
                draw.rounded_rectangle(box, radius=S * 0.03, fill=lighten(c, 0.2) + (255,))
            else:
                draw.rounded_rectangle(
                    box, radius=S * 0.03, outline=c + (255,), width=stroke
                )

    else:
        raise ValueError(f"unknown ui glyph {kind!r}")

    return img.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Rarity frames
# ---------------------------------------------------------------------------


def render_rarity(index: int, colour: tuple[int, int, int], size: int) -> Image.Image:
    """A hex ring with corner ticks. Empty centre: it sits behind a blade icon."""
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx = cy = 0.5 * S
    radius = 0.455 * S
    hexagon = [
        (cx + math.cos(math.pi / 3 * i - math.pi / 2) * radius,
         cy + math.sin(math.pi / 3 * i - math.pi / 2) * radius)
        for i in range(6)
    ]

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).line(
        [(int(x), int(y)) for x, y in hexagon + [hexagon[0]]],
        fill=colour + (150,),
        width=max(2, int(S * 0.020)),
        joint="curve",
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius=S * 0.022))
    img = Image.alpha_composite(img, glow)

    ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(ring).line(
        [(int(x), int(y)) for x, y in hexagon + [hexagon[0]]],
        fill=colour + (255,),
        width=max(2, int(S * 0.012)),
        joint="curve",
    )
    img = Image.alpha_composite(img, ring)

    # Tick marks on alternating vertices; higher rarities get more of them.
    draw = ImageDraw.Draw(img)
    ticks = index
    for i in range(ticks):
        vx, vy = hexagon[i % 6]
        inner = (
            cx + (vx - cx) * 0.80,
            cy + (vy - cy) * 0.80,
        )
        draw.line(
            [(int(inner[0]), int(inner[1])), (int(vx), int(vy))],
            fill=lighten(colour, 0.55) + (255,),
            width=max(2, int(S * 0.016)),
        )

    # Faint dashed inner track at high rarity.
    if index >= 4:
        track_r = radius * 0.90
        circle = [
            (cx + math.cos(a / 48 * math.tau) * track_r,
             cy + math.sin(a / 48 * math.tau) * track_r)
            for a in range(49)
        ]
        draw.line(
            [(int(x), int(y)) for x, y in circle],
            fill=colour + (90,),
            width=max(1, int(S * 0.006)),
        )

    return img.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Build plan
# ---------------------------------------------------------------------------

UI_GLYPHS = ("ui_forge", "ui_drone", "ui_heat", "ui_tech", "ui_inventory", "ui_vent", "ui_crit")
CURRENCIES = ("currency_sm", "currency_as", "currency_qc")


def build_plan(
    blades: list[dict], rarities: dict[str, dict]
) -> list[tuple[str, str, str, Callable[[int], Image.Image]]]:
    """(key, group, display name, renderer) in manifest order.

    The display name is what a human sees in the Creator Dashboard months from
    now, when `blade_entangle_scythe` is not a useful label and "Entangle
    Scythe" is.
    """
    plan: list[tuple[str, str, str, Callable[[int], Image.Image]]] = []

    currency_names = {
        "currency_sm": "Star-Matter",
        "currency_as": "Aether Shard",
        "currency_qc": "Quantum Core",
    }
    for key in CURRENCIES:
        kind = key.rsplit("_", 1)[-1]
        plan.append((key, "currency", currency_names[key], lambda s, k=kind: render_currency(k, s)))

    ui_names = {
        "ui_forge": "Glyph - Forge",
        "ui_drone": "Glyph - Drone",
        "ui_heat": "Glyph - Heat",
        "ui_tech": "Glyph - Tech Tree",
        "ui_inventory": "Glyph - Inventory",
        "ui_vent": "Glyph - Vent",
        "ui_crit": "Glyph - Critical",
    }
    for key in UI_GLYPHS:
        plan.append((key, "ui", ui_names[key], lambda s, k=key: render_ui(k, s)))

    for name in ("Scrap", "Forged", "Astral", "Void", "Quantum"):
        info = rarities[name]
        plan.append(
            (
                f"rarity_{info['index']}",
                "rarity",
                f"Rarity Frame - {name}",
                lambda s, i=info["index"], c=info["color"]: render_rarity(i, c, s),
            )
        )

    for blade in blades:
        plan.append(
            (
                f"blade_{blade['id']}",
                "blades",
                blade["name"],
                lambda s, b=blade: render_blade(b, s),
            )
        )

    return plan


def make_sheet(entries: list[tuple[str, Path]], out_path: Path, cell: int = 128) -> None:
    """Review sheet. Never uploaded; exists so a human can eyeball 40 icons at once."""
    try:
        font = ImageFont.load_default()
    except Exception:  # noqa: BLE001 - font is cosmetic
        font = None

    cols = 7
    rows = math.ceil(len(entries) / cols)
    label_h = 14
    pad = 10
    width = cols * (cell + pad) + pad
    height = rows * (cell + label_h + pad) + pad

    sheet = Image.new("RGB", (width, height), (18, 20, 28))
    draw = ImageDraw.Draw(sheet)

    for i, (key, path) in enumerate(entries):
        col = i % cols
        row = i // cols
        x = pad + col * (cell + pad)
        y = pad + row * (cell + label_h + pad)
        draw.rounded_rectangle(
            [x, y, x + cell, y + cell], radius=8, fill=(28, 31, 42)
        )
        if path.is_file():
            icon = Image.open(path).convert("RGBA")
            icon.thumbnail((cell - 8, cell - 8), Image.LANCZOS)
            sheet.paste(
                icon,
                (x + (cell - icon.width) // 2, y + (cell - icon.height) // 2),
                icon,
            )
        label = key if len(key) <= 20 else key[:18] + ".."
        draw.text((x + 2, y + cell + 1), label, fill=(150, 158, 175), font=font)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)
    print(f"contact sheet -> {out_path.relative_to(REPO_ROOT)}")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", choices=["all", "blades", "currency", "ui", "rarity"], default="all")
    parser.add_argument("--size", type=int, default=512, help="output edge length in px (default 512)")
    parser.add_argument("--out", type=Path, default=OUTPUT_DIR)
    parser.add_argument("--sheet-only", action="store_true", help="rebuild the contact sheet from existing PNGs")
    parser.add_argument("--no-sheet", action="store_true", help="skip the contact sheet")
    args = parser.parse_args(argv)

    blades, rarities = load_registry(REGISTRY_PATH)
    plan = build_plan(blades, rarities)

    icon_dir = args.out / "icons"
    icon_dir.mkdir(parents=True, exist_ok=True)

    if args.sheet_only:
        entries = [(key, icon_dir / f"{key}.png") for key, _, _, _ in plan]
        make_sheet(entries, args.out / "contact_sheet.png")
        return 0

    selected = [item for item in plan if args.only == "all" or item[1] == args.only]
    if not selected:
        sys.exit(f"nothing to render for --only {args.only}")

    # Glyphs and frames are display chrome, not hero art. Rendering them at 512
    # wastes upload quota for pixels Roblox will throw away.
    glyph_size = min(args.size, 256)

    index: dict[str, dict[str, str]] = {}
    written = 0
    for key, group, display, render in selected:
        size = args.size if group == "blades" else glyph_size
        icon = render(size)
        path = icon_dir / f"{key}.png"
        icon.save(path, "PNG", optimize=True)
        index[key] = {"path": f"icons/{key}.png", "name": display}
        written += 1

    print(f"rendered {written} icons into {icon_dir.relative_to(REPO_ROOT)}")

    # Merge with any icons already on disk so --only does not clobber the index.
    index_path = args.out / "index.json"
    if args.only != "all" and index_path.is_file():
        try:
            existing = json.loads(index_path.read_text(encoding="utf-8")).get("assets", {})
            if isinstance(existing, dict):
                existing.update(index)
                index = existing
        except json.JSONDecodeError:
            print("warning: index.json was unreadable, rewriting from scratch")

    ordered = {key: index[key] for key, _, _, _ in plan if key in index}
    index_path.write_text(json.dumps({"size": args.size, "assets": ordered}, indent=2) + "\n", encoding="utf-8")
    print(f"index -> {index_path.relative_to(REPO_ROOT)} ({len(ordered)} keys)")

    if not args.no_sheet:
        entries = [(key, icon_dir / f"{key}.png") for key, _, _, _ in plan if (icon_dir / f"{key}.png").is_file()]
        make_sheet(entries, args.out / "contact_sheet.png")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
