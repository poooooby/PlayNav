"""Super Training evidence pass: look for the regimen course table in the Alpha Sapphire
RomFS. Every GARC under romfs/a is parsed, every subfile LZ10/LZ11-decompressed when it
starts that way, and the result scanned for runs of the known course scores (Lv1 500/300/400/
300/200/200, Lv2 2500/1500/1500/1500/1000/1000, Lv3 4000/2500/2500/2500/2000/2000) as
little-endian u16 and u32, plus the target times in seconds (150/120/90) and frames.
Read-only; prints candidate archive/entry/sub offsets. Reuses garc_dump's parsers.

    python tools/st_evidence.py <work>/romfs [--only a/0/2/8,a/1/1/4] [--dump <out_dir>]

With --dump the decompressed subfiles of the archives named by --only are written out for
inspection (<out_dir>/a_X_Y_Z/<entry>_<sub>.bin).
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from garc_dump import lz_decode, parse_garc, GarcError  # noqa: E402

LV1 = [500, 300, 400, 300, 200, 200]
LV2 = [2500, 1500, 1500, 1500, 1000, 1000]
LV3 = [4000, 2500, 2500, 2500, 2000, 2000]
SECRET = [1800, 4000, 4800, 5600, 1200, 2400, 3600, 7200, 1600, 3200]
SETS = {"lv1": LV1, "lv2": LV2, "lv3": LV3, "secret": SECRET}


def clusters(blob: bytes, vals, fmt: str, window: int = 256):
    """Offsets where every distinct value of `vals` occurs within `window` bytes."""
    need = set(vals)
    pos = []
    for v in need:
        pat = struct.pack(fmt, v)
        i = blob.find(pat)
        n = 0
        while i != -1 and n < 20000:
            pos.append((i, v))
            n += 1
            i = blob.find(pat, i + 1)
    pos.sort()
    out = []
    for idx, (p, v) in enumerate(pos):
        seen = set()
        for q, x in pos[idx:]:
            if q - p > window:
                break
            seen.add(x)
        if seen >= need:
            out.append(p)
            if len(out) >= 4:
                break
    return out


def subfiles(path: str):
    data = open(path, "rb").read()
    try:
        _version, data_offset, entries = parse_garc(data)
    except GarcError:
        return
    for ei, subs in enumerate(entries):
        for (sub, start, end, length) in subs:
            raw = data[data_offset + start: data_offset + start + length]
            if not raw:
                continue
            dec = lz_decode(raw) if raw[0] in (0x10, 0x11) else None
            yield ei, sub, raw, dec


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    root = argv[1]
    only = None
    dump = None
    i = 2
    while i < len(argv):
        if argv[i] == "--only":
            only = set(argv[i + 1].split(","))
            i += 2
        elif argv[i] == "--dump":
            dump = argv[i + 1]
            i += 2
        else:
            i += 1
    arch_root = os.path.join(root, "a")
    hits = 0
    scanned = 0
    for a in sorted(os.listdir(arch_root)):
        for b in sorted(os.listdir(os.path.join(arch_root, a))):
            for c in sorted(os.listdir(os.path.join(arch_root, a, b))):
                name = "a/%s/%s/%s" % (a, b, c)
                if only and name not in only:
                    continue
                path = os.path.join(arch_root, a, b, c)
                for ei, sub, raw, dec in subfiles(path):
                    blob = dec or raw
                    scanned += 1
                    if dump:
                        d = os.path.join(dump, name.replace("/", "_"))
                        os.makedirs(d, exist_ok=True)
                        with open(os.path.join(d, "%04d_%02d%s.bin" % (ei, sub, "_lz" if dec else "")), "wb") as f:
                            f.write(blob)
                    for tag, vals in SETS.items():
                        for fmt in ("<H", "<I"):
                            cl = clusters(blob, vals, fmt)
                            if cl:
                                hits += 1
                                print("%s entry %d sub %d %s %s %s size %d%s" % (
                                    name, ei, sub, tag, fmt, [hex(x) for x in cl], len(blob),
                                    " (lz)" if dec else ""))
                                sys.stdout.flush()
    print("scanned %d subfiles, %d hits" % (scanned, hits))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
