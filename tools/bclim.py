"""BCLIM (3DS CTR layout image) decoder and a minimal PNG writer, stdlib only.

This is the development reference for the Lua decoder shipped in the mod
(src/import/bclim.lua): both follow the same layout notes, and tools/discover.py
checks this decoder pixel for pixel against bclimtool's output.

Layout (little endian):
  file = [texture data][CLIM header 0x14][imag section 0x14]
  CLIM: magic 'CLIM', BOM u16, header size u16, version u32, file size u32,
        section count u16, pad u16
  imag: magic 'imag', section size u32, width u16, height u16, format u32,
        data size u32
Texture data is 8x8 tiles in row-major tile order; inside a tile the 64 pixels
follow Morton (Z) order. ETC1/ETC1A4 tiles hold four 4x4 blocks (row-major
2x2) of 8 bytes each, ETC1A4 with an 8-byte alpha block before each colour
block.
"""

from __future__ import annotations

import struct
import zlib

FORMATS = {
    0x00: "L8", 0x01: "A8", 0x02: "LA4", 0x03: "LA8", 0x04: "HILO8",
    0x05: "RGB565", 0x06: "RGB8", 0x07: "RGBA5551", 0x08: "RGBA4",
    0x09: "RGBA8", 0x0A: "ETC1", 0x0B: "ETC1A4", 0x0C: "L4", 0x0D: "A4",
}
BYTES_PER_PIXEL = {
    "L8": 1, "A8": 1, "LA4": 1, "LA8": 2, "HILO8": 2, "RGB565": 2, "RGB8": 3,
    "RGBA5551": 2, "RGBA4": 2, "RGBA8": 4,
}

ETC1_MODIFIERS = [
    (2, 8), (5, 17), (9, 29), (13, 42), (18, 60), (24, 80), (33, 106), (47, 183),
]

# Morton order inside an 8x8 tile: index -> (x, y)
MORTON = []
for _i in range(64):
    _x = ((_i & 1) >> 0) | ((_i & 4) >> 1) | ((_i & 16) >> 2)
    _y = ((_i & 2) >> 1) | ((_i & 8) >> 2) | ((_i & 32) >> 3)
    MORTON.append((_x, _y))


class BclimError(Exception):
    pass


def parse_header(data: bytes):
    """Return (width, height, format_name, format_code, data_size)."""
    if len(data) < 0x28:
        raise BclimError("file too small for a CLIM trailer")
    clim = data[-0x28:-0x14]
    imag = data[-0x14:]
    if clim[:4] != b"CLIM" or imag[:4] != b"imag":
        raise BclimError("CLIM/imag magic missing")
    bom = struct.unpack_from("<H", clim, 4)[0]
    if bom not in (0xFEFF, 0xFFFE):
        raise BclimError("bad BOM 0x%04x" % bom)
    endian = "<" if bom == 0xFEFF else ">"
    width, height, fmt, data_size = struct.unpack_from(endian + "HHII", imag, 8)
    name = FORMATS.get(fmt)
    if name is None:
        raise BclimError("unknown format 0x%x" % fmt)
    return width, height, name, fmt, data_size


def _clamp(v):
    return 0 if v < 0 else 255 if v > 255 else v


def _pow2(v: int) -> int:
    p = 8
    while p < v:
        p *= 2
    return p


# bclimtool scales n-bit channels as round(v * 255 / max); 3DS hardware
# replicates bits instead. We follow bclimtool so the two decoders agree
# exactly; the difference is at most one unit per channel.
def _expand5(v):
    return (v * 255 + 15) // 31


def _expand6(v):
    return (v * 255 + 31) // 63


# ETC1 base colours expand by bit replication per the ETC1 specification
def _etc5(v):
    return (v << 3) | (v >> 2)


def _expand4(v):
    return v * 0x11


def decode_pixel(fmt: str, data: bytes, pos: int, nibble: int):
    """Return (r, g, b, a) for one pixel of a non-ETC format."""
    if fmt == "RGBA8":
        a, b, g, r = data[pos], data[pos + 1], data[pos + 2], data[pos + 3]
        return r, g, b, a
    if fmt == "RGB8":
        b, g, r = data[pos], data[pos + 1], data[pos + 2]
        return r, g, b, 255
    if fmt == "RGBA5551":
        v = data[pos] | (data[pos + 1] << 8)
        return (_expand5((v >> 11) & 31), _expand5((v >> 6) & 31),
                _expand5((v >> 1) & 31), 255 if v & 1 else 0)
    if fmt == "RGB565":
        v = data[pos] | (data[pos + 1] << 8)
        return _expand5((v >> 11) & 31), _expand6((v >> 5) & 63), _expand5(v & 31), 255
    if fmt == "RGBA4":
        v = data[pos] | (data[pos + 1] << 8)
        return (_expand4((v >> 12) & 15), _expand4((v >> 8) & 15),
                _expand4((v >> 4) & 15), _expand4(v & 15))
    if fmt == "LA8":
        a, l = data[pos], data[pos + 1]
        return l, l, l, a
    if fmt == "HILO8":
        g, r = data[pos], data[pos + 1]
        return r, g, 255, 255
    if fmt == "L8":
        l = data[pos]
        return l, l, l, 255
    if fmt == "A8":
        return 255, 255, 255, data[pos]
    if fmt == "LA4":
        v = data[pos]
        l = _expand4(v >> 4)
        return l, l, l, _expand4(v & 15)
    if fmt == "L4":
        v = (data[pos] >> (4 * nibble)) & 15
        l = _expand4(v)
        return l, l, l, 255
    if fmt == "A4":
        v = (data[pos] >> (4 * nibble)) & 15
        return 255, 255, 255, _expand4(v)
    raise BclimError("unsupported format " + fmt)


def _etc1_block(block: int, alphas: int | None, out, width, height, bx, by):
    """Decode one 4x4 ETC1 block at pixel origin (bx, by) into out (RGBA bytearray)."""
    diff = (block >> 33) & 1
    flip = (block >> 32) & 1
    table1 = ETC1_MODIFIERS[(block >> 37) & 7]
    table2 = ETC1_MODIFIERS[(block >> 34) & 7]
    if diff:
        r1 = (block >> 59) & 31
        g1 = (block >> 51) & 31
        b1 = (block >> 43) & 31
        dr = (block >> 56) & 7
        dg = (block >> 48) & 7
        db = (block >> 40) & 7
        dr = dr - 8 if dr & 4 else dr
        dg = dg - 8 if dg & 4 else dg
        db = db - 8 if db & 4 else db
        c1 = (_etc5(r1), _etc5(g1), _etc5(b1))
        c2 = (_etc5((r1 + dr) & 31), _etc5((g1 + dg) & 31), _etc5((b1 + db) & 31))
    else:
        c1 = (_expand4((block >> 60) & 15), _expand4((block >> 52) & 15), _expand4((block >> 44) & 15))
        c2 = (_expand4((block >> 56) & 15), _expand4((block >> 48) & 15), _expand4((block >> 40) & 15))
    for x in range(4):
        for y in range(4):
            p = x * 4 + y
            lsb = (block >> p) & 1
            msb = (block >> (16 + p)) & 1
            idx = (msb << 1) | lsb
            first = (y < 2) if flip else (x < 2)
            base = c1 if first else c2
            table = table1 if first else table2
            mod = table[1] if idx & 1 else table[0]
            if idx & 2:
                mod = -mod
            px, py = bx + x, by + y
            if px >= width or py >= height:
                continue
            a = 255
            if alphas is not None:
                a = _expand4((alphas >> (p * 4)) & 15)
            o = (py * width + px) * 4
            out[o] = _clamp(base[0] + mod)
            out[o + 1] = _clamp(base[1] + mod)
            out[o + 2] = _clamp(base[2] + mod)
            out[o + 3] = a


def decode(data: bytes):
    """Decode a BCLIM file. Returns (width, height, format_name, rgba bytes)."""
    width, height, fmt, _code, data_size = parse_header(data)
    tex = data[:data_size]
    out = bytearray(width * height * 4)
    # texture memory is laid out at power-of-two dimensions; the header holds the visible size
    tiles_x = _pow2(width) // 8
    tiles_y = _pow2(height) // 8
    if fmt in ("ETC1", "ETC1A4"):
        block_bytes = 16 if fmt == "ETC1A4" else 8
        pos = 0
        for ty in range(tiles_y):
            for tx in range(tiles_x):
                for by in range(2):
                    for bx in range(2):
                        if pos + block_bytes > len(tex):
                            raise BclimError("texture data truncated")
                        alphas = None
                        if fmt == "ETC1A4":
                            alphas = int.from_bytes(tex[pos:pos + 8], "little")
                            pos += 8
                        block = int.from_bytes(tex[pos:pos + 8], "little")
                        pos += 8
                        _etc1_block(block, alphas, out, width, height,
                                    tx * 8 + bx * 4, ty * 8 + by * 4)
        return width, height, fmt, bytes(out)

    bpp = BYTES_PER_PIXEL.get(fmt)
    half = fmt in ("L4", "A4")
    pos = 0
    for ty in range(tiles_y):
        for tx in range(tiles_x):
            for i in range(64):
                mx, my = MORTON[i]
                px, py = tx * 8 + mx, ty * 8 + my
                if half:
                    bpos, nibble = pos + i // 2, i & 1
                else:
                    bpos, nibble = pos + i * bpp, 0
                if px < width and py < height:
                    if bpos >= len(tex):
                        raise BclimError("texture data truncated")
                    r, g, b, a = decode_pixel(fmt, tex, bpos, nibble)
                    o = (py * width + px) * 4
                    out[o] = r
                    out[o + 1] = g
                    out[o + 2] = b
                    out[o + 3] = a
            pos += 32 if half else 64 * bpp
    return width, height, fmt, bytes(out)


def write_png(path: str, width: int, height: int, rgba: bytes) -> None:
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(kind: bytes, body: bytes) -> bytes:
        return (struct.pack(">I", len(body)) + kind + body
                + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def read_png_rgba(path: str):
    """Minimal PNG reader for comparing against bclimtool output (8-bit RGBA/RGB, non-interlaced)."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise BclimError("not a PNG: " + path)
    pos = 8
    width = height = None
    depth = ctype = interlace = None
    idat = bytearray()
    palette = None
    trns = None
    while pos < len(data):
        length, kind = struct.unpack_from(">I4s", data, pos)
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, ctype, _c, _f, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"PLTE":
            palette = body
        elif kind == b"tRNS":
            trns = body
        elif kind == b"IEND":
            break
    if depth != 8 or interlace != 0:
        raise BclimError("unsupported PNG (depth %s, interlace %s)" % (depth, interlace))
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out = bytearray(width * height * 4)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        ftype = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if ftype == 1:
                line[i] = (line[i] + a) & 255
            elif ftype == 2:
                line[i] = (line[i] + b) & 255
            elif ftype == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif ftype == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if pa <= pb and pa <= pc else b if pb <= pc else c
                line[i] = (line[i] + pred) & 255
        for x in range(width):
            o = (y * width + x) * 4
            if ctype == 6:
                out[o:o + 4] = line[x * 4:x * 4 + 4]
            elif ctype == 2:
                out[o:o + 3] = line[x * 3:x * 3 + 3]
                out[o + 3] = 255
            elif ctype == 4:
                l, a2 = line[x * 2], line[x * 2 + 1]
                out[o:o + 4] = bytes((l, l, l, a2))
            elif ctype == 0:
                l = line[x]
                out[o:o + 4] = bytes((l, l, l, 255))
            elif ctype == 3:
                idx = line[x]
                out[o:o + 3] = palette[idx * 3:idx * 3 + 3]
                out[o + 3] = trns[idx] if trns and idx < len(trns) else 255
        prev = line
    return width, height, bytes(out)


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 3:
        print("usage: bclim.py <in.bclim> <out.png>")
        sys.exit(2)
    with open(sys.argv[1], "rb") as fh:
        w, h, name, px = decode(fh.read())
    write_png(sys.argv[2], w, h, px)
    print("%s: %dx%d %s" % (sys.argv[1], w, h, name))
