"""Read a 3DS code module (.cro) or a raw code dump: segments, data tables, disassembly.

Development only. Finds the numbers the game's code holds (tables in .rodata, constants in
literal pools) so data/ files can cite them instead of guessing. Needs `capstone`
(pip install capstone) for `asm` and `refs`.

Usage:
  python tools/cro.py segs  <file.cro>
  python tools/cro.py data  <file.cro> [--max 0x700]        (.rodata / .data as ints and floats)
  python tools/cro.py asm   <file.cro> <out.asm>            (ARM disassembly of .text)
  python tools/cro.py refs  <file.cro> <offset hex>         (code that loads the literal at offset)
  python tools/cro.py find  <file> <float|int> <value>...   (where a run of values sits)
  python tools/cro.py words <file> <offset hex> <len> [--base 0x100000]   (any file, e.g. a code
                                                            dump from tools/gdbrsp.py)

The game's own modules live in the RomFS root (`romfs/Dll*.cro`); the main program is not in
RomFS: dump it from Azahar (`python tools/gdbrsp.py dump 0x00100000 0x715000 code.bin`, with
a gap near 0x006AF000 to skip).
"""
import re
import struct
import sys


def segments(b):
    seg_off, seg_num = struct.unpack_from("<2I", b, 0xC8)
    return [struct.unpack_from("<3I", b, seg_off + i * 12) for i in range(seg_num)]


def fmt(w):
    f = struct.unpack("<f", struct.pack("<I", w))[0]
    if 0x3C000000 < w < 0x48000000 and abs(f) < 1e5:
        return "%9.3ff" % f
    if w < 100000:
        return "%10d" % w
    return "  %08x" % w


def words(b, off, n, base=0):
    for r in range(off, off + n, 16):
        ws = struct.unpack_from("<4I", b, r)
        print("%08x " % (base + r) + " ".join(fmt(w) for w in ws))


def disasm(b):
    import capstone
    md = capstone.Cs(capstone.CS_ARCH_ARM, capstone.CS_MODE_ARM)
    text = next(s for s in segments(b) if s[2] == 0 and s[1])
    out = []
    for off in range(text[0], text[0] + text[1], 4):
        ins = next(md.disasm(b[off:off + 4], off), None)
        out.append((off, ins.mnemonic + " " + ins.op_str if ins else ".word 0x%08x" % int.from_bytes(b[off:off + 4], "little")))
    return out


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    cmd, path = argv[1], argv[2]
    b = open(path, "rb").read()
    if cmd == "segs":
        names = {0: "text", 1: "rodata", 2: "data", 3: "bss"}
        for o, n, t in segments(b):
            if n:
                print("%-6s at %06x size %06x" % (names.get(t, t), o, n))
    elif cmd == "data":
        lim = int(argv[argv.index("--max") + 1], 0) if "--max" in argv else 0x700
        for o, n, t in segments(b):
            if t in (1, 2) and n:
                print("-- %s at %x size %x" % ("rodata" if t == 1 else "data", o, n))
                words(b, o, min(n, lim))
    elif cmd == "asm":
        open(argv[3], "w").write("\n".join("%06x  %s" % l for l in disasm(b)))
    elif cmd == "refs":
        target = int(argv[3], 16)
        lines = disasm(b)
        pat = re.compile(r"\[pc, #(-?0x[0-9a-f]+|-?\d+)\]")
        for i, (o, t) in enumerate(lines):
            m = pat.search(t)
            if m and o + 8 + int(m.group(1), 0) == target:
                print("== loaded at %06x" % o)
                for l in lines[max(0, i - 12): i + 12]:
                    print("   %06x  %s" % l)
    elif cmd == "find":
        kind = argv[3]
        vals = [float(v) if kind == "float" else int(v, 0) for v in argv[4:]]
        pat = struct.pack("<%d%s" % (len(vals), "f" if kind == "float" else "I"), *vals)
        i = b.find(pat)
        while i >= 0:
            print("%08x" % i)
            i = b.find(pat, i + 1)
    elif cmd == "words":
        base = int(argv[argv.index("--base") + 1], 0) if "--base" in argv else 0
        words(b, int(argv[3], 16) - base, int(argv[4], 0), base)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
