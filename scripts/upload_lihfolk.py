"""Stage and upload the LihFolk Vault surfaces this game uses.

Two things are taken from the Vault, and only two, because the rest of the art
direction is drawn in code:

  * one night sky, as six 1024px faces, for the Orbital Bridge. The pack ships a
    lighting recipe per sky and `LobbyService` reads the same numbers.
  * one hammered-metal albedo, tiled behind the handbook's page header.

Everything else in the pack (815 models, 204 materials, 48 skies, animations,
VFX) is left alone. Meshes would have to survive the same authorisation dance
the blade meshes are currently losing, and a game whose lobby is built from
primitives does not need a prop library bolted on.

Licence: the pack grants free use inside an experience, including commercial
ones, and private uploads. It forbids reselling or redistributing the assets as
an asset pack. The staged copies below live in this repo and are uploaded as
private assets owned by the configured creator; that is use, not redistribution.

Usage:
    python scripts/upload_lihfolk.py --creator user:1416845247
    python scripts/upload_lihfolk.py --dry-run
    python scripts/upload_lihfolk.py --manifest-only
    python scripts/upload_lihfolk.py --source "D:/packs/LihFolk Asset Pack"

Requires `ROBLOX_API_KEY` (or `ROBLOX_OPEN_CLOUD_KEY`) with `asset:write`.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import upload_assets as ua  # noqa: E402

STAGE_DIR = ua.REPO_ROOT / "assets" / "lihfolk"
CACHE_PATH = STAGE_DIR / "uploaded.json"
STAGING_PATH = STAGE_DIR / "staging.json"

DEFAULT_SOURCE = Path(
    r"C:\Users\nelso\Documents\LihFolk\LIH.FOLK.VAULT.V2.FULL\LihFolk Asset Pack"
)

SKY_ID = "night_stars_indigo_001"

# Roblox property order is irrelevant; `AssetManifest.SkyOrder` fixes the read
# order and this table is keyed the way `Sky` names its faces.
SKY_FACES: dict[str, str] = {
    "bk": "SkyBk.png",
    "dn": "SkyDn.png",
    "ft": "SkyFt.png",
    "lf": "SkyLf.png",
    "rt": "SkyRt.png",
    "up": "SkyUp.png",
}

# The band wants texture, not structure: a hammered albedo reads as metal at
# 220px behind a scrim, while a plated albedo reads as brickwork and fights the
# banner type.
BAND_MATERIAL = Path("Materials") / "gold" / "gold_antiquehammered_003" / "Color.png"

SKY_BLOCK_RE = re.compile(r"(AssetManifest\.LihFolkSky = \{)(.*?)(\n\})", re.S)
ART_BLOCK_RE = re.compile(r"(AssetManifest\.LihFolkArt = \{)(.*?)(\n\})", re.S)


def asset_type_for(key: str) -> str:
    """Every surface is uploaded as an Image.

    A `Sky` face looks like a Decal slot, and uploading the faces as Decals gets
    six ids the sky renderer rejects with "Asset type does not match requested
    type". Image ids load and render. That is the whole reason this helper
    exists: the wrong choice is not obvious from the property names.
    """
    return "Image"


def wrap(asset_id: str) -> str:
    """The manifest stores `rbxassetid://` strings everywhere else; keep it true."""
    return f"rbxassetid://{asset_id}" if asset_id else ""


def stage(source: Path, force: bool) -> dict[str, Path]:
    """Copy the chosen files into the repo and record where they came from.

    A staged copy is the point: the uploader can be re-run on a machine that has
    never seen the Vault, and the licence/provenance record travels with the
    bytes instead of living in somebody's memory.
    """
    if not source.is_dir():
        sys.exit(
            f"LihFolk pack not found: {source}\n"
            "Pass --source with the folder that contains `Skies/` and `Materials/`."
        )

    sky_dir = source / "Skies" / SKY_ID
    if not sky_dir.is_dir():
        sys.exit(f"sky not found: {sky_dir}")

    plan: list[tuple[str, Path, Path]] = []
    for face, filename in SKY_FACES.items():
        plan.append((f"sky_{face}", sky_dir / filename, STAGE_DIR / "sky" / f"{face}.png"))
    plan.append(("band", source / BAND_MATERIAL, STAGE_DIR / "band.png"))

    staging: dict[str, dict] = {}
    if STAGING_PATH.is_file():
        loaded = json.loads(STAGING_PATH.read_text(encoding="utf-8-sig"))
        if isinstance(loaded, dict):
            staging = loaded

    staged: dict[str, Path] = {}
    for key, src, dst in plan:
        try:
            ua.validate_png(src)
        except (FileNotFoundError, ValueError) as exc:
            sys.exit(f"{key}: {exc}")
        digest = ua.file_hash(src)
        if force or not dst.is_file() or ua.file_hash(dst) != digest:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
        staged[key] = dst
        staging[key] = {
            "source": str(src.relative_to(source)),
            "file": str(dst.relative_to(STAGE_DIR)).replace("\\", "/"),
            "hash": digest,
            "bytes": dst.stat().st_size,
        }

    STAGE_DIR.mkdir(parents=True, exist_ok=True)
    STAGING_PATH.write_text(
        json.dumps(
            {
                "pack": "LihFolk Vault V2",
                "licence": "LihFolk Asset Pack licence - use in an experience, "
                "private uploads, no redistribution",
                "sky": SKY_ID,
                "assets": staging,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return staged


def render_sky(ids: dict[str, str]) -> str:
    lines = [f'\t{face} = "{wrap(ids.get(f"sky_{face}", ""))}",' for face in SKY_FACES]
    return "\n" + "\n".join(lines)


def render_art(ids: dict[str, str]) -> str:
    return "\n" + f'\tband = "{wrap(ids.get("band", ""))}",'


def write_manifest(ids: dict[str, str]) -> None:
    if not ua.MANIFEST_PATH.is_file():
        sys.exit(f"manifest not found: {ua.MANIFEST_PATH}")
    text = ua.MANIFEST_PATH.read_text(encoding="utf-8")

    for pattern, render, label in (
        (SKY_BLOCK_RE, render_sky, "AssetManifest.LihFolkSky"),
        (ART_BLOCK_RE, render_art, "AssetManifest.LihFolkArt"),
    ):
        match = pattern.search(text)
        if match is None:
            sys.exit(f"could not find the `{label} = {{ ... }}` table")
        text = text[: match.start(2)] + render(ids) + text[match.end(2) :]

    ua.MANIFEST_PATH.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--creator", default="user:1416845247", help="user:123 or group:123")
    parser.add_argument("--source", default=str(DEFAULT_SOURCE), help="LihFolk Asset Pack root")
    parser.add_argument("--force", action="store_true", help="re-upload even if the hash matches")
    parser.add_argument("--dry-run", action="store_true", help="print the plan, upload nothing")
    parser.add_argument(
        "--manifest-only",
        action="store_true",
        help="rebuild the manifest tables from the local cache",
    )
    args = parser.parse_args()

    cache = ua.load_json(CACHE_PATH)
    if not isinstance(cache, dict):
        cache = {}

    if args.manifest_only:
        ids = {key: str(cache.get(key, {}).get("assetId", "")) for key in [*[f"sky_{f}" for f in SKY_FACES], "band"]}
        write_manifest(ids)
        live = sum(1 for value in ids.values() if value)
        print(f"LihFolkArt/Sky rebuilt: {live}/{len(ids)} keys resolved")
        return 0

    staged = stage(Path(args.source), force=args.force)
    todo: list[tuple[str, Path, str]] = []
    for key, path in staged.items():
        digest = ua.file_hash(path)
        cached = cache.get(key, {})
        wanted = asset_type_for(key)
        if (
            not args.force
            and cached.get("hash") == digest
            and cached.get("assetId")
            and cached.get("assetType") == wanted
        ):
            continue
        todo.append((key, path, digest))

    print(f"{len(staged)} LihFolk images, {len(todo)} to upload")
    for key, path, _ in todo:
        print(f"  {key:<8} {path.name:<12} {path.stat().st_size / 1024:.0f} KiB")

    if args.dry_run:
        return 0

    api_key = ua.api_key_from_env()
    if not api_key:
        sys.exit(
            "ROBLOX_API_KEY is not set. Create a key with the asset:write scope at "
            "https://create.roblox.com/dashboard/credentials then:\n"
            '  setx ROBLOX_API_KEY "your-key-here"'
        )
    if ua.requests is None:
        sys.exit("requests is required to upload. Run: pip install -r requirements.txt")

    creator = ua.parse_creator(args.creator)
    session = ua.requests.Session()
    failures: list[tuple[str, str]] = []

    for key, path, digest in todo:
        label = f"sky {key.split('_', 1)[1].upper()}" if key.startswith("sky_") else "band"
        wanted = asset_type_for(key)
        print(f"[{key}] {path.name} -> {wanted}")
        try:
            asset_id = ua.upload_asset(
                session,
                api_key,
                path,
                display_name=f"Quantum Forge LihFolk {label}",
                creator=creator,
                asset_type=wanted,
                content_type="image/png",
                description="Quantum Forge - LihFolk Vault surface, used under the LihFolk Asset Pack licence",
            )
        except ua.UploadError as exc:
            print(f"    FAILED: {exc}")
            failures.append((key, str(exc)))
            continue
        cache[key] = {"hash": digest, "assetId": asset_id, "assetType": wanted, "file": path.name}
        ua.save_json(CACHE_PATH, cache)
        print(f"    uploaded as {asset_id}")

    ids = {key: str(cache.get(key, {}).get("assetId", "")) for key in staged}
    write_manifest(ids)
    live = sum(1 for value in ids.values() if value)
    print(f"LihFolkArt/Sky: {live}/{len(ids)} keys resolved")

    if failures:
        for key, reason in failures:
            print(f"  {key}: {reason}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
