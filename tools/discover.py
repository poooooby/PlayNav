"""Decode every dumped .bclim two ways, compare, and build contact sheets.

Usage:
  python tools/discover.py <garc_dir> <png_dir> <sheets_dir> [--bclimtool <exe>] [--limit N]

<garc_dir> is the output of garc_dump.py (holds index.json). For each .bclim:
  1. tools/bclim.py decodes it to <png_dir>/<archive>/<name>.py.png
  2. if --bclimtool is given, bclimtool decodes it to <name>.tool.png and the
     two are compared pixel for pixel; mismatches are listed in REPORT.md
Then one HTML contact sheet per archive goes to <sheets_dir>, plus index.html,
so the right assets can be picked by eye and named in data/oras_recipe.lua.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bclim  # noqa: E402


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    garc_dir, png_dir, sheets_dir = argv[1], argv[2], argv[3]
    tool = argv[argv.index("--bclimtool") + 1] if "--bclimtool" in argv else None
    limit = int(argv[argv.index("--limit") + 1]) if "--limit" in argv else None
    with open(os.path.join(garc_dir, "index.json"), encoding="utf-8") as f:
        index = json.load(f)
    clims = index["clims"][:limit] if limit else index["clims"]
    os.makedirs(png_dir, exist_ok=True)
    os.makedirs(sheets_dir, exist_ok=True)

    results = []
    mismatches = []
    errors = []
    by_archive = {}
    for i, c in enumerate(clims):
        src = os.path.join(garc_dir, c["file"])
        tag = c["file"].split("/")[0]
        base = os.path.splitext(os.path.basename(c["file"]))[0]
        out_dir = os.path.join(png_dir, tag)
        os.makedirs(out_dir, exist_ok=True)
        py_png = os.path.join(out_dir, base + ".py.png")
        try:
            with open(src, "rb") as fh:
                w, h, fmt, rgba = bclim.decode(fh.read())
            bclim.write_png(py_png, w, h, rgba)
        except Exception as err:  # noqa: BLE001
            errors.append((c["file"], str(err)))
            continue
        row = dict(c)
        row["png"] = os.path.relpath(py_png, sheets_dir).replace("\\", "/")
        row["fmt_name"] = fmt
        row["png_bytes"] = os.path.getsize(py_png)
        row["rgba_md5"] = hashlib.md5(rgba).hexdigest()
        row["match"] = None
        if tool:
            tool_png = os.path.join(out_dir, base + ".tool.png")
            proc = subprocess.run([tool, "-dfp", src, tool_png], capture_output=True, text=True)
            if proc.returncode != 0 or not os.path.exists(tool_png):
                row["match"] = "tool-failed"
                mismatches.append((c["file"], "bclimtool failed: " + (proc.stderr or proc.stdout).strip()[:200]))
            else:
                try:
                    tw, th, trgba = bclim.read_png_rgba(tool_png)
                    if (tw, th) != (w, h):
                        row["match"] = "size"
                        mismatches.append((c["file"], "size %dx%d vs tool %dx%d" % (w, h, tw, th)))
                    else:
                        diff = 0
                        first = None
                        for p in range(0, len(rgba), 4):
                            if rgba[p:p + 4] != trgba[p:p + 4]:
                                # treat fully transparent pixels as equal regardless of colour
                                if rgba[p + 3] == 0 and trgba[p + 3] == 0:
                                    continue
                                diff += 1
                                if first is None:
                                    first = (p // 4 % w, p // 4 // w, tuple(rgba[p:p + 4]), tuple(trgba[p:p + 4]))
                        row["match"] = "ok" if diff == 0 else "diff:%d" % diff
                        if diff:
                            mismatches.append((c["file"], "%s %d px differ, first at %s" % (fmt, diff, first)))
                except Exception as err:  # noqa: BLE001
                    row["match"] = "cmp-error"
                    mismatches.append((c["file"], "compare error: " + str(err)))
        results.append(row)
        by_archive.setdefault(tag, []).append(row)
        if (i + 1) % 100 == 0:
            print("... %d / %d" % (i + 1, len(clims)))

    # contact sheets
    for tag, rows in sorted(by_archive.items()):
        cells = []
        for r in rows:
            cells.append(
                '<figure><img src="%s" title="%s"><figcaption>%s<br>%dx%d %s<br>%s %s</figcaption></figure>' % (
                    r["png"], r["file"], os.path.basename(r["file"]), r["width"], r["height"], r["fmt_name"],
                    "LZ" if r["compressed"] else "raw", r["match"] or ""))
        html = ("<!doctype html><meta charset=utf-8><title>%s</title>"
                "<style>body{background:#223;color:#eee;font:12px sans-serif}"
                "figure{display:inline-block;margin:6px;text-align:center;vertical-align:top;background:#334;padding:4px}"
                "img{image-rendering:pixelated;background:repeating-conic-gradient(#666 0 25%%,#999 0 50%%) 0 0/16px 16px;max-width:256px}"
                "</style><h1>%s (%d)</h1>%s") % (tag, tag, len(rows), "".join(cells))
        with open(os.path.join(sheets_dir, tag + ".html"), "w", encoding="utf-8") as f:
            f.write(html)
    links = "".join('<li><a href="%s.html">%s</a> (%d)</li>' % (t, t, len(r)) for t, r in sorted(by_archive.items()))
    with open(os.path.join(sheets_dir, "index.html"), "w", encoding="utf-8") as f:
        f.write("<!doctype html><meta charset=utf-8><title>BCLIM sheets</title><ul>%s</ul>" % links)

    # report
    fmt_counts = {}
    total_png = 0
    for r in results:
        fmt_counts[r["fmt_name"]] = fmt_counts.get(r["fmt_name"], 0) + 1
        total_png += r["png_bytes"]
    with open(os.path.join(sheets_dir, "REPORT.md"), "w", encoding="utf-8") as f:
        f.write("# BCLIM discovery report\n\n")
        f.write("- decoded: %d\n- errors: %d\n- bclimtool mismatches: %d\n- total PNG bytes (RGBA8, zlib 9): %d\n\n" % (
            len(results), len(errors), len(mismatches), total_png))
        f.write("## formats\n\n")
        for k, v in sorted(fmt_counts.items(), key=lambda kv: -kv[1]):
            f.write("- %s: %d\n" % (k, v))
        if mismatches:
            f.write("\n## mismatches\n\n")
            for file, why in mismatches:
                f.write("- %s: %s\n" % (file, why))
        if errors:
            f.write("\n## errors\n\n")
            for file, why in errors:
                f.write("- %s: %s\n" % (file, why))
    with open(os.path.join(sheets_dir, "results.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, indent=1)
    # a Lua table of ground truth for the in-game decoder's local test
    with open(os.path.join(sheets_dir, "results.lua"), "w", encoding="utf-8") as f:
        f.write("return {\n")
        for r in results:
            f.write('  { archive = %r, entry = %d, sub = %d, clim_start = %d, clim_end = %d, '
                    'compressed = %s, w = %d, h = %d, format = %r, md5 = %r },\n' % (
                        r["archive"], r["entry"], r["sub"], r["clim_start"], r["clim_end"],
                        "true" if r["compressed"] else "false", r["width"], r["height"],
                        r["fmt_name"], r["rgba_md5"]))
        f.write("}\n")
    print("decoded %d, errors %d, mismatches %d, formats %s" % (len(results), len(errors), len(mismatches), fmt_counts))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
