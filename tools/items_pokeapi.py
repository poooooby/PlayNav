"""Build data/training_items.lua: the Gen 5/6 items Super Training hands out that Gen 3
lacks (the seven Wings and the Dusk / Shiny / Dawn Stones), registered by the mod as new
items. Names, effects and flavour text come from PokeAPI (https://pokeapi.co, data under
CC BY 4.0 / the fair-use terms PokeAPI states); prices from Bulbapedia's item pages (sell
value doubled, Gen 3 style); icons from PokeSprite (the images (c) Nintendo / Creatures / GAME FREAK; PokeSprite's
code is MIT), packed into assets/items.png by tools/items_atlas.py, credited in
assets/credits.txt.

Usage:
  python tools/items_pokeapi.py [--out data/training_items.lua] [--cache tools/_items_cache.json]
"""

from __future__ import annotations

import json
import os
import sys
import urllib.request

UA = "Mozilla/5.0 play_nav-items/1.0 (gen1recomp mod tooling)"
API = "https://pokeapi.co/api/v2/item/%s/"
FLAVOR_PREF = ["omega-ruby-alpha-sapphire", "x-y", "sun-moon", "black-white"]

# PokeAPI carries the Gen 8 "Feather" names; Super Training's era called them Wings
NAMES = {
    "health-wing": "Health Wing", "muscle-wing": "Muscle Wing", "resist-wing": "Resist Wing",
    "genius-wing": "Genius Wing", "clever-wing": "Clever Wing", "swift-wing": "Swift Wing",
    "pretty-wing": "Pretty Wing",
}

# slug, item index the mod registers, Gen 3 price (sell = half), field use, EV stat, icon folder
ITEMS = [
    ("health-wing", 400, 3000, "vitamin", "hp", "medicine"),
    ("muscle-wing", 401, 3000, "vitamin", "atk", "medicine"),
    ("resist-wing", 402, 3000, "vitamin", "def", "medicine"),
    ("genius-wing", 403, 3000, "vitamin", "spa", "medicine"),
    ("clever-wing", 404, 3000, "vitamin", "spd", "medicine"),
    ("swift-wing", 405, 3000, "vitamin", "spe", "medicine"),
    ("pretty-wing", 406, 200, "none", None, "valuable-item"),
    ("dusk-stone", 407, 2100, "none", None, "evo-item"),
    ("shiny-stone", 408, 2100, "none", None, "evo-item"),
    ("dawn-stone", 409, 2100, "none", None, "evo-item"),
]
PRICE_SOURCE = ("Bulbapedia: Wings sell for 1,500 in XY/ORAS, Pretty Wing 100, "
                "Dusk/Shiny/Dawn Stone 1,050; price = sell x 2 as Gen 3 does")


def fetch(slug: str, cache: dict) -> dict:
    if slug in cache:
        return cache[slug]
    req = urllib.request.Request(API % slug, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    cache[slug] = data
    return data


# the bag's words: Gen 3 draws an item's description as written, three lines of at most
# about 19 (Emerald's own: "Raises the base HP\nof one POKéMON."); PokeAPI's flavour text
# is one long sentence, so these are ours
BAG_TEXT = {
    "health-wing": 'Slightly raises\nthe base HP of\none POKéMON.',
    "muscle-wing": 'Slightly raises\nthe base ATTACK of\none POKéMON.',
    "resist-wing": 'Slightly raises\nthe base DEFENSE of\none POKéMON.',
    "genius-wing": 'Slightly raises\nthe base SP. ATK of\none POKéMON.',
    "clever-wing": 'Slightly raises\nthe base SP. DEF of\none POKéMON.',
    "swift-wing": 'Slightly raises\nthe base SPEED of\none POKéMON.',
    "pretty-wing": 'A pretty feather\nthat has no effect\non POKéMON.',
    "dusk-stone": 'Makes certain\nPOKéMON evolve. It\nis as dark as dark.',
    "shiny-stone": 'Makes certain\nPOKéMON evolve. It\nshines dazzlingly.',
    "dawn-stone": 'Makes certain\nPOKéMON evolve. It\nsparkles brightly.',
}


def english(entries, key):
    for e in entries:
        if e["language"]["name"] == "en":
            return e[key]
    return None


def flavor(data: dict) -> str:
    by_group = {}
    for f in data.get("flavor_text_entries", []):
        if f["language"]["name"] == "en":
            by_group.setdefault(f["version_group"]["name"], f["text"])
    for g in FLAVOR_PREF:
        if g in by_group:
            return by_group[g]
    return next(iter(by_group.values()), "")


def clean(text: str) -> str:
    return " ".join(text.replace("­", "").replace("\n", " ").split()).replace("’", "'")


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def main(argv: list[str]) -> int:
    out_path = argv[argv.index("--out") + 1] if "--out" in argv else "data/training_items.lua"
    cache_path = argv[argv.index("--cache") + 1] if "--cache" in argv else None
    cache = {}
    if cache_path and os.path.exists(cache_path):
        with open(cache_path, encoding="utf-8") as f:
            cache = json.load(f)
    rows = []
    for slug, index, price, field_use, stat, folder in ITEMS:
        d = fetch(slug, cache)
        # Gen 3's bag names are all capitals ("SODA POP"), as the engine's and other mods' are
        name = (NAMES.get(slug) or english(d["names"], "name") or slug.replace("-", " ")).upper()
        effect = english(d.get("effect_entries", []), "short_effect") or ""
        rows.append({
            "slug": slug, "index": index, "name": name, "price": price, "fieldUse": field_use,
            "stat": stat, "icon": "assets/items.png", "iconCell": len(rows), "folder": folder,
            "description": clean(flavor(d)), "effect": clean(effect), "pokeapiId": d["id"],
            "category": d["category"]["name"],
        })
    if cache_path:
        with open(cache_path, "w", encoding="utf-8") as f:
            json.dump(cache, f)
    lines = [
        "-- Items Super Training hands out that Gen 3 never had, registered by src/training/items.lua",
        "-- through mod.content.items (indices 400..409). Generated by tools/items_pokeapi.py:",
        "-- names and effects from PokeAPI (pokeapi.co), the bag's words ours (BAG_TEXT: Gen 3's three",
        "-- lines of at most 19, as Emerald's own); icons from PokeSprite, packed",
        "-- into the atlas assets/items.png (32x32 cells, five to a row; tools/items_atlas.py)",
        "-- (github.com/msikma/pokesprite; the images (c) Nintendo / Creatures / GAME FREAK); prices: " + PRICE_SOURCE + ".",
        "-- Wings raise one EV by 1 (within 252 / 510); Pretty Wing and the three stones are",
        "-- collectibles to sell (no Gen 3 line evolves with a Dusk, Shiny or Dawn Stone).",
        "",
        "return {",
    ]
    for r in rows:
        lines.append("  { slug = %s, index = %d, name = %s, price = %d, fieldUse = %s, stat = %s," % (
            lua_str(r["slug"]), r["index"], lua_str(r["name"]), r["price"], lua_str(r["fieldUse"]),
            lua_str(r["stat"]) if r["stat"] else "nil"))
        lines.append("    icon = %s, iconCell = %d, pokeapiId = %d, category = %s," % (lua_str(r["icon"]), r["iconCell"], r["pokeapiId"], lua_str(r["category"])))
        lines.append("    effect = %s," % lua_str(r["effect"]))
        lines.append("    description = %s }," % lua_str(BAG_TEXT.get(r["slug"], r["description"])))
    lines.append("}")
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote %s: %d items" % (out_path, len(rows)))
    for r in rows:
        print("  %d %-12s %-6d %s" % (r["index"], r["name"], r["price"], r["description"][:60]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
