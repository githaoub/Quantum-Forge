#!/usr/bin/env python3
"""Render the Roblox gamepass badge icons, locally, with no network and no Studio.

One icon is turned on at a time. `PASSES` names every pass the store will need,
`RENDERERS` holds the ones whose art is signed off. Asking for a pass that has
no renderer yet exits 2 and names what is missing, so nobody ships a half-built
badge by accident.

Style contract (ADR-029, extended to store art):

    * opaque circular badge on transparent corners, 9px clear margin at 512
    * every silhouette carries a `#0F1117` contour, minimum 0.006 * size
    * warm gold for the subject, electric cyan for motion, obsidian for ground
    * no text, no numbers, no external fonts, no randomness

Determinism: no `random`, no timestamps, no font files. Two runs on two
machines produce byte-identical PNGs; `--report` prints the sha256 so a change
is provable rather than asserted.

Outputs
-------
assets/generated/gamepasses/<key>.png       512x512 RGBA
assets/generated/gamepasses/contact_sheet.png   review sheet, not shipped

Usage
-----
    python scripts/generate_gamepass_icons.py
    python scripts/generate_gamepass_icons.py --only fast_forge --report
    python scripts/generate_gamepass_icons.py --no-sheet
"""

from __future__ import annotations

import argparse
import hashlib
import math
import sys
from pathlib import Path
from typing import Sequence

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover - operator error, not a code path
    sys.exit("Pillow is required. Run: pip install -r requirements.txt")


REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "assets" / "generated" / "gamepasses"

FINAL = 512
SUPERSAMPLE = 2
SS = FINAL * SUPERSAMPLE

# ---------------------------------------------------------------------------
# Palette. Mirrors Theme.Color minus the parts a badge does not need.
# ---------------------------------------------------------------------------

INK = (15, 17, 23)
SLATE_CORE = (40, 52, 76)
SLATE_EDGE = (5, 7, 11)
GOLD_HOT = (255, 194, 60)
GOLD_MID = (255, 150, 44)
GOLD_DEEP = (190, 78, 10)
CYAN = (0, 210, 255)
SPEC = (255, 250, 235)
STEEL_LIT = (128, 146, 174)
STEEL_MID = (64, 78, 102)
STEEL_DARK = (18, 23, 34)

# Field colours for the inverted composition. See `_disc`: the store renders
# this badge at 34.5 real px, and a dark ground measured p50 = 28 luminance with
# 7% of pixels above 120, which is a black circle on a store row. The field is
# gold now and the subject is ink. Same palette, same outlines, one third of the
# disc dark instead of two thirds.
FIELD_HOT = (255, 214, 108)
FIELD_MID = (255, 168, 62)
FIELD_DEEP = (206, 96, 14)

# Disc geometry, in fractions of the canvas. The radius leaves a 0.030 margin
# so the badge keeps a clear edge on the store card; Lanczos eats about 2px of
# it when the canvas is downsampled, which is why it is not 0.018.
DISC_R = 0.470
DISC_CX = 0.5
DISC_CY = 0.5

PASSES = [
    "fast_forge",
    "auto_vent",
    "x2_star_matter",
    "vip_aura",
    "eternal_forge",
]


# ---------------------------------------------------------------------------
# Colour and gradient helpers
# ---------------------------------------------------------------------------


def _clamp8(v: float) -> int:
    return 0 if v < 0 else 255 if v > 255 else int(round(v))


def _mix(a: Sequence[int], b: Sequence[int], t: float) -> tuple[int, int, int]:
    t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
    return (
        _clamp8(a[0] + (b[0] - a[0]) * t),
        _clamp8(a[1] + (b[1] - a[1]) * t),
        _clamp8(a[2] + (b[2] - a[2]) * t),
    )


def _lighten(c: Sequence[int], t: float) -> tuple[int, int, int]:
    return _mix(c, (255, 255, 255), t)


def _darken(c: Sequence[int], t: float) -> tuple[int, int, int]:
    return _mix(c, (0, 0, 0), t)


# Radial fields are rendered at 128px and upsampled. A radial falloff carries no
# detail above that resolution, and the full-canvas per-pixel loop costs 64x
# more for a pixel someone would have to diff to see.
GRAD_RES = 128


def _radial_alpha(
    size: int, cx: float, cy: float, radius: float, power: float = 1.6
) -> Image.Image:
    """White-to-black radial falloff, 255 at the centre, 0 at `radius`."""
    n = GRAD_RES
    small = Image.new("L", (n, n), 0)
    px = small.load()
    scx = cx / size * n
    scy = cy / size * n
    srad = max(radius / size * n, 1e-6)
    for y in range(n):
        for x in range(n):
            d = math.hypot(x + 0.5 - scx, y + 0.5 - scy) / srad
            px[x, y] = 0 if d >= 1.0 else int(round(255.0 * (1.0 - d) ** power))
    return small.resize((size, size), Image.Resampling.BICUBIC)


def _radial_rgb(
    size: int,
    cx: float,
    cy: float,
    radius: float,
    inner: Sequence[int],
    outer: Sequence[int],
    power: float = 1.25,
) -> Image.Image:
    n = GRAD_RES
    small = Image.new("RGB", (n, n), tuple(outer))
    px = small.load()
    scx = cx / size * n
    scy = cy / size * n
    srad = max(radius / size * n, 1e-6)
    for y in range(n):
        for x in range(n):
            d = min(1.0, math.hypot(x + 0.5 - scx, y + 0.5 - scy) / srad)
            px[x, y] = _mix(inner, outer, d**power)
    return small.resize((size, size), Image.Resampling.BICUBIC)


def _vertical(size: int, top: Sequence[int], bottom: Sequence[int]) -> Image.Image:
    column = Image.new("RGB", (1, size))
    px = column.load()
    for y in range(size):
        px[0, y] = _mix(top, bottom, y / max(1, size - 1))
    return column.resize((size, size), Image.Resampling.NEAREST)


def _shade(mask: Image.Image, top: Sequence[int], bottom: Sequence[int]) -> Image.Image:
    """Vertical gradient fitted to the mask's own bounding box.

    Canvas-space gradients are the classic flat-icon bug: a shape in the upper
    half receives the top slice of the ramp and comes out uniformly dark no
    matter how bright the ramp's top colour is. Shading per shape is what makes
    every solid read as lit from above.
    """
    size = mask.size[0]
    bbox = mask.getbbox()
    if bbox is None:
        return Image.new("RGB", mask.size, tuple(top))
    x0, y0, x1, y1 = bbox
    height = max(1, y1 - y0)
    ramp = _vertical(height, top, bottom).crop((0, 0, x1 - x0, height))
    out = Image.new("RGB", mask.size, tuple(bottom))
    out.paste(ramp, (x0, y0))
    return out


def _vignette_alpha(
    size: int, radius: float, inner: float = 0.56, power: float = 1.7
) -> Image.Image:
    """Rim darkening only. Transparent through the middle of the disc.

    A plain radial falloff is not a vignette - it is a black wash. Measured on
    the first pass: a full-ramp vignette at 0.92 strength dropped the anvil
    plate from 190 to 78 luminance and killed every highlight in the icon.
    """
    n = GRAD_RES
    small = Image.new("L", (n, n), 0)
    px = small.load()
    scx = scy = n / 2
    srad = max(radius / size * n, 1e-6)
    for y in range(n):
        for x in range(n):
            d = math.hypot(x + 0.5 - scx, y + 0.5 - scy) / srad
            if d <= inner:
                px[x, y] = 0
            else:
                t = min(1.0, (d - inner) / (1.0 - inner))
                px[x, y] = int(round(255.0 * (t**power)))
    return small.resize((size, size), Image.Resampling.BICUBIC)


def _mask(size: int, pts: Sequence[tuple[float, float]]) -> Image.Image:
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).polygon([(x, y) for x, y in pts], fill=255)
    return m


def _paint(base: Image.Image, mask: Image.Image, paint: Image.Image) -> Image.Image:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.paste(paint, (0, 0), mask)
    return Image.alpha_composite(base, layer)


def _bloom(
    base: Image.Image,
    cx: float,
    cy: float,
    radius: float,
    colour: Sequence[int],
    power: float = 2.0,
    strength: float = 1.0,
) -> Image.Image:
    mask = _radial_alpha(base.size[0], cx, cy, radius, power)
    if strength != 1.0:
        mask = Image.eval(mask, lambda v: _clamp8(v * strength))
    layer = Image.new("RGBA", base.size, tuple(colour) + (255,))
    layer.putalpha(mask)
    return Image.alpha_composite(base, layer)


def _stroke(
    draw: ImageDraw.ImageDraw,
    pts: Sequence[tuple[float, float]],
    colour: Sequence[int],
    width: int,
    closed: bool = True,
    alpha: int = 255,
) -> None:
    if len(pts) < 2:
        return
    seq = list(pts) + ([pts[0]] if closed else [])
    draw.line(
        [(int(round(x)), int(round(y))) for x, y in seq],
        fill=(colour[0], colour[1], colour[2], alpha),
        width=max(1, width),
        joint="curve",
    )


# ---------------------------------------------------------------------------
# Shared badge furniture
# ---------------------------------------------------------------------------


def _disc(img: Image.Image) -> Image.Image:
    """Gold field: hot at the crown, deep at the rim.

    Inverted from the first composition on purpose. Measured at the size the
    store actually draws (48 design px, 34.5 real px at 0.719 canvas scale), an
    obsidian disc with a steel subject came out p50 = 28 luminance with 7% of
    pixels above 120. That renders as a black circle, which is exactly the bug
    report. Gold ground plus an ink subject puts most of the disc above 120 and
    lets the silhouette be the dark thing.
    """
    S = img.size[0]
    cx, cy = DISC_CX * S, DISC_CY * S
    r = DISC_R * S
    # Two falloffs: a tight hot core up under the strike, and a broad ramp to the
    # rim. A single radial flattens to one tone after the downsample.
    core = _radial_rgb(S, cx, cy * 0.84, r, FIELD_HOT, FIELD_DEEP, 1.30)
    wide = _radial_rgb(S, cx, cy, r, FIELD_MID, FIELD_DEEP, 1.05)
    ground = Image.blend(core, wide, 0.38)
    circle = Image.new("L", (S, S), 0)
    ImageDraw.Draw(circle).ellipse(
        [cx - r, cy - r, cx + r, cy + r], fill=255
    )
    return _paint(img, circle, ground)


def _speed_lines(img: Image.Image) -> Image.Image:
    """Cyan motion streaks fanned out of the strike, weighted to the left.

    The hammer owns the upper right, so the streaks live in the negative space
    on the other side. Six of them, not ten: a fan of thin slivers reads as
    static, and every one of these has to survive the 64px downsample.
    """
    S = img.size[0]
    ox, oy = IMPACT[0] * S, IMPACT[1] * S
    # (angle degrees, length, half-width, alpha)
    streaks = [
        (188, 0.36, 0.0140, 190),
        (203, 0.31, 0.0120, 170),
        (219, 0.27, 0.0105, 150),
        (236, 0.23, 0.0092, 130),
        (254, 0.19, 0.0080, 110),
        (170, 0.31, 0.0118, 165),
        (-16, 0.25, 0.0098, 140),
        (-34, 0.20, 0.0082, 112),
    ]
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for angle, length, hw, alpha in streaks:
        a = math.radians(angle)
        dx, dy = math.cos(a), math.sin(a)
        px, py = -dy, dx
        w = hw * S
        tip = (ox + dx * length * S, oy + dy * length * S)
        d.polygon(
            [
                (ox + px * w, oy + py * w),
                tip,
                (ox - px * w, oy - py * w),
            ],
            fill=CYAN + (alpha,),
        )
    return Image.alpha_composite(img, layer)


def _shockwave(img: Image.Image, cx: float, cy: float) -> Image.Image:
    """One bold arc over the contact, plus a faint wider echo.

    Two arcs of equal weight read as a halo. One bright arc and one ghost arc
    read as an event.
    """
    S = img.size[0]
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for radius, width, colour, alpha in (
        (0.118, 0.0115, SPEC, 240),
        (0.172, 0.0055, _lighten(FIELD_HOT, 0.45), 120),
    ):
        r = radius * S
        d.arc(
            [cx - r, cy - r, cx + r, cy + r],
            start=158,
            end=382,
            fill=colour + (alpha,),
            width=max(2, int(width * S)),
        )
    return Image.alpha_composite(img, layer)


# ---------------------------------------------------------------------------
# Subject: anvil, hammer, sparks
# ---------------------------------------------------------------------------

# Silhouette, canvas fractions. Horn on the left, waisted body, flared base.
# The base stops short of the rim so the badge keeps a floor shadow.
ANVIL = [
    (0.050, 0.634),
    (0.206, 0.600),
    (0.796, 0.600),
    (0.828, 0.660),
    (0.706, 0.690),
    (0.668, 0.768),
    (0.730, 0.820),
    (0.754, 0.892),
    (0.246, 0.892),
    (0.270, 0.820),
    (0.332, 0.768),
    (0.294, 0.690),
    (0.150, 0.660),
]

# Contact point: just above the plate, under the striking face.
IMPACT = (0.536, 0.590)

# Raised and about to land. A steeper angle than the first pass reads as a
# swing rather than a hammer lying on the anvil.
HAMMER_ANGLE = math.radians(-42.0)
HAMMER_CENTRE = (0.484, 0.476)


def _render_anvil(img: Image.Image) -> Image.Image:
    """Anvil in ink, with one lit plate edge so the wedge reads at 48px.

    Drawn dark on a gold field. The first pass drew a steel anvil on an obsidian
    disc, and two mid-greys at 48px merge into a single grey smear. Here the body
    is near-black and the plate is the only light band, which is the read the eye
    needs when the whole badge is 34 real px wide.
    """
    S = img.size[0]
    pts = [(x * S, y * S) for x, y in ANVIL]
    mask = _mask(S, pts)

    # Body: black at the foot, lifted slightly toward the plate so the wedge is
    # not a flat cutout.
    img = _paint(img, mask, _shade(mask, _darken(INK, 0.10), _lighten(INK, 0.34)))

    d = ImageDraw.Draw(img)

    # Machined plate: bright steel along the top edge, then an ink lip so the
    # plate has thickness instead of reading as a painted stripe.
    d.polygon(
        [
            (0.206 * S, 0.600 * S),
            (0.796 * S, 0.600 * S),
            (0.806 * S, 0.628 * S),
            (0.196 * S, 0.628 * S),
        ],
        fill=STEEL_LIT + (255,),
    )
    d.polygon(
        [
            (0.196 * S, 0.628 * S),
            (0.806 * S, 0.628 * S),
            (0.812 * S, 0.648 * S),
            (0.190 * S, 0.648 * S),
        ],
        fill=INK + (255,),
    )
    # Molten seam splitting the plate, the one value brighter than the field.
    d.line(
        [(0.198 * S, 0.634 * S), (0.804 * S, 0.634 * S)],
        fill=SPEC + (255,),
        width=max(2, int(0.0090 * S)),
    )
    d.line(
        [(0.206 * S, 0.604 * S), (0.796 * S, 0.604 * S)],
        fill=_lighten(STEEL_LIT, 0.60) + (235,),
        width=max(2, int(0.0050 * S)),
    )

    # Waist: a recessed collar instead of a painted slot.
    d.line(
        [(0.348 * S, 0.734 * S), (0.652 * S, 0.734 * S)],
        fill=INK + (255,),
        width=max(2, int(0.026 * S)),
    )
    d.line(
        [(0.348 * S, 0.722 * S), (0.652 * S, 0.722 * S)],
        fill=STEEL_LIT + (220,),
        width=max(2, int(0.0060 * S)),
    )

    # Foot: plinth edge plus two bolts, which is all the detail that survives
    # a 48px thumbnail.
    d.line(
        [(0.262 * S, 0.826 * S), (0.738 * S, 0.826 * S)],
        fill=STEEL_LIT + (255,),
        width=max(2, int(0.010 * S)),
    )
    for bx in (0.318, 0.682):
        r = 0.016 * S
        d.ellipse(
            [bx * S - r, 0.862 * S - r, bx * S + r, 0.862 * S + r],
            fill=INK + (255,),
        )
        d.ellipse(
            [bx * S - r * 0.45, 0.862 * S - r * 0.45, bx * S + r * 0.45, 0.862 * S + r * 0.45],
            fill=STEEL_LIT + (255,),
        )

    _stroke(d, pts, INK, max(3, int(0.0085 * S)))
    return img


def _render_hammer(img: Image.Image) -> Image.Image:
    """Head over the plate, handle thrown up and to the right."""
    S = img.size[0]
    cx, cy = HAMMER_CENTRE[0] * S, HAMMER_CENTRE[1] * S
    c, s = math.cos(HAMMER_ANGLE), math.sin(HAMMER_ANGLE)

    def to_screen(lx: float, ly: float) -> tuple[float, float]:
        return (cx + lx * S * c - ly * S * s, cy + lx * S * s + ly * S * c)

    def poly(pts: Sequence[tuple[float, float]]) -> list[tuple[float, float]]:
        return [to_screen(x, y) for x, y in pts]

    # Local space: +x is the haft, +y runs along the head. A hammer head is a
    # long thin bar with the haft through the middle of its thickness, a collar
    # around the eye, and the striking face on one end. Three passes got this
    # wrong in three different ways: axes (axes swapped), mallets (square
    # proportions), and blades (a full-length bright edge with no lump in the
    # middle). The collar is what stops it reading as a knife.
    head = [(-0.050, -0.118), (0.050, -0.118), (0.058, 0.118), (-0.058, 0.118)]
    collar = [(-0.066, -0.026), (0.066, -0.026), (0.066, 0.026), (-0.066, 0.026)]
    neck = [(0.060, -0.026), (0.092, -0.019), (0.092, 0.019), (0.060, 0.026)]
    handle = [(0.086, -0.022), (0.300, -0.016), (0.300, 0.016), (0.086, 0.022)]
    pommel = [(0.288, -0.038), (0.328, -0.030), (0.328, 0.030), (0.288, 0.038)]

    head_mask = _mask(S, poly(head))
    collar_mask = _mask(S, poly(collar))
    neck_mask = _mask(S, poly(neck))
    handle_mask = _mask(S, poly(handle))
    pommel_mask = _mask(S, poly(pommel))

    img = _paint(img, pommel_mask, _shade(pommel_mask, STEEL_LIT, INK))
    # Walnut haft. Dark brown is the one material that reads as "handle" against
    # a gold field without competing with the ink silhouette.
    img = _paint(
        img, handle_mask, _shade(handle_mask, _darken(GOLD_DEEP, 0.52), _darken(GOLD_DEEP, 0.76))
    )
    img = _paint(
        img, neck_mask, _shade(neck_mask, _lighten(STEEL_MID, 0.10), INK)
    )
    # Light at the peen end, dark toward the striking end. The face cap is
    # painted over this ramp rather than through it, so it stays white-hot.
    img = _paint(
        img, head_mask, _shade(head_mask, _lighten(STEEL_MID, 0.16), INK)
    )
    img = _paint(
        img, collar_mask, _shade(collar_mask, STEEL_LIT, _darken(STEEL_MID, 0.34))
    )

    d = ImageDraw.Draw(img)

    # Haft wrap. Three bands read as a grip at 512 and as one notch at 48.
    for t in (0.104, 0.176, 0.248):
        band = [(t, -0.024), (t + 0.038, -0.021), (t + 0.038, 0.021), (t, 0.024)]
        d.polygon(poly(band), fill=INK + (255,))

    # Bevel down the upper long edge and a hard shade down the lower one. They
    # stop short of the face cap, so the tool does not read as a blade with a
    # ground edge running its whole length.
    d.polygon(
        poly([(0.026, -0.118), (0.050, -0.118), (0.056, 0.070), (0.032, 0.070)]),
        fill=_lighten(STEEL_LIT, 0.74) + (255,),
    )
    d.polygon(
        poly([(-0.050, -0.118), (-0.026, -0.118), (-0.030, 0.070), (-0.056, 0.070)]),
        fill=_darken(STEEL_DARK, 0.34) + (255,),
    )

    # Striking face: the whole end cap in bright steel with a white hot half.
    # Every other shape in the badge points at this rectangle.
    d.polygon(
        poly([(-0.058, 0.062), (0.058, 0.062), (0.058, 0.118), (-0.058, 0.118)]),
        fill=_lighten(STEEL_LIT, 0.62) + (255,),
    )
    d.polygon(
        poly([(-0.058, 0.062), (-0.004, 0.062), (-0.004, 0.118), (-0.058, 0.118)]),
        fill=SPEC + (255,),
    )
    # Gold heat band across the collar: the "fast forge" amber, and the one
    # saturated note on an otherwise steel tool.
    d.polygon(
        poly([(-0.066, -0.011), (0.066, -0.011), (0.066, 0.011), (-0.066, 0.011)]),
        fill=_lighten(GOLD_HOT, 0.30) + (255,),
    )
    # Peen cap, so the far end is not a chopped-off rectangle.
    d.polygon(
        poly([(-0.050, -0.118), (0.050, -0.118), (0.050, -0.094), (-0.050, -0.094)]),
        fill=_darken(STEEL_MID, 0.48) + (255,),
    )
    # Trailing edge catches the cyan rim light.
    d.line(
        poly([(-0.049, -0.114), (-0.056, 0.114)]),
        fill=CYAN + (190,),
        width=max(2, int(0.0050 * S)),
    )

    for pts in (poly(pommel), poly(head), poly(collar)):
        _stroke(d, pts, INK, max(3, int(0.0090 * S)))
    return img


def _render_sparks(img: Image.Image) -> Image.Image:
    """Sharp shards leaving the contact point. Fixed angles: no RNG.

    White-hot core with cyan trailing shards. The first pass used gold on
    obsidian; on a gold field those sparks are invisible, which is the same
    value-collision that made the disc read as a black circle.
    """
    S = img.size[0]
    ox, oy = IMPACT[0] * S, IMPACT[1] * S
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # Five shards plus a core star. A dozen fat triangles from one point read
    # as a starfish; a few thin ones plus one bright star read as impact.
    # Widths are deliberately small relative to length - that ratio is what
    # makes a shard look fast rather than decorative.
    # (angle deg, length, half-width, colour, alpha, start offset)
    shards = [
        (-99, 0.250, 0.0055, SPEC, 250, 0.030),
        (-72, 0.190, 0.0046, SPEC, 235, 0.024),
        (-126, 0.200, 0.0048, CYAN, 225, 0.026),
        (-47, 0.135, 0.0038, CYAN, 200, 0.020),
        (-152, 0.145, 0.0040, CYAN, 200, 0.020),
    ]
    for angle, length, hw, colour, alpha, start in shards:
        a = math.radians(angle)
        dx, dy = math.cos(a), math.sin(a)
        px, py = -dy, dx
        bx = ox + dx * start * S
        by = oy + dy * start * S
        w = hw * S
        d.polygon(
            [
                (bx + px * w, by + py * w),
                (bx + dx * length * S, by + dy * length * S),
                (bx - px * w, by - py * w),
            ],
            fill=colour + (alpha,),
        )

    # Core burst: two rings of concave spikes. Small, hot, and centred in the
    # gap - a wide brown splat reads as a stain, a tight white star reads as a
    # strike. This is the focal point of the badge.
    for reach, waist, colour, count, phase in (
        (0.100, 0.0130, SPEC, 8, 0),
        (0.058, 0.0180, (255, 255, 255), 4, 0),
    ):
        for k in range(count):
            a = math.radians(-90 + phase + (360 / count) * k)
            tip = (ox + math.cos(a) * reach * S, oy + math.sin(a) * reach * S)
            left = (
                ox + math.cos(a + math.pi * 0.20) * waist * S,
                oy + math.sin(a + math.pi * 0.20) * waist * S,
            )
            right = (
                ox + math.cos(a - math.pi * 0.20) * waist * S,
                oy + math.sin(a - math.pi * 0.20) * waist * S,
            )
            d.polygon([left, tip, right], fill=colour + (255,))
    return Image.alpha_composite(img, layer)


# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------


def render_fast_forge(size: int = SS) -> Image.Image:
    S = size

    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img = _disc(img)

    # Hot ground behind the strike, before anything solid goes down. A gold
    # bloom on a gold field is invisible, so the pre-light is the field's own
    # hot colour and the contact gets a white core.
    img = _bloom(img, IMPACT[0] * S, 0.660 * S, 0.320 * S, FIELD_HOT, 2.4, 0.50)
    img = _bloom(img, IMPACT[0] * S, IMPACT[1] * S, 0.165 * S, SPEC, 2.0, 0.38)
    img = _speed_lines(img)
    img = _shockwave(img, IMPACT[0] * S, IMPACT[1] * S)
    img = _render_anvil(img)

    # White-hot contact: the brightest single point in the icon.
    img = _bloom(img, IMPACT[0] * S, IMPACT[1] * S, 0.086 * S, SPEC, 1.7, 0.95)
    img = _bloom(img, IMPACT[0] * S, IMPACT[1] * S, 0.042 * S, (255, 255, 255), 1.4, 1.0)

    # Sparks before the hammer: they fly out from under the head, so the head
    # occludes the ones heading up-range. Drawing them last put thin gold
    # scratches over the steel and made the hammer look engraved.
    img = _render_sparks(img)
    img = _render_hammer(img)

    # Bevel just inside the rim. On a bright field the ink rim on its own makes
    # the disc a flat cutout; a struck coin has an inner edge, and this is it.
    bevel = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bevel_r = DISC_R - 0.026
    ImageDraw.Draw(bevel).ellipse(
        [
            (0.5 - bevel_r) * S,
            (0.5 - bevel_r) * S,
            (0.5 + bevel_r) * S,
            (0.5 + bevel_r) * S,
        ],
        outline=_lighten(FIELD_HOT, 0.62) + (200,),
        width=max(2, int(0.0090 * S)),
    )
    img = Image.alpha_composite(img, bevel)

    # Everything above is drawn on the full canvas so the glows can spill past
    # the rim and be trimmed in one place. Without this the speed lines and the
    # shockwave leave hard-edged junk on the transparent corners.
    circle = Image.new("L", (S, S), 0)
    ImageDraw.Draw(circle).ellipse(
        [
            (0.5 - DISC_R) * S,
            (0.5 - DISC_R) * S,
            (0.5 + DISC_R) * S,
            (0.5 + DISC_R) * S,
        ],
        fill=255,
    )
    img.putalpha(
        Image.composite(img.getchannel("A"), Image.new("L", (S, S), 0), circle)
    )

    # Vignette inside the disc: darkens the rim so the subject owns the middle.
    # Held at 0.38 rather than the 0.95 the obsidian ground could take - on a
    # gold field a full-strength rim wash is a brown ring.
    vignette = Image.new("RGBA", (S, S), INK + (0,))
    vmask = Image.eval(_vignette_alpha(S, DISC_R * S), lambda v: _clamp8(v * 0.38))
    vmask = Image.composite(vmask, Image.new("L", (S, S), 0), circle)
    vignette.putalpha(vmask)
    img = Image.alpha_composite(img, vignette)

    d = ImageDraw.Draw(img)
    d.ellipse(
        [
            (0.5 - DISC_R) * S,
            (0.5 - DISC_R) * S,
            (0.5 + DISC_R) * S,
            (0.5 + DISC_R) * S,
        ],
        outline=INK + (255,),
        width=max(3, int(0.0280 * S)),
    )
    return img


RENDERERS = {
    "fast_forge": render_fast_forge,
    "auto_vent": None,
    "x2_star_matter": None,
    "vip_aura": None,
    "eternal_forge": None,
}

# Passes whose art is supplied from outside this script rather than composed
# here. `auto_vent` came out of Nano Banana and the other three arrived the same
# way; all were normalised by `scripts/prepare_gamepass_art.py` (background keyed,
# disc rescaled to 0.94). Naming them explicitly keeps `--only` honest: "no
# renderer" and "the art exists but this script did not draw it" are different
# answers, and the second one must not read like a missing badge.
SUPPLIED = {"auto_vent", "x2_star_matter", "vip_aura", "eternal_forge"}


# ---------------------------------------------------------------------------
# Write, verify, contact sheet
# ---------------------------------------------------------------------------


def _probe(path: Path) -> dict:
    """Re-open the PNG and measure the claims instead of asserting them."""
    with Image.open(path) as probe:
        probe.load()
        rgba = probe.convert("RGBA")
    w, h = rgba.size
    alpha = rgba.getchannel("A")
    bbox = alpha.getbbox()
    corners = [
        alpha.getpixel((0, 0)),
        alpha.getpixel((w - 1, 0)),
        alpha.getpixel((0, h - 1)),
        alpha.getpixel((w - 1, h - 1)),
    ]
    centre = alpha.getpixel((w // 2, h // 2))

    small = rgba.resize((64, 64), Image.Resampling.LANCZOS)
    px = small.load()
    lum = [
        0.2126 * px[x, y][0] + 0.7152 * px[x, y][1] + 0.0722 * px[x, y][2]
        for y in range(64)
        for x in range(64)
        if px[x, y][3] > 40
    ]
    lum.sort()
    if lum:
        lo = lum[int(len(lum) * 0.10)]
        hi = lum[int(len(lum) * 0.90)]
        contrast = (hi + 5.0) / (lo + 5.0)
    else:
        lo = hi = contrast = 0.0

    return {
        "size": (w, h),
        "mode": rgba.mode,
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()[:16],
        "alpha_bbox": bbox,
        "corner_alpha": corners,
        "centre_alpha": centre,
        "colours": len(rgba.getcolors(maxcolors=1 << 24) or []),
        "thumb_p10": round(lo, 1),
        "thumb_p90": round(hi, 1),
        "thumb_contrast": round(contrast, 2),
    }


def _contact_sheet(keys: list[str], cell: int = 208) -> Path:
    """One row per icon: full badge, 64px thumbnail, filename."""
    label_font = ImageFont.load_default(size=15)
    small_font = ImageFont.load_default(size=11)
    pad = 18
    thumb = 64
    width = pad * 2 + cell + pad + thumb + pad + 250
    height = pad * 2 + max(1, len(keys)) * (cell + pad)

    sheet = Image.new("RGB", (width, height), (18, 20, 26))
    d = ImageDraw.Draw(sheet)

    for row, key in enumerate(keys):
        path = OUT_DIR / f"{key}.png"
        if not path.is_file():
            continue
        y = pad + row * (cell + pad)
        with Image.open(path) as icon:
            badge = icon.convert("RGBA").resize((cell, cell), Image.Resampling.LANCZOS)
            tiny = icon.convert("RGBA").resize((thumb, thumb), Image.Resampling.LANCZOS)
        # Checkerboard behind the badge proves the corners are transparent.
        for cy in range(0, cell, 16):
            for cx in range(0, cell, 16):
                shade = 34 if ((cx // 16) + (cy // 16)) % 2 == 0 else 44
                d.rectangle(
                    [pad + cx, y + cy, pad + cx + 16, y + cy + 16],
                    fill=(shade, shade, shade + 6),
                )
        sheet.paste(badge, (pad, y), badge)
        sheet.paste(tiny, (pad + cell + pad, y + 8), tiny)
        d.text((pad + cell + pad + thumb + pad, y + 6), key, font=label_font, fill=(240, 244, 252))
        d.text(
            (pad + cell + pad + thumb + pad, y + 26),
            f"{path.stat().st_size // 1024} KB",
            font=small_font,
            fill=(150, 162, 184),
        )

    out = OUT_DIR / "contact_sheet.png"
    sheet.save(out, "PNG", optimize=True)
    return out


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--only",
        nargs="+",
        metavar="KEY",
        help=f"render just these passes. Known keys: {', '.join(PASSES)}",
    )
    parser.add_argument("--all", action="store_true", help="render every pass that has a renderer")
    parser.add_argument("--no-sheet", action="store_true", help="skip contact_sheet.png")
    parser.add_argument("--report", action="store_true", help="print the measurement table")
    args = parser.parse_args(argv)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    if args.only:
        unknown = [k for k in args.only if k not in PASSES]
        if unknown:
            sys.exit(f"Unknown gamepass key(s): {', '.join(unknown)}. Known: {', '.join(PASSES)}")
        wanted = args.only
    else:
        wanted = [k for k in PASSES if RENDERERS.get(k) is not None]

    missing = [k for k in wanted if RENDERERS.get(k) is None]
    supplied = [k for k in missing if k in SUPPLIED]
    absent = [k for k in missing if k not in SUPPLIED]
    if supplied:
        print(
            "Supplied art, not drawn by this script: "
            + ", ".join(supplied)
            + ". Normalise it with scripts/prepare_gamepass_art.py instead."
        )
    if absent:
        sys.exit(
            "No renderer written yet for: "
            + ", ".join(absent)
            + ". Art is reviewed one badge at a time; add a function to RENDERERS first."
        )
    if supplied and not absent:
        return 0

    written: list[str] = []
    for key in wanted:
        canvas = RENDERERS[key]()
        final = canvas.resize((FINAL, FINAL), Image.Resampling.LANCZOS)
        path = OUT_DIR / f"{key}.png"
        final.save(path, "PNG", optimize=True)
        written.append(key)
        print(f"wrote {path.relative_to(REPO_ROOT)}  {FINAL}x{FINAL}")

    if not args.no_sheet:
        sheet = _contact_sheet([k for k in PASSES if (OUT_DIR / f"{k}.png").is_file()])
        print(f"wrote {sheet.relative_to(REPO_ROOT)}")

    if args.report:
        print()
        print(f"{'key':<18} {'size':<10} {'kB':>5} {'colours':>8} {'b10':>6} {'b90':>6} {'contrast':>9}  sha256")
        for key in written:
            p = _probe(OUT_DIR / f"{key}.png")
            print(
                f"{key:<18} {p['size'][0]}x{p['size'][1]:<7} {p['bytes'] // 1024:>5} "
                f"{p['colours']:>8} {p['thumb_p10']:>6} {p['thumb_p90']:>6} "
                f"{p['thumb_contrast']:>9}  {p['sha256']}"
            )
            print(
                f"{'':<18} alpha corner={p['corner_alpha']} centre={p['centre_alpha']} bbox={p['alpha_bbox']}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
