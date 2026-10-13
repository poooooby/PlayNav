# garc_blob.py <romfs garc path> <entry> <sub> <out.bin>: write the decompressed entry blob and list the magics in it (darc, CLYT, CLIM)
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import garc_dump as g
path, entry, sub, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
data = open(path, "rb").read()
ver, off, entries = g.parse_garc(data)
for j, s, e, l in entries[entry]:
    if j == sub:
        raw = data[off + s: off + e]
        blob = g.lz_decode(raw) or raw
        open(out, "wb").write(blob)
        print("len", len(blob))
        for m in (b"CLYT", b"CLAN", b"lyt1", b"pan1", b"pic1", b"txl1", b"wnd1", b"CLIM", b"darc", b"SARC"):
            i, hits = 0, []
            while True:
                i = blob.find(m, i)
                if i < 0: break
                hits.append(i); i += 1
            if hits: print(m, len(hits), hits[:6])
