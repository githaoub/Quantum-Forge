#!/usr/bin/env python3
"""Import the exported blades back into Blender and render a contact sheet.

The point is not decoration. `build_models.py` writes an FBX with
`axis_forward="-Z", axis_up="Y"`, and every claim about "tip up, edge forward,
pivot at the base of the hilt" is a claim about what Roblox sees *after* that
conversion. Checking the in-memory mesh proves nothing; reading the file back
through an importer is the only cheap proof.

Run it the same way as the builder, through the DCC-MCP gateway or:

    blender --background --python scripts/render_models.py

Writes `assets/models/contact_sheet.png` and prints the measured bounds of every
imported file, so a regression shows up in the log as well as in the picture.
"""

from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path

import bpy
from mathutils import Vector

def _repo_root() -> Path:
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
    raise RuntimeError("could not find the repo root")


REPO_ROOT = _repo_root()
MODEL_DIR = REPO_ROOT / "assets" / "models"
INDEX_PATH = MODEL_DIR / "index.json"
OUT_PATH = MODEL_DIR / "contact_sheet.png"

COLUMNS = 5
# Row pitch has to clear the tallest tier plus a gap, or a tier-5 greatsword
# overlaps the row above it.
ROW_PITCH = 7.0
TALLEST = 6.4
# Portrait, because the catalogue is 25 blades that are 8-20 times taller than
# they are wide. A landscape sheet fits the grid by making every blade 4 pixels
# across, which is how the first render managed to look like a row of pins.
RESOLUTION = (1000, 2000)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.objects, bpy.data.lights):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def import_fbx(path: Path) -> list[bpy.types.Object]:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(path), automatic_bone_orientation=True)
    return [o for o in bpy.data.objects if o not in before and o.type == "MESH"]


def measure(objects: list[bpy.types.Object]) -> dict:
    """World-space bounds of a freshly imported file."""
    lo = Vector((math.inf, math.inf, math.inf))
    hi = Vector((-math.inf, -math.inf, -math.inf))
    for obj in objects:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            lo = Vector((min(lo[i], world[i]) for i in range(3)))
            hi = Vector((max(hi[i], world[i]) for i in range(3)))
    return {"lo": lo, "hi": hi, "size": hi - lo}


def _srgb_to_linear(channel: float) -> float:
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def tint(objects: list[bpy.types.Object], key: str, rgb: list[int] | None) -> None:
    """Give the blade the registry's own colour so the sheet shows real palette."""
    if not rgb:
        return
    material = bpy.data.materials.get(f"qf_{key}")
    if material is None:
        material = bpy.data.materials.new(f"qf_{key}")
        material.use_nodes = True
        shader = material.node_tree.nodes["Principled BSDF"]
        shader.inputs["Base Color"].default_value = (
            *(_srgb_to_linear(c / 255.0) for c in rgb),
            1.0,
        )
        shader.inputs["Metallic"].default_value = 0.25
        shader.inputs["Roughness"].default_value = 0.48
    for obj in objects:
        obj.data.materials.clear()
        obj.data.materials.append(material)


def studio_lighting() -> None:
    world = bpy.data.worlds.get("QFWorld") or bpy.data.worlds.new("QFWorld")
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs[0].default_value = (0.11, 0.12, 0.16, 1.0)
    background.inputs[1].default_value = 1.0
    bpy.context.scene.world = world

    for name, location, energy in (
        ("Key", (16.0, -14.0, 12.0), 5000.0),
        ("Fill", (10.0, 18.0, 4.0), 2200.0),
        ("Rim", (-14.0, 6.0, 16.0), 3000.0),
    ):
        data = bpy.data.lights.new(name, type="AREA")
        data.energy = energy
        data.size = 14.0
        light = bpy.data.objects.new(name, data)
        light.location = location
        light.rotation_euler = (Vector((0.0, 0.0, 10.0)) - light.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(light)


def main() -> int:
    files = sorted(MODEL_DIR.glob("*.fbx"))
    if not files:
        print(f"[render] no .fbx in {MODEL_DIR}; run build_models.py first", file=sys.stderr)
        return 1

    index = json.loads(INDEX_PATH.read_text(encoding="utf-8")) if INDEX_PATH.is_file() else {}
    colours = {entry["id"]: entry.get("bladeColor") for entry in index.get("blades", [])}

    rows = math.ceil(len(files) / COLUMNS)
    # ortho_scale spans the *larger* sensor axis, which is the height here.
    span_z = (rows - 1) * ROW_PITCH + TALLEST
    ortho = span_z * 1.06
    visible_w = ortho * RESOLUTION[0] / RESOLUTION[1]
    col_pitch = visible_w * 0.9 / COLUMNS

    clear_scene()
    studio_lighting()

    placed: list[tuple[list[bpy.types.Object], dict]] = []
    worst = 0.0
    for index_of, path in enumerate(files):
        objects = import_fbx(path)
        if not objects:
            print(f"[render] {path.name}: imported nothing", file=sys.stderr)
            return 1
        bounds = measure(objects)
        tint(objects, path.stem, colours.get(path.stem))
        placed.append((objects, bounds))

        # Pivot at the base of the hilt means the lowest vertex sits on the
        # origin plane. Anything else mounts half a sword underground.
        pivot_error = abs(bounds["lo"].z)
        worst = max(worst, pivot_error)
        print(
            f"[render] {path.stem:<20} {bounds['size'].x:5.2f} x {bounds['size'].y:5.2f} x "
            f"{bounds['size'].z:5.2f}  tris={sum(len(o.data.polygons) for o in objects):>4}  "
            f"pivotZ={bounds['lo'].z:+.4f}"
        )

    for slot, (objects, bounds) in enumerate(placed):
        column, row = slot % COLUMNS, slot // COLUMNS
        offset = Vector((
            0.0,
            (column - (COLUMNS - 1) * 0.5) * col_pitch - (bounds["lo"].y + bounds["hi"].y) * 0.5,
            -row * ROW_PITCH - bounds["lo"].z,
        ))
        for obj in objects:
            obj.location += offset

    centre = Vector((0.0, 0.0, -(rows - 1) * ROW_PITCH * 0.5 + TALLEST * 0.5))

    camera_data = bpy.data.cameras.new("Camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = ortho
    camera = bpy.data.objects.new("Camera", camera_data)
    # Blades face +X/-X, so the camera looks down -X to see the flats.
    camera.location = centre + Vector((80.0, 0.0, 0.0))
    camera.rotation_euler = (math.radians(90.0), 0.0, math.radians(90.0))
    bpy.context.collection.objects.link(camera)
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    # This build exposes `BLENDER_EEVEE`; 4.2+ renamed it `BLENDER_EEVEE_NEXT`.
    # Ask, do not assume, or the render dies after all the imports have run.
    engines = bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys()
    scene.render.engine = next(
        (name for name in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH") if name in engines),
        "BLENDER_WORKBENCH",
    )
    scene.render.resolution_x, scene.render.resolution_y = RESOLUTION
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(OUT_PATH)
    scene.view_settings.view_transform = "Standard"

    bpy.ops.render.render(write_still=True)
    print(f"[render] {len(files)} blades -> {OUT_PATH}")
    print(f"[render] worst pivot offset {worst:.4f} studs")
    return 0


_CODE = main()
print(f"[render] exit {_CODE}")
