"""Read Gen 6 (X/Y, ORAS) text files out of a GARC and search them. Development-time only:
the mod never ships game text; this finds which archive / file / line holds a string so a
runtime extraction can point at it, the way data/oras_recipe.lua points at textures.

Gen 6 text: header u16 sections, u16 lines, u32 total, u32 initialKey (0), u32 sectionOffset;
the section starts with u32 length, then `lines` entries of (u32 offset, u16 length, u16 pad);
each line is UTF-16LE xor-encrypted with key 0x7C89 + i * 0x2983, rotated left 3 bits per char.
Escapes (0x0010 variables, 0xE07F / 0xE08D etc.) are rendered as [VAR ...] / [n].

    python tools/gen6_text.py <romfs> <a/x/y/z> [--find "Toughen"] [--file N]
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from garc_dump import lz_decode, parse_garc, GarcError  # noqa: E402


SHOW_VARS = "--vars" in sys.argv


def decode_text(blob: bytes):
    if len(blob) < 0x10:
        return None
    sections, lines, total, key0, sec_off = struct.unpack_from("<HHIII", blob, 0)
    if sections != 1 or lines == 0 or lines > 5000 or sec_off + 4 > len(blob):
        return None
    out = []
    key = 0x7C89
    for i in range(lines):
        ent = sec_off + 4 + i * 8
        if ent + 8 > len(blob):
            return None
        off, length = struct.unpack_from("<IH", blob, ent)
        start = sec_off + off
        if start + length * 2 > len(blob):
            return None
        k = key
        chars = []
        for j in range(length):
            c = struct.unpack_from("<H", blob, start + j * 2)[0] ^ k
            k = ((k << 3) | (k >> 13)) & 0xFFFF
            chars.append(c)
        key = (key + 0x2983) & 0xFFFF
        s, j = [], 0
        while j < len(chars):
            c = chars[j]
            if c == 0:
                break
            if c == 0x10:  # variable: count, then words
                n = chars[j + 1] if j + 1 < len(chars) else 0
                args = chars[j + 2: j + 2 + n]
                s.append("[VAR %s]" % " ".join("%04X" % a for a in args) if SHOW_VARS else "[VAR]")
                j += 2 + n
                continue
            if c == 0xE07F:
                s.append(" ")
            elif c == 0xE08D:
                s.append("…")
            elif c in (0xE08E, 0xE08F):
                s.append("♂" if c == 0xE08E else "♀")
            elif c == 0x000A or c == 0xE07E:
                s.append("\n")
            else:
                s.append(chr(c))
            j += 1
        out.append("".join(s))
    return out


def files(romfs: str, arch: str):
    path = os.path.join(romfs, *arch.split("/"))
    data = open(path, "rb").read()
    _v, data_offset, entries = parse_garc(data)
    for ei, subs in enumerate(entries):
        for (sub, start, end, length) in subs:
            raw = data[data_offset + start: data_offset + start + length]
            dec = lz_decode(raw) if raw and raw[0] in (0x10, 0x11) else None
            yield ei, sub, dec or raw


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    romfs, arch = argv[1], argv[2]
    find = argv[argv.index("--find") + 1] if "--find" in argv else None
    only = int(argv[argv.index("--file") + 1]) if "--file" in argv else None
    sys.stdout.reconfigure(encoding="utf-8")
    for ei, sub, blob in files(romfs, arch):
        if only is not None and ei != only:
            continue
        lines = decode_text(blob)
        if not lines:
            continue
        for li, line in enumerate(lines):
            if find is None or find.lower() in line.lower():
                print("%s file %d line %d: %s" % (arch, ei, li, line.replace("\n", " | ")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
