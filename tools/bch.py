"""List and extract the textures in a 3DS BCH model / effect file, stdlib only.

Usage:
  python tools/bch.py list <garc> [entry] [--deep]              # every BCH in a GARC: its textures (name, size, format)
  python tools/bch.py extract <garc> <entry> <outdir> [--deep]  # one entry's textures as PNGs
  python tools/bch.py find <romfs-dir> <regex>                  # textures named like regex, in every GARC (deep)
  python tools/bch.py model <garc> <entry> <outdir>             # the entry's model (BCH or CGFX): OBJ + MTL, the file, a Lua reference

--deep also opens LZ entries and Game Freak's packages ('PC', 'GR', 'MM', 'AD' ...: a two-letter
tag, a u16 count, count + 1 u32 offsets) and the packages inside them, where most of the 3D
scenery lives; a sub entry is then printed as its path through them ('0/3/1').

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


def cgfx_textures(b):
    """the image textures in a CGFX (NintendoWare 3D scene; Amie's Tile Puzzle stages a/0/1/8
    entries 3-8): every 'TXOB' holding pixels (a material's references hold none). After the
    magic: name (self-relative) +8, height / width +20 / +24, format +48, the image +52
    (self-relative): height, width, size, data (self-relative at +12). Twin of bch.lua."""
    out, seen, p = [], set(), 0
    while True:
        o = b.find(b'TXOB', p)
        if o < 0:
            return out
        p = o + 4
        if o + 68 > len(b):
            continue
        hh, w = u32(b, o + 20), u32(b, o + 24)
        fmt = PICA_FORMATS.get(u32(b, o + 48))
        ip = o + 52 + struct.unpack_from('<i', b, o + 52)[0]
        if not fmt or not (8 <= w <= 2048 and 8 <= hh <= 2048) or ip <= o or ip + 16 > len(b):
            continue
        if (u32(b, ip), u32(b, ip + 4)) != (hh, w):
            continue
        try:
            name = cstring(b, o + 8 + struct.unpack_from('<i', b, o + 8)[0])
        except (ValueError, IndexError):
            continue
        if name in seen:
            continue
        seen.add(name)
        out.append({'name': name, 'w': w, 'h': hh, 'addr': None, 'fmt': fmt,
                    'data': ip + 12 + struct.unpack_from('<i', b, ip + 12)[0]})


def textures(b):
    if b[:4] == b'CGFX':
        return cgfx_textures(b)
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


def package(b):
    """Game Freak's package (X / Y / OR / AS: 'PC' Pokemon, 'GR' field, 'MM', 'AD', 'PT' ...):
    a two-letter tag, a u16 count, then count + 1 u32 offsets (the last is the end) -> the
    files, or None when b is not one"""
    if len(b) < 8 or not (65 <= b[0] <= 90 and 65 <= b[1] <= 90):
        return None
    n = struct.unpack_from('<H', b, 2)[0]
    if n == 0 or n > 4096 or 4 + 4 * (n + 1) > len(b):
        return None
    offs = [u32(b, 4 + 4 * i) for i in range(n + 1)]
    if offs[0] < 4 + 4 * (n + 1) or any(offs[i] > offs[i + 1] for i in range(n)) or offs[-1] > len(b):
        return None
    return [b[offs[i]:offs[i + 1]] for i in range(n)]


def unwrap(b):
    """an LZ entry's contents (LZ10 / LZ11), else b"""
    if b[:1] in (b'\x10', b'\x11') and len(b) > 4:
        try:
            d = g.lz_decode(b)
            if d:
                return d
        except Exception:
            pass
    return b


def walk(b, path, depth=0):
    """every BCH inside b, opening LZ and packages on the way: (path, bch)"""
    b = unwrap(b)
    if b[:4] in (b'BCH\x00', b'CGFX'):
        yield path, b
        return
    if depth > 6:
        return
    files = package(b)
    if files:
        for i, f in enumerate(files):
            if f:
                yield from walk(f, '%s/%d' % (path, i), depth + 1)


def garc_bchs(path, deep=False):
    """every BCH in a GARC: (entry, sub, bch) - with deep, also those inside packages
    (sub then names the path through them, as 'j/i/...')"""
    data = open(path, 'rb').read()
    ver, off, entries = g.parse_garc(data)
    for k, subs in enumerate(entries):
        for j, s, e, l in subs:
            raw = data[off + s: off + e]
            if not deep:
                blob = unwrap(raw)
                if blob[:4] in (b'BCH\x00', b'CGFX'):
                    yield k, j, blob
                continue
            for p, blob in walk(raw, str(j)):
                yield k, p, blob


def f32(b, p):
    return struct.unpack_from('<f', b, p)[0]


def f24(v):
    """a PICA float24 (sign 1, exponent 7 biased 63, mantissa 16) -> float"""
    if v & 0x7fffff == 0:
        return 0.0
    sign = -1.0 if v & 0x800000 else 1.0
    e = (v >> 16) & 0x7f
    m = v & 0xffff
    return sign * (1 + m / 65536.0) * 2.0 ** (e - 63)


# the vertex shader inputs' meanings, by input register (PICAAttributeName): what 0x2bb / 0x2bc
# map each loaded attribute to
ATTR_NAMES = ['pos', 'normal', 'tangent', 'color', 'uv0', 'uv1', 'uv2', 'bone', 'weight']
ATTR_TYPES = {0: ('b', 1), 1: ('B', 1), 2: ('h', 2), 3: ('f', 4)}   # s8, u8, s16, f32


def invert34(m):
    """the inverse of an affine 3x4 (rows r0, r1, r2: [a b c tx]) -> 3x4"""
    a, b, c, tx = m[0]
    d, e, f, ty = m[1]
    g_, h, i, tz = m[2]
    det = a * (e * i - f * h) - b * (d * i - f * g_) + c * (d * h - e * g_)
    if abs(det) < 1e-12:
        return [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0]]
    inv = [[(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
           [(f * g_ - d * i) / det, (a * i - c * g_) / det, (c * d - a * f) / det],
           [(d * h - e * g_) / det, (b * g_ - a * h) / det, (a * e - b * d) / det]]
    out = []
    for r in range(3):
        row = inv[r]
        out.append([row[0], row[1], row[2], -(row[0] * tx + row[1] * ty + row[2] * tz)])
    return out


def apply34(m, x, y, z):
    return (m[0][0] * x + m[0][1] * y + m[0][2] * z + m[0][3],
            m[1][0] * x + m[1][1] * y + m[1][2] * z + m[1][3],
            m[2][0] * x + m[2][1] * y + m[2][2] * z + m[2][3])


def model(b, index=0):
    """A BCH model's meshes in model space (twin of src/import/bch.lua M.model): per mesh its
    material's texture, render priority, positions (each vertex moved by its bone's bind pose -
    the inverse of the bone's stored inverse bind matrix; a skinned vertex by its first bone),
    UVs and triangle indices. Offsets (BCH 0x21, as SPICA's H3D reads them): model table main
    +0x00 / count +0x04; a model: materials +0x34 / +0x38 (0x2c each), meshes +0x40 / +0x44
    (0x38 each), bones +0x70 / +0x74 (0x64 each), name +0x84; a mesh: material u16 +0, node u16
    +4, priority u16 +6, attribute commands +8 / +0xc (gpu-relative), sub meshes +0x10 / +0x14
    (0x34 each: bone count u16 +2, bone indices u16 x 20 +4, commands +0x2c / +0x30); a bone:
    parent s16 +4, the inverse bind 3x4 +0x2c, name +0x5c; a material: texture 0 name +0x1c.
    A sub mesh's first byte is its skinning: smooth (2) vertices are in model space (the bind
    pose leaves them be), rigid (1) ones in their bone's (moved by its bind pose); the stadium's
    flags are rigid and posed only by its animation (e74)."""
    h = header(b)
    m = h['main']
    strs = h['strings']
    gpu, data = h['gpu'], h['data']

    def name_at(off):
        try:
            return cstring(b, strs + off)
        except (ValueError, IndexError):
            return None

    mdl = m + u32(b, m + u32(b, m + 0x00) + 4 * index)
    out = {'name': name_at(u32(b, mdl + 0x84)), 'materials': [], 'bones': [], 'meshes': []}
    mat_tab, mat_n = u32(b, mdl + 0x34), u32(b, mdl + 0x38)
    for k in range(mat_n):
        e = m + mat_tab + k * 0x2c
        out['materials'].append({'name': name_at(u32(b, e + 0x28)), 'texture': name_at(u32(b, e + 0x1c))})
    bone_tab, bone_n = u32(b, mdl + 0x70), u32(b, mdl + 0x74)
    worlds = []
    for k in range(bone_n):
        e = m + bone_tab + k * 0x64
        parent = struct.unpack_from('<h', b, e + 4)[0]
        inv = [[f32(b, e + 0x2c + 4 * (r * 4 + c)) for c in range(4)] for r in range(3)]
        world = invert34(inv)
        worlds.append(world)
        out['bones'].append({'name': name_at(u32(b, e + 0x5c)), 'parent': parent, 'world': world})
    mesh_tab, mesh_n = u32(b, mdl + 0x40), u32(b, mdl + 0x44)
    # every mesh's vertex buffer start (data-relative), and the first index buffer's: a buffer
    # runs to the next start, so a mesh's vertex count is its span over its stride - more than
    # 256 vertices take u16 indices, whether or not 0x227's bit 31 says so (the stadium's
    # spa_stadium00 mesh: 1516 vertices, its indices u16, the bit clear)
    starts, first_ib = [], None
    for k in range(mesh_n):
        e = m + mesh_tab + k * 0x38
        r = commands(b, gpu + u32(b, e + 8), u32(b, e + 0xc))
        starts.append(r.get(0x203, [0])[0])
        sub_tab, sub_n = u32(b, e + 0x10), u32(b, e + 0x14)
        for s in range(sub_n):
            se = m + sub_tab + s * 0x34
            sr = commands(b, gpu + u32(b, se + 0x2c), u32(b, se + 0x30))
            for a in sr.get(0x227, []):
                a &= 0x7fffffff
                first_ib = a if first_ib is None else min(first_ib, a)
    bounds = sorted(set(starts + ([first_ib] if first_ib is not None else [])))

    def span_end(start):
        later = [x for x in bounds if x > start]
        return later[0] if later else len(b) - data

    for k in range(mesh_n):
        e = m + mesh_tab + k * 0x38
        mat = struct.unpack_from('<H', b, e)[0]
        prio = struct.unpack_from('<H', b, e + 6)[0]
        regs = commands(b, gpu + u32(b, e + 8), u32(b, e + 0xc))
        fmt_lo = regs.get(0x201, [0])[0]
        r202 = regs.get(0x202, [0])[0]
        n_attr = (r202 >> 28) + 1
        fixed_mask = (r202 >> 16) & 0xfff
        fmts = []
        for a in range(12):
            nib = (fmt_lo >> (4 * a)) & 0xf if a < 8 else (r202 >> (4 * (a - 8))) & 0xf
            fmts.append((nib & 3, (nib >> 2) + 1))
        # which input register (meaning) each attribute index feeds
        perm = regs.get(0x2bb, [0])[0] | (regs.get(0x2bc, [0])[0] << 32)
        meaning = [ATTR_NAMES[(perm >> (4 * a)) & 0xf] if ((perm >> (4 * a)) & 0xf) < len(ATTR_NAMES) else 'user'
                   for a in range(12)]
        # buffer 0: offset (data-relative), its attributes in order, its stride
        boff = regs.get(0x203, [0])[0]
        order = regs.get(0x204, [0])[0] | ((regs.get(0x205, [0])[0] & 0xffff) << 32)
        r205 = regs.get(0x205, [0])[0]
        stride, count = (r205 >> 16) & 0xff, r205 >> 28
        layout, at = [], 0
        for slot in range(count):
            a = (order >> (4 * slot)) & 0xf
            if a >= 12:
                # padding: 4 / 8 / 12 / 16 bytes
                at += 4 * (a - 11)
                continue
            t, n = fmts[a]
            ch, size = ATTR_TYPES[t]
            align = size
            at = (at + align - 1) // align * align
            layout.append((meaning[a], a, ch, size, n, at))
            at += size * n
        subs, tris, used = [], [], set()
        skin = 0
        vcount = (span_end(boff) - boff) // stride if stride else 0
        sub_tab, sub_n = u32(b, e + 0x10), u32(b, e + 0x14)
        for s in range(sub_n):
            se = m + sub_tab + s * 0x34
            # skinning: 0 none, 1 rigid (vertices in their bone's space), 2 smooth (model space)
            skin = max(skin, b[se])
            nb = struct.unpack_from('<H', b, se + 2)[0]
            bones_ = [struct.unpack_from('<H', b, se + 4 + 2 * i)[0] for i in range(min(nb, 20))]
            sregs = commands(b, gpu + u32(b, se + 0x2c), u32(b, se + 0x30))
            idx = []
            for addr, cnt in zip(sregs.get(0x227, []), sregs.get(0x228, [])):
                wide = (addr >> 31) or vcount > 256
                base = data + (addr & 0x7fffffff)
                for i in range(cnt):
                    v = struct.unpack_from('<H', b, base + 2 * i)[0] if wide else b[base + i]
                    idx.append(v)
            for v in idx:
                used.add(v)
            subs.append({'bones': bones_, 'idx': idx})
            tris.extend(idx)
        nverts = (max(used) + 1) if used else 0
        # each vertex's bone: the sub mesh's bone list through the vertex's first bone index
        vbone = [None] * nverts
        for sm in subs:
            for v in sm['idx']:
                if vbone[v] is None:
                    vbone[v] = sm['bones']
        pos, uv, col = [], [], []
        for v in range(nverts):
            vals = {}
            for (mean, a, ch, size, n, off) in layout:
                p = data + boff + v * stride + off
                vals[mean] = struct.unpack_from('<' + ch * n, b, p)
            x, y, z = vals.get('pos', (0, 0, 0))[:3]
            bl = vbone[v] or [0]
            bi = vals['bone'][0] if 'bone' in vals else 0
            bone = bl[bi] if bi < len(bl) else (bl[0] if bl else 0)
            if skin == 1 and bone < len(worlds):
                x, y, z = apply34(worlds[bone], x, y, z)
            pos.append((x, y, z))
            u, w = vals.get('uv0', (0, 0))[:2]
            uv.append((u, w))
            cl = [l for l in layout if l[0] == 'color' and l[2] == 'B']
            if cl:
                c = vals['color']
                col.append((c[0] / 255, c[1] / 255, c[2] / 255, (c[3] if len(c) > 3 else 255) / 255))
        out['meshes'].append({'material': mat, 'texture': out['materials'][mat]['texture'] if mat < mat_n else None,
                              'priority': prio, 'pos': pos, 'uv': uv, 'col': col or None, 'idx': tris, 'skin': skin,
                              'layout': [(l[0], l[2], l[4]) for l in layout], 'stride': stride,
                              'fixed': fixed_mask, 'attrs': n_attr})
    return out


# ------- CGFX models (NintendoWare: Amie PLAY's stage, a/1/0/1 entry 0): twin of
# src/import/bch.lua M.cgfxModel; the layouts are documented there

def s32(b, p):
    return struct.unpack_from('<i', b, p)[0]


def cgfx_dict(b, p):
    """a DICT at p -> [(name, object)]"""
    if b[p:p + 4] != b'DICT':
        return []
    out = []
    for i in range(u32(b, p + 8)):
        e = p + 0x1c + i * 16
        out.append((cstring(b, e + 8 + s32(b, e + 8)), e + 12 + s32(b, e + 12)))
    return out


def cgfx_list(b, p):
    """a count at p and a self-relative pointer to self-relative pointers -> objects"""
    n = u32(b, p)
    if n == 0:
        return []
    t = p + 4 + s32(b, p + 4)
    return [t + 4 * i + s32(b, t + 4 * i) for i in range(n)]


def cgfx_data(b, kind):
    d = struct.unpack_from('<H', b, 6)[0]
    if b[d:d + 4] != b'DATA' or u32(b, d + 8 + 8 * kind) == 0:
        return []
    q = d + 12 + 8 * kind
    return cgfx_dict(b, q + s32(b, q))


CGFX_GL = {0x1400: ('b', 1), 0x1401: ('B', 1), 0x1402: ('h', 2), 0x1403: ('H', 2), 0x1406: ('f', 4)}
CGFX_USE = {0: 'pos', 1: 'normal', 2: 'tangent', 3: 'color', 4: 'uv0'}


def cgfx_model(b):
    """a CGFX file's first model, the same shape as model()'s meshes (texture, priority = the
    material's layer, skin 0, pos, uv, col, idx); materials by name"""
    (mname, cm) = cgfx_data(b, 0)[0]
    tex_names = set(n for n, _ in cgfx_data(b, 1))
    mats = cgfx_dict(b, cm + 0xc0 + s32(b, cm + 0xc0)) if u32(b, cm + 0xbc) else []
    mat_tex, mat_layer = {}, {}
    for i, (n, a) in enumerate(mats):
        mat_layer[i] = u32(b, a + 0x20)
        for p in range(a, min(a + 0x800, len(b) - 4), 4):
            t = p + s32(b, p)
            if 0 <= t < len(b):
                name = cstring(b, t)
                if name in tex_names:
                    mat_tex[i] = name
                    break
    shapes = cgfx_list(b, cm + 0xc4)
    out = {'name': mname, 'materials': [{'name': n, 'texture': mat_tex.get(i)} for i, (n, _) in enumerate(mats)],
           'meshes': []}
    for me in cgfx_list(b, cm + 0xb4):
        sh = shapes[u32(b, me + 0x18)]
        mi = u32(b, me + 0x1c)
        off = struct.unpack_from('<3f', b, sh + 0x20)
        pos, uv, col = [], [], []
        for vb in cgfx_list(b, sh + 0x38):
            if u32(b, vb) != 0x40000002:
                continue
            length, raw, stride = u32(b, vb + 0x14), vb + 0x18 + s32(b, vb + 0x18), u32(b, vb + 0x24)
            attrs = []
            for a in cgfx_list(b, vb + 0x28):
                use = CGFX_USE.get(u32(b, a + 4))
                ch, _ = CGFX_GL.get(u32(b, a + 0x24), ('B', 1))
                attrs.append((use, ch, u32(b, a + 0x28), struct.unpack_from('<f', b, a + 0x2c)[0], u32(b, a + 0x30)))
            for v in range(length // stride):
                x = y = z = u = w = 0.0
                c = None
                for use, ch, n, k, ao in attrs:
                    if not use:
                        continue
                    vals = struct.unpack_from('<' + ch * n, b, raw + v * stride + ao)
                    if use == 'pos':
                        x, y, z = vals[0] * k, vals[1] * k, vals[2] * k
                    elif use == 'uv0':
                        u, w = vals[0] * k, vals[1] * k
                    elif use == 'color':
                        c = (vals[0] * k, vals[1] * k, vals[2] * k, vals[3] * k if n >= 4 else 1.0)
                pos.append((x + off[0], y + off[1], z + off[2]))
                uv.append((u, w))
                if c:
                    col.append(c)
        idx = []
        for sm in cgfx_list(b, sh + 0x2c):
            for face in cgfx_list(b, sm + 0xc):
                for fd in cgfx_list(b, face):
                    size, raw = u32(b, fd + 8), fd + 0xc + s32(b, fd + 0xc)
                    if u32(b, fd) == 0x1403:
                        idx.extend(struct.unpack_from('<%dH' % (size // 2), b, raw))
                    else:
                        idx.extend(b[raw:raw + size])
        out['meshes'].append({'material': mi, 'texture': mat_tex.get(mi), 'priority': mat_layer.get(mi, 0),
                              'pos': pos, 'uv': uv, 'col': col or None, 'idx': idx, 'skin': 0})
    return out


def write_obj(mdl, path):
    """the model as an OBJ + MTL to look at (textures by name, PNGs beside it)"""
    base = os.path.splitext(path)[0]
    with open(base + '.mtl', 'w') as f:
        for mat in mdl['materials']:
            f.write('newmtl %s\nKd 1 1 1\nmap_Kd %s.png\n\n' % (mat['name'], mat['texture']))
    with open(path, 'w') as f:
        f.write('mtllib %s.mtl\n' % os.path.basename(base))
        vi = 1
        for k, mesh in enumerate(mdl['meshes']):
            f.write('o mesh%d_%s\nusemtl %s\n' % (k, mesh['texture'], mdl['materials'][mesh['material']]['name']))
            for (x, y, z) in mesh['pos']:
                f.write('v %.4f %.4f %.4f\n' % (x, y, z))
            for (u, w) in mesh['uv']:
                f.write('vt %.5f %.5f\n' % (u, w))
            idx = mesh['idx']
            for i in range(0, len(idx) - 2, 3):
                a, b2, c = idx[i] + vi, idx[i + 1] + vi, idx[i + 2] + vi
                f.write('f %d/%d %d/%d %d/%d\n' % (a, a, b2, b2, c, c))
            vi += len(mesh['pos'])


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    deep = '--deep' in argv
    argv = [a for a in argv if a != '--deep']
    if argv[0] == 'list':
        only = int(argv[2]) if len(argv) > 2 else None
        for k, j, b in garc_bchs(argv[1], deep):
            if only is not None and k != only:
                continue
            try:
                ts = textures(b)
            except Exception as ex:
                print('%3d.%s: %s' % (k, j, ex))
                continue
            if ts:
                print('%3d.%s: %s' % (k, j, '  '.join('%s %dx%d %s' % (t['name'], t['w'], t['h'], t['fmt']) for t in ts)))
        return 0
    if argv[0] == 'find':
        # every texture whose name matches, in every GARC under a folder (always deep)
        import re
        root, pat = argv[1], re.compile(argv[2], re.I)
        for dirpath, _, files in os.walk(root):
            for fn in sorted(files):
                p = os.path.join(dirpath, fn)
                try:
                    with open(p, 'rb') as fh:
                        if fh.read(4) != b'CRAG':
                            continue
                    for k, j, b in garc_bchs(p, True):
                        try:
                            ts = textures(b)
                        except Exception:
                            continue
                        hits = [t for t in ts if t['name'] and pat.search(t['name'])]
                        if hits:
                            rel = os.path.relpath(p, root).replace(os.sep, '/')
                            print('%s %d.%s: %s' % (rel, k, j, '  '.join('%s %dx%d %s' % (t['name'], t['w'], t['h'], t['fmt']) for t in hits)))
                except Exception as ex:
                    print('%s: %s' % (p, ex), file=sys.stderr)
        return 0
    if argv[0] == 'model':
        # python tools/bch.py model <garc> <entry> <outdir>: the entry's first model as an OBJ to
        # look at, its unpacked BCH and a Lua reference for tests/bch_model_test.lua
        entry, outdir = int(argv[2]), argv[3]
        os.makedirs(outdir, exist_ok=True)
        for k, j, b in garc_bchs(argv[1]):
            if k != entry or b[:4] not in (b'BCH\x00', b'CGFX'):
                continue
            bch = b[:4] == b'BCH\x00'
            mdl = model(b) if bch else cgfx_model(b)
            stem = os.path.join(outdir, 'e%d' % entry)
            open(stem + ('.bch' if bch else '.cgfx'), 'wb').write(b)
            write_obj(mdl, stem + '_model.obj')
            with open(stem + '_model.lua', 'w') as f:
                f.write('return { name = "%s", meshes = {\n' % mdl['name'])
                for me in mdl['meshes']:
                    sx = sum(x for x, _, _ in me['pos']); sy = sum(y for _, y, _ in me['pos']); sz = sum(z for _, _, z in me['pos'])
                    su = sum(u for u, _ in me['uv']); sv = sum(v for _, v in me['uv'])
                    sc = sum(sum(c) for c in me['col']) if me['col'] else 0
                    f.write('  { texture = "%s", priority = %d, skin = %d, verts = %d, tris = %d, sum = { %.4f, %.4f, %.4f, %.5f, %.5f, %.4f }, idx = %d },\n'
                            % (me['texture'], me['priority'], me['skin'], len(me['pos']), len(me['idx']) // 3, sx, sy, sz, su, sv, sc, sum(me['idx'])))
                f.write('} }\n')
            print('%s: %d meshes -> %s' % (mdl['name'], len(mdl['meshes']), stem))
            return 0
        print('no BCH / CGFX model in entry', entry)
        return 1
    if argv[0] == 'extract':
        entry, outdir = int(argv[2]), argv[3]
        os.makedirs(outdir, exist_ok=True)
        for k, j, b in garc_bchs(argv[1], deep):
            if k != entry:
                continue
            for t in textures(b):
                if not (t['w'] and t['h']) or not isinstance(t['fmt'], str):
                    continue
                rgba = decode_raw(t['fmt'], t['w'], t['h'], b[t['data']:])
                tag = str(j).replace('/', '-')
                path = os.path.join(outdir, '%d_%s_%s.png' % (k, tag, t['name'] or 'tex'))
                bclim.write_png(path, t['w'], t['h'], rgba)
                print('wrote', path, t['w'], t['h'], t['fmt'])
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
