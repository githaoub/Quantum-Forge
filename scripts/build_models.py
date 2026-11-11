#!/usr/bin/env python3
"""Build the blade catalogue and the fleet drone as game-ready meshes in Blender.

Run *inside* Blender (the DCC-MCP gateway calls it via
`blender_scripting__execute_script_file`, or use
`scripts/blender.cmd --background --python scripts/build_models.py`).

What it guarantees, because the engine cares about all of it:

* under 2,500 triangles per model;
* built along +Z in Blender, tip up, cutting edge facing -Y. The FBX export
  (`axis_forward='-Z'`, `axis_up='Y'`) maps that to +Y up / -Z forward in
  Roblox, which is what the viewport cameras assume;
* origin exactly at the base of the hilt (z = 0 at the bottom of the pommel), so
  a `PivotTo` puts the grip in the hand and the blade above it;
* two objects per blade: `<id>` for the metal body and `<id>_glow` for the
  emissive core, runes and vents. Roblox imports them as separate MeshParts, so
  the client can give the core `Neon` and the body `Metal` without a texture.

The catalogue is parsed out of `src/shared/BladeRegistry.luau` rather than
duplicated, so adding a blade to the Luau table is enough to get it into the
build. Silhouette parameters are per id in `RECIPES` below; the registry only
carries colours and tier.

Geometry is authored from explicit vertex/face lists instead of `bpy.ops`
primitives. Every part then shares one world origin, which means no
`transform_apply` pass and no chance of an object's origin drifting away from
the hilt between runs.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import sys
from pathlib import Path

import bpy
import bmesh

# Bump when the export settings (axis, scale, smoothing) change. It feeds
# `geometry_hash`, so an export contract change invalidates the upload cache
# even when the mesh itself is identical.
EXPORT_VERSION = 2


def _repo_root() -> Path:
    """Locate the repo without relying on `__file__`.

    Blender's script-file executor runs this via `exec()`, where `__file__` is
    not guaranteed and `__name__` is not `"__main__"`. Rather than guess, walk
    up from every plausible anchor until the catalogue is actually found. A
    wrong root writes twenty-six meshes into the wrong directory and reports
    success while doing it.
    """
    anchors: list[Path] = []
    try:
        anchors.append(Path(__file__).resolve().parent)
    except NameError:
        pass
    if os.environ.get("QF_REPO_ROOT"):
        anchors.append(Path(os.environ["QF_REPO_ROOT"]).resolve())
    anchors.append(Path.cwd().resolve())

    for anchor in anchors:
        for candidate in (anchor, *anchor.parents):
            if (candidate / "src" / "shared" / "BladeRegistry.luau").is_file():
                return candidate
    raise RuntimeError(
        "could not find the repo root: no ancestor of "
        f"{[str(a) for a in anchors]} contains src/shared/BladeRegistry.luau"
    )


REPO_ROOT = _repo_root()
REGISTRY_PATH = REPO_ROOT / "src" / "shared" / "BladeRegistry.luau"
OUT_DIR = REPO_ROOT / "assets" / "models"

TRI_BUDGET = 2500

# Total height in studs per tier, grip and guard included. A tier-1 cleaver is a
# short tool; the tier-5 relic is a two-handed greatsword. The runtime rescales
# to this number from the manifest, so the file's own unit scale does not matter.
TIER_HEIGHT = {1: 4.0, 2: 4.6, 3: 5.2, 4: 5.8, 5: 6.4}

# ---------------------------------------------------------------------------
# Silhouette recipes
# ---------------------------------------------------------------------------
#
# One line per registry id. These are the sculpting notes, not a colour swap:
# `guard` and `pommel` name real sub-assemblies, `curve` bends the blade in the
# XZ plane, `split` cuts it into two halves with a core between them, and
# `notches` saws chunks out of a scrap edge.
#
# Fields:
#   grip, guard_h  fractions of total height taken by the hilt and the guard
#   width          blade width at the ricasso, as a fraction of total height
#   thick          blade thickness at the ricasso, fraction of total height
#   curve          sideways sweep at the tip, fraction of total height
#   belly          extra width in the lower third (falchion mass)
#   tip            where the taper starts (0.55 = holds width to 55% then converges)
#   double         both edges sharp; otherwise the +Y side is a blunt spine
#   guard          bar | chevron | vguard | horns | clamp | ring
#   pommel         cap | spike | crystal | ring
#   glow           none | fuller | split | vent
#   runes          number of neon ticks on the flat
#   notches        number of saw teeth cut into the cutting edge
#   split          blade is two halves with a suspended core

RECIPES: dict[str, dict] = {
    # --- Tier 1: scrap. Short, brutal, repaired rather than made. -------------
    "rusted_cleaver": dict(grip=0.16, guard_h=0.035, width=0.150, thick=0.030, curve=0.00, belly=0.10, tip=0.62, double=False, guard="bar", pommel="cap", glow="fuller", runes=0, notches=3, split=False),
    "scrap_fang": dict(grip=0.15, guard_h=0.030, width=0.120, thick=0.026, curve=0.10, belly=0.04, tip=0.45, double=False, guard="chevron", pommel="spike", glow="vent", runes=0, notches=2, split=False),
    "rivet_edge": dict(grip=0.17, guard_h=0.032, width=0.105, thick=0.022, curve=0.00, belly=0.00, tip=0.58, double=True, guard="bar", pommel="cap", glow="none", runes=0, notches=0, split=False),
    "coil_shard": dict(grip=0.15, guard_h=0.034, width=0.118, thick=0.024, curve=0.13, belly=0.06, tip=0.52, double=False, guard="vguard", pommel="ring", glow="vent", runes=1, notches=0, split=False),
    "cinder_spike": dict(grip=0.15, guard_h=0.036, width=0.085, thick=0.020, curve=0.00, belly=0.00, tip=0.40, double=True, guard="horns", pommel="spike", glow="vent", runes=0, notches=0, split=False),
    # --- Tier 2: forged. Industrial, heavy, visibly assembled. ----------------
    "iron_vigil": dict(grip=0.18, guard_h=0.040, width=0.140, thick=0.030, curve=0.00, belly=0.00, tip=0.60, double=True, guard="clamp", pommel="ring", glow="fuller", runes=1, notches=0, split=False),
    "forgebrand": dict(grip=0.20, guard_h=0.042, width=0.190, thick=0.036, curve=0.00, belly=0.03, tip=0.66, double=True, guard="horns", pommel="crystal", glow="fuller", runes=2, notches=0, split=False),
    "temperline": dict(grip=0.16, guard_h=0.036, width=0.122, thick=0.026, curve=0.12, belly=0.07, tip=0.54, double=False, guard="vguard", pommel="cap", glow="fuller", runes=2, notches=0, split=False),
    "anvils_oath": dict(grip=0.21, guard_h=0.044, width=0.205, thick=0.038, curve=0.00, belly=0.00, tip=0.68, double=True, guard="clamp", pommel="spike", glow="fuller", runes=2, notches=0, split=False),
    "slagspite": dict(grip=0.16, guard_h=0.038, width=0.165, thick=0.032, curve=0.17, belly=0.09, tip=0.48, double=False, guard="horns", pommel="crystal", glow="vent", runes=1, notches=3, split=False),
    # --- Tier 3: astral. Long, slim, a core running through the steel. --------
    "nova_reaver": dict(grip=0.17, guard_h=0.038, width=0.160, thick=0.028, curve=0.15, belly=0.05, tip=0.55, double=True, guard="vguard", pommel="crystal", glow="split", runes=2, notches=0, split=True),
    "starlight_falchion": dict(grip=0.16, guard_h=0.036, width=0.128, thick=0.024, curve=0.18, belly=0.08, tip=0.50, double=False, guard="vguard", pommel="ring", glow="split", runes=3, notches=0, split=True),
    "comets_wake": dict(grip=0.16, guard_h=0.040, width=0.140, thick=0.026, curve=0.04, belly=0.00, tip=0.60, double=True, guard="horns", pommel="spike", glow="split", runes=2, notches=0, split=True),
    "gravwell_sabre": dict(grip=0.17, guard_h=0.038, width=0.158, thick=0.030, curve=0.14, belly=0.06, tip=0.52, double=False, guard="clamp", pommel="crystal", glow="split", runes=3, notches=0, split=True),
    "astral_cutter": dict(grip=0.16, guard_h=0.036, width=0.146, thick=0.026, curve=0.20, belly=0.04, tip=0.50, double=True, guard="ring", pommel="crystal", glow="split", runes=3, notches=0, split=True),
    # --- Tier 4: void. Mass and absence. Wider chassis, colder cores. --------
    "nullbreaker": dict(grip=0.19, guard_h=0.042, width=0.215, thick=0.040, curve=0.00, belly=0.00, tip=0.66, double=True, guard="clamp", pommel="spike", glow="split", runes=3, notches=0, split=True),
    "voidfang": dict(grip=0.16, guard_h=0.040, width=0.176, thick=0.032, curve=0.21, belly=0.10, tip=0.44, double=False, guard="horns", pommel="crystal", glow="vent", runes=3, notches=3, split=False),
    "entropy_edge": dict(grip=0.17, guard_h=0.038, width=0.150, thick=0.028, curve=0.05, belly=0.00, tip=0.58, double=True, guard="clamp", pommel="ring", glow="split", runes=3, notches=0, split=True),
    "event_horizon": dict(grip=0.16, guard_h=0.036, width=0.164, thick=0.028, curve=0.22, belly=0.04, tip=0.48, double=True, guard="ring", pommel="crystal", glow="split", runes=3, notches=0, split=True),
    "blackstar_glaive": dict(grip=0.17, guard_h=0.038, width=0.142, thick=0.026, curve=0.24, belly=0.05, tip=0.46, double=True, guard="vguard", pommel="spike", glow="split", runes=3, notches=0, split=True),
    # --- Tier 5: quantum. The endgame silhouettes. ----------------------------
    "hadron_splitter": dict(grip=0.19, guard_h=0.044, width=0.222, thick=0.040, curve=0.00, belly=0.00, tip=0.64, double=True, guard="clamp", pommel="crystal", glow="split", runes=4, notches=0, split=True),
    "quanta_verge": dict(grip=0.17, guard_h=0.040, width=0.150, thick=0.026, curve=0.06, belly=0.00, tip=0.56, double=True, guard="ring", pommel="crystal", glow="split", runes=4, notches=0, split=True),
    "singularity_blade": dict(grip=0.17, guard_h=0.040, width=0.168, thick=0.030, curve=0.19, belly=0.03, tip=0.52, double=True, guard="vguard", pommel="crystal", glow="split", runes=4, notches=0, split=True),
    "entangle_scythe": dict(grip=0.46, guard_h=0.022, width=0.132, thick=0.024, curve=0.34, belly=0.00, tip=0.40, double=False, guard="horns", pommel="spike", glow="split", runes=4, notches=0, split=True),
    "forge_eternal": dict(grip=0.20, guard_h=0.046, width=0.235, thick=0.042, curve=0.00, belly=0.00, tip=0.66, double=True, guard="clamp", pommel="crystal", glow="split", runes=5, notches=0, split=True),
}

# Fallback for an id that has no line above. Never a stick: it derives a full
# sword from the registry fields so a new blade renders before its recipe lands.
PROFILE_FALLBACK = {
    "straight": dict(width=0.120, curve=0.00, belly=0.00, tip=0.58, double=True, grip=0.16, guard_h=0.038),
    "curved": dict(width=0.128, curve=0.14, belly=0.06, tip=0.52, double=False, grip=0.16, guard_h=0.038),
    "glaive": dict(width=0.112, curve=0.09, belly=0.04, tip=0.60, double=True, grip=0.48, guard_h=0.022),
    "scythe": dict(width=0.100, curve=0.30, belly=0.00, tip=0.42, double=False, grip=0.58, guard_h=0.020),
    "greatsword": dict(width=0.190, curve=0.00, belly=0.02, tip=0.66, double=True, grip=0.20, guard_h=0.042),
}

RING_COUNT = 16
GLOW_RINGS = 12


# ---------------------------------------------------------------------------
# Registry parsing
# ---------------------------------------------------------------------------


def _number(text: str) -> float:
    return float(text)


def _colour(block: str, key: str) -> tuple[int, int, int] | None:
    match = re.search(rf"{key}\s*=\s*\{{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\}}", block)
    if not match:
        return None
    return tuple(int(match.group(i)) for i in (1, 2, 3))


def parse_registry() -> list[dict]:
    """Pull every blade record out of the Luau catalogue.

    Deliberately a regex over record bodies rather than a Luau parser: the table
    is a flat list of `{ ... }` records with literal fields, and a real parser
    would be more code than the thing it parses.
    """
    source = REGISTRY_PATH.read_text(encoding="utf-8")
    blades: list[dict] = []
    for block in re.finditer(r"\{\s*id\s*=\s*\"([^\"]+)\"(.*?)\n\t\}", source, re.S):
        blade_id, body = block.group(1), block.group(2)
        name = re.search(r'name\s*=\s*"([^"]+)"', body)
        tier = re.search(r"tier\s*=\s*(\d+)", body)
        shape = re.search(r'shape\s*=\s*"([^"]+)"', body)
        material = re.search(r'material\s*=\s*"([^"]+)"', body)
        blades.append(
            {
                "id": blade_id,
                "name": name.group(1) if name else blade_id,
                "tier": int(tier.group(1)) if tier else 1,
                "shape": shape.group(1) if shape else "straight",
                "material": material.group(1) if material else "Metal",
                "bladeColor": _colour(body, "bladeColor"),
                "glowColor": _colour(body, "glowColor"),
                "gripColor": _colour(body, "gripColor"),
            }
        )
    return blades


def recipe_for(spec: dict) -> dict:
    recipe = RECIPES.get(spec["id"])
    if recipe is not None:
        return recipe
    base = dict(PROFILE_FALLBACK.get(spec["shape"], PROFILE_FALLBACK["straight"]))
    base.update(
        guard="vguard" if spec["tier"] >= 3 else "bar",
        pommel="crystal" if spec["tier"] >= 3 else "cap",
        glow="split" if spec["tier"] >= 3 else "fuller",
        runes=max(0, spec["tier"] - 1),
        notches=2 if spec["tier"] == 1 else 0,
        split=spec["tier"] >= 3,
    )
    return base


# ---------------------------------------------------------------------------
# Mesh primitives
# ---------------------------------------------------------------------------


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.objects):
        for item in list(block):
            if getattr(item, "users", 0) == 0:
                block.remove(item)


def add_object(name: str, verts, faces) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def join_objects(objects: list[bpy.types.Object], name: str) -> bpy.types.Object | None:
    """Join a group into one object. Returns the survivor."""
    objects = [obj for obj in objects if obj is not None]
    if not objects:
        return None
    if len(objects) == 1:
        objects[0].name = name
        return objects[0]

    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    return joined


def section_points(half_w: float, half_t: float, double: bool):
    """One cross-section in the XY plane: width spans Y, thickness spans X.

    `double` puts a ridge on the +Y side and a sharp vertex on -Y, so both edges
    cut. A single-edged blade keeps a blunt spine across +Y instead.
    """
    if double:
        return [
            (0.0, -half_w),
            (half_t, -half_w * 0.42),
            (half_t * 0.92, half_w * 0.55),
            (0.0, half_w * 0.92),
            (-half_t * 0.92, half_w * 0.55),
            (-half_t, -half_w * 0.42),
        ]
    return [
        (0.0, -half_w),
        (half_t, -half_w * 0.30),
        (half_t, half_w * 0.90),
        (0.0, half_w * 1.00),
        (-half_t, half_w * 0.90),
        (-half_t, -half_w * 0.30),
    ]


def _lane_points(half_w: float, half_t: float, gap: float, lane: str, double: bool):
    """Cross-section for one lane of a blade.

    `full` is a whole blade. `edge` and `spine` are the two halves of a split
    blade, cut along the width axis: the edge half keeps the cutting vertex, the
    spine half keeps the thick back, and the flat walls face each other across
    `gap`.
    """
    if lane == "full":
        return section_points(half_w, half_t, double)
    if lane == "edge":
        return [
            (0.0, -half_w),
            (half_t, -half_w * 0.42),
            (half_t, -gap * 0.90),
            (0.0, -gap),
            (-half_t, -gap * 0.90),
            (-half_t, -half_w * 0.42),
        ]
    return [
        (half_t, gap * 0.90),
        (half_t, half_w * 0.55),
        (0.0, half_w * 0.92),
        (-half_t, half_w * 0.55),
        (-half_t, gap * 0.90),
        (0.0, gap),
    ]


def loft(name: str, z0: float, height: float, recipe: dict, total: float, gap: float = 0.0):
    """Loft the blade body along +Z.

    Width follows `tip` (hold, then converge), `belly` swells the lower third,
    `curve` sweeps the tip sideways, and `notches` saws the cutting edge. The
    last ring collapses to an edge so the tip is a point, not a blunt cap.

    `gap` > 0 cuts the blade along its width into two lanes and closes the cut
    again over the last fifth, so the split reads as a channel through the blade
    rather than a slot through the whole tip.

    The earlier version offset two full-width blades along the thickness axis,
    which is a sandwich: from most angles you looked straight through the seam
    and the sword read as hollow. Splitting across the width is what puts real
    steel on both sides of the light.
    """
    width = recipe["width"] * total
    thickness = recipe["thick"] * total
    curve = recipe["curve"] * total
    belly = recipe["belly"]
    tip_start = recipe["tip"]
    double = recipe["double"]
    notches = recipe.get("notches", 0)

    lanes = ["full"] if gap <= 0.0 else ["edge", "spine"]
    ring_size = 6
    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []

    for lane in lanes:
        base = len(verts)
        for index in range(RING_COUNT):
            u = (index / (RING_COUNT - 1)) * 0.97
            if u <= tip_start:
                taper = 1.0
            else:
                t = (u - tip_start) / (1.0 - tip_start)
                taper = (1.0 - t) ** 0.78
            swell = 1.0 + belly * math.sin(math.pi * u) * (1.0 - u)
            half_w = width * 0.5 * taper * swell
            # Saw teeth: an alternating bite out of the cutting edge, in the
            # middle third where a scrap blade would actually be damaged.
            if notches and 0.28 < u < 0.78 and index % 3 == 1:
                half_w *= 1.0 - 0.16 * (notches / 3.0)
            half_t = thickness * 0.5 * (1.0 - 0.72 * u)
            # Close the channel before the tip: a slit that runs to the point
            # leaves two loose prongs instead of a blade.
            gap_u = gap * max(0.0, min(1.0, 1.0 - (u - 0.80) / 0.20))
            z = z0 + u * height
            for x, y in _lane_points(half_w, half_t, gap_u, lane, double):
                verts.append((x, y + curve * (u ** 1.7), z))

        for index in range(RING_COUNT - 1):
            a = base + index * ring_size
            b = (index + 1) * ring_size + base
            for k in range(ring_size):
                k2 = (k + 1) % ring_size
                faces.append((a + k, a + k2, b + k2, b + k))

    # Tip: a real converging point, shared by both lanes.
    tip_index = len(verts)
    verts.append((0.0, curve + width * 0.01, z0 + height))
    for lane_number in range(len(lanes)):
        last = lane_number * RING_COUNT * ring_size + (RING_COUNT - 1) * ring_size
        for k in range(ring_size):
            k2 = (k + 1) % ring_size
            faces.append((last + k, last + k2, tip_index))

    # Base caps last, reversed so the winding stays outward. Face order is part
    # of `geometry_hash`, and this order matches the pre-split builder exactly, so
    # a solid blade does not re-upload just because the split path was rewritten.
    for lane_number in range(len(lanes)):
        base = lane_number * RING_COUNT * ring_size
        faces.append(tuple(range(base + ring_size - 1, base - 1, -1)))

    return add_object(name, verts, faces)


def glow_channel(name: str, z0: float, height: float, recipe: dict, total: float, gap: float):
    """The emissive core.

    A split blade gets one slab filling the channel between the two lanes, run
    from the guard to where the cut closes. A solid blade inlays it as a fuller:
    a narrow strip on the flat, standing a few percent proud of the surface so it
    reads at thumbnail size.

    Both are `Neon` on the client, which is the whole reason they are a separate
    object: one material per MeshPart, and the body must stay metal.
    """
    width = recipe["width"] * total
    thickness = recipe["thick"] * total
    curve = recipe["curve"] * total
    tip_start = recipe["tip"]
    split = gap > 0.0
    u_max = 0.80 if split else 0.86

    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    ring_size = 4

    for index in range(GLOW_RINGS):
        u = (index / (GLOW_RINGS - 1)) * u_max
        if u <= tip_start:
            taper = 1.0
        else:
            t = (u - tip_start) / (1.0 - tip_start)
            taper = (1.0 - t) ** 0.78
        half_w = width * 0.5 * taper
        if split:
            # Fills the channel wall to wall, and a hair wider so it cannot
            # z-fight with the inner faces of the two lanes.
            half_y = gap * 1.12
            half_x = thickness * 0.30 * (1.0 - 0.5 * u)
        else:
            half_y = half_w * 0.14
            half_x = thickness * 0.56 * (1.0 - 0.6 * u)
        z = z0 + u * height
        y = curve * (u ** 1.7)
        verts.extend(
            [
                (half_x, y - half_y, z),
                (half_x, y + half_y, z),
                (-half_x, y + half_y, z),
                (-half_x, y - half_y, z),
            ]
        )

    for index in range(GLOW_RINGS - 1):
        a = index * ring_size
        b = (index + 1) * ring_size
        for k in range(ring_size):
            k2 = (k + 1) % ring_size
            faces.append((a + k, a + k2, b + k2, b + k))
    faces.append((3, 2, 1, 0))
    top = (GLOW_RINGS - 1) * ring_size
    faces.append((top + 0, top + 1, top + 2, top + 3))

    return add_object(name, verts, faces)


def prism(name: str, centre, size, rotation=0.0, taper=1.0, twist=0.0, pitch=0.0):
    """A box, optionally tapered along Z, twisted, and angled.

    `rotation` turns about Z (yaw inside the blade's flat), `pitch` turns about X
    (sweeping a guard wing upward). Both exist because a guard wing that yaws
    instead of pitching swings out of the sword's plane and reads as a bracket
    wrapped around the blade, not as a wing rising off the hilt.
    """
    cx, cy, cz = centre
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    cos_r, sin_r = math.cos(rotation), math.sin(rotation)
    cos_t, sin_t = math.cos(twist), math.sin(twist)
    cos_p, sin_p = math.cos(pitch), math.sin(pitch)

    verts = []
    for z_sign, scale in ((-1, 1.0), (1, taper)):
        for x_sign, y_sign in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            x = x_sign * hx * scale
            y = y_sign * hy * scale
            z = z_sign * hz
            # Twist opens the two caps against each other, which reads as a
            # forged bevel rather than a stretched cube.
            rx = x * cos_t - y * sin_t
            ry = x * sin_t + y * cos_t
            # Pitch first, about the local X axis, so the long axis of a wing
            # lifts instead of swinging forward.
            py = ry * cos_p - z * sin_p
            pz = ry * sin_p + z * cos_p
            verts.append((cx + rx * cos_r - py * sin_r, cy + rx * sin_r + py * cos_r, cz + pz))

    faces = [
        (0, 1, 2, 3),
        (7, 6, 5, 4),
        (0, 4, 5, 1),
        (1, 5, 6, 2),
        (2, 6, 7, 3),
        (3, 7, 4, 0),
    ]
    return add_object(name, verts, faces)


def cone(name: str, base_z: float, tip_z: float, radius: float, sides: int = 8, centre=(0.0, 0.0)):
    cx, cy = centre
    verts = []
    for index in range(sides):
        angle = index / sides * math.tau
        verts.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius, base_z))
    verts.append((cx, cy, tip_z))
    faces = []
    for index in range(sides):
        nxt = (index + 1) % sides
        faces.append((index, nxt, sides))
    faces.append(tuple(range(sides - 1, -1, -1)))
    return add_object(name, verts, faces)


def torus(name: str, centre, major: float, minor: float, axis: str = "Z", major_seg: int = 14, minor_seg: int = 6):
    """A real torus. Used for ring guards, ring pommels and the drone's halo."""
    cx, cy, cz = centre
    verts = []
    faces = []
    for i in range(major_seg):
        a = i / major_seg * math.tau
        ca, sa = math.cos(a), math.sin(a)
        for j in range(minor_seg):
            b = j / minor_seg * math.tau
            cb, sb = math.cos(b), math.sin(b)
            radial = major + minor * cb
            if axis == "Z":
                verts.append((cx + radial * ca, cy + radial * sa, cz + minor * sb))
            elif axis == "Y":
                verts.append((cx + radial * ca, cy + minor * sb, cz + radial * sa))
            else:
                verts.append((cx + minor * sb, cy + radial * ca, cz + radial * sa))

    for i in range(major_seg):
        i2 = (i + 1) % major_seg
        for j in range(minor_seg):
            j2 = (j + 1) % minor_seg
            faces.append((i * minor_seg + j, i2 * minor_seg + j, i2 * minor_seg + j2, i * minor_seg + j2))
    return add_object(name, verts, faces)


# ---------------------------------------------------------------------------
# Sub-assemblies
# ---------------------------------------------------------------------------


def build_grip(name: str, grip_h: float, total: float):
    """Tapered grip with three binding rings and a collar at the top."""
    radius = total * 0.021
    sides = 10
    verts = []
    faces = []
    for index in range(sides):
        a = index / sides * math.tau
        verts.append((math.cos(a) * radius, math.sin(a) * radius, grip_h * 0.10))
    for index in range(sides):
        a = index / sides * math.tau
        verts.append((math.cos(a) * radius * 1.12, math.sin(a) * radius * 1.12, grip_h * 0.94))
    for index in range(sides):
        nxt = (index + 1) % sides
        faces.append((index, nxt, sides + nxt, sides + index))
    faces.append(tuple(range(sides - 1, -1, -1)))
    faces.append(tuple(range(sides * 2 - 1, sides - 1, -1)))
    grip = add_object(f"{name}_grip", verts, faces)

    parts = [grip]
    for index in range(3):
        z = grip_h * (0.24 + index * 0.24)
        parts.append(torus(f"{name}_bind{index}", (0.0, 0.0, z), radius * 1.14, radius * 0.16, axis="Z", major_seg=12, minor_seg=4))

    parts.append(
        prism(f"{name}_collar", (0.0, 0.0, grip_h), (radius * 3.6, radius * 3.6, grip_h * 0.14), twist=math.radians(45))
    )
    return parts


def build_pommel(name: str, grip_h: float, total: float, kind: str):
    radius = total * 0.021
    z = grip_h * 0.10
    parts = []

    if kind == "cap":
        parts.append(prism(f"{name}_pommel", (0.0, 0.0, z), (radius * 4.0, radius * 4.0, radius * 2.2), twist=math.radians(45)))
    elif kind == "spike":
        parts.append(cone(f"{name}_pommel", z + radius * 1.4, z - radius * 2.6, radius * 2.1, sides=8))
    elif kind == "crystal":
        parts.append(prism(f"{name}_socket", (0.0, 0.0, z + radius * 0.8), (radius * 3.4, radius * 3.4, radius * 1.4), twist=math.radians(45)))
        crystal = prism(
            f"{name}_crystal",
            (0.0, 0.0, z - radius * 1.2),
            (radius * 2.4, radius * 2.4, radius * 2.8),
            rotation=math.radians(45),
            taper=0.15,
        )
        parts.append(crystal)
    else:  # ring
        parts.append(torus(f"{name}_pommel", (0.0, 0.0, z), radius * 2.2, radius * 0.42, axis="Y", major_seg=12, minor_seg=5))
    return parts


def build_guard(name: str, z: float, guard_h: float, total: float, recipe: dict):
    """Six silhouettes. `stance` is the guard's half-span."""
    width = recipe["width"] * total
    stance = width * 1.55
    grip_r = total * 0.021
    depth = grip_r * 2.4
    kind = recipe["guard"]
    parts = [
        prism(f"{name}_guardblock", (0.0, 0.0, z), (depth, width * 0.72, guard_h), twist=math.radians(12))
    ]

    if kind == "bar":
        parts.append(prism(f"{name}_bar", (0.0, 0.0, z), (depth, stance * 2.0, guard_h * 0.55), taper=0.72))
        for side in (-1, 1):
            parts.append(prism(f"{name}_quillon{side}", (0.0, side * stance, z + guard_h * 0.22), (depth * 0.8, stance * 0.30, guard_h * 0.8), pitch=math.radians(24) * side, taper=0.35))
    elif kind == "chevron":
        for side in (-1, 1):
            parts.append(
                prism(
                    f"{name}_chevron{side}",
                    (0.0, side * stance * 0.46, z + guard_h * 0.30),
                    (depth * 0.9, stance * 0.98, guard_h * 0.5),
                    pitch=math.radians(22) * side,
                    taper=0.5,
                )
            )
    elif kind == "vguard":
        for side in (-1, 1):
            parts.append(
                prism(
                    f"{name}_sweep{side}",
                    (0.0, side * stance * 0.50, z + guard_h * 0.62),
                    (depth * 0.84, stance * 1.10, guard_h * 0.42),
                    pitch=math.radians(36) * side,
                    taper=0.4,
                )
            )
            parts.append(
                cone(
                    f"{name}_sweeptip{side}",
                    z + guard_h * 1.05,
                    z + guard_h * 1.55,
                    guard_h * 0.32,
                    sides=6,
                    centre=(0.0, side * stance * 0.98),
                )
            )
    elif kind == "horns":
        for side in (-1, 1):
            parts.append(
                prism(
                    f"{name}_hornroot{side}",
                    (0.0, side * stance * 0.26, z + guard_h * 0.34),
                    (depth * 0.92, stance * 0.62, guard_h * 0.62),
                    pitch=math.radians(14) * side,
                    taper=0.7,
                )
            )
            parts.append(
                prism(
                    f"{name}_horntip{side}",
                    (0.0, side * stance * 0.62, z + guard_h * 0.95),
                    (depth * 0.6, stance * 0.34, guard_h * 1.0),
                    pitch=math.radians(34) * side,
                    taper=0.2,
                )
            )
    elif kind == "clamp":
        for side in (-1, 1):
            parts.append(
                prism(
                    f"{name}_jaw{side}",
                    (0.0, side * stance * 0.40, z + guard_h * 0.18),
                    (depth * 1.12, stance * 0.66, guard_h * 1.15),
                    pitch=math.radians(7) * side,
                    taper=0.86,
                )
            )
    else:  # ring
        parts.append(torus(f"{name}_ring", (0.0, 0.0, z + guard_h * 0.2), stance * 0.86, guard_h * 0.30, axis="X", major_seg=16, minor_seg=5))
    return parts


def build_glow(name: str, blade_z: float, blade_h: float, z_guard: float, guard_h: float, total: float, recipe: dict, gap: float):
    """Emissive sub-assemblies, all parented into one `_glow` object.

    Every decoration here is sized *against the blade thickness on X*, never
    against its width. The first cut used the width for X, which built a plate
    standing across the sword: measured on Comet's Wake, a 0.655-stud bar through
    a 0.135-stud blade, reading as a white rectangle punched through the steel.
    A mark on the flat is thin in X and small in Y; the width only ever sizes the
    span across the face.
    """
    parts = []
    width = recipe["width"] * total
    thickness = recipe["thick"] * total
    radius = total * 0.021

    if recipe["glow"] in ("fuller", "split"):
        parts.append(glow_channel(f"{name}_core", blade_z, blade_h, recipe, total, gap))
    if recipe["glow"] == "vent":
        for side in (-1, 1):
            parts.append(
                prism(
                    f"{name}_vent{side}",
                    (0.0, side * width * 0.26, blade_z + blade_h * 0.20),
                    (thickness * 1.15, width * 0.13, blade_h * 0.30),
                )
            )

    if recipe["guard"] == "clamp":
        parts.append(prism(f"{name}_seam", (0.0, 0.0, z_guard + guard_h * 0.95), (radius * 2.6, width * 0.9, guard_h * 0.16)))

    if recipe["pommel"] == "crystal":
        parts.append(
            prism(
                f"{name}_pommelcore",
                (0.0, 0.0, total * 0.021 * 0.10 - total * 0.021 * 1.2),
                (radius * 1.5, radius * 1.5, radius * 1.9),
                rotation=math.radians(45),
                taper=0.2,
            )
        )

    for index in range(recipe["runes"]):
        u = 0.20 + index * 0.13
        if u > 0.88:
            break
        z = blade_z + blade_h * u
        # A tick across the flat, poking a few percent proud on both faces so it
        # is visible from either side of the sword.
        parts.append(
            prism(
                f"{name}_rune{index}",
                (0.0, recipe["curve"] * total * (u ** 1.7), z),
                (thickness * 1.20, width * 0.42, blade_h * 0.014),
            )
        )
    return parts


# ---------------------------------------------------------------------------
# Blade assembly
# ---------------------------------------------------------------------------


def build_blade(spec: dict) -> tuple[bpy.types.Object, bpy.types.Object | None]:
    recipe = recipe_for(spec)
    total = TIER_HEIGHT.get(spec["tier"], 5.0)
    name = spec["id"]

    grip_h = total * recipe["grip"]
    guard_h = total * recipe["guard_h"]
    blade_z = grip_h + guard_h
    blade_h = total - blade_z

    body = []
    body.extend(build_grip(name, grip_h, total))
    body.extend(build_pommel(name, grip_h, total, recipe["pommel"]))
    body.extend(build_guard(name, grip_h, guard_h, total, recipe))

    # Channel width for a split blade: 14% of the half-width. Wide enough to read
    # as a deliberate cut at thumbnail size, narrow enough that the sword is
    # still mostly steel.
    gap = 0.0
    if recipe["split"]:
        gap = recipe["width"] * total * 0.5 * 0.14

    body.append(loft(name, blade_z, blade_h, recipe, total, gap))

    glow_parts = build_glow(name, blade_z, blade_h, grip_h, guard_h, total, recipe, gap)

    body_obj = join_objects(body, name)
    glow_obj = join_objects(glow_parts, f"{name}_glow")
    return body_obj, glow_obj


# ---------------------------------------------------------------------------
# Fleet drone
# ---------------------------------------------------------------------------


def build_drone() -> tuple[bpy.types.Object, bpy.types.Object | None]:
    """A forge drone: machined core housing, three angled pods, an energy halo.

    Centred on the origin rather than sitting on it — the fleet viewport spins
    the model about its own centre, so a base-anchored drone would orbit instead
    of turning on the spot.
    """
    name = "fleet_drone"
    body = []
    glow = []

    radius = 1.0

    # Core housing: an eight-sided barrel with a bevelled cap at each end, which
    # reads as machined rather than as a sphere.
    barrel = prism(f"{name}_core", (0.0, 0.0, 0.0), (radius * 1.5, radius * 1.5, radius * 1.1), taper=0.9)
    body.append(barrel)
    body.append(torus(f"{name}_belt", (0.0, 0.0, 0.0), radius * 0.86, radius * 0.10, axis="Z", major_seg=14, minor_seg=5))

    # Three angled thruster pods around the equator.
    for index in range(3):
        angle = index / 3 * math.tau
        cx, cy = math.cos(angle) * radius * 1.45, math.sin(angle) * radius * 1.45
        pod = prism(
            f"{name}_pod{index}",
            (cx, cy, -radius * 0.08),
            (radius * 0.52, radius * 0.72, radius * 0.92),
            rotation=angle,
            taper=0.72,
        )
        body.append(pod)
        glow.append(
            prism(
                f"{name}_podglow{index}",
                (cx, cy, -radius * 0.62),
                (radius * 0.34, radius * 0.46, radius * 0.12),
                rotation=angle,
            )
        )

    # Energy halo, canted so it never lines up with the pods.
    halo = torus(f"{name}_halo", (0.0, 0.0, radius * 0.55), radius * 1.18, radius * 0.055, axis="Z", major_seg=20, minor_seg=6)
    halo.data.transform(__import__("mathutils").Matrix.Rotation(math.radians(14), 4, "X"))
    glow.append(halo)

    # Reactor: a faceted crystal inside the housing, visible from either face.
    glow.append(prism(f"{name}_reactor", (0.0, 0.0, 0.0), (radius * 0.62, radius * 0.62, radius * 0.74), rotation=math.radians(45), taper=0.35))

    body_obj = join_objects(body, name)
    glow_obj = join_objects(glow, f"{name}_glow")
    return body_obj, glow_obj


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------


def triangulate(obj: bpy.types.Object) -> int:
    """Triangulate in place, fix winding, and return the triangle count.

    The loft builds its rings bottom-up while the tip fan and the base cap are
    authored from the other side, so some faces come out wound backwards.
    Roblox renders those as holes; `recalc_face_normals` makes the surface
    consistently outward before anything leaves Blender.
    """
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return len(mesh.polygons)


def geometry_hash(objects: list[bpy.types.Object]) -> str:
    """Stable hash of the meshes, independent of the FBX container.

    Blender's FBX writer is not byte-deterministic: the same object exports to a
    different file on every run (embedded header data). The uploader used to key
    its cache on the file hash, so rebuilding invalidated every entry and
    re-uploaded each blade as a duplicate. This hashes what actually matters.
    """
    digest = hashlib.sha256()
    digest.update(f"qf-export-v{EXPORT_VERSION}|".encode())
    for obj in sorted(objects, key=lambda item: item.name):
        digest.update(f"{obj.name}|".encode())
        mesh = obj.data
        for vertex in mesh.vertices:
            digest.update(f"{vertex.co.x:.6f},{vertex.co.y:.6f},{vertex.co.z:.6f};".encode())
        for polygon in mesh.polygons:
            digest.update((",".join(str(index) for index in polygon.vertices) + ";").encode())
    return digest.hexdigest()


def bounds(objects: list[bpy.types.Object]):
    """World-space extents straight from the vertex data.

    `obj.bound_box` is the cached object-space box and lags a mesh edit on the
    same frame, which is exactly how a height gets written into the manifest that
    does not match the exported file.
    """
    lo = [math.inf, math.inf, math.inf]
    hi = [-math.inf, -math.inf, -math.inf]
    for obj in objects:
        for vertex in obj.data.vertices:
            for axis in range(3):
                lo[axis] = min(lo[axis], vertex.co[axis])
                hi[axis] = max(hi[axis], vertex.co[axis])
    return [hi[i] - lo[i] for i in range(3)], lo, hi


def export(objects: list[bpy.types.Object], asset_id: str) -> dict:
    fbx_path = OUT_DIR / f"{asset_id}.fbx"
    obj_path = OUT_DIR / f"{asset_id}.obj"
    formats: list[str] = []

    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]

    try:
        bpy.ops.export_scene.fbx(
            filepath=str(fbx_path),
            use_selection=True,
            object_types={"MESH"},
            apply_scale_options="FBX_SCALE_NONE",
            axis_forward="-Z",
            axis_up="Y",
            use_mesh_modifiers=True,
            mesh_smooth_type="FACE",
            bake_anim=False,
            path_mode="STRIP",
        )
        formats.append("fbx")
    except Exception as exc:  # pragma: no cover - exporter absence is environmental
        print(f"[models] fbx export failed for {asset_id}: {exc}")

    try:
        bpy.ops.wm.obj_export(
            filepath=str(obj_path),
            export_selected_objects=True,
            apply_modifiers=True,
            forward_axis="NEGATIVE_Z",
            up_axis="Y",
        )
        formats.append("obj")
    except Exception as exc:
        print(f"[models] obj export failed for {asset_id}: {exc}")

    return {"formats": formats, "fbx": fbx_path.name, "obj": obj_path.name}


def record(asset_id: str, spec: dict, objects: list[bpy.types.Object], exported: dict) -> dict:
    dims, lo, hi = bounds(objects)
    tris = sum(len(obj.data.polygons) for obj in objects)
    verts = sum(len(obj.data.vertices) for obj in objects)
    return {
        "id": asset_id,
        "name": spec.get("name", asset_id),
        "tier": spec.get("tier", 0),
        "shape": spec.get("shape", "prop"),
        "material": spec.get("material", "Metal"),
        "tris": tris,
        "verts": verts,
        # Z is the built-up axis in Blender; the FBX axis conversion maps it to
        # Roblox +Y, which is the height the runtime rescales to.
        "heightStuds": round(dims[2], 3),
        "widthStuds": round(dims[1], 3),
        "depthStuds": round(dims[0], 3),
        "originZ": round(lo[2], 4),
        "geometryHash": geometry_hash(objects),
        "fbx": exported["fbx"] if "fbx" in exported["formats"] else None,
        "obj": exported["obj"] if "obj" in exported["formats"] else None,
        "parts": [obj.name for obj in sorted(objects, key=lambda item: item.name)],
        "bladeColor": spec.get("bladeColor"),
        "glowColor": spec.get("glowColor"),
        "gripColor": spec.get("gripColor"),
    }


def main() -> int:
    blades = parse_registry()
    if not blades:
        print("[models] no blades parsed from BladeRegistry.luau", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    records: list[dict] = []
    failures: list[str] = []

    for spec in blades:
        clear_scene()
        body, glow = build_blade(spec)
        objects = [obj for obj in (body, glow) if obj is not None]
        tris = 0
        for obj in objects:
            tris += triangulate(obj)
            for polygon in obj.data.polygons:
                polygon.use_smooth = False
        if tris > TRI_BUDGET:
            failures.append(f"{spec['id']}: {tris} tris over budget {TRI_BUDGET}")

        # Origins are already at the world origin: every vertex was authored in
        # model space through `add_object`, so no transform needs applying.
        exported = export(objects, spec["id"])
        entry = record(spec["id"], spec, objects, exported)
        entry["tris"] = tris
        records.append(entry)
        print(
            f"[models] {spec['id']:<20} tier {spec['tier']}  {tris:>5} tris  "
            f"{entry['heightStuds']:.2f} studs  {'+'.join(obj.name for obj in objects)}"
        )

    drone_spec = {"name": "Autonomous Fleet Drone", "tier": 0, "shape": "drone", "material": "Metal"}
    clear_scene()
    body, glow = build_drone()
    objects = [obj for obj in (body, glow) if obj is not None]
    drone_tris = 0
    for obj in objects:
        drone_tris += triangulate(obj)
        for polygon in obj.data.polygons:
            polygon.use_smooth = False
    exported = export(objects, "fleet_drone")
    drone_entry = record("fleet_drone", drone_spec, objects, exported)
    drone_entry["tris"] = drone_tris
    print(f"[models] fleet_drone          prop      {drone_tris:>5} tris  {'+'.join(obj.name for obj in objects)}")

    index = {
        "generated_with": "scripts/build_models.py",
        "export_version": EXPORT_VERSION,
        "triangle_budget": TRI_BUDGET,
        "axis": {"up": "+Y", "forward": "-Z"},
        "origin": "base of hilt (blades) / model centre (drone)",
        "blades": records,
        "props": [drone_entry],
    }
    (OUT_DIR / "index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")

    total_tris = sum(entry["tris"] for entry in records) + drone_tris
    print(
        f"[models] {len(records)} blades + 1 prop, {total_tris} tris total, "
        f"budget {TRI_BUDGET} per model"
    )
    for failure in failures:
        print(f"[models] BUDGET: {failure}", file=sys.stderr)
    return 1 if failures else 0


# Blender's script-file executor runs this through `exec()` without setting
# `__name__`, so the standard `if __name__ == "__main__"` guard never fires. The
# build is the point of the file, so it runs on load.
if True:
    try:
        _status = main()
    except Exception:
        import traceback

        traceback.print_exc()
        _status = 1
    print(f"[models] exit {_status}")
