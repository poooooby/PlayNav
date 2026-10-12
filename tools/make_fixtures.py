"""Build tiny synthetic 3DS container fixtures for the Lua decoder tests.

Usage:
  python tools/make_fixtures.py tests/fixtures

Nothing here comes from a ROM. A few hand-made images are encoded as BCLIM in
several formats, LZ11-compressed, packed into a GARC, placed in a RomFS inside
an NCCH inside an NCSD image, and written as fixtures/mini.cci plus the
expected RGBA (as hex) in fixtures/expected.lua. tests/import_fixtures_test.lua
then runs src/import/*.lua over the image and checks every pixel.
"""

from __future__ import annotations

import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bclim  # noqa: E402

MU = 0x200


# ------- images (RGBA tuples per pixel)

def gradient(w, h):
    px = []
    for y in range(h):
        for x in range(w):
            px.append(((x * 255) // max(1, w - 1), (y * 255) // max(1, h - 1), 128, 255 if (x + y) % 3 else 0))
    return px


def stripes(w, h):
    return [((x // 2 % 2) * 255, (y // 2 % 2) * 255, 64, 255) for y in range(h) for x in range(w)]


# ------- BCLIM encoders for the formats the mod relies on

def quant(v, bits):
    return round(v * ((1 << bits) - 1) / 255)


def encode_pixel(fmt, r, g, b, a):
    if fmt == "RGBA8":
        return bytes((a, b, g, r))
    if fmt == "RGB8":
        return bytes((b, g, r))
    if fmt == "RGBA4":
        v = (quant(r, 4) << 12) | (quant(g, 4) << 8) | (quant(b, 4) << 4) | quant(a, 4)
        return struct.pack("<H", v)
    if fmt == "RGBA5551":
        v = (quant(r, 5) << 11) | (quant(g, 5) << 6) | (quant(b, 5) << 1) | (1 if a >= 128 else 0)
        return struct.pack("<H", v)
    if fmt == "RGB565":
        v = (quant(r, 5) << 11) | (quant(g, 6) << 5) | quant(b, 5)
        return struct.pack("<H", v)
    if fmt == "LA8":
        return bytes((a, r))
    if fmt == "L8":
        return bytes((r,))
    if fmt == "A8":
        return bytes((a,))
    if fmt == "LA4":
        return bytes(((quant(r, 4) << 4) | quant(a, 4),))
    raise ValueError(fmt)


FORMAT_CODE = {name: code for code, name in bclim.FORMATS.items()}


def encode_bclim(pixels, w, h, fmt):
    pw, ph = bclim._pow2(w), bclim._pow2(h)
    data = bytearray()
    half = fmt in ("L4", "A4")
    for ty in range(ph // 8):
        for tx in range(pw // 8):
            nib = []
            for i in range(64):
                mx, my = bclim.MORTON[i]
                x, y = tx * 8 + mx, ty * 8 + my
                if x < w and y < h:
                    r, g, b, a = pixels[y * w + x]
                else:
                    r, g, b, a = 0, 0, 0, 0
                if half:
                    nib.append(quant(r if fmt == "L4" else a, 4))
                else:
                    data += encode_pixel(fmt, r, g, b, a)
            if half:
                for k in range(0, 64, 2):
                    data.append(nib[k] | (nib[k + 1] << 4))
    clim = b"CLIM" + struct.pack("<HHIIHH", 0xFEFF, 0x14, 0x02020000, len(data) + 0x28, 1, 0)
    imag = b"imag" + struct.pack("<IHHII", 0x14, w, h, FORMAT_CODE[fmt], len(data))
    return bytes(data) + clim + imag


# ------- LZ11 compressor (greedy, enough to exercise all three match kinds)

def lz11_compress(data: bytes) -> bytes:
    out = bytearray(b"\x11" + struct.pack("<I", len(data))[:3])
    pos = 0
    n = len(data)
    while pos < n:
        flags = 0
        chunk = bytearray()
        for bit in range(8):
            if pos >= n:
                break
            best_len, best_disp = 0, 0
            start = max(0, pos - 4096)
            for cand in range(start, pos):
                length = 0
                while pos + length < n and length < 0x10110 and data[cand + length] == data[pos + length]:
                    length += 1
                if length > best_len:
                    best_len, best_disp = length, pos - cand
            if best_len >= 3:
                flags |= 0x80 >> bit
                d = best_disp - 1
                if best_len <= 0x10:
                    c = best_len - 1
                    chunk += bytes(((c << 4) | (d >> 8), d & 0xFF))
                elif best_len <= 0x110:
                    c = best_len - 0x11
                    chunk += bytes(((c >> 4), ((c & 0xF) << 4) | (d >> 8), d & 0xFF))
                else:
                    c = best_len - 0x111
                    chunk += bytes((0x10 | (c >> 12), (c >> 4) & 0xFF, ((c & 0xF) << 4) | (d >> 8), d & 0xFF))
                pos += best_len
            else:
                chunk.append(data[pos])
                pos += 1
        out.append(flags)
        out += chunk
    return bytes(out)


# ------- GARC (version 4, one sub-entry per entry)

def build_garc(entries: list[bytes]) -> bytes:
    header = bytearray()
    fatb_entries = bytearray()
    fato_offsets = []
    data = bytearray()
    for blob in entries:
        fato_offsets.append(len(fatb_entries))
        start = len(data)
        padded = (len(blob) + 3) & ~3
        data += blob + b"\x00" * (padded - len(blob))
        fatb_entries += struct.pack("<IIII", 1, start, start + padded, len(blob))
    fato = b"OTAF" + struct.pack("<IHH", 12 + 4 * len(entries), len(entries), 0xFFFF) + b"".join(struct.pack("<I", o) for o in fato_offsets)
    fatb = b"BTAF" + struct.pack("<II", 12 + len(fatb_entries), len(entries)) + fatb_entries
    fimb = b"BMIF" + struct.pack("<II", 12, len(data))
    header_size = 0x1C
    data_offset = header_size + len(fato) + len(fatb) + len(fimb)
    header += b"CRAG" + struct.pack("<IHHIII", header_size, 0xFEFF, 0x0400, 4, data_offset, data_offset + len(data))
    header += struct.pack("<I", max(len(e) for e in entries))
    return bytes(header + fato + fatb + fimb + data)


# ------- RomFS level 3 with the tree a/0/4/<n>

def utf16(s):
    return s.encode("utf-16-le")


def build_romfs(files: dict[str, bytes]) -> bytes:
    # directories: root, a, 0, 4 ; files inside "4"
    dir_meta = bytearray()
    file_meta = bytearray()
    data = bytearray()

    def dir_entry(parent, sibling, child, first_file, name):
        nm = utf16(name)
        off = len(dir_meta)
        dir_meta.extend(struct.pack("<IIIIII", parent, sibling, child, first_file, 0xFFFFFFFF, len(nm)))
        dir_meta.extend(nm + b"\x00" * ((4 - len(nm) % 4) % 4))
        return off

    # offsets are known from the fixed names: root(0), "a", "0", "4"
    root = dir_entry(0, 0xFFFFFFFF, 0x18, 0xFFFFFFFF, "")           # child = next entry
    a_off = dir_entry(root, 0xFFFFFFFF, 0, 0xFFFFFFFF, "a")           # placeholders fixed below
    zero_off = dir_entry(a_off, 0xFFFFFFFF, 0, 0xFFFFFFFF, "0")
    four_off = dir_entry(zero_off, 0xFFFFFFFF, 0xFFFFFFFF, 0, "4")  # first file = file 0
    # patch child pointers
    struct.pack_into("<I", dir_meta, a_off + 8, zero_off)
    struct.pack_into("<I", dir_meta, zero_off + 8, four_off)
    names = sorted(files)
    for i, name in enumerate(names):
        blob = files[name]
        nm = utf16(name)
        off = len(data)
        data += blob + b"\x00" * ((16 - len(blob) % 16) % 16)
        sibling = 0xFFFFFFFF
        file_meta_len_before = len(file_meta)
        file_meta.extend(struct.pack("<IIQQII", four_off, sibling, off, len(blob), 0xFFFFFFFF, len(nm)))
        file_meta.extend(nm + b"\x00" * ((4 - len(nm) % 4) % 4))
        if i > 0:
            # previous entry's sibling -> this one
            struct.pack_into("<I", file_meta, prev + 4, file_meta_len_before)
        prev = file_meta_len_before
    dir_hash = struct.pack("<I", 0xFFFFFFFF) * 4
    file_hash = struct.pack("<I", 0xFFFFFFFF) * 4
    hdr_len = 0x28
    dir_hash_off = hdr_len
    dir_meta_off = dir_hash_off + len(dir_hash)
    file_hash_off = dir_meta_off + len(dir_meta)
    file_meta_off = file_hash_off + len(file_hash)
    data_off = (file_meta_off + len(file_meta) + 15) & ~15
    header = struct.pack("<10I", hdr_len, dir_hash_off, len(dir_hash), dir_meta_off, len(dir_meta),
                         file_hash_off, len(file_hash), file_meta_off, len(file_meta), data_off)
    body = bytearray(header + dir_hash + dir_meta + file_hash + file_meta)
    body += b"\x00" * (data_off - len(body))
    body += data
    return bytes(body)


def build_image(romfs_l3: bytes) -> bytes:
    # IVFC header: level 3 at block-aligned offset after 0x60 + master hash (0x20)
    block_log2 = 12
    block = 1 << block_log2
    ivfc = bytearray(0x5C)
    ivfc[0:4] = b"IVFC"
    struct.pack_into("<I", ivfc, 4, 0x10000)
    struct.pack_into("<I", ivfc, 8, 0x20)
    l3_off_in_romfs = ((0x60 + 0x20 + block - 1) // block) * block
    struct.pack_into("<Q", ivfc, 0x3C, 0)
    struct.pack_into("<Q", ivfc, 0x44, len(romfs_l3))
    struct.pack_into("<I", ivfc, 0x4C, block_log2)
    romfs = bytearray(ivfc) + b"\x00" * (l3_off_in_romfs - len(ivfc)) + romfs_l3
    romfs += b"\x00" * ((MU - len(romfs) % MU) % MU)
    # NCCH: header 0x200, romfs right after
    ncch = bytearray(0x200)
    ncch[0x100:0x104] = b"NCCH"
    ncch[0x188:0x190] = bytes((0, 0, 0, 0, 1, 3, 0, 4))      # flags[7] = NoCrypto
    romfs_off_mu = 1
    struct.pack_into("<II", ncch, 0x1B0, romfs_off_mu, len(romfs) // MU)
    ncch += romfs
    # NCSD: header 0x4000, partition 0 at 0x4000
    ncsd = bytearray(0x4000)
    ncsd[0x100:0x104] = b"NCSD"
    struct.pack_into("<II", ncsd, 0x120, 0x4000 // MU, len(ncch) // MU)
    return bytes(ncsd + ncch)


def main(argv):
    out = argv[1] if len(argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tests", "fixtures")
    os.makedirs(out, exist_ok=True)
    images = [
        ("RGBA8", 12, 10, gradient(12, 10)),
        ("RGBA4", 9, 17, stripes(9, 17)),
        ("RGBA5551", 16, 8, gradient(16, 8)),
        ("RGB565", 5, 5, stripes(5, 5)),
        ("LA4", 8, 8, gradient(8, 8)),
        ("L4", 10, 6, gradient(10, 6)),
        ("RGB8", 7, 3, stripes(7, 3)),
    ]
    expected = []
    blobs = []
    for idx, (fmt, w, h, px) in enumerate(images):
        clim = encode_bclim(px, w, h, fmt)
        # decode with the Python reference to get the exact expected bytes (quantised)
        dw, dh, dfmt, rgba = bclim.decode(clim)
        assert (dw, dh, dfmt) == (w, h, fmt)
        expected.append({"entry": idx, "fmt": fmt, "w": w, "h": h, "md5": __import__("hashlib").md5(rgba).hexdigest(),
                         "rgba_hex": rgba.hex()})
        # odd entries compressed, even raw; the 3rd also a two-CLIM pack
        if idx == 2:
            pack = clim + encode_bclim(stripes(4, 4), 4, 4, "RGBA8")
            pdw, pdh, pdf, prgba = bclim.decode(encode_bclim(stripes(4, 4), 4, 4, "RGBA8"))
            expected[-1]["pack_second"] = {"w": 4, "h": 4, "fmt": "RGBA8", "rgba_hex": prgba.hex()}
            blob = lz11_compress(pack)
        else:
            blob = lz11_compress(clim) if idx % 2 else clim
        expected[-1]["compressed"] = bool(idx % 2 or idx == 2)
        blobs.append(blob)
    garc = build_garc(blobs)
    romfs = build_romfs({"1": garc, "2": b"", "3": b"second file"})
    image = build_image(romfs)
    with open(os.path.join(out, "mini.cci"), "wb") as f:
        f.write(image)
    with open(os.path.join(out, "expected.lua"), "w", encoding="utf-8") as f:
        f.write("-- generated by tools/make_fixtures.py from synthetic pixels; not ROM-derived\nreturn {\n")
        f.write("  archive = 'a/0/4/1', imageSize = %d,\n  entries = {\n" % len(image))
        for e in expected:
            f.write("    { entry = %d, fmt = %r, w = %d, h = %d, compressed = %s, md5 = %r, rgba = %r" % (
                e["entry"], e["fmt"], e["w"], e["h"], "true" if e["compressed"] else "false", e["md5"], e["rgba_hex"]))
            if "pack_second" in e:
                p = e["pack_second"]
                f.write(",\n      second = { w = %d, h = %d, fmt = %r, rgba = %r }" % (p["w"], p["h"], p["fmt"], p["rgba_hex"]))
            f.write(" },\n")
        f.write("  },\n}\n")
    print("wrote %s (%d bytes) and expected.lua with %d entries" % (os.path.join(out, "mini.cci"), len(image), len(expected)))
    # self-check with the Python reference chain
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import romfs_extract
    img = romfs_extract.Image(os.path.join(out, "mini.cci"))
    fs = romfs_extract.open_romfs(img)
    paths = {p: (o, l) for p, o, l in romfs_extract.walk(fs)}
    assert "a/0/4/1" in paths and paths["a/0/4/2"][1] == 0, paths
    off, length = paths["a/0/4/1"]
    import garc_dump
    version, data_offset, entries = garc_dump.parse_garc(img.read(off, length))
    assert len(entries) == len(blobs)
    print("python self-check ok: %d entries, romfs paths %s" % (len(entries), sorted(paths)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
