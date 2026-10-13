"""Read a 3DS BCSTM stream (DSP-ADPCM), stdlib only: header facts and a WAV decode.

Usage:
  python tools/bcstm.py info <file.bcstm> [...]          # channels, rate, samples, loop
  python tools/bcstm.py wav <file.bcstm> <out.wav>        # decode every channel to 16-bit PCM

The development twin of src/import/bcstm.lua (the import job decodes the game's
music with it). The decoded files stay in the work tree, never in the repo.
"""

from __future__ import annotations

import struct
import sys
import wave


def parse(b: bytes) -> dict:
    if b[:4] != b"CSTM":
        raise ValueError("not a CSTM file")
    if b[4:6] != b"\xff\xfe":
        raise ValueError("big-endian CSTM is not handled")
    nsec = struct.unpack_from("<H", b, 0x10)[0]
    secs = {}
    for i in range(nsec):
        sid, _, off, size = struct.unpack_from("<HHiI", b, 0x14 + i * 12)
        secs[sid] = (off, size)
    info = secs[0x4000][0]
    data = secs[0x4002][0]
    if b[info:info + 4] != b"INFO":
        raise ValueError("INFO block missing")
    base = info + 8
    _, _, stream_off = struct.unpack_from("<HHi", b, base)
    _, _, chan_off = struct.unpack_from("<HHi", b, base + 16)
    s = base + stream_off
    enc, loop, nch = b[s], b[s + 1], b[s + 2]
    (rate, loop_start, frames, nblocks, block_size, block_samples, last_size, last_samples,
     last_padded) = struct.unpack_from("<9I", b, s + 4)
    _, _, data_off = struct.unpack_from("<HHi", b, s + 0x38)
    ct = base + chan_off
    count = struct.unpack_from("<I", b, ct)[0]
    chans = []
    for i in range(count):
        _, _, off = struct.unpack_from("<HHi", b, ct + 4 + i * 8)
        ci = ct + off
        _, _, aoff = struct.unpack_from("<HHi", b, ci)
        a = ci + aoff
        coefs = struct.unpack_from("<16h", b, a)
        ps, h1, h2 = struct.unpack_from("<Hhh", b, a + 32)
        chans.append({"coefs": coefs, "ps": ps, "hist1": h1, "hist2": h2})
    return {
        "encoding": enc, "loop": bool(loop), "channels": nch, "rate": rate, "loop_start": loop_start,
        "frames": frames, "blocks": nblocks, "block_size": block_size, "block_samples": block_samples,
        "last_size": last_size, "last_samples": last_samples, "last_padded": last_padded,
        "data": data + 8 + data_off, "chans": chans,
    }


def decode(b: bytes, h: dict) -> list[list[int]]:
    if h["encoding"] != 2:
        raise ValueError("encoding %d is not DSP-ADPCM" % h["encoding"])
    nch = h["channels"]
    out = [[] for _ in range(nch)]
    hist = [(c["hist1"], c["hist2"]) for c in h["chans"]]
    pos = h["data"]
    for blk in range(h["blocks"]):
        last = blk == h["blocks"] - 1
        size = h["last_size"] if last else h["block_size"]
        stride = h["last_padded"] if last else h["block_size"]
        nsamp = h["last_samples"] if last else h["block_samples"]
        for c in range(nch):
            coefs = h["chans"][c]["coefs"]
            h1, h2 = hist[c]
            p = pos + c * stride
            dst = out[c]
            left = nsamp
            q = p
            while left > 0 and q < p + size:
                head = b[q]
                scale = 1 << (head & 15)
                c1, c2 = coefs[(head >> 4) * 2], coefs[(head >> 4) * 2 + 1]
                for k in range(14):
                    if left <= 0:
                        break
                    byte = b[q + 1 + k // 2]
                    n = (byte >> 4) if k % 2 == 0 else (byte & 15)
                    if n >= 8:
                        n -= 16
                    v = ((n * scale) << 11) + 1024 + c1 * h1 + c2 * h2
                    v >>= 11
                    v = -32768 if v < -32768 else 32767 if v > 32767 else v
                    dst.append(v)
                    h2, h1 = h1, v
                    left -= 1
                q += 8
            hist[c] = (h1, h2)
        pos += stride * nch
    return out


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2
    if argv[0] == "info":
        for path in argv[1:]:
            h = parse(open(path, "rb").read())
            print("%s: ch %d, %d Hz, %d samples (%.1f s), loop %s from %d (%.2f s), blocks %d x %d" % (
                path.replace("\\", "/").split("/")[-1], h["channels"], h["rate"], h["frames"],
                h["frames"] / h["rate"], h["loop"], h["loop_start"], h["loop_start"] / h["rate"],
                h["blocks"], h["block_size"]))
        return 0
    if argv[0] == "wav":
        b = open(argv[1], "rb").read()
        h = parse(b)
        ch = decode(b, h)[:2]
        with wave.open(argv[2], "wb") as w:
            w.setnchannels(len(ch))
            w.setsampwidth(2)
            w.setframerate(h["rate"])
            frames = bytearray()
            for i in range(len(ch[0])):
                for c in ch:
                    frames += struct.pack("<h", c[i])
            w.writeframes(bytes(frames))
        print("wrote", argv[2], len(ch[0]), "samples")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
