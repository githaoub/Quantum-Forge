"""Create the store's Game Passes and Developer Products through Open Cloud.

Roblox added Open Cloud endpoints for both in December 2025, but they are BETA
and gated behind scopes that a typical "upload assets" key does not carry:

    game-pass:write          POST /game-passes/v1/universes/{universeId}/game-passes
    developer-product:write  POST /developer-products/v2/universes/{universeId}/developer-products

Without those scopes every write returns:

    {"errors":[{"code":0,"message":"Scope not authorized."}]}

so this script fails loudly with the exact edit to make rather than half-working.

    # dry run: check what already exists and what would be created
    python scripts/create_store_items.py --check

    # create everything, print the id map
    python scripts/create_store_items.py

    # create and write the ids back into MonetizationConfig.luau
    python scripts/create_store_items.py --apply

Pass icons use `imageFile` (a multipart file part), not an asset id. The badge
PNGs already in assets/generated/gamepasses/ are what gets uploaded, so the
pass icon and the store badge are the same art.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

try:
    import requests
except ImportError:  # pragma: no cover
    sys.exit("requests is required. Run: pip install -r requirements.txt")

REPO_ROOT = Path(__file__).resolve().parent.parent
ICON_DIR = REPO_ROOT / "assets" / "generated" / "gamepasses"
CONFIG = REPO_ROOT / "src" / "shared" / "MonetizationConfig.luau"

# Roblox has no endpoint that turns a place id into a universe id offline, so it
# is cached here. Re-resolve with:
#   curl -H "x-api-key: $ROBLOX_API_KEY" \
#     https://apis.roblox.com/universes/v1/places/<placeId>/universe
PLACE_ID = 102663811434617
UNIVERSE_ID = 10775534186

# name, description, price in Robux, badge png, config key
#
# Pricing rule: every pass is an impulse buy at 59. VIP is the bundle at 119,
# so it is cheaper than Fast Forge + Auto-Vent + 2x Star-Matter + Eternal Forge
# separately (4 x 59 = 236). A premium price on a small game sells nothing.
PASSES = [
    (
        "VIP",
        "Every gamepass, forever, plus the VIP badge, aura and gold strike trail. Cheaper than buying them one by one.",
        119,
        "vip_aura",
        "vipAura",
    ),
    (
        "Eternal Forge",
        "+25% to all Star-Matter income, forever.",
        59,
        "eternal_forge",
        "eternalForge",
    ),
    ("Fast Forge", "Doubles accepted clicks per second.", 59, "fast_forge", "fastForge"),
    ("2x Star-Matter", "Doubles all Star-Matter income, forever.", 59, "x2_star_matter", "x2StarMatter"),
    (
        "Auto-Vent AI",
        "Vents at 85% heat automatically, so you never burn out.",
        59,
        "auto_vent",
        "autoVent",
    ),
]

# Emergency Vent was delisted: the free vent key already does the same thing,
# so the product was a trap. Its receipt path remains in MonetizationService
# for any purchase made before it was removed.
PRODUCTS = [
    (
        "Starter Forge Pack",
        "Twenty minutes of 2x income. The first purchase also adds +5% income, permanently.",
        9,
        "starter_forge",
        "starterForge",
    ),
    (
        "Instant Overdrive",
        "One hour of 2x income. Each extra charge adds +1x. The clock resets to one hour.",
        25,
        "instant_overdrive",
        "instantOverdrive",
    ),
    (
        "Express Salvage",
        "Permanently cuts every expedition's clock by 25%.",
        35,
        "express_salvage",
        "expressSalvage",
    ),
]

SCOPE_HINT = """
Open Cloud refused the write. Add the scope to the API key, then re-run:

  1. https://create.roblox.com/dashboard/credentials?activeTab=ApiKeysTab
  2. Open the key this script uses (the one in ROBLOX_API_KEY).
  3. Edit -> API Permissions -> add, for universe {universe}:
         game-pass         : write     (create and price the 5 passes)
         developer-product : write     (create the 4 boosts and utilities)
     Optionally add the matching :read scopes so --check can list them.
  4. Save. Propagates in about a minute.
"""


def api_key() -> str:
    key = os.environ.get("ROBLOX_API_KEY")
    if not key:
        sys.exit("ROBLOX_API_KEY is not set in this shell.")
    return key


def headers(key: str) -> dict[str, str]:
    return {"x-api-key": key, "Accept": "application/json"}


def list_passes(session: requests.Session, key: str) -> list[dict]:
    r = session.get(
        f"https://apis.roblox.com/game-passes/v1/universes/{UNIVERSE_ID}/game-passes/creator",
        headers=headers(key),
        timeout=40,
    )
    if r.status_code == 403:
        return []
    r.raise_for_status()
    return r.json().get("gamePasses", [])


def list_products(session: requests.Session, key: str) -> list[dict]:
    r = session.get(
        f"https://apis.roblox.com/developer-products/v2/universes/{UNIVERSE_ID}/developer-products/creator",
        headers=headers(key),
        timeout=40,
    )
    if r.status_code == 403:
        return []
    r.raise_for_status()
    return r.json().get("developerProducts", [])


def create_pass(session: requests.Session, key: str, name: str, desc: str, price: int, png: Path) -> int:
    with png.open("rb") as fh:
        r = session.post(
            f"https://apis.roblox.com/game-passes/v1/universes/{UNIVERSE_ID}/game-passes",
            headers=headers(key),
            files={"imageFile": (png.name, fh.read(), "image/png")},
            data={
                "name": name,
                "description": desc,
                "price": str(price),
                "isForSale": "true",
                "isRegionalPricingEnabled": "false",
            },
            timeout=120,
        )
    if r.status_code == 403:
        sys.exit(SCOPE_HINT.format(universe=UNIVERSE_ID))
    if not r.ok:
        raise RuntimeError(f"{name}: {r.status_code} {r.text[:300]}")
    body = r.json()
    return int(body.get("gamePassId") or body.get("id") or 0)


def create_product(session: requests.Session, key: str, name: str, desc: str, price: int, png: Path) -> int:
    with png.open("rb") as fh:
        r = session.post(
            f"https://apis.roblox.com/developer-products/v2/universes/{UNIVERSE_ID}/developer-products",
            headers=headers(key),
            files={"imageFile": (png.name, fh.read(), "image/png")},
            data={
                "name": name,
                "description": desc,
                "price": str(price),
                "isForSale": "true",
            },
            timeout=120,
        )
    if r.status_code == 403:
        sys.exit(SCOPE_HINT.format(universe=UNIVERSE_ID))
    if not r.ok:
        raise RuntimeError(f"{name}: {r.status_code} {r.text[:300]}")
    body = r.json()
    return int(body.get("productId") or body.get("id") or 0)


def patch_config(ids: dict[str, int]) -> int:
    """Write the numeric ids into MonetizationConfig, keyed by entry name.

    Each entry is `<key> = { ... id = 0, ... }`. The replacement is anchored on
    the entry name and stops at the next `} ::`, so `id` never lands in the wrong
    table.
    """
    text = CONFIG.read_text(encoding="utf-8")
    changed = 0
    for key, asset in ids.items():
        if asset == 0:
            continue
        pattern = re.compile(
            r"(\n\t" + re.escape(key) + r" = \{(?:(?!\n\t\}).)*?\n\t\tid = )0(,)",
            re.S,
        )
        new_text, n = pattern.subn(lambda m: f"{m.group(1)}{asset}{m.group(2)}", text, count=1)
        if n:
            text = new_text
            changed += 1
        else:
            print(f"  ! could not patch {key} (already set, or the shape changed)")
    CONFIG.write_text(text, encoding="utf-8", newline="")
    return changed


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="list what already exists, create nothing")
    ap.add_argument("--apply", action="store_true", help="write the new ids into MonetizationConfig.luau")
    args = ap.parse_args(argv)

    key = api_key()
    session = requests.Session()

    existing_passes = list_passes(session, key)
    existing_products = list_products(session, key)
    print(f"universe {UNIVERSE_ID}")
    print(f"  {len(existing_passes)} game pass(es) already exist" + (f": {[p.get('name') for p in existing_passes]}" if existing_passes else ""))
    print(f"  {len(existing_products)} developer product(s) already exist" + (f": {[p.get('name') for p in existing_products]}" if existing_products else ""))

    # Name -> id, so a re-run patches the config instead of creating a second
    # copy of every listing. Duplicate store items are real money and real
    # support tickets, not a cosmetic bug.
    by_name: dict[str, int] = {}
    for entry in existing_passes + existing_products:
        name = entry.get("name")
        asset = entry.get("gamePassId") or entry.get("productId") or entry.get("id") or 0
        if name and asset:
            by_name[str(name)] = int(asset)

    plan = [(n, d, p, i, k, "pass") for n, d, p, i, k in PASSES]
    plan += [(n, d, p, i, k, "product") for n, d, p, i, k in PRODUCTS]

    missing = [row for row in plan if not (ICON_DIR / f"{row[3]}.png").is_file()]
    if missing:
        sys.exit("missing badge art: " + ", ".join(f"{m[3]}.png" for m in missing))

    if args.check:
        for name, _desc, price, slug, _key, kind in plan:
            state = f"exists (id {by_name[name]})" if name in by_name else "would create"
            print(f"  {state:<22} {kind:<8} {name:<22} R$ {price:<5} icon {slug}.png")
        print("\n--check made no changes.")
        return 0

    ids: dict[str, int] = {}
    for name, desc, price, slug, config_key, kind in plan:
        if name in by_name:
            ids[config_key] = by_name[name]
            print(f"  {kind:<8} {name:<22} R$ {price:<5} -> {by_name[name]} (existing)")
            continue
        png = ICON_DIR / f"{slug}.png"
        maker = create_pass if kind == "pass" else create_product
        asset = maker(session, key, name, desc, price, png)
        ids[config_key] = asset
        print(f"  {kind:<8} {name:<22} R$ {price:<5} -> {asset}")

    print()
    print("IDs:")
    for k, v in ids.items():
        print(f"  {k:<18} = {v}")

    if args.apply:
        n = patch_config(ids)
        print(f"\npatched {n} entr{'y' if n == 1 else 'ies'} in {CONFIG.relative_to(REPO_ROOT)}")
        print("now run: selene src/ && rojo build -o verify.rbxlx")
    else:
        print("\nnot written to config (pass --apply to patch MonetizationConfig.luau)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
