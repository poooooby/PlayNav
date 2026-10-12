"""Pack the item icons into one atlas, assets/items.png: 32x32 cells, five to a row, in the
order of tools/items_pokeapi.py's ITEMS (the cell an item uses is its `iconCell` in
data/training_items.lua). Development only.

Usage:
  python tools/items_atlas.py <icon dir> [--out assets/items.png]

<icon dir> holds <slug>.png for every item (PokeSprite's icons; see assets/credits.txt).
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from items_pokeapi import ITEMS  # noqa: E402

CELL, COLS = 32, 5


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    src = argv[1]
    out = argv[argv.index("--out") + 1] if "--out" in argv else "assets/items.png"
    rows = (len(ITEMS) + COLS - 1) // COLS
    atlas = Image.new("RGBA", (COLS * CELL, rows * CELL), (0, 0, 0, 0))
    for i, row in enumerate(ITEMS):
        slug = row[0]
        icon = Image.open(os.path.join(src, slug + ".png")).convert("RGBA")
        if icon.size != (CELL, CELL):
            raise SystemExit("%s is %dx%d, not %dx%d" % (slug, icon.width, icon.height, CELL, CELL))
        atlas.paste(icon, ((i % COLS) * CELL, (i // COLS) * CELL))
        print("cell %d  %s" % (i, slug))
    atlas.save(out, optimize=True)
    print("wrote", out, atlas.size)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
