#!/usr/bin/env python3
"""Generate layered VFX sprite sheets, locally, with no network and no Studio.

Implements the pipeline described in `incremental/video-02-ai-vfx-pipeline.md`:

* every effect is drawn **layer by layer** — glow, rim, body, hot core — not as
  one composite sticker;
* every layer is **pure white on transparent**, so the engine can tint the same
  sheet into plasma blue, void purple or thermal gold with no second upload;
* animation is a **4x4 / 16-frame flipbook**, in and out over the frame range;
* every stroke **tapers to a point at both ends**; there are no blunt cutoffs;
* nothing is drawn within 4 px of a frame edge (enforced numerically in
  `margin_factor`, not by eye), so a sheet cannot show a square bounding box
  when it is stretched in 3D space.

Shape rules that keep this out of clip-art territory, learned the hard way on
the first pass:

* no 1px circles — a mathematically perfect ring reads as a drawn circle, not as
  energy. Rings are wide, soft and blurred into the glow layer;
* every edge carries deterministic width jitter, so silhouettes are torn rather
  than machined;
* paths are resampled to ~1.5px before stamping. Coarse sampling turns a tapered
  stroke into a string of beads.

Outputs
-------
assets/generated/vfx/<effect>_<layer>.png   one sheet per layer, 2048x2048
assets/generated/vfx/index.json             frame timing + sheet coordinates
assets/generated/vfx/contact_sheet.png      review sheet, not shipped
src/shared/VfxManifest.luau                 sheet metadata the game reads

Asset IDs are preserved across runs: re-generating art never wipes an uploaded
ID. Only geometry and metadata are rewritten.

Everything is deterministic. Two runs on two machines produce byte-identical
PNGs, which matters because the upload step keys off content hashes.

Usage
-----
    python scripts/generate_vfx.py
    python scripts/generate_vfx.py --only slash impact
    python scripts/generate_vfx.py --frame 256 --no-manifest
"""

from __future__ import annotations

import argparse
import json
import math
import random
import re
import sys
from pathlib import Path
from typing import Callable, Sequence

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
except ImportError:  # pragma: no cover - operator error, not a code path
    sys.exit("Pillow is required. Run: pip install -r requirements.txt")


REPO_ROOT = Path(__file__).resolve().parent.parent
GENERATED_DIR = REPO_ROOT / "assets" / "generated"
VFX_DIR = GENERATED_DIR / "vfx"
MANIFEST_PATH = REPO_ROOT / "src" / "shared" / "VfxManifest.luau"

FRAME = 512
GRID = 4
FRAMES = GRID * GRID

# Pillow has no antialiasing on draw calls. Drawing at 2x and downsampling once
# is enough at 512px because the soft glow layer hides the remaining stair-step;
# 4x (as the icon script uses) doubles runtime for no visible gain on blurred
# shapes.
SS = 2

# Nothing within this many output pixels of the frame edge. Scaled with SS.
EDGE_MARGIN = 4

LAYERS = ("glow", "rim", "body", "hotcore")

WHITE = (255, 255, 255)


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def arc_points(cx: float, cy: float, radius: float, a0: float, a1: float, count: int) -> list[tuple[float, float]]:
    return [
        (cx + radius * math.cos(lerp(a0, a1, i / (count - 1))),
         cy + radius * math.sin(lerp(a0, a1, i / (count - 1))))
        for i in range(count)
    ]


def resample(points: Sequence[tuple[float, float]], step: float) -> list[tuple[float, float]]:
    """Densify a polyline so stamping produces a stroke, not a dotted line."""
    if len(points) < 2:
        return list(points)
    out: list[tuple[float, float]] = []
    for index in range(len(points) - 1):
        x0, y0 = points[index]
        x1, y1 = points[index + 1]
        span = math.hypot(x1 - x0, y1 - y0)
        count = max(1, int(span / step))
        for k in range(count):
            t = k / count
            out.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    out.append(points[-1])
    return out


def stamp(
    mask: Image.Image,
    points: Sequence[tuple[float, float]],
    width: Callable[[float], float],
    alpha: Callable[[float], float] | int,
    jitter: float = 0.0,
    seed: int = 0,
) -> None:
    """Stamp a tapered stroke along a path.

    `width(u)` is full width in pixels at path parameter u. `alpha(u)` is 0..255.
    `jitter` perturbs the width per sample so the silhouette tears instead of
    following a mathematically perfect offset curve.
    """
    path = resample(points, 1.5)
    if len(path) < 2:
        return
    draw = ImageDraw.Draw(mask)
    rng = random.Random(seed)
    count = len(path)
    for index, (x, y) in enumerate(path):
        u = index / (count - 1)
        w = width(u)
        if jitter:
            w *= 1.0 + rng.uniform(-jitter, jitter)
        radius = w * 0.5
        if radius < 0.4:
            continue
        shade = int(alpha(u) if callable(alpha) else alpha)
        if shade <= 0:
            continue
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=min(255, shade))


def taper_both(u: float, power: float = 0.7) -> float:
    """0 at both ends, 1 in the middle. The only shape allowed to touch a border."""
    return math.sin(math.pi * u) ** power


def taper_lead(u: float, heft: float = 0.45, point: float = 0.75) -> float:
    """Pointed at both ends but massed toward u=1 — a cutting edge, not a capsule."""
    return (u ** heft) * ((1 - u) ** point)


def widen(mask: Image.Image, amount: int) -> Image.Image:
    return mask.filter(ImageFilter.MaxFilter(amount * 2 + 1))


def blur_scale(mask: Image.Image, radius: float, gain: float) -> Image.Image:
    blurred = mask.filter(ImageFilter.GaussianBlur(radius))
    return blurred.point(lambda value: min(255, int(value * gain)))


# ---------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------


class Effects:
    """Each method returns {layer: L-mask} at supersampled frame size."""

    def __init__(self, size: int) -> None:
        self.size = size
        self.c = size / 2

    # -- internal ----------------------------------------------------------

    def blank(self) -> dict[str, Image.Image]:
        return {layer: Image.new("L", (self.size, self.size), 0) for layer in LAYERS}

    def finish(self, masks: dict[str, Image.Image], glow_gain: float = 0.9) -> dict[str, Image.Image]:
        """Derive the glow bloom and a *subtractive* rim from the drawn layers.

        The rim must be `dilated - body`, never `dilated`. A dilated copy is a
        fatter solid shape; composited over the body it becomes one thick slab
        with a hard border, which is exactly why the first passes read as drawn
        donuts and hard-edged cones. A subtractive band is a thin highlight that
        lives only on the silhouette, so runtime tinting can push it to a
        different colour without thickening the effect.

        The glow is two radii blended with `lighter`: a tight halo that keeps the
        shape legible plus a wide bloom that gives it light. A single blur radius
        has no falloff and reads as a flat vignette.
        """
        combined = Image.new("L", (self.size, self.size), 0)
        combined.paste(masks["body"], (0, 0), masks["body"])
        combined.paste(masks["hotcore"], (0, 0), masks["hotcore"])

        tight = blur_scale(combined, self.size * 0.010, 1.85 * glow_gain)
        wide = blur_scale(combined, self.size * 0.032, 2.40 * glow_gain)
        masks["glow"] = ImageChops.lighter(tight, wide)

        # A 1-2px band is invisible once the 512px frame is drawn at 200px on
        # screen, so the rim is sized in output pixels: ~4px after downsample.
        grown = widen(masks["body"], max(3, int(self.size * 0.007)))
        rim = ImageChops.subtract(grown, masks["body"])
        # Sub-pixel softening so the band is not an aliased staircase at 512px.
        masks["rim"] = rim.filter(ImageFilter.GaussianBlur(self.size * 0.0015))
        return masks

    def soft_ring(
        self,
        mask: Image.Image,
        radius: float,
        thickness: float,
        alpha: int,
        seed: int,
        lobes: int = 0,
    ) -> None:
        """A shockwave, not a drawn circle.

        Three things stop this reading as clip-art: the radius is modulated by a
        low-frequency sine (so the front is not a perfect circle), the thickness
        carries deterministic per-angle noise, and the whole band lives in the
        wide glow rather than as a hairline. `lobes` > 0 makes the modulation
        periodic, which is what a loop-safe aura needs.
        """
        count = 256
        rng = random.Random(seed)
        noise = [rng.uniform(0.84, 1.16) for _ in range(count)]
        wobble_phase = rng.uniform(0, math.tau)

        points: list[tuple[float, float]] = []
        for index in range(count + 1):  # +1 closes the loop without a gap
            u = index / count
            theta = u * math.tau
            wobble = 1.0
            if lobes:
                wobble += 0.032 * math.sin(theta * lobes + wobble_phase)
            wobble += 0.010 * math.sin(theta * 3.0 + wobble_phase * 0.7)
            r = radius * wobble
            points.append((self.c + math.cos(theta) * r, self.c + math.sin(theta) * r))

        def width(u: float) -> float:
            index = int(u * count) % count
            return thickness * noise[index]

        stamp(mask, points, width, alpha, jitter=0.05, seed=seed)

    # -- effects -----------------------------------------------------------

    def slash(self, frame: int) -> dict[str, Image.Image]:
        masks = self.blank()
        t = frame / (FRAMES - 1)
        ease = 1 - (1 - t) ** 2.4

        start = math.radians(-38)
        # Never zero: frame 0 has to read as a strike, not as an empty cell.
        span = math.radians(70 + 195 * ease)
        radius = self.size * (0.335 + 0.03 * ease)

        fade = 255 if t < 0.62 else int(255 * (1 - (t - 0.62) / 0.38) ** 1.4)
        fade = max(0, fade)

        path = arc_points(self.c, self.c, radius, start, start + span, 90)
        peak = self.size * 0.072 * (0.6 + 0.4 * ease)
        stamp(masks["body"], path, lambda u: peak * taper_lead(u, 0.5, 0.85), fade, jitter=0.1, seed=11)

        # Hot core: the leading third, hairline and full brightness.
        lead = path[int(len(path) * 0.6):]
        stamp(masks["hotcore"], lead, lambda u: self.size * 0.020 * taper_lead(u, 0.6, 0.9), fade, jitter=0.12, seed=12)

        # Displaced air, not a second stroke. An earlier pass drew the ghost at a
        # slightly smaller radius over the full sweep, which is a parallel twin of
        # the main arc and reads as a double slash. This one sits *outside* the
        # blade, covers less than the streak, and is far dimmer, so it reads as
        # wake instead of geometry.
        wake = arc_points(self.c, self.c, radius * 1.05, start + span * 0.18, start + span, 90)
        stamp(masks["body"], wake, lambda u: peak * 0.42 * taper_both(u, 1.1), int(fade * 0.22), jitter=0.2, seed=14)

        return self.finish(masks)

    def impact(self, frame: int) -> dict[str, Image.Image]:
        masks = self.blank()
        t = frame / (FRAMES - 1)
        ease = t ** 0.45
        rng = random.Random(7331)

        # The shock front is a ring that has *shattered*, not a circle. A
        # continuous band is a drawn donut no matter how it is shaded; six arcs
        # with uneven gaps and radii read as a wave coming apart.
        segments = 8
        for index in range(segments):
            centre = index * math.tau / segments + rng.uniform(-0.32, 0.32)
            half = rng.uniform(0.12, 0.26)
            radius = self.size * (0.245 + 0.215 * ease) * rng.uniform(0.82, 1.18)
            path = arc_points(self.c, self.c, radius, centre - half, centre + half, 20)
            width = self.size * rng.uniform(0.016, 0.032) * (1 - t * 0.45)
            alpha = int(225 * (1 - t) ** 1.2)
            stamp(
                masks["body"],
                path,
                lambda u, w=width: w * taper_both(u, 0.7),
                alpha,
                jitter=0.22,
                seed=400 + index,
            )

        # Fine debris thrown past the front. Short tangential smears at varying
        # radii: radial needles from one shared centre read as a spider.
        for index in range(12):
            angle = index * math.tau / 12 + rng.uniform(-0.30, 0.30)
            radial = max(1.0, self.size * (0.42 + rng.uniform(0, 0.20)) * ease)
            length = self.size * rng.uniform(0.030, 0.090)
            half = (length / radial) * 0.5
            path = arc_points(self.c, self.c, radial, angle - half, angle + half, 8)
            width = self.size * rng.uniform(0.006, 0.013)
            stamp(
                masks["body"],
                path,
                lambda u, w=width: w * taper_both(u, 0.8),
                int(190 * (1 - t) ** 1.5),
                seed=500 + index,
            )

        # Core flash. Small and gone in six frames — a big persistent disc turns
        # the burst into a portal.
        if t < 0.34:
            core = self.size * (0.055 + 0.040 * ease)
            stamp(
                masks["hotcore"],
                [(self.c - core * 0.1, self.c), (self.c + core * 0.1, self.c)],
                lambda u, r=core: r * 2 * taper_both(u, 0.3),
                int(255 * (1 - t / 0.34) ** 1.1),
            )

        return self.finish(masks, glow_gain=1.0)

    def vent_puffs(self) -> list[dict[str, float]]:
        """Puff parameters, drawn once per effects instance.

        Re-seeding the RNG per frame (what an earlier pass did) gives every frame
        a completely different puff layout, so the smoke boils like TV static
        instead of flowing. Identity has to persist; only the phase advances.
        """
        cached: list[dict[str, float]] | None = getattr(self, "_puffs", None)
        if cached is not None:
            return cached

        rng = random.Random(500)
        cached = [
            {
                "phase": rng.random(),
                "dx": rng.gauss(0.0, 1.0),
                "dy": rng.gauss(0.0, 1.0),
                "scale": rng.uniform(0.65, 1.45),
                "alpha": rng.uniform(0.55, 1.25),
                "sway": rng.uniform(0.0, math.tau),
            }
            for _ in range(150)
        ]
        self._puffs = cached
        return cached

    def vent(self, frame: int) -> dict[str, Image.Image]:
        masks = self.blank()
        t = frame / (FRAMES - 1)
        mouth_y = self.c + self.size * 0.26

        # A plume is a ragged cloud, not a cone. The failed passes used columns
        # with a linear drift term, which draws two straight edges no amount of
        # per-puff noise can hide. Here every puff picks its own lateral offset
        # from a gaussian whose width grows with height, so there is no boundary
        # to trace — only density falling off.
        for puff in self.vent_puffs():
            u = (puff["phase"] + t * 0.62) % 1.0
            rise = u * self.size * 0.62
            spread = self.size * (0.012 + 0.145 * u)
            sway = math.sin(u * 4.0 + t * 3.2 + puff["sway"]) * self.size * 0.022 * u
            x = self.c + puff["dx"] * spread + sway
            y = mouth_y - rise + puff["dy"] * self.size * 0.007
            radius = self.size * (0.014 + 0.036 * u) * puff["scale"]
            # Fades to nothing approaching the top, so a wrapped puff never pops
            # back into existence at the mouth.
            alpha = int(140 * (1 - t) ** 0.55 * (1 - u) ** 0.55 * puff["alpha"])
            if alpha <= 2:
                continue
            stamp(
                masks["body"],
                [(x, y), (x + 0.6, y - 0.6)],
                lambda uu, r=radius: r * 2,
                alpha,
            )

        # The throat: bright, shrinking as the vent empties.
        throat = self.size * 0.034
        stamp(
            masks["hotcore"],
            [(self.c - throat * 0.1, mouth_y), (self.c + throat * 0.1, mouth_y)],
            lambda u, r=throat: r * 2 * taper_both(u, 0.3),
            int(235 * (1 - t) ** 0.7),
        )

        # A narrow bright spine through the lower third of the plume, so the
        # steam has a light source and is not just grey noise.
        spine = [
            (self.c + math.sin(u * 3.4) * self.size * 0.012, mouth_y - u * self.size * 0.24 * (0.5 + t))
            for u in [i / 12 for i in range(13)]
        ]
        stamp(masks["hotcore"], spine, lambda u: self.size * 0.018 * taper_both(u, 0.9), int(95 * (1 - t)), jitter=0.1, seed=5)

        return self.finish(masks, glow_gain=0.95)

    def overheat(self, frame: int) -> dict[str, Image.Image]:
        masks = self.blank()
        t = frame / (FRAMES - 1)
        ease = t ** 0.55
        rng = random.Random(9001)

        if t < 0.90:
            self.soft_ring(
                masks["body"],
                self.size * (0.09 + 0.33 * ease),
                self.size * (0.050 * (1 - t) + 0.008),
                int(215 * (1 - t / 0.90) ** 1.2),
                seed=91,
                lobes=4,
            )

        # Long tangential heat arcs instead of cracks. Cracks converge on the
        # core by construction, and any number of them reads as a spider; these
        # never touch the core, so the core stays the only focal point and the
        # arcs read as expanding heat.
        for index in range(4):
            angle = index * math.tau / 4 + rng.uniform(-0.55, 0.55)
            radial = self.size * rng.uniform(0.20, 0.34) * (0.5 + ease * 0.9)
            half = rng.uniform(0.45, 0.95)
            path = arc_points(self.c, self.c, radial, angle - half, angle + half, 26)
            width = self.size * rng.uniform(0.014, 0.026)
            stamp(
                masks["body"],
                path,
                lambda u, w=width: w * taper_both(u, 0.8),
                int(155 * (1 - t) ** 1.2),
                jitter=0.22,
                seed=300 + index,
            )

        # Embers thrown off the burning core.
        for index in range(16):
            angle = rng.uniform(0, math.tau)
            radial = self.size * rng.uniform(0.11, 0.42) * (0.3 + ease)
            x = self.c + math.cos(angle) * radial
            y = self.c + math.sin(angle) * radial
            ember = self.size * rng.uniform(0.005, 0.011)
            stamp(
                masks["body"],
                [(x - 0.5, y), (x + 0.5, y)],
                lambda u, r=ember: r * 2,
                int(200 * (1 - t) ** 1.5),
            )

        if t < 0.5:
            core = self.size * (0.075 + 0.05 * ease)
            stamp(
                masks["hotcore"],
                [(self.c - core * 0.1, self.c), (self.c + core * 0.1, self.c)],
                lambda u, r=core: r * 2 * taper_both(u, 0.3),
                int(255 * (1 - t / 0.5) ** 1.1),
            )

        return self.finish(masks, glow_gain=1.0)

    def aura(self, frame: int) -> dict[str, Image.Image]:
        """Loop-safe: frame FRAMES wraps to frame 0 with no visible seam."""
        masks = self.blank()
        phase = frame / FRAMES

        # Base ring, steady. The three-lobe modulation means it is not a compass
        # circle, and the width is generous so the rim derivation has something
        # to cut a band out of instead of shaving a hairline.
        self.soft_ring(masks["body"], self.size * 0.355, self.size * 0.014, 92, seed=41, lobes=3)

        rng = random.Random(31337)
        for index in range(11):
            offset = rng.uniform(0, math.tau)
            angle = offset + phase * math.tau
            radial = self.size * (0.355 + rng.uniform(-0.035, 0.035))
            cx = self.c + math.cos(angle) * radial
            cy = self.c + math.sin(angle) * radial
            length = self.size * rng.uniform(0.055, 0.100)
            direction = angle + math.pi / 2 + rng.uniform(-0.45, 0.45)
            path = [
                (cx + math.cos(direction) * length * (i / 8 - 0.5),
                 cy + math.sin(direction) * length * (i / 8 - 0.5))
                for i in range(9)
            ]
            stamp(
                masks["body"],
                path,
                lambda u, w=self.size * rng.uniform(0.010, 0.017): w * taper_lead(u, 0.45, 1.0),
                215,
                jitter=0.16,
                seed=200 + index,
            )

        # Two slow motes that counter-rotate against the ring, which is what
        # makes the loop read as motion rather than as a spinning disc.
        for index in range(2):
            angle = -phase * math.tau * 0.6 + index * math.pi
            radial = self.size * 0.30
            cx = self.c + math.cos(angle) * radial
            cy = self.c + math.sin(angle) * radial
            stamp(
                masks["hotcore"],
                [(cx - 0.5, cy), (cx + 0.5, cy)],
                lambda u: self.size * 0.028 * taper_both(u, 0.35),
                170,
            )

        return self.finish(masks, glow_gain=0.9)


EFFECTS: dict[str, tuple[Callable[[Effects, int], dict[str, Image.Image]], int, bool]] = {
    # name: (builder, fps, loop)
    "slash": (Effects.slash, 30, False),
    "impact": (Effects.impact, 26, False),
    "vent": (Effects.vent, 22, False),
    "overheat": (Effects.overheat, 24, False),
    "aura": (Effects.aura, 20, True),
}


# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------


def margin_factor(mask: Image.Image, margin: int) -> float:
    """Largest centre-anchored scale that keeps `mask` inside the safe area."""
    bbox = mask.getbbox()
    if bbox is None:
        return 1.0
    left, top, right, bottom = bbox
    size = mask.size[0]
    centre = size / 2
    room = (centre - margin, centre - margin, size - margin - centre, size - margin - centre)
    reach = (centre - left, centre - top, right - centre, bottom - centre)
    factor = 1.0
    for available, distance in zip(room, reach):
        if distance > 0:
            factor = min(factor, available / distance)
    return factor


def scale_about_centre(mask: Image.Image, factor: float) -> Image.Image:
    if factor >= 1.0:
        return mask
    size = mask.size[0]
    side = max(1, int(round(size * factor)))
    inner = mask.resize((side, side), Image.LANCZOS)
    canvas = Image.new("L", mask.size, 0)
    offset = (size - side) // 2
    canvas.paste(inner, (offset, offset))
    return canvas


def frame_to_rgba(mask: Image.Image) -> Image.Image:
    rgba = Image.new("RGBA", mask.size, WHITE + (0,))
    rgba.putalpha(mask)
    return rgba


def build_sheet(builder: Callable[[Effects, int], dict[str, Image.Image]], frame_px: int, margin_out: int) -> dict[str, Image.Image]:
    internal = frame_px * SS
    effects = Effects(internal)
    margin_in = margin_out * SS

    # Pass 1: draw every frame. Pass 2: apply one scale to the whole effect.
    # Scaling per frame would make an effect pulse in size as its bounding box
    # crossed the margin on some frames and not others.
    frames: list[dict[str, Image.Image]] = [builder(effects, index) for index in range(FRAMES)]

    factor = 1.0
    for masks in frames:
        for mask in masks.values():
            factor = min(factor, margin_factor(mask, margin_in))

    sheets = {layer: Image.new("RGBA", (frame_px * GRID, frame_px * GRID), WHITE + (0,)) for layer in LAYERS}

    for index, masks in enumerate(frames):
        column, row = index % GRID, index // GRID
        for layer in LAYERS:
            mask = scale_about_centre(masks[layer], factor)
            cell = frame_to_rgba(mask).resize((frame_px, frame_px), Image.LANCZOS)
            sheets[layer].paste(cell, (column * frame_px, row * frame_px), cell)

    return sheets


def build_particle(kind: str, size: int = 64) -> Image.Image:
    """Single-frame particle texture. ParticleEmitters need one image, not a sheet."""
    image = Image.new("RGBA", (size, size), WHITE + (0,))
    pixels = image.load()
    centre = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            dx = (x - centre) / centre
            dy = (y - centre) / centre
            distance = math.sqrt(dx * dx + dy * dy)
            if distance >= 1.0:
                continue
            if kind == "spark":
                alpha = (1 - distance) ** 2.4
            else:  # ember: tighter core, asymmetric tail
                alpha = (1 - distance) ** 1.5 * (0.55 + 0.45 * (1 - dy) * 0.5)
            pixels[x, y] = WHITE + (int(255 * min(1.0, alpha)),)
    return image


def check_margin(sheet: Image.Image, frame_px: int, margin: int) -> int:
    """Smallest distance from any opaque pixel to its frame border.

    The 4px rule is the whole reason a sheet does not show a square bounding box
    when it is stretched over a part, so it gets measured rather than trusted:
    the downsample from supersampled masks can bleed a pixel or two.
    """
    worst = frame_px
    alpha = sheet.split()[3]
    for row in range(GRID):
        for column in range(GRID):
            cell = alpha.crop(
                (column * frame_px, row * frame_px, (column + 1) * frame_px, (row + 1) * frame_px)
            )
            bbox = cell.getbbox()
            if bbox is None:
                continue
            left, top, right, bottom = bbox
            worst = min(worst, left, top, frame_px - right, frame_px - bottom)
    return worst


def make_contact_sheet(
    sheets: dict[str, dict[str, Image.Image]],
    frame_px: int,
    out_path: Path,
    cell: int = 128,
    preview_frames: Sequence[int] = (0, 4, 8, 12),
    backdrop: tuple[int, int, int, int] = (10, 12, 18, 255),
) -> None:
    """Composite the white-on-alpha sheets onto a dark board for human review.

    The sheets themselves are pure white with an alpha channel, so opening one
    directly shows nothing at all — it has to be composited before it means
    anything. Rows are effects, columns are the sampled frames.
    """
    rows = len(sheets)
    sheet = Image.new("RGBA", (cell * len(preview_frames), cell * rows), backdrop)

    for row, (_name, layers) in enumerate(sheets.items()):
        for column, frame in enumerate(preview_frames):
            composite = Image.new("RGBA", (frame_px, frame_px), backdrop)
            for layer in LAYERS:
                source = layers[layer]
                composite.alpha_composite(
                    source.crop(
                        ((frame % GRID) * frame_px, (frame // GRID) * frame_px,
                         (frame % GRID) * frame_px + frame_px, (frame // GRID) * frame_px + frame_px)
                    )
                )
            sheet.paste(composite.resize((cell, cell), Image.LANCZOS), (column * cell, row * cell))

    sheet.save(out_path)


# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

EXISTING_ID_RE = re.compile(r'([A-Za-z0-9_]+)\s*=\s*"rbxassetid://(\d+)"')


def load_existing_ids() -> dict[str, str]:
    """Preserve uploaded IDs so re-generating art never un-publishes a sheet."""
    if not MANIFEST_PATH.exists():
        return {}
    text = MANIFEST_PATH.read_text(encoding="utf-8")
    return {key: f"rbxassetid://{value}" for key, value in EXISTING_ID_RE.findall(text)}


def luau_manifest(effect_meta: dict[str, dict], particle_meta: dict[str, dict], ids: dict[str, str]) -> str:
    lines = [
        "--!strict",
        "-- GENERATED by scripts/generate_vfx.py. Do not hand-edit the tables.",
        "--",
        "-- `Sheets` is a flat key -> asset-id map, the same shape as",
        "-- `AssetManifest.Assets`, so the uploader can rewrite one block and the game",
        "-- can build a key with `effect .. \"_\" .. layer`. `rbxassetid://0` means the",
        "-- sheet has not been uploaded and the effect must fall back to procedural",
        "-- drawing rather than rendering an empty ImageLabel.",
        "--",
        "-- The manifest is annotated rather than inferred on purpose: an inferred",
        "-- table literal with named keys is *sealed*, and indexing it with a computed",
        "-- string is a strict-mode error. Without the annotation `Sheets[key]` below",
        "-- would not compile.",
        "",
        "export type EffectMeta = {",
        "\tframes: number,",
        "\tfps: number,",
        "\tloop: boolean,",
        "}",
        "",
        "export type Manifest = {",
        "\tFrameSize: number,",
        "\tColumns: number,",
        "\tRows: number,",
        "\tLayerOrder: { string },",
        "\tSheets: { [string]: string },",
        "\tEffects: { [string]: EffectMeta },",
        "\tlayer: (effect: string, layerName: string) -> string?,",
        "\tisReal: () -> boolean,",
        "}",
        "",
        'local PLACEHOLDER = "rbxassetid://0"',
        "",
        "local VfxManifest = {} :: Manifest",
        "",
        f"VfxManifest.FrameSize = {FRAME}",
        f"VfxManifest.Columns = {GRID}",
        f"VfxManifest.Rows = {GRID}",
        'VfxManifest.LayerOrder = { "glow", "rim", "body", "hotcore" }',
        "",
        "VfxManifest.Sheets = {",
    ]
    for name in effect_meta:
        for layer in LAYERS:
            key = f"{name}_{layer}"
            lines.append(f'\t{key} = "{ids.get(key, "rbxassetid://0")}",')
    for name in particle_meta:
        key = f"particle_{name}"
        lines.append(f'\t{key} = "{ids.get(key, "rbxassetid://0")}",')
    lines.append("}")
    lines.append("")
    lines.append("VfxManifest.Effects = {")
    for name, meta in effect_meta.items():
        lines.append(
            f"\t{name} = {{ frames = {meta['frames']}, fps = {meta['fps']}, "
            f"loop = {'true' if meta['loop'] else 'false'} }},"
        )
    lines.append("}")
    lines.append("")
    lines.append("--- Asset id for one layer of one effect, or nil when not uploaded.")
    lines.append("function VfxManifest.layer(effect: string, layerName: string): string?")
    lines.append('\tlocal id = VfxManifest.Sheets[effect .. "_" .. layerName]')
    lines.append("\tif id == nil or id == PLACEHOLDER then")
    lines.append("\t\treturn nil")
    lines.append("\tend")
    lines.append("\treturn id")
    lines.append("end")
    lines.append("")
    lines.append("--- True when at least one sheet has been uploaded.")
    lines.append("function VfxManifest.isReal(): boolean")
    lines.append("\tfor _, id in VfxManifest.Sheets do")
    lines.append("\t\tif id ~= PLACEHOLDER then")
    lines.append("\t\t\treturn true")
    lines.append("\t\tend")
    lines.append("\tend")
    lines.append("\treturn false")
    lines.append("end")
    lines.append("")
    lines.append("return VfxManifest")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", nargs="*", default=None, help="subset of effect names")
    parser.add_argument("--frame", type=int, default=FRAME, help=f"pixels per frame (default {FRAME})")
    parser.add_argument("--no-manifest", action="store_true", help="skip writing src/shared/VfxManifest.luau")
    parser.add_argument("--review", action="store_true", help="also write a large all-16-frames review board")
    parser.add_argument("--layers", default=None, metavar="EFFECT", help="write a per-layer board for one effect")
    args = parser.parse_args(argv)

    if args.frame % GRID != 0:
        parser.error("--frame must be divisible by 4")

    names = args.only or list(EFFECTS)
    unknown = [name for name in names if name not in EFFECTS]
    if unknown:
        parser.error(f"unknown effect(s): {', '.join(unknown)}")

    VFX_DIR.mkdir(parents=True, exist_ok=True)

    sheets: dict[str, dict[str, Image.Image]] = {}
    effect_meta: dict[str, dict] = {}
    margin_report: dict[str, int] = {}

    for name in names:
        builder, fps, loop = EFFECTS[name]
        print(f"  {name}: {FRAMES} frames x {len(LAYERS)} layers at {args.frame}px")
        layer_sheets = build_sheet(builder, args.frame, EDGE_MARGIN)
        sheets[name] = layer_sheets

        worst = min(check_margin(image, args.frame, EDGE_MARGIN) for image in layer_sheets.values())
        status = "ok" if worst >= EDGE_MARGIN else f"TIGHT (want >= {EDGE_MARGIN})"
        print(f"    margin {worst}px  {status}")
        margin_report[name] = worst

        for layer, image in layer_sheets.items():
            image.save(VFX_DIR / f"{name}_{layer}.png")
        effect_meta[name] = {"frames": FRAMES, "fps": fps, "loop": loop}

    particle_meta: dict[str, dict] = {}
    for kind in ("spark", "ember"):
        image = build_particle(kind)
        image.save(VFX_DIR / f"particle_{kind}.png")
        particle_meta[kind] = {"size": image.size[0]}

    index = {
        "generated_with": "scripts/generate_vfx.py",
        "frame_size": args.frame,
        "columns": GRID,
        "rows": GRID,
        "layer_order": list(LAYERS),
        "effects": {
            name: {
                **meta,
                "sheet_size": args.frame * GRID,
                "layers": {layer: f"vfx/{name}_{layer}.png" for layer in LAYERS},
            }
            for name, meta in effect_meta.items()
        },
        "particles": {name: f"vfx/particle_{name}.png" for name in particle_meta},
    }
    (VFX_DIR / "index.json").write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")

    make_contact_sheet(sheets, args.frame, VFX_DIR / "contact_sheet.png")

    if args.review:
        make_contact_sheet(
            sheets,
            args.frame,
            VFX_DIR / "review.png",
            cell=192,
            preview_frames=tuple(range(FRAMES)),
        )

    if args.layers is not None:
        if args.layers not in sheets:
            parser.error(f"unknown effect for --layers: {args.layers}")
        empty = Image.new("RGBA", (args.frame * GRID, args.frame * GRID), WHITE + (0,))
        layer_rows = {
            layer: {other: (sheets[args.layers][other] if other == layer else empty) for other in LAYERS}
            for layer in LAYERS
        }
        make_contact_sheet(
            layer_rows,
            args.frame,
            VFX_DIR / f"layers_{args.layers}.png",
            cell=160,
            preview_frames=(0, 4, 8, 12),
        )

    if not args.no_manifest:
        ids = load_existing_ids()
        MANIFEST_PATH.write_text(luau_manifest(effect_meta, particle_meta, ids), encoding="utf-8")

    files = len(list(VFX_DIR.glob("*.png")))
    print(f"  wrote {files} PNGs, index.json, contact_sheet.png")

    tight = {name: value for name, value in margin_report.items() if value < EDGE_MARGIN}
    if tight:
        for name, value in tight.items():
            print(f"  MARGIN VIOLATION {name}: {value}px < {EDGE_MARGIN}px")
        return 1

    if not args.no_manifest:
        print(f"  wrote {MANIFEST_PATH.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
