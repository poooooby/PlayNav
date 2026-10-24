"""Bake Pokemon-Amie's Head It art into one indexed atlas (Wilds of Hoenn's colour-number trick,
as tools/decor_atlas.py and tools/berry_atlas.py).

The pictures come from a page provided via The Spriters Resource ("Pokemon-Amie - Head It";
attribution in assets/credits.txt). The page has no grid: each piece lies loose, some trimmed of
their empty edges. ENTRIES says, for each of the game's textures (named as data/oras_recipe.lua's
lyt/head_* rows), its size, the page's rectangle that holds it and where that goes in it.
ALIASES are the same picture under another name (a layout pack that repeats it, or the game's
own copies: a yarn ball's last three frames are one picture). What the page does not carry -
the reward medals and puffs, the smoke, the stars, the number and score windows, the message
window, the RESULTS banner, the HIGH SCORE stamp, the clouds, the grass, the heading frames -
is left out and still comes from the card image. The numbers are 16-bit: 0 transparent, 1..n
an entry of that picture's own palette. Out:
  assets/amie_head.png   one 16-bit greyscale image, the pictures packed in shelves
  data/amie_head.lua     { depth = 16, cells = { [id] = { x, y, w, h, pal } }, alias = { [id] = id } }
src/amie/decor_art.lua expands a cell into a full-colour image the first time it is drawn.

  python tools/head_atlas.py "<...Pokemon-Amie - Head It.png>"
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WIDTH = 1024
PREFIX = "lyt/"

# texture, its w and h, the page's rectangle (x, y, w, h), where that lands in the texture
ENTRIES = [
    ("head_ball/ball00_00", 60, 90, 0, 1206, 60, 90, 0, 0),
    ("head_ball/ball00_01", 60, 90, 60, 1206, 60, 90, 0, 0),
    ("head_ball/ball00_02", 60, 90, 120, 1206, 60, 90, 0, 0),
    ("head_ball/ball00_03", 60, 90, 0, 1296, 60, 90, 0, 0),
    ("head_ball/ball01_00", 60, 90, 0, 1386, 60, 90, 0, 0),
    ("head_ball/ball01_01", 60, 90, 60, 1386, 60, 90, 0, 0),
    ("head_ball/ball01_02", 60, 90, 120, 1386, 60, 90, 0, 0),
    ("head_ball/ball01_03", 60, 90, 0, 1476, 60, 90, 0, 0),
    ("head_ball/ball02_00", 60, 90, 0, 1566, 60, 90, 0, 0),
    ("head_ball/ball02_01", 60, 90, 60, 1566, 60, 90, 0, 0),
    ("head_ball/ball02_02", 60, 90, 120, 1566, 60, 90, 0, 0),
    ("head_ball/ball02_03", 60, 90, 0, 1656, 60, 90, 0, 0),
    ("head_ball/ball03_00", 60, 90, 0, 1746, 60, 90, 0, 0),
    ("head_ball/ball03_01", 60, 90, 60, 1746, 60, 90, 0, 0),
    ("head_ball/ball03_02", 60, 90, 120, 1746, 60, 90, 0, 0),
    ("head_ball/giant02", 128, 256, 256, 1836, 128, 256, 0, 0),
    ("head_down/1", 44, 44, 44, 0, 44, 44, 0, 0),
    ("head_down/2", 44, 44, 88, 0, 44, 44, 0, 0),
    ("head_down/3", 44, 44, 132, 0, 44, 44, 0, 0),
    ("head_down/5", 44, 44, 0, 44, 44, 44, 0, 0),
    ("head_down/signal_blue", 48, 48, 236, 88, 48, 48, 0, 0),
    ("head_down/signal_red", 48, 48, 0, 152, 48, 48, 0, 0),
    ("head_down/signal_yellow", 48, 48, 48, 152, 48, 48, 0, 0),
    ("head_effect/exc", 64, 64, 44, 88, 64, 64, 0, 0),
    ("head_effect/hit01", 64, 32, 172, 88, 64, 32, 0, 0),
    ("head_front/0", 44, 44, 0, 0, 44, 44, 0, 0),
    ("head_front/4", 44, 44, 176, 0, 44, 44, 0, 0),
    ("head_front/6", 44, 44, 44, 44, 44, 44, 0, 0),
    ("head_front/7", 44, 44, 88, 44, 44, 44, 0, 0),
    ("head_front/8", 44, 44, 132, 44, 44, 44, 0, 0),
    ("head_front/9", 44, 44, 176, 44, 44, 44, 0, 0),
    ("head_rear/signal_yellow", 400, 170, 0, 386, 400, 170, 0, 0),
    ("head_bg/bg_DOWN", 320, 240, 0, 966, 320, 240, 0, 0),
    ("head_rear/sky", 400, 240, 0, 726, 400, 240, 0, 0),
    ("head_front/10", 44, 44, 1, 89, 42, 42, 1, 2),
    ("head_down/exc2", 64, 64, 112, 86, 58, 67, 2, -2),
    ("head_demo/TouchPen", 64, 64, 98, 153, 62, 62, 2, 0),
    ("head_ball/giant00", 128, 256, 2, 1895, 127, 194, 2, 59),
    ("head_ball/giant01", 128, 256, 129, 1895, 127, 194, 0, 59),
    ("head_rear/signal_red", 400, 170, 0, 611, 389, 54, 0, 64),
    ("head_rear/signal_blue", 400, 170, 0, 227, 400, 156, 0, 11),
]

ALIASES = {
    "head_ball/ball00_04": "head_ball/ball00_03",
    "head_ball/ball00_05": "head_ball/ball00_03",
    "head_ball/ball01_04": "head_ball/ball01_03",
    "head_ball/ball01_05": "head_ball/ball01_03",
    "head_ball/ball02_04": "head_ball/ball02_03",
    "head_ball/ball02_05": "head_ball/ball02_03",
    "head_demo/ball00_00": "head_ball/ball00_00",
    "head_demo/ball00_01": "head_ball/ball00_01",
    "head_demo/ball00_02": "head_ball/ball00_02",
    "head_effect/exc2": "head_down/exc2",
    "head_front/1": "head_down/1",
    "head_front/2": "head_down/2",
    "head_front/3": "head_down/3",
    "head_front/5": "head_down/5",
}


def unrip(im):
    """The page's pictures back to the game's levels. Two ways the page changed them:
    - 4-bit channels widened as n * 16 (white 240) where the game uses n * 17: a picture whose
      every value is a multiple of 16 has them put back (its alpha alone when only that is);
    - a 4-bit alpha drawn over white and squared: alpha a became a * a / 255 and each colour c
      became c * a / 255 + 255 * (1 - a / 255) - a picture whose alphas all sit on those squared
      levels has both undone."""
    px = list(im.getdata())
    seen = [p for p in px if p[3] > 0]
    if not seen:
        return im
    def x16(vals): return all(v % 16 == 0 for v in vals)
    alphas = {p[3] for p in seen}
    squared = {round(255 * (n / 15) ** 2) for n in range(16)}
    if not alphas <= {17 * n for n in range(16)} and all(min(abs(a - s) for s in squared) <= 1 for a in alphas):
        out = []
        for p in px:
            if p[3] == 0:
                out.append(p)
                continue
            k = (p[3] / 255) ** 0.5
            c = [max(0, min(255, round((v - 255 * (1 - k)) / k))) for v in p[:3]]
            out.append((c[0], c[1], c[2], 17 * round(k * 15)))
        im = im.copy()
        im.putdata(out)
        return im
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
    pics = {}
    for id_, w, h, sx, sy, sw, sh, dx, dy in ENTRIES:
        pic = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        pic.alpha_composite(page.crop((sx, sy, sx + sw, sy + sh)), (max(0, dx), max(0, dy)),
                            (max(0, -dx), max(0, -dy)))
        pics[id_] = unrip(pic)
    # shelves: tallest first, left to right
    order = sorted(pics, key=lambda k: (-pics[k].size[1], k))
    places, x, y, shelf = {}, 0, 0, 0
    for id_ in order:
        w, h = pics[id_].size
        if x + w > WIDTH:
            x, y, shelf = 0, y + shelf, 0
        places[id_] = (x, y)
        x += w
        shelf = max(shelf, h)
    atlas = Image.new("I;16", (WIDTH, y + shelf), 0)
    rows = []
    for id_, pic in pics.items():
        w, h = pic.size
        px = pic.load()
        ax, ay = places[id_]
        pal, index = [], {}
        for yy in range(h):
            for xx in range(w):
                p = px[xx, yy]
                if p[3] == 0:
                    continue
                if p not in index:
                    pal.append(p)
                    index[p] = len(pal)
                atlas.putpixel((ax + xx, ay + yy), index[p])
        rows.append((PREFIX + id_, ax, ay, w, h, pal))

    png = os.path.join(ROOT, "assets", "amie_head.png")
    atlas.save(png, optimize=True)
    lines = [
        "-- generated by tools/head_atlas.py: Pokemon-Amie's Head It art in assets/amie_head.png",
        "-- (16-bit grey value = colour number, 0 transparent) and its palettes. Art: see",
        "-- assets/credits.txt (Head It).",
        "return {",
        "  depth = 16,",
        "  cells = {",
    ]
    for id_, ax, ay, w, h, pal in sorted(rows):
        hexes = ", ".join('"%02x%02x%02x%02x"' % p for p in pal)
        lines.append(f'    ["{id_}"] = {{ x = {ax}, y = {ay}, w = {w}, h = {h}, pal = {{ {hexes} }} }},')
    lines += ["  },", "  alias = {"]
    for k, v in sorted(ALIASES.items()):
        if PREFIX + v in dict((r[0], 1) for r in rows):
            lines.append(f'    ["{PREFIX + k}"] = "{PREFIX + v}",')
    lines += ["  },", "}", ""]
    with open(os.path.join(ROOT, "data", "amie_head.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print(f"{len(rows)} pictures; {png} {atlas.size} {os.path.getsize(png)} bytes")


if __name__ == "__main__":
    main()
