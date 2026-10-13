"""Recipe rows for a game screen played by src/lytplayer.lua: every texture its layouts (and
their clips' texture patterns) name, found in the packs the screen searches, as
`add(archive, entry, sub, clim, "lyt/<pack>/<name>", w, h, fmt)` lines for
data/oras_recipe.lua, plus the `files(...)` row for each layout pack. Development only.

Usage:
  python tools/lyt_rows.py <romfs> <pack>=<archive>:<entry>:<sub> ... -- <pack>:<layout.bclyt>:<pack,pack,...> ...

Example (Super Training's regimen):
  python tools/lyt_rows.py romfs st_hud=a/1/1/4:0:0 st_aim=a/1/1/4:1:0 st_menu=a/1/1/3:0:0 \\
    st_common=a/0/2/8:2:0 st_lang=a/2/1/7:0:2 -- st_hud:upper.bclyt:st_hud,st_lang \\
    st_aim:lower.bclyt:st_aim st_menu:result_upper.bclyt:st_menu,st_common,st_lang

Textures a layout names that no listed pack holds are reported on stderr (the game fills
them at run time: icons, sprites); the code sets those panes' images.
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import garc_dump as g  # noqa: E402
from darc import entries  # noqa: E402

FMT = ["L8", "A8", "LA4", "LA8", "HILO8", "RGB565", "RGB8", "RGBA5551", "RGBA4", "RGBA8", "ETC1", "ETC1A4", "L4", "A4"]


def blob(romfs, archive, entry, sub):
    data = open(os.path.join(romfs, *archive.split("/")), "rb").read()
    _, off, ents = g.parse_garc(data)
    for j, s, e, _ in ents[entry]:
        if j == sub:
            raw = data[off + s: off + e]
            return g.lz_decode(raw) or raw
    raise SystemExit("no %s %d %d" % (archive, entry, sub))


def clims(b):
    base = b.find(b"darc")
    out, i = {}, 0
    for n, d, o, s in entries(b, base):
        if not n.endswith(".bclim"):
            continue
        t = b[o + s - 0x28: o + s]
        w, h, f = struct.unpack_from("<HHI", t, 0x1c)
        out[n] = (i, w, h, FMT[f] if f < len(FMT) else str(f))
        i += 1
    return out


def cstr(b, p):
    return b[p:b.index(b"\x00", p)].decode("latin-1")


def layout_textures(b, lname):
    base = b.find(b"darc")
    o = next(o for n, d, o, s in entries(b, base) if n == lname)
    hs = struct.unpack_from("<H", b, o + 6)[0]
    fs = struct.unpack_from("<I", b, o + 12)[0]
    p, names = o + hs, []
    while p < o + fs:
        mg, size = b[p:p + 4], struct.unpack_from("<I", b, p + 4)[0]
        if mg == b"txl1":
            d = p + 8
            for i in range(struct.unpack_from("<I", b, d)[0]):
                names.append(cstr(b, d + 4 + struct.unpack_from("<I", b, d + 4 + i * 4)[0]))
        p += size
    # the texture patterns of the layout's clips (<layout>_*.bclan)
    prefix = lname[:-6] + "_"
    for n, d, o2, s in entries(b, base):
        if not (n.endswith(".bclan") and n.startswith(prefix)):
            continue
        q = o2 + struct.unpack_from("<H", b, o2 + 6)[0]
        while q < o2 + s:
            mg, size = b[q:q + 4], struct.unpack_from("<I", b, q + 4)[0]
            if mg == b"pai1":
                for i in range(struct.unpack_from("<H", b, q + 12)[0]):
                    names.append(cstr(b, q + 20 + struct.unpack_from("<I", b, q + 20 + i * 4)[0]))
            q += size
    return names


def main(argv):
    if "--" not in argv or len(argv) < 4:
        print(__doc__)
        return 2
    romfs = argv[1]
    cut = argv.index("--")
    packs = {}
    for spec in argv[2:cut]:
        name, where = spec.split("=")
        archive, entry, sub = where.split(":")
        b = blob(romfs, archive, int(entry), int(sub))
        packs[name] = (archive, int(entry), int(sub), b, clims(b))
    need, files = {}, []
    for spec in argv[cut + 1:]:
        pack, lname, search = spec.split(":")
        b = packs[pack][3]
        if pack not in files:
            files.append(pack)
        for n in layout_textures(b, lname):
            for s in search.split(","):
                if n in packs[s][4]:
                    need.setdefault(s, set()).add(n)
                    break
            else:
                print("-- unresolved %s %s" % (lname, n), file=sys.stderr)
    for pack in files:
        archive, entry, sub, b, _ = packs[pack]
        count = sum(1 for n, d, o, s in entries(b, b.find(b"darc")) if n.endswith((".bclyt", ".bclan")))
        print('files("%s", %d, %d, "lyt/%s", %d, "")' % (archive, entry, sub, pack, count))
    for pack, (archive, entry, sub, _, cl) in packs.items():
        for n in sorted(need.get(pack, ()), key=lambda n: cl[n][0]):
            i, w, h, f = cl[n]
            print('add("%s", %d, %d, %d, "lyt/%s/%s", %d, %d, "%s")' % (archive, entry, sub, i, pack, n[:-6], w, h, f))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
