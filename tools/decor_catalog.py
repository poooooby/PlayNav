"""Build data/decor_catalog.lua and the a/1/4/5 recipe block.

Usage:
  python tools/decor_catalog.py <garc_all/index.json> [--catalog data/decor_catalog.lua] [--recipe-out <file>]

Archive a/1/4/5 of Alpha Sapphire holds the whole Pokemon-Amie decor
catalogue in blocks per category, in Bulbapedia's order:
  18 type blocks of 8:  thumbnail, wallpaper, cushion 1a, 1b, cushion 2a, 2b, object 1, object 2
  16 blocks of 6:       thumbnail, wallpaper, cushion 1, cushion 2, object 1, object 2
                        (9 colours, 3 clouds, 3 patterns, Classy; the colours start at 145,
                         entry 144 holding an unnamed 26x26 texture, and Classy ends with the
                         Wooden Bed at entry 240)
Item names come from Bulbapedia, "List of Pokemon-Amie Decor items" (CC BY-NC-SA 2.5), with
three pairs put in the game's own order (text archive a/0/7/3 file 110 lists every item in
archive order): Blue before Red Circle Cushion, Iron before Cast-Iron Cushion, and the
Lightbulb Object spelt the game's way.
Sizes and formats are read from the dump index so the recipe can verify them.
"""

from __future__ import annotations

import json
import os
import re
import sys

TYPES = ["Normal", "Fire", "Water", "Electric", "Grass", "Ice", "Fighting", "Poison", "Ground",
         "Flying", "Psychic", "Bug", "Rock", "Ghost", "Dragon", "Dark", "Steel", "Fairy"]
COLORS = ["Pink", "Blue", "Orange", "Green", "Purple", "Brown", "Yellow", "White", "Black"]
CLOUDS = ["Pink Cloud", "Blue Cloud", "Sunset"]
PATTERNS = ["Polka Dot", "Punk", "Checkered"]

# cushions 1 and 2 per type: (c1a, c1b, c2a, c2b), objects (o1, o2)
TYPE_ITEMS = {
    "Normal": (("Cocoa Treat Cushion", "Chocolate Treat Cushion"), ("Mint Ring Cushion", "Cream Ring Cushion"),
               ("Normal Heart Object", "Decorative Treat Object")),
    "Fire": (("Blue Fire Cushion", "Red Fire Cushion"), ("Hot Lava Cushion", "Cooled Lava Cushion"),
             ("Fire Heart Object", "Campfire Object")),
    "Water": (("White Seashell Cushion", "Pink Seashell Cushion"), ("Green Drop Cushion", "Blue Drop Cushion"),
              ("Water Heart Object", "Sparkling Pearl Object")),
    "Electric": (("Light Cushion", "Blue Light Cushion"), ("Shock Cushion", "Blue Shock Cushion"),
                 ("Electric Heart Object", "Lightbulb Object")),
    "Grass": (("Leaf Cushion", "Leaflet Cushion"), ("Stump Cushion", "White Stump Cushion"),
              ("Grass Heart Object", "Flower Object")),
    "Ice": (("Frozen Cushion", "Ice Chunk Cushion"), ("Snowball Cushion", "Ice Ball Cushion"),
            ("Ice Heart Object", "Snowman Object")),
    "Fighting": (("Blue Target Cushion", "Red Target Cushion"), ("Training Log Cushion", "Trial Log Cushion"),
                 ("Fighting Heart Object", "Substitute Cushion")),
    "Poison": (("Rising Smoke Cushion", "Dangerous Smoke Cushion"), ("Green Poison Cushion", "Pink Poison Cushion"),
               ("Poison Heart Object", "Deadly Poison Object")),
    "Ground": (("Deep Hole Cushion", "Shallow Hole Cushion"), ("Hard Ground Cushion", "Soft Ground Cushion"),
               ("Ground Heart Object", "Mysterious Cactus")),
    "Flying": (("White Feather Cushion", "Black Feather Cushion"), ("Blue Flag Perch", "Red Flag Perch"),
               ("Flying Heart Object", "Mysterious Eggs")),
    "Psychic": (("Blue Circle Cushion", "Red Circle Cushion"), ("Bent Spoon Cushion", "Twisted Spoon Cushion"),
                ("Psychic Heart Object", "Mystery Crystal")),
    "Bug": (("Withered Leaf Cushion", "Fallen Leaf Cushion"), ("Gray Yarn Cushion", "Yellow Yarn Cushion"),
            ("Bug Heart Object", "Honey Object")),
    "Rock": (("Gray Rock Cushion", "Black Rock Cushion"), ("Iron Ore Cushion", "Gold Ore Cushion"),
             ("Rock Heart Object", "Sparkling Mineral Object")),
    "Ghost": (("Ghostly Pumpkin Cushion", "Cursed Pumpkin Cushion"), ("Spooky Sheet Cushion", "Monstrous Sheet Cushion"),
              ("Ghost Heart Object", "Will-o'-the-Wisp Candle")),
    "Dragon": (("Dragon Hill Cushion", "Dragon Rock Cushion"), ("Blue Gem Cushion", "Purple Gem Cushion"),
               ("Dragon Heart Object", "Dragon Castle")),
    "Dark": (("Cool Black Cushion", "Cool Red Cushion"), ("Shredded Black Cushion", "Shredded Red Cushion"),
             ("Dark Heart Object", "Nocturnal Chair")),
    "Steel": (("Cross-Top Screw Cushion", "Slot-Top Screw Cushion"), ("Iron Cushion", "Cast-Iron Cushion"),
              ("Steel Heart Object", "Crown Object")),
    "Fairy": (("Pink Arch Cushion", "Blue Arch Cushion"), ("Pretty Ball Cushion", "Lovely Ball Cushion"),
              ("Fairy Heart Object", "Rainbow Parasol")),
}
CLOUD_CUSHION1 = {"Pink Cloud": "Pink Cloud Cushion", "Blue Cloud": "Blue Cloud Cushion", "Sunset": "Orange Cloud Cushion"}
CLOUD_CUSHION2 = {"Pink Cloud": "Hot Pink Cloud Cushion", "Blue Cloud": "Light Blue Cloud Cushion", "Sunset": "Soft Orange Cushion"}
CLOUD_OBJ1 = {"Pink Cloud": "Pink Star Cloud", "Blue Cloud": "Blue Star Cloud", "Sunset": "Orange Star Cloud"}
CLOUD_OBJ2 = {"Pink Cloud": "Peach Cloud Table", "Blue Cloud": "Sky Blue Cloud Table", "Sunset": "Orange Cloud Table"}

SET_OF_TYPE = {t: "D" for t in ["Bug", "Dark", "Electric", "Fighting", "Flying", "Ghost", "Ground", "Ice",
                                 "Normal", "Poison", "Psychic", "Rock", "Steel"]}
SET_OF_TYPE.update({t: "E" for t in ["Dragon", "Fairy", "Fire", "Grass", "Water"]})

DEFAULTS = ["Pink Wallpaper", "Blue Wallpaper", "Orange Wallpaper", "Leaf Cushion", "Pink Egg Cushion",
            "Blue Egg Cushion", "Orange Egg Cushion", "Green Egg Cushion", "Orange Cloud Cushion",
            "Pink Star Cloud", "Sky Blue Cloud Table"]

FMT = {0: "L8", 1: "A8", 2: "LA4", 3: "LA8", 4: "HILO8", 5: "RGB565", 6: "RGB8", 7: "RGBA5551",
       8: "RGBA4", 9: "RGBA8", 10: "ETC1", 11: "ETC1A4", 12: "L4", 13: "A4"}


def slug(name: str) -> str:
    s = name.lower().replace("'", "").replace("-", "_")
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return s


def blocks():
    """Yield (category, set, entries) where entries is a list of (kind, name)."""
    for t in TYPES:
        (c1a, c1b), (c2a, c2b), (o1, o2) = TYPE_ITEMS[t]
        yield t, SET_OF_TYPE[t], [("thumb", t + " Wallpaper"), ("wall", t + " Wallpaper"),
                                  ("cushion", c1a), ("cushion", c1b), ("cushion", c2a), ("cushion", c2b),
                                  ("object", o1), ("object", o2)]
    for c in COLORS:
        yield c, "A", [("thumb", c + " Wallpaper"), ("wall", c + " Wallpaper"), ("cushion", c + " Egg Cushion"),
                       ("cushion", c + " Pillar Cushion"), ("object", c + " Star Object"), ("object", c + " Cube Object")]
    for c in CLOUDS:
        yield c, "C", [("thumb", c + " Wallpaper"), ("wall", c + " Wallpaper"), ("cushion", CLOUD_CUSHION1[c]),
                       ("cushion", CLOUD_CUSHION2[c]), ("object", CLOUD_OBJ1[c]), ("object", CLOUD_OBJ2[c])]
    for p in PATTERNS:
        yield p, "B", [("thumb", p + " Wallpaper"), ("wall", p + " Wallpaper"), ("cushion", p + " Candy Cushion"),
                       ("cushion", p + " Pillar Cushion"), ("object", p + " Star Object"), ("object", p + " Cube Object")]
    yield "Classy", "F", [("thumb", "Chic Wallpaper"), ("wall", "Chic Wallpaper"), ("cushion", "Homey Wooden Chair"),
                          ("cushion", "Comfy Wooden Chair"), ("object", "Wooden Table"), ("object", "Wooden Bed")]


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    index_path = argv[1]
    cat_out = os.path.join("data", "decor_catalog.lua")
    recipe_out = None
    if "--catalog" in argv:
        cat_out = argv[argv.index("--catalog") + 1]
    if "--recipe-out" in argv:
        recipe_out = argv[argv.index("--recipe-out") + 1]
    with open(index_path, encoding="utf-8") as f:
        clims = json.load(f)["clims"]
    rows = [r for r in clims if r["archive"] == "a/1/4/5"]
    rows.sort(key=lambda r: (r["entry"], r["sub"], r.get("clim_start", 0)))
    by_entry = {r["entry"]: r for r in rows}
    items = []
    entry = 0
    for category, set_id, entries in blocks():
        if category == "Classy":
            entry = 235
        elif set_id == "A" and entry == 144:
            # the colour sets start one entry late: 144 holds an unnamed 26x26 texture
            # (found 2026-10-17: every label from here to 233 sat one entry early, so the
            # colour wallpapers drew their 40x40 thumbnails and each item its neighbour's art)
            entry = 145
        for kind, name in entries:
            r = by_entry.get(entry)
            if r is None:
                raise SystemExit("no texture at entry %d for %s" % (entry, name))
            ident = ("thumb/" if kind == "thumb" else kind + "/") + slug(name.replace(" Wallpaper", "") if kind in ("thumb", "wall") else name)
            items.append({"id": ident, "name": name, "kind": kind, "category": category, "set": set_id,
                          "entry": entry, "w": r["width"], "h": r["height"], "fmt": FMT[r["format"]]})
            entry += 1
    if any(i["entry"] > 240 for i in items):
        raise SystemExit("ran past the archive")
    # sanity: 34 wallpapers, 34 thumbs, 104 cushions, 68 objects
    counts = {}
    for i in items:
        counts[i["kind"]] = counts.get(i["kind"], 0) + 1
    assert counts == {"thumb": 34, "wall": 34, "cushion": 104, "object": 68}, counts
    defaults = set(DEFAULTS)
    lines = [
        "-- Pokemon-Amie decor catalogue, generated by tools/decor_catalog.py from the layout of",
        "-- Alpha Sapphire archive a/1/4/5. Item names from Bulbapedia, \"List of Pokemon-Amie Decor",
        "-- items\" (CC BY-NC-SA 2.5). Sets: A colour, B pattern, C cloud, D / E the type sets,",
        "-- F classy. kind: wall | thumb (a wallpaper's icon) | cushion | object. `entry` is the",
        "-- archive entry the texture sits in; `default` marks the eleven items every player starts with.",
        "return {",
    ]
    for i in items:
        d = ", default = true" if (i["name"] in defaults and i["kind"] != "thumb") else ""
        lines.append('  { id = "%s", name = "%s", kind = "%s", category = "%s", set = "%s", entry = %d, w = %d, h = %d%s },'
                     % (i["id"], i["name"].replace('"', "'"), i["kind"], i["category"], i["set"], i["entry"], i["w"], i["h"], d))
    lines.append("}")
    os.makedirs(os.path.dirname(cat_out) or ".", exist_ok=True)
    with open(cat_out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote %s: %d items (%s)" % (cat_out, len(items), counts))
    if recipe_out:
        rl = ["-- ------- the decor catalogue (a/1/4/5): generated by tools/decor_catalog.py",
              'local DC = "a/1/4/5"']
        for i in items:
            rl.append('add(DC, %d, 0, 0, "%s", %d, %d, "%s", "%s")' % (i["entry"], i["id"], i["w"], i["h"], i["fmt"], i["name"].replace('"', "'")))
        with open(recipe_out, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(rl) + "\n")
        print("wrote %s: %d recipe lines" % (recipe_out, len(rl) - 2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
