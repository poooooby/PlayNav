# darc.py <blob> [darc offset]: list a darc archive's files (name, offset, size)
import sys, struct
def entries(b, base):
    assert b[base:base + 4] == b"darc", b[base:base + 4]
    bom, hlen, ver, fsize, toff, tlen, doff = struct.unpack_from("<HHIIIII", b, base + 4)
    t = base + toff
    root_end = struct.unpack_from("<III", b, t)[2]
    names = t + root_end * 12
    out, stack = [], []
    for i in range(root_end):
        noff, dataoff, size = struct.unpack_from("<III", b, t + i * 12)
        isdir = noff >> 24
        p = names + (noff & 0xFFFFFF); s = []
        while True:
            c = struct.unpack_from("<H", b, p)[0]
            if c == 0: break
            s.append(chr(c)); p += 2
        out.append(("".join(s), bool(isdir), base + dataoff, size))
    return out
if __name__ == "__main__":
    b = open(sys.argv[1], "rb").read()
    base = int(sys.argv[2]) if len(sys.argv) > 2 else b.find(b"darc")
    for n, d, o, s in entries(b, base):
        print(("D " if d else "  ") + n, o, s)
