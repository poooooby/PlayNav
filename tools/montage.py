"""Tile decoded textures of one archive into a single montage PNG for review.

Usage:
  python tools/montage.py <sheets_dir> <archive_tag> <out.png> [--cols 10] [--cell 72] [--max 120] [--skip N]

Reads <sheets_dir>/results.json (from discover.py), takes the rows of
<archive_tag> (e.g. a_0_4_3) in index order, scales each texture down to fit a
cell, draws it on a checker background, and writes the grid plus a
<out>.txt sidecar listing cell number -> file, size, format.
"""

from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bclim  # noqa: E402


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    sheets, tag, out = argv[1], argv[2], argv[3]
    cols = int(argv[argv.index("--cols") + 1]) if "--cols" in argv else 10
    cell = int(argv[argv.index("--cell") + 1]) if "--cell" in argv else 72
    maxn = int(argv[argv.index("--max") + 1]) if "--max" in argv else 120
    skip = int(argv[argv.index("--skip") + 1]) if "--skip" in argv else 0
    with open(os.path.join(sheets, "results.json"), encoding="utf-8") as f:
        rows = [r for r in json.load(f) if r["file"].startswith(tag + "/")]
    rows = rows[skip:skip + maxn]
    n = len(rows)
    if n == 0:
        print("no rows for", tag)
        return 1
    grid_rows = (n + cols - 1) // cols
    W, H = cols * cell, grid_rows * cell
    img = bytearray(W * H * 4)
    # checker background
    for y in range(H):
        for x in range(W):
            o = (y * W + x) * 4
            v = 110 if ((x // 8) + (y // 8)) % 2 else 150
            img[o:o + 4] = bytes((v, v, v, 255))
    sidecar = []
    for i, r in enumerate(rows):
        png = os.path.normpath(os.path.join(sheets, r["png"]))
        w, h, rgba = bclim.read_png_rgba(png)
        scale = max(w / (cell - 4), h / (cell - 4), 1.0)
        dw, dh = max(1, int(w / scale)), max(1, int(h / scale))
        cx, cy = (i % cols) * cell + 2, (i // cols) * cell + 2
        for yy in range(dh):
            sy = min(h - 1, int(yy * scale))
            for xx in range(dw):
                sx = min(w - 1, int(xx * scale))
                p = (sy * w + sx) * 4
                a = rgba[p + 3]
                if a == 0:
                    continue
                o = ((cy + yy) * W + (cx + xx)) * 4
                if a == 255:
                    img[o:o + 3] = rgba[p:p + 3]
                else:
                    for c in range(3):
                        img[o + c] = (rgba[p + c] * a + img[o + c] * (255 - a)) // 255
        # cell border
        for xx in range(cell):
            for yy in (0, cell - 1):
                o = (((i // cols) * cell + yy) * W + (i % cols) * cell + xx) * 4
                img[o:o + 3] = bytes((40, 40, 60))
        sidecar.append("%3d  %s  %dx%d %s %s" % (i, r["file"], r["width"], r["height"], r["fmt_name"],
                                                 "LZ" if r["compressed"] else "raw"))
    bclim.write_png(out, W, H, bytes(img))
    with open(out + ".txt", "w", encoding="utf-8") as f:
        f.write("\n".join(sidecar) + "\n")
    print("wrote %s (%d cells, %dx%d)" % (out, n, W, H))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
