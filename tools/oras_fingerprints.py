"""Check data/oras_fingerprints.lua against a card image, independently of the Lua readers.

Usage:
  python tools/oras_fingerprints.py <card image or CIA> [data/oras_fingerprints.lua]

Twin of tools/oras_fingerprints.lua, which writes the table: here the RomFS walk is
tools/romfs_extract.py, the GARC tables tools/garc_dump.py and the hash zlib.crc32.
Prints every row that differs and exits 1 if any does. Against Alpha Sapphire
(USA) Rev 2 every row must match; against another dump it shows which parts
NaviPlay would fall back on.
"""

from __future__ import annotations

import os
import re
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import garc_dump  # noqa: E402
import romfs_extract as rf  # noqa: E402

ROW = re.compile(r'\["([^"]+)"\] = \{ size = (\d+), crc = "([0-9a-f]{8})" \}')
CHUNK = 8 * 1024 * 1024


def crc_range(img, off, length):
    c = 0
    while length > 0:
        n = min(length, CHUNK)
        c = zlib.crc32(img.read(off, n), c)
        off, length = off + n, length - n
    return "%08x" % c


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    table = argv[2] if len(argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "data", "oras_fingerprints.lua")
    rows = ROW.findall(open(table, encoding="utf-8").read())
    img = rf.Image(argv[1])
    fs = rf.open_romfs(img)
    files = {path: (off, length) for path, off, length in rf.walk(fs)}
    garcs = {}
    bad = 0
    for key, size, crc in rows:
        parts = key.split(":")
        where = files.get(parts[0])
        if where is None:
            print("MISSING", key)
            bad += 1
            continue
        off, length = where
        if len(parts) == 1:
            got_size, got = length, crc_range(img, off, length)
        else:
            entry, sub = int(parts[1]), int(parts[2])
            if parts[0] not in garcs:
                data = img.read(off, length)
                garcs[parts[0]] = (data, garc_dump.parse_garc(data))
            data, (_ver, data_off, entries) = garcs[parts[0]]
            span = [s for s in entries[entry] if s[0] == sub] if entry < len(entries) else []
            if not span:
                print("MISSING", key)
                bad += 1
                continue
            _j, start, _end, slen = span[0]
            blob = data[data_off + start:data_off + start + slen]
            got_size, got = len(blob), "%08x" % zlib.crc32(blob)
        if got_size != int(size) or got != crc:
            print("DIFFERS %s: size %d crc %s, table %s %s" % (key, got_size, got, size, crc))
            bad += 1
    print("%d of %d rows match" % (len(rows) - bad, len(rows)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
