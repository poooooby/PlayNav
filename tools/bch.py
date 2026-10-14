"""List and extract the textures in a 3DS BCH model / effect file, stdlib only.

Usage:
  python tools/bch.py list <garc> [entry]              # every BCH in a GARC: its textures (name, size, format)
  python tools/bch.py extract <garc> <entry> <outdir>  # one entry's textures as PNGs

A BCH (version 0x21 in X / Y / OR / AS) has a main header of (pointer table, count, name tree)
triples per content type; the fourth is the textures. Each texture holds a GPU command list
whose texture-unit registers give its size (0x82), data address (0x85, relative to the data
section) and PICA format (0x8e). Pixels decode with tools/bclim.py's routines (the same
hardware formats, Morton-tiled at power-of-two sizes).
"""

from __future__ import annotations

import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bclim  # noqa: E402
import garc_dump as g  # noqa: E402

PICA_FORMATS = {0: 'RGBA8', 1: 'RGB8', 2: 'RGBA5551', 3: 'RGB565', 4: 'RGBA4', 5: 'LA8', 6: 'HILO8', 7: 'L8',
                8: 'A8', 9: 'LA4', 10: 'L4', 11: 'A4', 12: 'ETC1', 13: 'ETC1A4'}


def u32(b, p):
    return struct.unpack_from('<I', b, p)[0]


def header(b):
    if b[:4] != b'BCH\x00':
        raise ValueError('not a BCH')
    bc = b[4]
    h = {'bc': bc, 'main': u32(b, 8), 'strings': u32(b, 12), 'gpu': u32(b, 16), 'data': u32(b, 20)}
    return h


def cstring(b, p):
    e = b.index(b'\x00', p)
    return b[p:e].decode('ascii', 'replace')


def commands(b, at, words):
    """PICA command list -> {register: [values]}"""
    regs = {}
    i, end = at, at + words * 4
    while i + 8 <= end:
        param, hdr = u32(b, i), u32(b, i + 4)
        reg, extra, consec = hdr & 0xffff, (hdr >> 20) & 0x7ff, hdr >> 31
        vals = [param] + [u32(b, i + 8 + 4 * k) for k in range(extra)]
        for k, v in enumerate(vals):
            regs.setdefault(reg + (k if consec else 0), []).append(v)
        i += 8 + 4 * extra
        if (extra % 2) == 1:
            i += 4
    return regs


def textures(b):
    h = header(b)
    m = h['main']
    table, count = u32(b, m + 0x24), u32(b, m + 0x28)
    out = []
    for k in range(count):
        e = m + u32(b, m + table + k * 4)
        cmd_off, cmd_words = u32(b, e), u32(b, e + 4)
        regs = commands(b, h['gpu'] + cmd_off, cmd_words)
        # the name: the eighth word of the entry, an offset into the string table
        try:
            name = cstring(b, h['strings'] + u32(b, e + 0x1c))
        except (ValueError, IndexError):
            name = None
        dim = regs.get(0x82, [0])[0]
        w, hh = dim >> 16, dim & 0xffff
        addr = regs.get(0x85, [0])[0]
        fmt = regs.get(0x8e, [None])[0]
        out.append({'name': name, 'w': w, 'h': hh, 'addr': addr, 'fmt': PICA_FORMATS.get(fmt, fmt),
                    'data': h['data'] + addr})
    return out


def decode_raw(fmt, width, height, tex):
    out = bytearray(width * height * 4)
    tiles_x, tiles_y = bclim._pow2(width) // 8, bclim._pow2(height) // 8
    if fmt in ('ETC1', 'ETC1A4'):
        bb = 16 if fmt == 'ETC1A4' else 8
        pos = 0
        for ty in range(tiles_y):
            for tx in range(tiles_x):
                for by in range(2):
                    for bx in range(2):
                        alphas = None
                        if fmt == 'ETC1A4':
                            alphas = int.from_bytes(tex[pos:pos + 8], 'little')
                            pos += 8
                        block = int.from_bytes(tex[pos:pos + 8], 'little')
                        pos += 8
                        bclim._etc1_block(block, alphas, out, width, height, tx * 8 + bx * 4, ty * 8 + by * 4)
        return bytes(out)
    bpp = bclim.BYTES_PER_PIXEL.get(fmt)
    half = fmt in ('L4', 'A4')
    pos = 0
    for ty in range(tiles_y):
        for tx in range(tiles_x):
            for i in range(64):
                mx, my = bclim.MORTON[i]
                px, py = tx * 8 + mx, ty * 8 + my
                bpos, nib = (pos + i // 2, i & 1) if half else (pos + i * bpp, 0)
                if px < width and py < height and bpos < len(tex):
                    r, gg, bl, a = bclim.decode_pixel(fmt, tex, bpos, nib)
                    o = (py * width + px) * 4
                    out[o:o + 4] = bytes((r, gg, bl, a))
            pos += 32 if half else 64 * bpp
    return bytes(out)


def garc_bchs(path):
    data = open(path, 'rb').read()
    ver, off, entries = g.parse_garc(data)
    for k, subs in enumerate(entries):
        for j, s, e, l in subs:
            raw = data[off + s: off + e]
            blob = (g.lz_decode(raw) if raw[:1] in (b'\x10', b'\x11') else None) or raw
            if blob[:4] == b'BCH\x00':
                yield k, j, blob


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    if argv[0] == 'list':
        only = int(argv[2]) if len(argv) > 2 else None
        for k, j, b in garc_bchs(argv[1]):
            if only is not None and k != only:
                continue
            try:
                ts = textures(b)
            except Exception as ex:
                print('%3d.%d: %s' % (k, j, ex))
                continue
            if ts:
                print('%3d.%d: %s' % (k, j, '  '.join('%s %dx%d %s' % (t['name'], t['w'], t['h'], t['fmt']) for t in ts)))
        return 0
    if argv[0] == 'extract':
        entry, outdir = int(argv[2]), argv[3]
        os.makedirs(outdir, exist_ok=True)
        for k, j, b in garc_bchs(argv[1]):
            if k != entry:
                continue
            for t in textures(b):
                if not (t['w'] and t['h']) or not isinstance(t['fmt'], str):
                    continue
                rgba = decode_raw(t['fmt'], t['w'], t['h'], b[t['data']:])
                path = os.path.join(outdir, '%d_%s.png' % (k, t['name'] or 'tex'))
                bclim.write_png(path, t['w'], t['h'], rgba)
                print('wrote', path, t['w'], t['h'], t['fmt'])
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
