"""Dump every BCLIM found in a Pokemon ORAS RomFS 'a' tree, stdlib only.

Usage:
  python tools/garc_dump.py <romfs_dir> <out_dir> [--only a/0/4/3,a/0/4/2] [--all-entries]

For each GARC under romfs/a/x/y/z: parse the FATO/FATB tables, read every
subfile, LZ10/LZ11-decompress it when it starts with 0x10/0x11 and the size
fits, then look for CLIM trailers both as whole files and embedded inside
containers. Writes <out>/a_x_y_z/<entry>_<sub>[_<n>].bclim and <out>/index.json.

This mirrors what src/import/garc.lua and src/import/lz.lua do inside the
mod, so a mismatch between the two is a bug in one of them.
"""

from __future__ import annotations

import json
import os
import struct
import sys

# Textures are small; anything past these caps is a model or audio pack and is
# only scanned raw (not decompressed) so a full-tree pass stays minutes long.
MAX_DECOMPRESSED = 8 * 1024 * 1024
MAX_COMPRESSED_FOR_LZ = 4 * 1024 * 1024


class GarcError(Exception):
    pass


# ------- LZ10 / LZ11 (Nintendo), same algorithm as src/import/gen5/Lz.lua

def lz_decode(data: bytes, limit: int = MAX_DECOMPRESSED) -> bytes | None:
    if len(data) < 4:
        return None
    kind = data[0]
    if kind not in (0x10, 0x11):
        return None
    size = data[1] | (data[2] << 8) | (data[3] << 16)
    pos = 4
    if size == 0 and kind == 0x11:
        if len(data) < 8:
            return None
        size = struct.unpack_from("<I", data, 4)[0]
        pos = 8
    if size <= 0 or size > limit:
        return None
    out = bytearray()
    n = len(data)
    try:
        while len(out) < size:
            flags = data[pos]
            pos += 1
            for bit in range(8):
                if len(out) >= size:
                    break
                if flags & (0x80 >> bit):
                    b = data[pos]
                    pos += 1
                    if kind == 0x10:
                        b2 = data[pos]
                        pos += 1
                        count = (b >> 4) + 3
                        disp = ((b & 0xF) << 8 | b2) + 1
                    else:
                        indicator = b >> 4
                        if indicator == 0:
                            b2 = data[pos]
                            b3 = data[pos + 1]
                            pos += 2
                            count = ((b & 0xF) << 4 | (b2 >> 4)) + 0x11
                            disp = ((b2 & 0xF) << 8 | b3) + 1
                        elif indicator == 1:
                            b2 = data[pos]
                            b3 = data[pos + 1]
                            b4 = data[pos + 2]
                            pos += 3
                            count = ((b & 0xF) << 12 | b2 << 4 | (b3 >> 4)) + 0x111
                            disp = ((b3 & 0xF) << 8 | b4) + 1
                        else:
                            b2 = data[pos]
                            pos += 1
                            count = indicator + 1
                            disp = ((b & 0xF) << 8 | b2) + 1
                    if disp > len(out):
                        return None
                    start = len(out) - disp
                    for i in range(count):
                        out.append(out[start + i])
                else:
                    out.append(data[pos])
                    pos += 1
            if pos > n:
                return None
    except IndexError:
        return None
    if len(out) != size:
        return None
    return bytes(out)


# ------- GARC

def parse_garc(data: bytes):
    """Return (version, data_offset, entries) where entries = list of list of (start, end, length)."""
    if data[:4] != b"CRAG":
        raise GarcError("not a GARC")
    header_size, bom, version, chunk_count, data_offset, file_size = struct.unpack_from("<IHHIII", data, 4)
    if bom != 0xFEFF:
        raise GarcError("big-endian GARC not supported")
    pos = header_size
    if data[pos:pos + 4] != b"OTAF":
        raise GarcError("FATO missing at 0x%x" % pos)
    fato_size, fato_count, _pad = struct.unpack_from("<IHH", data, pos + 4)
    fato = struct.unpack_from("<%dI" % fato_count, data, pos + 12)
    pos += fato_size
    if data[pos:pos + 4] != b"BTAF":
        raise GarcError("FATB missing at 0x%x" % pos)
    fatb_size, fatb_count = struct.unpack_from("<II", data, pos + 4)
    table = pos + 12
    entries = []
    for off in fato:
        p = table + off
        flags = struct.unpack_from("<I", data, p)[0]
        p += 4
        subs = []
        for j in range(32):
            if flags & (1 << j):
                start, end, length = struct.unpack_from("<III", data, p)
                p += 12
                subs.append((j, start, end, length))
        entries.append(subs)
    pos += fatb_size
    if data[pos:pos + 4] != b"BMIF":
        raise GarcError("FIMB missing at 0x%x" % pos)
    return version, data_offset, entries


# ------- CLIM discovery

def find_clims(blob: bytes):
    """Yield (start, end) byte ranges of every BCLIM inside blob (whole file or embedded)."""
    found = []
    pos = 0
    while True:
        p = blob.find(b"CLIM", pos)
        if p < 0:
            break
        pos = p + 4
        if p + 0x28 > len(blob):
            continue
        bom = struct.unpack_from("<H", blob, p + 4)[0]
        if bom not in (0xFEFF, 0xFFFE):
            continue
        endian = "<" if bom == 0xFEFF else ">"
        file_size = struct.unpack_from(endian + "I", blob, p + 0x0C)[0]
        if blob[p + 0x14:p + 0x18] != b"imag":
            continue
        end = p + 0x28
        start = end - file_size
        if start < 0 or file_size < 0x28:
            continue
        found.append((start, end))
    return found


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    romfs, out = argv[1], argv[2]
    only = None
    all_entries = "--all-entries" in argv
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1].split(","))
    root = os.path.join(romfs, "a")
    index = []
    stats = {"garcs": 0, "subfiles": 0, "lz": 0, "clims": 0, "errors": 0}
    for x in sorted(os.listdir(root)):
        for y in sorted(os.listdir(os.path.join(root, x))):
            dy = os.path.join(root, x, y)
            if not os.path.isdir(dy):
                continue
            for z in sorted(os.listdir(dy)):
                path = os.path.join(dy, z)
                if not os.path.isfile(path):
                    continue
                name = "a/%s/%s/%s" % (x, y, z)
                if only and name not in only:
                    continue
                with open(path, "rb") as f:
                    data = f.read()
                try:
                    version, data_offset, entries = parse_garc(data)
                except GarcError as err:
                    stats["errors"] += 1
                    print("skip %s: %s" % (name, err))
                    continue
                stats["garcs"] += 1
                tag = name.replace("/", "_")
                for ei, subs in enumerate(entries):
                    for (sj, start, end, length) in subs:
                        if length == 0:
                            continue
                        raw = data[data_offset + start:data_offset + start + length]
                        stats["subfiles"] += 1
                        dec = lz_decode(raw) if length <= MAX_COMPRESSED_FOR_LZ else None
                        compressed = dec is not None
                        blob = dec if compressed else raw
                        if compressed:
                            stats["lz"] += 1
                        clims = find_clims(blob)
                        if all_entries and not clims:
                            d = os.path.join(out, tag)
                            os.makedirs(d, exist_ok=True)
                            with open(os.path.join(d, "%04d_%02d.bin" % (ei, sj)), "wb") as f:
                                f.write(blob)
                        for n, (cs, ce) in enumerate(clims):
                            clim = blob[cs:ce]
                            width, height, fmt, _size = struct.unpack_from("<HHII", clim, len(clim) - 0x14 + 8)
                            d = os.path.join(out, tag)
                            os.makedirs(d, exist_ok=True)
                            fname = "%04d_%02d%s.bclim" % (ei, sj, "" if len(clims) == 1 else "_%d" % n)
                            with open(os.path.join(d, fname), "wb") as f:
                                f.write(clim)
                            stats["clims"] += 1
                            index.append({
                                "archive": name, "entry": ei, "sub": sj,
                                "file": "%s/%s" % (tag, fname),
                                "garc_version": version, "data_offset": data_offset,
                                "start": start, "length": length, "compressed": compressed,
                                "blob_size": len(blob), "clim_start": cs, "clim_end": ce,
                                "width": width, "height": height, "format": fmt,
                                "embedded": len(clims) > 1 or cs != 0 or ce != len(blob),
                            })
                if stats["garcs"] % 50 == 0:
                    print("... %d archives, %d clims" % (stats["garcs"], stats["clims"]))
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "index.json"), "w", encoding="utf-8") as f:
        json.dump({"stats": stats, "clims": index}, f, indent=1)
    print(json.dumps(stats))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
