"""Print a BCLAN (3DS layout animation) as per-pane keyframe tracks.

Usage:
  python tools/clan.py <blob> <clan offset>
  python tools/clan.py <blob> --darc <name.bclan>     (find it in the blob's darc)

<blob> is a decompressed archive entry (tools/garc_blob.py). Tracks print as
  <pane> <tag>.<target>  frame:value ...
tags: CLPA pane SRT (0..2 translate xyz, 3..5 rotate xyz, 6..7 scale xy, 8..9 size wh),
CLVC vertex colours (0..15 = corner TL/TR/BL/BR x rgba, 16 = pane alpha), CLVI
visibility, CLTS texture SRT, CLMC material colour, CLTP texture pattern.
Hermite keys are (frame, value, slope); step keys are (frame, value).
"""
import struct
import sys

PA = ["tx", "ty", "tz", "rx", "ry", "rz", "sx", "sy", "w", "h"]
VC = ["%s.%s" % (c, ch) for c in ("tl", "tr", "bl", "br") for ch in "rgba"] + ["alpha"]


def cstr(b, p, n):
    return b[p:p + n].split(b"\0")[0].decode("latin-1")


def parse(b, base):
    assert b[base:base + 4] == b"CLAN", b[base:base + 4]
    hsize = struct.unpack_from("<H", b, base + 6)[0]
    fsize = struct.unpack_from("<I", b, base + 12)[0]
    p, end = base + hsize, base + fsize
    out = {"frames": None, "loop": None, "tracks": []}
    while p < end:
        magic = b[p:p + 4]
        size = struct.unpack_from("<I", b, p + 4)[0]
        if size == 0:
            break
        if magic == b"pai1":
            frames, loop = struct.unpack_from("<HB", b, p + 8)
            ntex, nent, entoff = struct.unpack_from("<HHI", b, p + 12)
            out["frames"], out["loop"] = frames, bool(loop)
            for e in range(nent):
                eo = p + struct.unpack_from("<I", b, p + entoff + e * 4)[0]
                name = cstr(b, eo, 20)
                ninfo, kind = b[eo + 20], b[eo + 21]
                for i in range(ninfo):
                    io = eo + struct.unpack_from("<I", b, eo + 24 + i * 4)[0]
                    tag = b[io:io + 4].decode("latin-1")
                    ntgt = b[io + 4]
                    for t in range(ntgt):
                        to = io + struct.unpack_from("<I", b, io + 8 + t * 4)[0]
                        idx, target, curve = b[to], b[to + 1], b[to + 2]
                        nkeys = struct.unpack_from("<H", b, to + 4)[0]
                        koff = struct.unpack_from("<I", b, to + 8)[0]
                        keys = []
                        for k in range(nkeys):
                            kp = to + koff + k * (12 if curve == 2 else 8)
                            if curve == 2:
                                keys.append(struct.unpack_from("<fff", b, kp))
                            else:
                                f, v = struct.unpack_from("<fH", b, kp)
                                keys.append((f, v))
                        if tag == "CLPA":
                            tname = PA[target] if target < len(PA) else target
                        elif tag == "CLVC":
                            tname = VC[target] if target < len(VC) else target
                        else:
                            tname = "%d.%d" % (idx, target)
                        out["tracks"].append({"pane": name, "kind": kind, "tag": tag, "target": tname,
                                              "curve": "hermite" if curve == 2 else "step", "keys": keys})
        p += size
    return out


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    b = open(argv[1], "rb").read()
    if argv[2] == "--darc":
        sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
        import darc
        base = next(o for n, d, o, s in darc.entries(b, b.find(b"darc")) if n == argv[3])
    else:
        base = int(argv[2])
    a = parse(b, base)
    print("frames", a["frames"], "loop", a["loop"])
    for t in a["tracks"]:
        keys = " ".join("%g:%g" % (k[0], round(k[1], 3)) for k in t["keys"])
        print("%-6s %s.%s  %s" % (t["pane"], t["tag"], t["target"], keys))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
