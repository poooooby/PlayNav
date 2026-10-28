"""Bake the Game Boy games' back and front pics into indexed atlases (the colour-number trick
of tools/balloon_atlas.py).

Gen 1 and Gen 2's own pics are four shades, their white left see-through, the backs with dotted
outlines; NaviPlay draws a Pokemon over 3DS scenes (Amie's PLAY and minigames, the regimen's
rider), so Gen 1 / 2 take Pokemon Crystal's sprites instead, from the Crystal Animated Sprites
with Shiny Visuals pack (assets/back/{normal,shiny}/<n>.png; assets/front/{normal,shiny}/<n>/
NNN.png, an animation: its first frame; 4 colours + transparent each, up to 56x56). Each is
stored as COLOUR NUMBERS, 1 lightest .. 4 darkest by its normal colours' order (0 transparent),
the colours in data. A shiny whose pixels map one to one onto its normal's shares the cell and
adds its own palette; the others (a shade split or merged) get a cell of their own.
Out (gb_backs for --side back, gb_fronts for --side front):
  assets/gb_<side>s.png   a grid of 56x56 cells, 16 across; grey value = colour number x 63
  data/gb_<side>s.lua     { size, cols, cells = { [key] = { c, r, w, h, pal, shiny | shinyCell } } }
                          key: the National Dex number ("25"), Unown's letters "201B" .. ("201" = A)
src/refresh/host_gb.lua expands a cell into a full-colour pic.

  python tools/gb_backs_atlas.py --side back --pack "<pack>/assets/back"
  python tools/gb_backs_atlas.py --side front --pack "<pack>/assets/front"
"""
import argparse
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SIZE, COLS, STEP = 56, 16, 63


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def pixels(path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    return w, h, [im.getpixel((x, y)) for y in range(h) for x in range(w)]


def numbered(px):
    """colour numbers 1 (lightest) .. n by the image's own colours; 0 transparent"""
    cols = sorted({p[:3] for p in px if p[3] >= 128}, key=lum, reverse=True)
    index = {c: i + 1 for i, c in enumerate(cols)}
    return [0 if p[3] < 128 else index[p[:3]] for p in px], cols


def hexes(cols):
    return ["%02x%02x%02x" % c for c in cols]


def key_of(name):
    """a back "25.png" / "201B.png", a front's folder "25" / "201-b" -> "25" / "201B" (or None)"""
    m = re.match(r"^(\d+)([A-Z?!]?)\.png$", name) or re.match(r"^(\d+)(?:-([a-z?!]))?$", name)
    if not m:
        return None
    n, letter = int(m.group(1)), (m.group(2) or "").upper()
    if n < 1 or n > 251:
        return None
    return str(n) + letter


def order(name):
    return (int(re.match(r"\d+", name).group()), name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", required=True, help="the pack's assets/back or assets/front folder")
    ap.add_argument("--side", choices=("back", "front"), default="back")
    args = ap.parse_args()
    front = args.side == "front"
    normal, shiny = os.path.join(args.pack, "normal"), os.path.join(args.pack, "shiny")

    def file_of(folder, name):
        return os.path.join(folder, name, "001.png") if front else os.path.join(folder, name)

    names = sorted((n for n in os.listdir(normal)
                    if key_of(n) and (os.path.isdir(os.path.join(normal, n)) == front)), key=order)
    cells, grids, extra = {}, [], 0
    for name in names:
        w, h, px = pixels(file_of(normal, name))
        if w > SIZE or h > SIZE:
            sys.exit("%s is %dx%d, over %d" % (name, w, h, SIZE))
        nums, cols = numbered(px)
        rec = {"cell": len(grids), "w": w, "h": h, "pal": hexes(cols)}
        grids.append((w, h, nums))
        sp = file_of(shiny, name)
        if os.path.exists(sp):
            sw, sh, spx = pixels(sp)
            spal, ok = {}, (sw, sh) == (w, h)
            if ok:
                for n, p in zip(nums, spx):
                    if n == 0:
                        if p[3] >= 128:
                            ok = False
                            break
                        continue
                    if p[3] < 128 or spal.setdefault(n, p[:3]) != p[:3]:
                        ok = False
                        break
            if ok and len(spal) == len(cols):
                rec["shiny"] = hexes([spal[i + 1] for i in range(len(cols))])
            else:
                snums, scols = numbered(spx)
                rec["shinyCell"] = {"cell": len(grids), "w": sw, "h": sh, "pal": hexes(scols)}
                grids.append((sw, sh, snums))
                extra += 1
        cells[key_of(name)] = rec

    stem = "gb_%ss" % args.side
    rows = (len(grids) + COLS - 1) // COLS
    atlas = Image.new("L", (COLS * SIZE, rows * SIZE), 0)
    for i, (w, h, nums) in enumerate(grids):
        ox, oy = (i % COLS) * SIZE, (i // COLS) * SIZE
        for y in range(h):
            for x in range(w):
                atlas.putpixel((ox + x, oy + y), nums[y * w + x] * STEP)
    atlas.save(os.path.join(ROOT, "assets", stem + ".png"), optimize=True)

    def cell(rec):
        i = rec["cell"]
        return "c = %d, r = %d, w = %d, h = %d, pal = { %s }" % (
            i % COLS, i // COLS, rec["w"], rec["h"], ", ".join('"%s"' % c for c in rec["pal"]))

    lines = [
        "-- generated by tools/gb_backs_atlas.py: the Game Boy games' %s pics (Pokemon Crystal's," % args.side,
        "-- from the Crystal Animated Sprites with Shiny Visuals pack) in assets/%s.png: 56x56" % stem,
        "-- cells, grey value = colour number x 63 (0 transparent, 1 lightest .. 4 darkest), the colours",
        "-- here. `shiny`: the shiny's colours for the same cell; `shinyCell`: a cell of its own.",
        "return {",
        "  size = %d, cols = %d, step = %d," % (SIZE, COLS, STEP),
        "  cells = {",
    ]
    for key in sorted(cells, key=order):
        rec = cells[key]
        parts = [cell(rec)]
        if "shiny" in rec:
            parts.append("shiny = { %s }" % ", ".join('"%s"' % c for c in rec["shiny"]))
        if "shinyCell" in rec:
            parts.append("shinyCell = { %s }" % cell(rec["shinyCell"]))
        lines.append('    ["%s"] = { %s },' % (key, ", ".join(parts)))
    lines += ["  },", "}", ""]
    with open(os.path.join(ROOT, "data", stem + ".lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("%d %ss, %d shiny cells of their own, atlas %dx%d"
          % (len(cells), args.side, extra, COLS * SIZE, rows * SIZE))


if __name__ == "__main__":
    main()
