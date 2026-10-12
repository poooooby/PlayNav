"""Validate data/oras_recipe.lua against a garc_dump index and measure sizes.

Usage:
  python tools/recipe_check.py <garc_dir> <out_dir>

For every recipe entry: find the dumped .bclim (archive/entry/sub/clim), check
the declared width/height/format, decode it, write <out_dir>/<id>.png and
report totals for PNG (RGBA8) vs raw RGBA bytes. Prints a table of problems.
"""

from __future__ import annotations

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bclim  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse_recipe(path: str):
    """Pull add(...) calls and the loops out of the Lua recipe without a Lua interpreter."""
    # run it through luajit if available for exactness
    import subprocess
    script = (
        "local r = dofile(os.getenv('RECIPE')); for _, a in ipairs(r.assets) do "
        "if a.kind ~= 'text' then print(a.archive, a.entry, a.sub, a.clim, a.id, a.w, a.h, a.fmt) end end"
    )
    env = dict(os.environ, RECIPE=path)
    try:
        out = subprocess.run(["luajit", "-e", script], capture_output=True, text=True, check=True, env=env).stdout
    except (OSError, subprocess.CalledProcessError) as err:
        raise SystemExit("luajit is needed to read the recipe: %s" % err)
    rows = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) != 8:
            continue
        rows.append({"archive": parts[0], "entry": int(parts[1]), "sub": int(parts[2]), "clim": int(parts[3]),
                     "id": parts[4], "w": int(parts[5]), "h": int(parts[6]), "fmt": parts[7]})
    return rows


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    garc_dir, out_dir = argv[1], argv[2]
    with open(os.path.join(garc_dir, "index.json"), encoding="utf-8") as f:
        index = json.load(f)["clims"]
    # map (archive, entry, sub, clim#) -> row; clim# is the per-blob order
    by_key = {}
    order = {}
    for c in index:
        k = (c["archive"], c["entry"], c["sub"])
        n = order.get(k, 0)
        order[k] = n + 1
        by_key[(c["archive"], c["entry"], c["sub"], n)] = c
    recipe = parse_recipe(os.path.join(ROOT, "data", "oras_recipe.lua"))
    os.makedirs(out_dir, exist_ok=True)
    problems = []
    png_total = raw_total = 0
    ids = set()
    for a in recipe:
        if a["id"] in ids:
            problems.append((a["id"], "duplicate id"))
        ids.add(a["id"])
        c = by_key.get((a["archive"], a["entry"], a["sub"], a["clim"]))
        if not c:
            problems.append((a["id"], "no CLIM %d in %s entry %d/%d" % (a["clim"], a["archive"], a["entry"], a["sub"])))
            continue
        fmt_name = bclim.FORMATS.get(c["format"], "?")
        if (c["width"], c["height"], fmt_name) != (a["w"], a["h"], a["fmt"]):
            problems.append((a["id"], "is %dx%d %s, recipe says %dx%d %s" % (
                c["width"], c["height"], fmt_name, a["w"], a["h"], a["fmt"])))
        with open(os.path.join(garc_dir, c["file"]), "rb") as fh:
            w, h, fmt, rgba = bclim.decode(fh.read())
        dest = os.path.join(out_dir, a["id"].replace("/", "__") + ".png")
        bclim.write_png(dest, w, h, rgba)
        png_total += os.path.getsize(dest)
        raw_total += len(rgba)
    print("recipe entries: %d, problems: %d" % (len(recipe), len(problems)))
    for pid, why in problems:
        print("  %s: %s" % (pid, why))
    print("PNG total: %d bytes (%.0f KB); raw RGBA total: %d bytes (%.0f KB)" % (
        png_total, png_total / 1024, raw_total, raw_total / 1024))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
