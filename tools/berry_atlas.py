"""Bake Pokemon-Amie's Berry Picker art into one indexed atlas (Wilds of Hoenn's colour-number
trick, as tools/decor_atlas.py).

The pictures come from a page provided via The Spriters Resource ("Pokemon-Amie - Berry
Picker"; attribution in assets/credits.txt). The page has no grid: each piece lies loose, some
trimmed of their empty edges. ENTRIES says, for each of the game's textures (named as
data/oras_recipe.lua's lyt/berry_* rows), its size and the page's rectangle that holds it and
where that goes in it. ALIASES are the same picture under another layout pack's name (the
berries sit in four of them; the grass's three sway frames share the page's one). What the page
does not carry - the reward medals and puffs, the smoke, the stars, the number windows, the
message window, the RESULTS banner and panel, the sky, the sparkles - is left out and still comes from the
card image. The numbers are 16-bit (the backdrops hold thousands of colours): 0 transparent,
1..n an entry of that picture's own palette. Out:
  assets/amie_berry.png   one 16-bit greyscale image, the pictures packed in shelves
  data/amie_berry.lua     { depth = 16, cells = { [id] = { x, y, w, h, pal } }, alias = { [id] = id } }
src/amie/decor_art.lua expands a cell into a full-colour image the first time it is drawn.

  python tools/berry_atlas.py "<...Pokemon-Amie - Berry Picker.png>"
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
    ("berry_rear/game01_bgUp", 320, 500, 0, 87, 320, 500, 0, 0),
    ("berry_score/game01_bgDown", 400, 240, 320, 87, 400, 240, 0, 0),
    ("berry_balloon/kinomi00", 32, 32, 327, 429, 32, 32, 0, 0),
    ("berry_balloon/kinomi01", 32, 32, 359, 429, 32, 32, 0, 0),
    ("berry_balloon/kinomi02", 30, 30, 391, 429, 30, 30, 0, 0),
    ("berry_balloon/kinomi03", 32, 32, 421, 429, 32, 32, 0, 0),
    ("berry_balloon/kinomi04", 32, 32, 453, 429, 32, 32, 0, 0),
    ("berry_balloon/kinomi05", 32, 32, 485, 429, 32, 32, 0, 0),
    ("berry_balloon/kinomi06", 32, 32, 518, 428, 32, 32, 0, 0),
    ("berry_balloon/kinomi07", 30, 30, 550, 428, 30, 30, 0, 0),
    ("berry_balloon/kinomi08", 32, 32, 580, 428, 32, 32, 0, 0),
    ("berry_rear/nuts_pile", 320, 240, 0, 656, 320, 240, 0, 0),
    ("berry_rear/nuts_pile2", 320, 240, 320, 656, 320, 240, 0, 0),
    ("berry_rear/nuts_pile3", 320, 240, 640, 656, 320, 240, 0, 0),
    ("berry_score/0", 44, 44, 7, 0, 30, 42, 8, 2),
    ("berry_score/1", 44, 44, 61, 1, 11, 40, 17, 2),
    ("berry_score/2", 44, 44, 97, 1, 27, 40, 9, 2),
    ("berry_score/3", 44, 44, 141, 1, 26, 40, 10, 2),
    ("berry_score/4", 44, 44, 183, 1, 30, 40, 7, 2),
    ("berry_score/5", 44, 44, 228, 1, 28, 40, 8, 2),
    ("berry_score/6", 44, 44, 272, 1, 28, 41, 8, 2),
    ("berry_score/7", 44, 44, 8, 45, 28, 40, 8, 2),
    ("berry_score/8", 44, 44, 52, 44, 29, 42, 8, 2),
    ("berry_score/9", 44, 44, 96, 44, 29, 41, 8, 2),
    ("berry_score/10", 44, 44, 133, 44, 42, 42, 1, 2),
    ("berry_balloon/balloon_note", 40, 40, 178, 43, 38, 40, 2, 0),
    ("berry_balloon/balloon_note2", 40, 40, 218, 43, 38, 40, 2, 0),
    ("berry_balloon/balloon_star", 40, 40, 258, 45, 36, 35, 2, 2),
    ("berry_rear/01_cloud", 88, 14, 453, 335, 86, 13, 1, 1),
    ("berry_balloon/balloon00", 60, 80, 333, 339, 59, 75, 1, 5),
    ("berry_balloon/balloonx", 60, 80, 404, 350, 34, 33, 12, 16),
    ("berry_balloon/kinomi09", 32, 32, 618, 434, 20, 20, 6, 6),
    ("berry_rear/grass", 320, 69, 0, 620, 320, 36, 0, 33),
    ("berry_rear/grass_back_R00", 116, 50, 320, 593, 116, 49, 0, 1),
    ("berry_rear/grass_back_L00", 146, 52, 436, 592, 146, 52, 0, 0),
    ("berry_score/stamp", 100, 30, 0, 897, 100, 29, 0, 1),
    ("berry_demo/TouchPen", 64, 64, 101, 894, 64, 65, 1, -1),
]

ALIASES = {
    "berry_demo/balloon00": "berry_balloon/balloon00",
    "berry_demo/balloon_note": "berry_balloon/balloon_note",
    "berry_demo/kinomi00": "berry_balloon/kinomi00",
    "berry_demo/kinomi01": "berry_balloon/kinomi01",
    "berry_demo/kinomi02": "berry_balloon/kinomi02",
    "berry_front/msg_win_c": "berry_demo/msg_win_c",
    "berry_front/msg_win_u": "berry_demo/msg_win_u",
    "berry_front/msg_win_ul": "berry_demo/msg_win_ul",
    "berry_nuts/kinomi00": "berry_balloon/kinomi00",
    "berry_nuts/kinomi01": "berry_balloon/kinomi01",
    "berry_nuts/kinomi02": "berry_balloon/kinomi02",
    "berry_nuts/kinomi03": "berry_balloon/kinomi03",
    "berry_nuts/kinomi04": "berry_balloon/kinomi04",
    "berry_nuts/kinomi05": "berry_balloon/kinomi05",
    "berry_nuts/kinomi06": "berry_balloon/kinomi06",
    "berry_nuts/kinomi07": "berry_balloon/kinomi07",
    "berry_nuts/kinomi08": "berry_balloon/kinomi08",
    "berry_nuts/kinomi09": "berry_balloon/kinomi09",
    "berry_nutsanim/kinomi00": "berry_balloon/kinomi00",
    "berry_nutsanim/kinomi01": "berry_balloon/kinomi01",
    "berry_nutsanim/kinomi02": "berry_balloon/kinomi02",
    "berry_nutsanim/kinomi03": "berry_balloon/kinomi03",
    "berry_nutsanim/kinomi04": "berry_balloon/kinomi04",
    "berry_nutsanim/kinomi05": "berry_balloon/kinomi05",
    "berry_nutsanim/kinomi06": "berry_balloon/kinomi06",
    "berry_rear/grass_back_L01": "berry_rear/grass_back_L00",
    "berry_rear/grass_back_L02": "berry_rear/grass_back_L00",
    "berry_rear/grass_back_R01": "berry_rear/grass_back_R00",
    "berry_rear/grass_back_R02": "berry_rear/grass_back_R00",
    "berry_score/msg_win_c": "berry_demo/msg_win_c",
    "berry_score/msg_win_u": "berry_demo/msg_win_u",
    "berry_score/msg_win_ul": "berry_demo/msg_win_ul",
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

    png = os.path.join(ROOT, "assets", "amie_berry.png")
    atlas.save(png, optimize=True)
    lines = [
        "-- generated by tools/berry_atlas.py: Pokemon-Amie's Berry Picker art in assets/amie_berry.png",
        "-- (16-bit grey value = colour number, 0 transparent) and its palettes. Art: see",
        "-- assets/credits.txt (Berry Picker).",
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
    with open(os.path.join(ROOT, "data", "amie_berry.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print(f"{len(rows)} pictures; {png} {atlas.size} {os.path.getsize(png)} bytes")


if __name__ == "__main__":
    main()
