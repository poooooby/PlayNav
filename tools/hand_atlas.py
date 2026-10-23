"""Bake Pokemon-Amie's hand into one indexed atlas (Wilds of Hoenn's colour-number trick, as
tools/decor_atlas.py).

The hand's frames (PLAY's cursor: open, wave, point, its reactions to a burn, a shock, a freeze,
water, junk, a hit, a hurt, the tap sparkle) come from a page provided via The Spriters
Resource ("Pokemon-Amie - Hand"; attribution in assets/credits.txt): a teal grid of cells, each
frame at its cell's top left, 32x32 or 64x64. CELLS below says which cell holds which frame
(ids as the game's kawaigari_icon textures; icon_freeze1 / 2 and icon_water1 / 2 are further
frames the page carries, named in its order). icon_kara is the game's empty frame. Each frame
is stored as COLOUR NUMBERS: 0 transparent, 1..n an entry of that frame's own palette. Out:
  assets/amie_hand.png   one greyscale image, the frames packed in shelves; grey = number
  data/amie_hand.lua     { cells = { [id] = { x, y, w, h, pal } } }, pal = "rrggbbaa" strings
src/amie/decor_art.lua expands a cell into a full-colour image the first time it is drawn.

  python tools/hand_atlas.py "<...Pokemon-Amie - Hand.png>"
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WIDTH = 256
PREFIX = "lyt/amie_hand/"

# the page's cells (their top-left corners), the frame each holds and its size
CELLS = [
    (2, 2, "icon_hand_a0", 32), (36, 2, "icon_hand_a1", 32),
    (2, 36, "icon_oide_fix", 32), (36, 36, "icon_oide_a0", 32), (70, 36, "icon_oide_a1", 32),
    (104, 36, "icon_oide_a2", 32),
    (2, 70, "icon_yubi_a1", 32), (36, 70, "icon_yubi_a2", 32), (70, 70, "icon_yubi_a3", 32),
    (104, 70, "icon_yubi_fix", 32),
    (2, 104, "icon_freeze0", 32), (36, 104, "icon_freeze1", 32), (70, 104, "icon_freeze2", 32),
    (104, 104, "icon_hand", 32),
    (2, 138, "icon_hit0", 32), (36, 138, "icon_hit1", 32), (70, 138, "icon_hit2", 32),
    (104, 138, "icon_hit3", 32), (138, 138, "icon_hurt0", 32), (172, 138, "icon_hurt1", 32),
    (206, 138, "icon_hurt2", 32),
    (2, 172, "icon_burn0", 64), (68, 172, "icon_burn1", 64), (134, 172, "icon_burn2", 64),
    (200, 172, "icon_burn3", 64),
    (2, 238, "icon_water0", 64),
    (2, 304, "filth", 32), (36, 304, "icon_junk0", 32), (70, 304, "icon_junk1", 32),
    (2, 338, "icon_water1", 64), (68, 338, "icon_water2", 64),
    (2, 404, "icon_biribiri0", 64), (68, 404, "icon_biribiri1", 64), (134, 404, "icon_biribiri2", 64),
    (200, 404, "icon_biribiri3", 64),
    (2, 470, "icon_tap0", 32), (36, 470, "icon_tap1", 32), (70, 470, "icon_tap2", 32),
    (104, 470, "icon_tap3", 32), (138, 470, "icon_tap4", 32),
]
EMPTY = [("icon_kara", 32)]   # frames with nothing in them


def unrip(im):
    """The page's 4-bit channels back to the game's levels: it expanded a 4-bit value n as
    n * 16 (white 240, opaque 240) where the game uses n * 17. A sprite whose every channel
    value is a multiple of 16 is such a texture throughout; one whose alpha alone is (a 4-bit
    alpha over full colour) has only its alpha put back."""
    px = list(im.getdata())
    seen = [p for p in px if p[3] > 0]
    def x16(vals): return all(v % 16 == 0 for v in vals)
    rgb = x16(c for p in seen for c in p[:3])
    alpha = x16(p[3] for p in seen)
    if not (rgb or alpha):
        return im
    up = lambda v: v + v // 16
    out = []
    for p in px:
        if p[3] == 0:
            out.append(p)
        elif rgb:
            out.append((up(p[0]), up(p[1]), up(p[2]), up(p[3]) if alpha else p[3]))
        else:
            out.append((p[0], p[1], p[2], up(p[3])))
    im = im.copy()
    im.putdata(out)
    return im


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    page = Image.open(sys.argv[1]).convert("RGBA")
    # shelves: tallest first, left to right
    items = sorted(CELLS, key=lambda c: (-c[3], c[2]))
    places, x, y, shelf = {}, 0, 0, 0
    for _, _, id_, s in items:
        if x + s > WIDTH:
            x, y, shelf = 0, y + shelf, 0
        places[id_] = (x, y)
        x += s
        shelf = max(shelf, s)
    atlas = Image.new("L", (WIDTH, y + shelf), 0)
    rows = []
    for cx, cy, id_, s in CELLS:
        px = unrip(page.crop((cx, cy, cx + s, cy + s))).load()
        ax, ay = places[id_]
        pal, index = [], {}
        for yy in range(s):
            for xx in range(s):
                p = px[xx, yy]
                if p[3] == 0:
                    continue
                if p not in index:
                    pal.append(p)
                    index[p] = len(pal)
                    if len(pal) > 255:
                        sys.exit(f"{id_}: more than 255 colours")
                atlas.putpixel((ax + xx, ay + yy), index[p])
        rows.append((PREFIX + id_, ax, ay, s, pal))
    # an empty frame reads cell 0, 0 of nothing: its palette is empty, every pixel transparent
    for id_, s in EMPTY:
        rows.append((PREFIX + id_, 0, 0, s, []))

    png = os.path.join(ROOT, "assets", "amie_hand.png")
    atlas.save(png, optimize=True)
    lines = [
        "-- generated by tools/hand_atlas.py: Pokemon-Amie's hand in assets/amie_hand.png",
        "-- (grey value = colour number, 0 transparent) and its palettes. Art: see assets/credits.txt",
        "-- (Pokemon-Amie hand).",
        "return {",
        "  cells = {",
    ]
    for id_, ax, ay, s, pal in sorted(rows):
        hexes = ", ".join('"%02x%02x%02x%02x"' % p for p in pal)
        lines.append(f'    ["{id_}"] = {{ x = {ax}, y = {ay}, w = {s}, h = {s}, pal = {{ {hexes} }} }},')
    lines += ["  },", "}", ""]
    with open(os.path.join(ROOT, "data", "amie_hand.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print(f"{len(rows)} frames; {png} {atlas.size} {os.path.getsize(png)} bytes")


if __name__ == "__main__":
    main()
