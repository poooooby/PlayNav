"""Build data/petting_gen3.lua from Bulbapedia's "Petting" article.

Usage:
  python tools/petting_table.py [--cache tools/_petting.wikitext] [--out data/petting_gen3.lua]

Downloads the article's wikitext through the MediaWiki API (or reads a cached
copy), keeps the base form of National Dex numbers 1..386, and maps each
favored / disfavored spot and special effect to one of the coarse zones the
mod lays over a front sprite:

  head    top of the head: ears, horns, crest, hair, antennae, the bulb
  face    eyes, nose, mouth, beak, forehead, chin
  cheeks  cheeks, whiskers, jaw
  chest   throat, neck, chest, mane, collar, under the chin
  belly   stomach, body, torso, pouch, the shell front
  side    back, shell, wings, fins, shoulders, spikes along the back
  limbs   hands, arms, claws, paws, legs, feet, pincers, stingers
  bottom  tail, rattle, rear, lower body

The output carries the original text so a zone can be hand-tuned later.
The data is derived from Bulbapedia (CC BY-NC-SA 2.5); keep the attribution
line in the generated file and in README.md.
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.request

API = ("https://bulbapedia.bulbagarden.net/w/api.php?action=parse&page=Petting"
       "&prop=wikitext&format=json&formatversion=2")
UA = "Mozilla/5.0 play_nav-petting-table/1.0 (gen1recomp mod tooling)"

# ordered: the first matching rule wins
ZONE_RULES = [
    ("chest", ["under chin", "under its chin", "under the chin", "throat", "neck", "chest", "mane",
               "collar", "bib", "ruff", "scarf", "breast"]),
    ("cheeks", ["cheek", "whisker", "jaw", "sideburn"]),
    ("bottom", ["pendulum", "tail", "rattle", "rear", "bottom", "hind", "lower body", "base of body", "stinger on",
                "rump", "behind", "tip of its body"]),
    ("limbs", ["root", "stalk", "stick", "bone", "glove", "hand", "arm", "claw", "paw", "leg", "foot", "feet", "finger", "pincer", "stinger",
               "fist", "knee", "elbow", "flipper", "toe", "hoof", "hooves", "tentacle", "spoon"]),
    ("face", ["lip", "trunk", "tusk", "bill", "forehead", "between eyes", "between the eyes", "between its eyes", "eye", "nose", "nostril",
              "mouth", "beak", "snout", "chin", "teeth", "tooth", "lips", "muzzle", "face", "brow",
              "mask", "visor", "tongue", "fang"]),
    ("head", ["crescent", "star", "antler", "lilypad", "fruit", "hood", "head", "ear", "horn", "crest", "crown", "hair", "antenna", "tuft", "bulb", "flower",
              "mushroom", "leaf", "leaves", "hat", "cap", "fin on", "plume", "feather on", "top of",
              "petal", "frill", "skull", "helmet", "halo", "gem on its forehead", "scalp", "mohawk",
              "bud", "sprout", "spike on head"]),
    ("belly", ["baby", "egg", "bell", "stomach", "belly", "abdomen", "body", "torso", "pouch", "navel", "swirl", "middle",
               "center", "gem", "orb", "core", "pearl", "jewel", "plate"]),
    ("side", ["rock", "magnet", "left", "right", "back", "shell", "wing", "fin", "shoulder", "side", "spike", "dorsal", "hump", "sail",
              "ridge", "scales on", "armor", "carapace", "blade", "cannon", "flank", "hip"]),
]

EFFECTS = ["burning", "paralyzing", "freezing", "cutting", "gooey", "slimy", "haunted"]


def fetch(cache: str | None) -> str:
    if cache and os.path.exists(cache):
        with open(cache, encoding="utf-8") as f:
            return f.read()
    req = urllib.request.Request(API, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as resp:
        text = json.load(resp)["parse"]["wikitext"]
    if cache:
        with open(cache, "w", encoding="utf-8") as f:
            f.write(text)
    return text


def zone_of(text: str) -> str | None:
    t = text.lower()
    for zone, keys in ZONE_RULES:
        for k in keys:
            if k in t:
                return zone
    return None


def parse_effect(note: str):
    """'Burning effect: tip of tail' -> ('burning', 'bottom', 'tip of tail')."""
    m = re.match(r"\s*([A-Za-z]+) effect:?\s*(.*)", note)
    if not m:
        return None
    kind = m.group(1).lower()
    if kind not in EFFECTS:
        return None
    where = m.group(2).strip()
    if "entire" in where.lower() or "whole" in where.lower() or "all over" in where.lower():
        return kind, "all", where
    return kind, zone_of(where) or "belly", where


def main(argv):
    cache = None
    out = os.path.join("data", "petting_gen3.lua")
    if "--cache" in argv:
        cache = argv[argv.index("--cache") + 1]
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
    text = fetch(cache)
    rows = {}
    # {{tt|shown|tooltip}} inside a row would split on its own pipes
    text = re.sub(r"\{\{tt\|([^|}]*)\|[^}]*\}\}", r"\1", text)
    for m in re.finditer(r"\{\{lop/Petting\|([^}]*)\}\}", text):
        parts = [p.strip() for p in m.group(1).split("|")]
        num = parts[0]
        if not re.fullmatch(r"\d{3}", num):
            continue  # alternate forms carry a letter suffix
        n = int(num)
        if n < 1 or n > 386 or n in rows:
            continue
        fields = [p for p in parts[1:] if not p.startswith("form=")]
        name = fields[0] if fields else "?"
        fav = fields[1] if len(fields) > 1 else ""
        dis = fields[2] if len(fields) > 2 else ""
        note = fields[3] if len(fields) > 3 else ""
        fav = fav.replace("*", "").strip()
        dis = dis.replace("*", "").strip()
        if fav.upper() == "N/A": fav = ""
        if dis.upper() == "N/A": dis = ""
        eff = parse_effect(note) if note else None
        rows[n] = (name, fav, dis, zone_of(fav), zone_of(dis), eff, note)
    missing = [n for n in range(1, 387) if n not in rows]
    unmapped = [(n, r[1]) for n, r in rows.items() if r[1] and not r[3]] + \
               [(n, r[2]) for n, r in rows.items() if r[2] and not r[4]]
    lines = [
        "-- Petting spots per species (National Dex 1..386), generated by tools/petting_table.py.",
        "-- Derived from Bulbapedia, \"Petting\" (https://bulbapedia.bulbagarden.net/wiki/Petting),",
        "-- text available under CC BY-NC-SA 2.5. Each row: favored zone, disfavored zone,",
        "-- effect kind, effect zone, then the original texts. Zones: head, face, cheeks,",
        "-- chest, belly, side, limbs, bottom, all.",
        "return {",
    ]
    for n in sorted(rows):
        name, fav, dis, fz, dz, eff, note = rows[n]
        ek = eff[0] if eff else None
        ez = eff[1] if eff else None

        def q(s):
            return "nil" if s is None or s == "" else '"' + s.replace('"', "'") + '"'

        lines.append("  [%d] = { %s, %s, %s, %s, %s, %s, %s }, -- %s" % (
            n, q(fz), q(dz), q(ek), q(ez), q(fav), q(dis), q(eff[2] if eff else None), name))
    lines.append("}")
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote %s: %d species, %d missing, %d spots unmapped" % (out, len(rows), len(missing), len(unmapped)))
    if missing:
        print("missing:", missing)
    for n, t in unmapped[:40]:
        print("unmapped %d: %s" % (n, t))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
