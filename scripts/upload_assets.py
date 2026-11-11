#!/usr/bin/env python3
"""Upload generated art to Roblox and rewrite the matching Luau manifest.

Two properties matter here:

1. **Resumable.** Upload progress is cached by content hash. Re-running after a
   crash or a rate limit only sends what actually changed. A 40-asset batch
   interrupted at 31 does not restart.

2. **Idempotent.** The cache is written after every success, so the manifest can
   always be regenerated from what succeeded. `--manifest-only` rebuilds the
   Luau file with zero network calls, which is what you want after a manual
   re-upload through the Creator Dashboard.

Two asset families are supported, and they never touch each other's files:

- **icons** (default) -> `AssetManifest.luau` -> `AssetManifest.Assets`
- **VFX sprite sheets** (`--vfx`) -> `VfxManifest.luau`
- **3D meshes** (`--mesh`) -> `AssetManifest.luau` -> `AssetManifest.Meshes`

The Luau module is rewritten in place, not regenerated from a Python template.
For icons only the `AssetManifest.Assets` table body is replaced; for sheets the
file is re-emitted by `generate_vfx.py` itself, so the emitter cannot drift from
the generator; for meshes only the `AssetManifest.Meshes` block is replaced.

Meshes land in a separate table on purpose. A Roblox mesh asset id and an image
asset id are both "an rbxassetid", so nothing in the type system stops you from
handing one to the other — and an `ImageLabel` given a model id renders a
grey box that looks like a bug in the UI rather than a bug in the manifest.
Two tables, two accessors, no accidental crossover.

Requires an Open Cloud API key with the `asset:write` scope, passed via the
ROBLOX_API_KEY environment variable (never on the command line — it ends up in
shell history).

    setx ROBLOX_API_KEY "your-key-here"
    python scripts/upload_assets.py --creator user:123456789
    python scripts/upload_assets.py --creator group:987654321 --only blade_
    python scripts/upload_assets.py --dry-run
    python scripts/upload_assets.py --manifest-only
    python scripts/upload_assets.py --vfx --creator user:123456789
    python scripts/upload_assets.py --mesh --creator user:123456789
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Sequence

try:
    import requests
except ImportError:  # only the upload path needs it; --manifest-only does not
    requests = None  # type: ignore[assignment]


REPO_ROOT = Path(__file__).resolve().parent.parent
GENERATED_DIR = REPO_ROOT / "assets" / "generated"
INDEX_PATH = GENERATED_DIR / "index.json"
CACHE_PATH = GENERATED_DIR / "uploaded.json"
MANIFEST_PATH = REPO_ROOT / "src" / "shared" / "AssetManifest.luau"

VFX_DIR = GENERATED_DIR / "vfx"
VFX_INDEX_PATH = VFX_DIR / "index.json"
VFX_CACHE_PATH = VFX_DIR / "uploaded.json"
VFX_MANIFEST_PATH = REPO_ROOT / "src" / "shared" / "VfxManifest.luau"

MODEL_DIR = REPO_ROOT / "assets" / "models"
MODEL_INDEX_PATH = MODEL_DIR / "index.json"
MODEL_CACHE_PATH = MODEL_DIR / "uploaded.json"

ASSETS_BASE = "https://apis.roblox.com/assets/v1"
UPLOAD_URL = f"{ASSETS_BASE}/assets"
OPERATION_URL = f"{ASSETS_BASE}/operations"

# `Model`, not `Mesh`. The Assets API's `Mesh` type only accepts mesh data
# downloaded from the asset delivery API — it exists for re-uploading, not for
# importing. `Model` ingests .fbx and returns a package containing MeshParts,
# which is the documented path for new geometry.
MESH_ASSET_TYPE = "Model"
MESH_CONTENT_TYPE = "model/fbx"
MESH_SIZE_LIMIT = 20 * 1024 * 1024

MAX_ATTEMPTS = 5
OPERATION_POLLS = 30
OPERATION_INTERVAL = 2.0
TIMEOUT = 60

GROUP_ORDER = (
    ("currency_", "Currency"),
    ("ui_", "UI glyphs"),
    ("rarity_", "Rarity frames"),
    ("blade_", "Blades"),
)


# ---------------------------------------------------------------------------
# Local state
# ---------------------------------------------------------------------------


def api_key_from_env() -> str:
    """The Open Cloud key, under either name the project has used.

    `ROBLOX_OPEN_CLOUD_KEY` is the name in the docs and the `.env` template;
    `ROBLOX_API_KEY` is what the original script read and what is already set on
    this machine. Accepting both means the pipeline is not sensitive to which
    one was exported.
    """
    for name in ("ROBLOX_OPEN_CLOUD_KEY", "ROBLOX_API_KEY"):
        value = os.environ.get(name, "").strip()
        if value:
            return value
    return ""


def load_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        # utf-8-sig, not utf-8: PowerShell's Set-Content -Encoding UTF8 writes a
        # BOM, and a BOM makes json.loads raise on line 1 column 1. Hand-editing
        # a cache file should not be able to wedge the uploader.
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError as exc:
        sys.exit(f"{path} is not valid JSON: {exc}")


def save_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_png(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)
    with path.open("rb") as handle:
        magic = handle.read(8)
    if magic != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path.name} is not a PNG")
    if path.stat().st_size < 512:
        raise ValueError(f"{path.name} is suspiciously small ({path.stat().st_size} bytes)")


# ---------------------------------------------------------------------------
# Creator context
# ---------------------------------------------------------------------------


def parse_creator(raw: str) -> dict:
    """`user:123` or `group:456` -> the creationContext payload."""
    if ":" not in raw:
        sys.exit("--creator must look like user:123456 or group:123456")
    kind, _, ident = raw.partition(":")
    kind = kind.strip().lower()
    ident = ident.strip()
    if not ident.isdigit():
        sys.exit(f"--creator id must be numeric, got {ident!r}")
    if kind == "user":
        return {"creator": {"userId": int(ident)}}
    if kind == "group":
        return {"creator": {"groupId": int(ident)}}
    sys.exit(f"--creator kind must be 'user' or 'group', got {kind!r}")


# ---------------------------------------------------------------------------
# Open Cloud calls
# ---------------------------------------------------------------------------


class UploadError(RuntimeError):
    pass


def _retry_after(response: "requests.Response", fallback: float) -> float:
    raw = response.headers.get("Retry-After")
    if raw:
        try:
            return max(1.0, float(raw))
        except ValueError:
            pass
    return fallback


def upload_asset(
    session: "requests.Session",
    api_key: str,
    file_path: Path,
    display_name: str,
    creator: dict,
    asset_type: str = "Image",
    content_type: str = "image/png",
    description: str = "Quantum Forge - generated asset",
) -> str:
    """POST one file, then poll the operation. Returns the asset id.

    The multipart body is the shape the Assets API documents: a single `request`
    field carrying the JSON, plus a `fileContent` part carrying the bytes. The
    earlier version of this function posted the JSON as flat form fields with the
    file under `file`, which is not the documented contract — it silently
    uploads nothing and 400s.
    """
    request_body = {
        "assetType": asset_type,
        "displayName": display_name,
        "description": description,
        "creationContext": creator,
    }

    for attempt in range(1, MAX_ATTEMPTS + 1):
        with file_path.open("rb") as handle:
            payload = handle.read()

        try:
            response = session.post(
                UPLOAD_URL,
                headers={"x-api-key": api_key, "Accept": "application/json"},
                files={
                    "request": (None, json.dumps(request_body), "application/json"),
                    "fileContent": (file_path.name, payload, content_type),
                },
                timeout=TIMEOUT,
            )
        except requests.RequestException as exc:
            if attempt == MAX_ATTEMPTS:
                raise UploadError(f"network failure after {attempt} attempts: {exc}") from exc
            time.sleep(2**attempt)
            continue

        if response.status_code in (401, 403):
            raise UploadError(
                f"HTTP {response.status_code}: {response.text[:300]}\n"
                "The API key is missing, invalid, or lacks the asset:write scope, "
                "or the creator is not permitted to own assets."
            )

        if response.status_code == 429:
            wait = _retry_after(response, fallback=float(2**attempt))
            print(f"    rate limited, sleeping {wait:.0f}s")
            time.sleep(wait)
            continue

        if response.status_code >= 500:
            if attempt == MAX_ATTEMPTS:
                raise UploadError(f"server error {response.status_code}: {response.text[:300]}")
            time.sleep(2**attempt)
            continue

        if response.status_code >= 400:
            raise UploadError(f"HTTP {response.status_code}: {response.text[:300]}")

        body = response.json()
        operation_id = body.get("operationId") or body.get("path", "").rsplit("/", 1)[-1]
        if not operation_id:
            raise UploadError(f"no operationId in response: {body}")

        return poll_operation(session, api_key, operation_id)

    raise UploadError("exhausted attempts")


def poll_operation(session: "requests.Session", api_key: str, operation_id: str) -> str:
    url = f"{OPERATION_URL}/{operation_id}"

    for _ in range(OPERATION_POLLS):
        try:
            response = session.get(
                url,
                headers={"x-api-key": api_key, "Accept": "application/json"},
                timeout=TIMEOUT,
            )
        except requests.RequestException:
            time.sleep(OPERATION_INTERVAL)
            continue

        if response.status_code == 429:
            time.sleep(_retry_after(response, fallback=OPERATION_INTERVAL))
            continue

        if response.status_code >= 400:
            raise UploadError(f"operation poll failed HTTP {response.status_code}: {response.text[:300]}")

        body = response.json()

        if body.get("error"):
            message = body["error"].get("message", body["error"])
            raise UploadError(f"operation failed: {message}")

        if body.get("done"):
            result = body.get("response") or {}
            asset_id = result.get("assetId") or result.get("assetID")
            if not asset_id:
                raise UploadError(f"operation finished without an assetId: {body}")
            moderation = (result.get("moderationResult") or {}).get("moderationState")
            if moderation:
                # The API returns `MODERATION_STATE_APPROVED`, not `Approved`.
                # Comparing raw strings flagged every clean upload as suspect.
                state = str(moderation).replace("MODERATION_STATE_", "").title()
                if state not in ("Approved", "Pending"):
                    print(f"    moderation state: {state}")
            return str(asset_id)

        time.sleep(OPERATION_INTERVAL)

    raise UploadError(f"operation {operation_id} did not finish in time")


# ---------------------------------------------------------------------------
# Manifest rewrite
# ---------------------------------------------------------------------------

ASSETS_BLOCK_RE = re.compile(
    r"(AssetManifest\.Assets = \{)(.*?)(\n\})",
    re.S,
)


def _group_for(key: str) -> str:
    for prefix, label in GROUP_ORDER:
        if key.startswith(prefix):
            return label
    return "Other"


def render_assets_block(assets: dict[str, str]) -> str:
    """`{key: rbxassetid://...}` -> the Luau table body, grouped for legibility."""
    ordered: dict[str, list[tuple[str, str]]] = {}
    for key in sorted(assets):
        ordered.setdefault(_group_for(key), []).append((key, assets[key]))

    lines: list[str] = []
    for _, label in GROUP_ORDER + (("", "Other"),):
        entries = ordered.get(label)
        if not entries:
            continue
        if lines:
            lines.append("")
        lines.append(f"\t-- {label}")
        width = max(len(key) for key, _ in entries)
        for key, value in entries:
            lines.append(f'\t{key.ljust(width)} = "{value}",')

    return "\n" + "\n".join(lines)


def write_manifest(ids: dict[str, str]) -> int:
    if not MANIFEST_PATH.is_file():
        sys.exit(f"manifest not found: {MANIFEST_PATH}")

    text = MANIFEST_PATH.read_text(encoding="utf-8")
    if not ASSETS_BLOCK_RE.search(text):
        sys.exit(
            "could not find the `AssetManifest.Assets = { ... }` table in the "
            "manifest. Refusing to write a partial file."
        )

    resolved = {
        key: (f"rbxassetid://{asset_id}" if asset_id else "rbxassetid://0")
        for key, asset_id in ids.items()
    }

    updated = ASSETS_BLOCK_RE.sub(
        lambda m: m.group(1) + render_assets_block(resolved) + m.group(3),
        text,
        count=1,
    )
    MANIFEST_PATH.write_text(updated, encoding="utf-8")
    return len(resolved)


# ---------------------------------------------------------------------------
# VFX sprite sheets
# ---------------------------------------------------------------------------


def load_vfx_index() -> dict:
    index = load_json(VFX_INDEX_PATH)
    if not isinstance(index, dict) or not index.get("effects"):
        sys.exit(f"no effects in {VFX_INDEX_PATH}. Run: python scripts/generate_vfx.py")
    return index


def vfx_targets(index: dict) -> dict[str, Path]:
    """`<effect>_<layer>` and `particle_<kind>` -> the sheet on disk.

    The keys are exactly the keys `VfxManifest.luau` uses, so a sheet's identity
    is the same string in the index, the cache, the manifest and the runtime
    lookup. Anything else would eventually upload one effect's body over
    another's.
    """
    targets: dict[str, Path] = {}
    for effect, meta in index["effects"].items():
        for layer, relative in meta["layers"].items():
            targets[f"{effect}_{layer}"] = GENERATED_DIR / relative
    for kind, relative in index.get("particles", {}).items():
        targets[f"particle_{kind}"] = GENERATED_DIR / relative
    return targets


def write_vfx_manifest(index: dict, cache: dict) -> int:
    """Re-emit `VfxManifest.luau` through the generator's own emitter.

    Re-implementing the emitter here is how the two files would drift, and a
    drifted manifest means a sheet id attached to the wrong effect. Missing ids
    stay `rbxassetid://0`, which the runtime reads as "use the procedural path".
    """
    sys.path.insert(0, str(REPO_ROOT / "scripts"))
    import generate_vfx  # late import: only the VFX path needs Pillow loaded

    effect_meta = {
        name: {"frames": meta["frames"], "fps": meta["fps"], "loop": meta["loop"]}
        for name, meta in index["effects"].items()
    }
    particle_meta = {kind: {} for kind in index.get("particles", {})}

    ids: dict[str, str] = {}
    for key in vfx_targets(index):
        asset_id = str(cache.get(key, {}).get("assetId", ""))
        if asset_id:
            ids[key] = f"rbxassetid://{asset_id}"

    VFX_MANIFEST_PATH.write_text(
        generate_vfx.luau_manifest(effect_meta, particle_meta, ids), encoding="utf-8"
    )
    return len(vfx_targets(index))


def upload_vfx(args: argparse.Namespace) -> int:
    index = load_vfx_index()
    targets = vfx_targets(index)

    cache = load_json(VFX_CACHE_PATH)
    if not isinstance(cache, dict):
        cache = {}

    if args.manifest_only:
        count = write_vfx_manifest(index, cache)
        live = sum(1 for key in targets if cache.get(key, {}).get("assetId"))
        print(f"vfx manifest rebuilt: {live}/{count} sheets resolved")
        return 0

    todo: list[tuple[str, Path, str, str]] = []
    for key, path in targets.items():
        if args.only and not key.startswith(args.only):
            continue
        try:
            validate_png(path)
        except (FileNotFoundError, ValueError) as exc:
            sys.exit(f"{key}: {exc}")
        digest = file_hash(path)
        cached = cache.get(key, {})
        if not args.force and cached.get("hash") == digest and cached.get("assetId"):
            continue
        todo.append((key, path, f"QF VFX {key}", digest))

    print(f"{len(targets)} sheets in index, {len(todo)} to upload")

    if args.dry_run:
        for key, path, display, _ in todo:
            size = path.stat().st_size / 1024
            print(f"  would upload {key:<22} {display:<26} {size:>7.0f} KiB")
        return 0

    if requests is None:
        sys.exit("requests is required to upload. Run: pip install -r requirements.txt")

    api_key = api_key_from_env()
    if not api_key:
        sys.exit(
            "No Open Cloud key. Set ROBLOX_OPEN_CLOUD_KEY (or ROBLOX_API_KEY) from "
            "https://create.roblox.com/dashboard/credentials (scope asset:write), e.g.\n"
            '  setx ROBLOX_OPEN_CLOUD_KEY "your-key-here"'
        )
    if not args.creator:
        sys.exit("--creator is required (user:123456 or group:123456)")
    creator = parse_creator(args.creator)

    if args.limit:
        todo = todo[: args.limit]

    session = requests.Session()
    uploaded = 0
    failures: list[tuple[str, str]] = []

    try:
        for position, (key, path, display, digest) in enumerate(todo, start=1):
            print(f"[{position}/{len(todo)}] {key}")
            try:
                asset_id = upload_one(session, api_key, path, display, creator)
            except UploadError as exc:
                print(f"    FAILED: {exc}")
                failures.append((key, str(exc)))
                # A bad key or a bad creator fails every subsequent call too.
                if "HTTP 401" in str(exc) or "HTTP 403" in str(exc):
                    break
                continue

            cache[key] = {"assetId": asset_id, "hash": digest, "name": display}
            save_json(VFX_CACHE_PATH, cache)
            uploaded += 1
            print(f"    ok -> {asset_id}")
    except KeyboardInterrupt:
        print("\ninterrupted; cache is saved up to the last completed upload")

    count = write_vfx_manifest(index, cache)
    live = sum(1 for key in targets if cache.get(key, {}).get("assetId"))
    print(f"\nuploaded {uploaded} this run")
    print(f"vfx manifest rebuilt: {live}/{count} sheets resolved")
    if live < count:
        print("  unresolved sheets stay rbxassetid://0 and use the procedural fallback")

    if failures:
        print("\nfailures:")
        for key, message in failures:
            print(f"  {key}: {message.splitlines()[0]}")
        return 1

    return 0


# ---------------------------------------------------------------------------
# 3D meshes
# ---------------------------------------------------------------------------


def load_model_index() -> dict:
    index = load_json(MODEL_INDEX_PATH)
    if not isinstance(index, dict) or not index.get("blades"):
        sys.exit(
            f"no blades in {MODEL_INDEX_PATH}.\n"
            "Build them first: blender --background --python scripts/build_models.py"
        )
    return index


def validate_fbx(path: Path) -> None:
    """Cheap gate: real FBX magic, under the API's 20 MB cap, not truncated."""
    if not path.is_file():
        raise FileNotFoundError(path)
    with path.open("rb") as handle:
        header = handle.read(21)
    # Binary FBX starts "Kaydara FBX Binary  \x00"; ASCII FBX starts "; FBX".
    if not (header.startswith(b"Kaydara FBX Binary") or header.startswith(b"; FBX")):
        raise ValueError(f"{path.name} is not an FBX")
    size = path.stat().st_size
    if size > MESH_SIZE_LIMIT:
        raise ValueError(f"{path.name} is {size / 1048576:.1f} MB, over the 20 MB API limit")
    if size < 2048:
        raise ValueError(f"{path.name} is suspiciously small ({size} bytes)")


def mesh_targets(index: dict) -> dict[str, Path]:
    """Asset id -> the FBX on disk. Keyed by registry id, never by filename.

    Blades are the bulk, but `props` (the fleet drone) rides the same pipeline:
    same asset type, same cache, same manifest table, so the runtime looks both
    up through `AssetManifest.mesh()`.
    """
    targets: dict[str, Path] = {}
    for entry in list(index.get("blades", [])) + list(index.get("props", [])):
        if entry.get("fbx"):
            targets[entry["id"]] = MODEL_DIR / entry["fbx"]
    return targets


def mesh_records(index: dict) -> list[dict]:
    """Every mesh record, blades first. One list for the manifest writer."""
    return list(index.get("blades", [])) + list(index.get("props", []))


def mesh_digest(blade: dict, path: Path) -> str:
    """Cache identity for a blade.

    The geometry hash from `build_models.py`, not the file hash. Blender's FBX
    writer is not byte-deterministic — the same mesh exports to a different file
    every run — so keying on the file made every rebuild invalidate all 25
    entries and re-upload them. Uploads never overwrite, so that would also pile
    up duplicate assets in the account.
    """
    digest = blade.get("geometryHash")
    if isinstance(digest, str) and digest:
        return digest
    return file_hash(path)


MESHES_BLOCK_RE = re.compile(r"(AssetManifest\.Meshes = \{)(.*?)(\n\})", re.S)


def write_mesh_manifest(index: dict, cache: dict) -> int:
    """Replace only the `AssetManifest.Meshes` block, keeping prose intact.

    Height and triangle count ride along with each id because the runtime needs
    them: the importer does not guarantee a stud-per-unit scale, so
    `BladePreview` measures the MeshPart and rescales to `entry.height`. Without
    the number in the manifest the model is whatever size Roblox felt like.
    """
    if not MANIFEST_PATH.is_file():
        sys.exit(f"manifest not found: {MANIFEST_PATH}")

    text = MANIFEST_PATH.read_text(encoding="utf-8")
    if not MESHES_BLOCK_RE.search(text):
        sys.exit(
            "could not find the `AssetManifest.Meshes = { ... }` table in the "
            "manifest. Refusing to write a partial file."
        )

    width = max(len(blade["id"]) for blade in mesh_records(index))
    lines: list[str] = []
    for blade in mesh_records(index):
        key = blade["id"]
        asset_id = str(cache.get(key, {}).get("assetId", ""))
        resolved = f"rbxassetid://{asset_id}" if asset_id else "rbxassetid://0"
        lines.append(
            f'\t{key.ljust(width)} = {{ id = "{resolved}", '
            f'height = {blade["heightStuds"]:.2f}, tris = {blade["tris"]} }},'
        )

    updated = MESHES_BLOCK_RE.sub(lambda m: m.group(1) + "\n" + "\n".join(lines) + m.group(3), text, count=1)
    MANIFEST_PATH.write_text(updated, encoding="utf-8")
    return len(mesh_records(index))


def upload_meshes(args: argparse.Namespace) -> int:
    index = load_model_index()
    targets = mesh_targets(index)
    blades = {blade["id"]: blade for blade in mesh_records(index)}

    cache = load_json(MODEL_CACHE_PATH)
    if not isinstance(cache, dict):
        cache = {}

    if args.manifest_only:
        count = write_mesh_manifest(index, cache)
        live = sum(1 for key in targets if cache.get(key, {}).get("assetId"))
        print(f"mesh manifest rebuilt: {live}/{count} blades resolved")
        return 0

    todo: list[tuple[str, Path, str, str]] = []
    for key, path in targets.items():
        if args.only and not key.startswith(args.only):
            continue
        try:
            validate_fbx(path)
        except (FileNotFoundError, ValueError) as exc:
            sys.exit(f"{key}: {exc}")
        digest = mesh_digest(blades[key], path)
        cached = cache.get(key, {})
        if not args.force and cached.get("hash") == digest and cached.get("assetId"):
            continue
        todo.append((key, path, f"QF {blades[key].get('name') or key}", digest))

    print(f"{len(targets)} meshes in index, {len(todo)} to upload")

    if args.dry_run:
        for key, path, display, _ in todo:
            print(f"  would upload {key:<22} {display:<28} {path.stat().st_size / 1024:>7.0f} KiB")
        return 0

    if requests is None:
        sys.exit("requests is required to upload. Run: pip install -r requirements.txt")

    api_key = api_key_from_env()
    if not api_key:
        sys.exit(
            "No Open Cloud key. Set ROBLOX_OPEN_CLOUD_KEY (or ROBLOX_API_KEY) from "
            "https://create.roblox.com/dashboard/credentials (scope asset:write), e.g.\n"
            '  setx ROBLOX_OPEN_CLOUD_KEY "your-key-here"'
        )
    if not args.creator:
        sys.exit("--creator is required (user:123456 or group:123456)")
    creator = parse_creator(args.creator)

    if args.limit:
        todo = todo[: args.limit]

    session = requests.Session()
    uploaded = 0
    failures: list[tuple[str, str]] = []

    try:
        for position, (key, path, display, digest) in enumerate(todo, start=1):
            print(f"[{position}/{len(todo)}] {key}")
            try:
                asset_id = upload_asset(
                    session,
                    api_key,
                    path,
                    display,
                    creator,
                    asset_type=MESH_ASSET_TYPE,
                    content_type=MESH_CONTENT_TYPE,
                    description="Quantum Forge blade mesh - built by scripts/build_models.py",
                )
            except UploadError as exc:
                print(f"    FAILED: {exc}")
                failures.append((key, str(exc)))
                if "HTTP 401" in str(exc) or "HTTP 403" in str(exc):
                    break
                continue

            cache[key] = {"assetId": asset_id, "hash": digest, "name": display}
            save_json(MODEL_CACHE_PATH, cache)
            uploaded += 1
            print(f"    ok -> {asset_id}")
    except KeyboardInterrupt:
        print("\ninterrupted; cache is saved up to the last completed upload")

    count = write_mesh_manifest(index, cache)
    live = sum(1 for key in targets if cache.get(key, {}).get("assetId"))
    print(f"\nuploaded {uploaded} this run")
    print(f"mesh manifest rebuilt: {live}/{count} blades resolved")
    if live < count:
        print("  unresolved meshes stay rbxassetid://0 and the client keeps the")
        print("  primitive-built blade (see BladePreview.mount)")

    if failures:
        print("\nfailures:")
        for key, message in failures:
            print(f"  {key}: {message.splitlines()[0]}")
        return 1

    return 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--creator",
        default=os.environ.get("ROBLOX_CREATOR", ""),
        help="user:123456 or group:123456 (or set ROBLOX_CREATOR)",
    )
    parser.add_argument("--only", default="", help="upload only keys with this prefix")
    parser.add_argument("--limit", type=int, default=0, help="stop after N uploads this run")
    parser.add_argument("--force", action="store_true", help="re-upload even if the hash matches")
    parser.add_argument("--dry-run", action="store_true", help="print the plan, upload nothing")
    parser.add_argument("--manifest-only", action="store_true", help="rebuild the Luau manifest from cache")
    parser.add_argument(
        "--vfx",
        action="store_true",
        help="upload VFX sprite sheets and rewrite VfxManifest.luau instead of icons",
    )
    parser.add_argument(
        "--mesh",
        action="store_true",
        help="upload blade meshes and rewrite AssetManifest.Meshes instead of icons",
    )
    args = parser.parse_args(argv)

    if args.vfx and args.mesh:
        parser.error("--vfx and --mesh are separate families; run them one at a time")

    if args.vfx:
        return upload_vfx(args)

    if args.mesh:
        return upload_meshes(args)

    index = load_json(INDEX_PATH)
    entries = index.get("assets")
    if not isinstance(entries, dict) or not entries:
        sys.exit(f"no assets in {INDEX_PATH}. Run: python scripts/generate_icons.py")

    cache = load_json(CACHE_PATH)
    if not isinstance(cache, dict):
        cache = {}

    if args.manifest_only:
        ids = {key: str(cache.get(key, {}).get("assetId", "")) for key in entries}
        count = write_manifest(ids)
        live = sum(1 for v in ids.values() if v)
        print(f"manifest rebuilt: {live}/{count} keys resolved")
        return 0

    api_key = os.environ.get("ROBLOX_API_KEY", "").strip()
    if not args.dry_run:
        if requests is None:
            sys.exit("requests is required to upload. Run: pip install -r requirements.txt")
        if not api_key:
            sys.exit(
                "ROBLOX_API_KEY is not set. Create a key with the asset:write scope at "
                "https://create.roblox.com/dashboard/credentials then:\n"
                '  setx ROBLOX_API_KEY "your-key-here"'
            )

    creator: dict = {}
    if not args.dry_run:
        if not args.creator:
            sys.exit("--creator is required (user:123456 or group:123456)")
        creator = parse_creator(args.creator)

    todo: list[tuple[str, Path, str, str]] = []
    for key in entries:
        meta = entries[key]
        path = GENERATED_DIR / meta["path"]
        display = meta.get("name", key)
        try:
            validate_png(path)
        except (FileNotFoundError, ValueError) as exc:
            sys.exit(f"{key}: {exc}")
        digest = file_hash(path)
        cached = cache.get(key, {})
        if not args.force and cached.get("hash") == digest and cached.get("assetId"):
            continue
        if args.only and not key.startswith(args.only):
            continue
        todo.append((key, path, display, digest))

    skipped = sum(1 for key in entries if not any(t[0] == key for t in todo))
    print(f"{len(entries)} assets in index, {len(todo)} to upload, {skipped} cached")

    if args.limit:
        todo = todo[: args.limit]

    if args.dry_run:
        for key, path, display, _ in todo:
            print(f"  would upload {key:<28} {display:<26} {path.stat().st_size / 1024:.0f} KiB")
        return 0

    session = requests.Session()
    uploaded = 0
    failures: list[tuple[str, str]] = []

    try:
        for position, (key, path, display, digest) in enumerate(todo, start=1):
            print(f"[{position}/{len(todo)}] {key} -> {display}")
            try:
                asset_id = upload_asset(
                    session,
                    api_key,
                    path,
                    display,
                    creator,
                    description="Quantum Forge - generated by scripts/generate_icons.py",
                )
            except UploadError as exc:
                print(f"    FAILED: {exc}")
                failures.append((key, str(exc)))
                # A bad key or a bad creator fails every subsequent call too.
                if "HTTP 401" in str(exc) or "HTTP 403" in str(exc):
                    break
                continue

            cache[key] = {"assetId": asset_id, "hash": digest, "name": display}
            save_json(CACHE_PATH, cache)
            uploaded += 1
            print(f"    ok -> {asset_id}")
    except KeyboardInterrupt:
        print("\ninterrupted; cache is saved up to the last completed upload")

    ids = {key: str(cache.get(key, {}).get("assetId", "")) for key in entries}
    count = write_manifest(ids)
    live = sum(1 for v in ids.values() if v)
    print(f"\nuploaded {uploaded} this run")
    print(f"manifest rebuilt: {live}/{count} keys resolved")

    if failures:
        print("\nfailures:")
        for key, message in failures:
            print(f"  {key}: {message.splitlines()[0]}")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
