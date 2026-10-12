"""Read a decrypted 3DS card image (.cci / NCSD) and extract RomFS files, stdlib only.

Usage:
  python tools/romfs_extract.py <game.cci> list                 # print every file path and size
  python tools/romfs_extract.py <game.cci> extract <out> [a/]   # extract (optionally only paths under a prefix)

This is the development twin of src/import/ctr.lua: NCSD header -> partition 0
NCCH -> RomFS (IVFC) -> level 3 directory/file metadata tables. Only the
tables and the requested files are read, never the whole image.
"""

from __future__ import annotations

import os
import struct
import sys

MEDIA_UNIT = 0x200


class CtrError(Exception):
    pass


class Image:
    def __init__(self, path: str):
        self.f = open(path, "rb")
        self.f.seek(0, 2)
        self.size = self.f.tell()

    def read(self, offset: int, length: int) -> bytes:
        if offset < 0 or offset + length > self.size:
            raise CtrError("read out of bounds: 0x%x+0x%x" % (offset, length))
        self.f.seek(offset)
        data = self.f.read(length)
        if len(data) != length:
            raise CtrError("short read at 0x%x" % offset)
        return data

    def close(self):
        self.f.close()


def open_romfs(img: Image):
    """Locate the level-3 RomFS inside partition 0. Returns dict with absolute offsets."""
    if img.read(0x100, 4) != b"NCSD":
        raise CtrError("not an NCSD image")
    p0_off, p0_len = struct.unpack("<II", img.read(0x120, 8))
    ncch = p0_off * MEDIA_UNIT
    if img.read(ncch + 0x100, 4) != b"NCCH":
        raise CtrError("partition 0 is not an NCCH")
    flags = img.read(ncch + 0x188, 8)
    if not (flags[7] & 0x04):
        raise CtrError("NCCH is encrypted (NoCrypto flag clear); supply a decrypted image")
    romfs_off, romfs_len = struct.unpack("<II", img.read(ncch + 0x1B0, 8))
    romfs = ncch + romfs_off * MEDIA_UNIT
    ivfc = img.read(romfs, 0x5C)
    if ivfc[:4] != b"IVFC":
        raise CtrError("RomFS IVFC header missing")
    l3_logical = struct.unpack_from("<Q", ivfc, 0x3C)[0]
    l3_block_log2 = struct.unpack_from("<I", ivfc, 0x4C)[0]
    # The level-3 image follows the IVFC header + master hash, aligned to its block size.
    master_hash_size = struct.unpack_from("<I", ivfc, 0x08)[0]
    block = 1 << l3_block_log2
    l3 = romfs + ((0x60 + master_hash_size + block - 1) // block) * block
    hdr = img.read(l3, 0x28)
    (header_len, dir_hash_off, dir_hash_len, dir_meta_off, dir_meta_len,
     file_hash_off, file_hash_len, file_meta_off, file_meta_len, data_off) = struct.unpack("<10I", hdr)
    if header_len != 0x28:
        raise CtrError("unexpected RomFS level-3 header length 0x%x" % header_len)
    return {
        "ncch": ncch, "romfs": romfs, "l3": l3,
        "dir_meta": img.read(l3 + dir_meta_off, dir_meta_len),
        "file_meta": img.read(l3 + file_meta_off, file_meta_len),
        "data": l3 + data_off,
        "l3_logical": l3_logical,
    }


def _name(table: bytes, off: int, length_pos: int):
    n = struct.unpack_from("<I", table, length_pos)[0]
    raw = table[length_pos + 4:length_pos + 4 + n]
    return raw.decode("utf-16-le", errors="replace")


def walk(fs, dir_off: int = 0, prefix: str = ""):
    """Yield (path, data_offset_absolute, length) for every file under dir_off."""
    dm, fm = fs["dir_meta"], fs["file_meta"]
    first_child, first_file = struct.unpack_from("<II", dm, dir_off + 8)
    f = first_file
    while f != 0xFFFFFFFF:
        _parent, sibling = struct.unpack_from("<II", fm, f)
        data_off, data_len = struct.unpack_from("<QQ", fm, f + 8)
        name = _name(fm, f, f + 0x1C)
        yield prefix + name, fs["data"] + data_off, data_len
        f = sibling
    d = first_child
    while d != 0xFFFFFFFF:
        _parent, sibling = struct.unpack_from("<II", dm, d)
        name = _name(dm, d, d + 0x14)
        yield from walk(fs, d, prefix + name + "/")
        d = sibling


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    img = Image(argv[1])
    fs = open_romfs(img)
    cmd = argv[2]
    if cmd == "list":
        n = 0
        for path, off, length in walk(fs):
            print("%10d  %s" % (length, path))
            n += 1
        print("%d files" % n, file=sys.stderr)
        return 0
    if cmd == "extract":
        out = argv[3]
        prefix = argv[4] if len(argv) > 4 else ""
        n, total = 0, 0
        for path, off, length in walk(fs):
            if not path.startswith(prefix):
                continue
            dest = os.path.join(out, *path.split("/"))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as fh:
                remaining, pos = length, off
                while remaining > 0:
                    chunk = min(remaining, 8 * 1024 * 1024)
                    fh.write(img.read(pos, chunk))
                    pos += chunk
                    remaining -= chunk
            n += 1
            total += length
        print("extracted %d files, %d bytes" % (n, total))
        return 0
    print("unknown command", cmd)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
