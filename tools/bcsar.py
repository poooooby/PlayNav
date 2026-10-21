"""Read a 3DS sound archive (BCSAR) and render its sound effects, stdlib only (numpy for `match`).

Usage:
  python tools/bcsar.py list <file.bcsar> [prefix]               # effects: volume, notes, commands
  python tools/bcsar.py render <file.bcsar> <name> <out.wav>       # one effect (e.g. SEQ_SE_SP_001)
  python tools/bcsar.py music <file.bcsar> <name> <out.wav> [tempo] [gainDb]  # a song to its loop's end (SEQ_BGM_KW_GAME01), tempo x, raised gainDb (soft knee)
  python tools/bcsar.py renderall <file.bcsar> <prefix> <dir>      # every SEQ_<prefix>* to <dir>/<name>.wav
  python tools/bcsar.py match <dir> <capture.raw> [rate]           # find the effects in a capture
                                                                   # (mono s16le, default 8000 Hz)

An effect is a sequence (CSEQ: notes, waits, pan, volume, pitch bend, vibrato, envelope, tracks)
played on its bank's instruments (CBNK: key / velocity regions -> a wave, its original key,
volume, pan, pitch, ADSR), the waves being DSP-ADPCM CWAVs in wave archives (CWAR). The
development twin of src/import/bcsar.lua + src/import/seqsynth.lua (the import job renders
the game's effects with those); the WAVs stay in the work tree, never in the repo.
"""

from __future__ import annotations

import math
import os
import struct
import sys
import wave

OUT_RATE = 32728          # the 3DS's own output rate
TEMPO, TIMEBASE = 120, 48  # NW defaults
ENV_STEP = 0.003           # envelope update period, s
MAX_SECONDS = 4.0          # a looping wave left held is cut here (a charge breaks at 2.6 s)
LFO_HZ_PER_SPEED = 0.390625


def u16(b, p): return struct.unpack_from('<H', b, p)[0]
def u32(b, p): return struct.unpack_from('<I', b, p)[0]
def s32(b, p): return struct.unpack_from('<i', b, p)[0]


def ref(b, p):
    """(type, offset) of an 8-byte reference."""
    return u16(b, p), s32(b, p + 4)


def section(b, off, tag):
    n = u16(b, off + 0x10)
    for i in range(n):
        so = s32(b, off + 0x14 + i * 12 + 4)
        if b[off + so: off + so + 4] == tag:
            return off + so, u32(b, off + 0x14 + i * 12 + 8)
    raise ValueError('no %s section' % tag)


# ------- the archive

class Archive:
    def __init__(self, data: bytes):
        b = self.b = data
        if b[:4] != b'CSAR':
            raise ValueError('not a CSAR file')
        self.strg, _ = section(b, 0, b'STRG')
        self.info, _ = section(b, 0, b'INFO')
        self.file, _ = section(b, 0, b'FILE')
        base = self.info + 8
        refs = {}
        for i in range(8):
            t, o = ref(b, base + i * 8)
            refs[t] = base + o
        self.tables = {k: self._table(refs[k]) for k in (0x2100, 0x2101, 0x2103, 0x2106)}
        self.names = self._names()

    def _table(self, t):
        n = u32(self.b, t)
        return [t + ref(self.b, t + 4 + i * 8)[1] for i in range(n)]

    def _names(self):
        b = self.b
        sb = self.strg + 8
        st = sb + ref(b, sb)[1]
        lt = sb + ref(b, sb + 8)[1]
        n = u32(b, st)
        strings = []
        for i in range(n):
            o, size = s32(b, st + 4 + i * 12 + 4), u32(b, st + 4 + i * 12 + 8)
            strings.append(b[st + o: st + o + size - 1].decode('ascii'))
        ids = {}
        count = u32(b, lt + 4)
        for i in range(count):
            leaf, _, _, _, sid, iid = struct.unpack_from('<HHIIII', b, lt + 8 + i * 20)
            if leaf == 1 and sid < n:
                ids[strings[sid]] = iid
        return ids

    def file_bytes(self, fid):
        b = self.b
        e = self.tables[0x2106][fid]
        t, o = ref(b, e)
        if t != 0x220c:
            raise ValueError('file %d is not inside the archive' % fid)
        loc = e + o
        foff, size = s32(b, loc + 4), u32(b, loc + 8)
        start = self.file + 8 + foff
        return b[start: start + size]

    def sound(self, name):
        """{volume, seq (CSEQ bytes), banks [CBNK bytes]}"""
        b = self.b
        iid = self.names.get(name)
        if iid is None or iid >> 24 != 1:
            raise KeyError(name)
        e = self.tables[0x2100][iid & 0xffffff]
        fid, volume = u32(b, e), b[e + 8]
        seqinfo = e + 0x44
        bt = seqinfo + ref(b, seqinfo)[1]
        banks = []
        for i in range(u32(b, bt)):
            bid = u32(b, bt + 4 + i * 4)
            if bid == 0xffffffff:
                banks.append(None)
                continue
            be = self.tables[0x2101][bid & 0xffffff]
            banks.append(self.file_bytes(u32(b, be)))
        return {'name': name, 'volume': volume, 'seq': self.file_bytes(fid), 'banks': banks}

    def wave(self, warc_id, index):
        we = self.tables[0x2103][warc_id & 0xffffff]
        warc = self.file_bytes(u32(self.b, we))
        info, _ = section(warc, 0, b'INFO')
        data, _ = section(warc, 0, b'FILE')
        o, size = s32(warc, info + 8 + 4 + index * 12 + 4), u32(warc, info + 8 + 4 + index * 12 + 8)
        return warc[data + 8 + o: data + 8 + o + size]


# ------- waves (CWAV, DSP-ADPCM / PCM)

def dsp_decode(b, p, nsamples, coefs, h1, h2):
    out = []
    while len(out) < nsamples:
        head = b[p]
        scale = 1 << (head & 15)
        c1, c2 = coefs[(head >> 4) * 2], coefs[(head >> 4) * 2 + 1]
        for k in range(14):
            if len(out) >= nsamples:
                break
            byte = b[p + 1 + k // 2]
            n = (byte >> 4) if k % 2 == 0 else (byte & 15)
            if n >= 8:
                n -= 16
            v = (((n * scale) << 11) + 1024 + c1 * h1 + c2 * h2) >> 11
            v = -32768 if v < -32768 else 32767 if v > 32767 else v
            out.append(v)
            h2, h1 = h1, v
        p += 8
    return out


def cwav(b):
    """{rate, loop, loopStart, samples: [floats -1..1] (first channel)}"""
    if b[:4] != b'CWAV':
        raise ValueError('not a CWAV')
    info, _ = section(b, 0, b'INFO')
    data, _ = section(b, 0, b'DATA')
    body = info + 8
    enc, loop = b[body], b[body + 1]
    rate, ls, le = u32(b, body + 4), u32(b, body + 8), u32(b, body + 12)
    ct = body + 0x14
    ch = ct + ref(b, ct + 4)[1]
    sample_off = data + 8 + ref(b, ch)[1]
    if enc == 2:
        a = ch + ref(b, ch + 8)[1]
        coefs = struct.unpack_from('<16h', b, a)
        h1, h2 = struct.unpack_from('<hh', b, a + 34)
        pcm = dsp_decode(b, sample_off, le, coefs, h1, h2)
    elif enc == 1:
        pcm = list(struct.unpack_from('<%dh' % le, b, sample_off))
    elif enc == 0:
        pcm = [(x - 256 if x > 127 else x) * 256 for x in b[sample_off: sample_off + le]]
    else:
        raise ValueError('encoding %d' % enc)
    return {'rate': rate, 'loop': bool(loop), 'loopStart': ls, 'samples': [v / 32768 for v in pcm]}


# ------- banks

def bank_regions(bnk):
    """instrument index -> list of (keyLow, keyHigh, region dict) ; region: wave (warc, idx),
    key, volume, pan, pitch, adsr"""
    info, _ = section(bnk, 0, b'INFO')
    body = info + 8
    wt = body + ref(bnk, body)[1]
    waves = [(u32(bnk, wt + 4 + i * 8), u32(bnk, wt + 8 + i * 8)) for i in range(u32(bnk, wt))]
    it = body + ref(bnk, body + 8)[1]
    insts = {}

    def velregion(p):
        idx, flags = u32(bnk, p), u32(bnk, p + 4)
        r = {'wave': waves[idx], 'key': 60, 'volume': 127, 'pan': 64, 'pitch': 1.0,
             'adsr': (127, 127, 127, 0, 127)}
        q = p + 8
        if flags & 1: r['key'] = bnk[q]; q += 4
        if flags & 2: r['volume'] = bnk[q]; q += 4
        if flags & 4: r['pan'] = bnk[q]; q += 4
        if flags & 8: r['pitch'] = struct.unpack_from('<f', bnk, q)[0]; q += 4
        if flags & 0x10: q += 4
        for bit in range(5, 9):
            if flags & (1 << bit): q += 4
        if flags & 0x200:
            env = p + u32(bnk, q)
            curve = env + s32(bnk, env + 4)
            r['adsr'] = tuple(bnk[curve: curve + 5])
            q += 4
        return r

    def container(p, inner):
        """direct (0x6000) / range (0x6001) / index (0x6002) -> list of (lo, hi, target offset)"""
        t, o = ref(bnk, p)
        c = p + o
        if t == 0x6000:
            rtyp, ro = ref(bnk, c)
            return [(0, 127, c + ro, rtyp)] if rtyp in (0x5901, 0x5902) else []
        if t == 0x6001:
            n = u32(bnk, c)
            keys = list(bnk[c + 4: c + 4 + n])
            rt = c + 4 + ((n + 3) // 4) * 4
            out, lo = [], 0
            for i in range(n):
                rtyp, ro = ref(bnk, rt + i * 8)
                if rtyp in (0x5901, 0x5902):          # 0x5903 is an empty range
                    out.append((lo, keys[i], c + ro, rtyp))
                lo = keys[i] + 1
            return out
        if t == 0x6002:
            lo, hi = bnk[c], bnk[c + 1]
            out = []
            for i in range(hi - lo + 1):
                rtyp, ro = ref(bnk, c + 4 + i * 8)
                if rtyp in (0x5901, 0x5902):
                    out.append((lo + i, lo + i, c + ro, rtyp))
            return out
        raise ValueError('region table type %x' % t)

    for i in range(u32(bnk, it)):
        t, o = ref(bnk, it + 4 + i * 8)
        if t != 0x5900:
            continue
        inst = it + o
        regions = []
        for klo, khi, kp, kt in container(inst, None):
            for vlo, vhi, vp, vt in container(kp, None):
                if vt == 0x5902:
                    regions.append((klo, khi, velregion(vp)))
        insts[i] = regions
    return insts


# ------- the sequencer

class Rng:
    """Park-Miller (exact in doubles), the same in src/import/seqsynth.lua"""
    def __init__(self, seed=12345):
        self.s = seed

    def range(self, lo, hi):
        self.s = (self.s * 16807) % 2147483647
        return lo + self.s % (hi - lo + 1)


def varlen(d, i):
    v = 0
    while True:
        c = d[i]
        i += 1
        v = (v << 7) | (c & 0x7f)
        if not c & 0x80:
            return v, i


ARG1 = set(range(0xb0, 0xe0))           # one u8 argument
ARG2 = {0xe0, 0xe1, 0xe3, 0xe4}          # one s16 (big-endian)


def parse_track(d, start, rng, music=False):
    """the events of one track, in ticks: notes, parameter changes and sweeps, track opens.
    Returns a list of (tick, kind, args) and the opened tracks [(index, offset)].
    music: a song - calls (8a) and returns (fd) are followed, and the first jump (89) back to
    an earlier point ends the track there; parse_track.loop is then (loop start tick, loop end
    tick). Effects keep the old reading (jumps and calls stepped over)."""
    ev, opens = [], []
    i, t = start, 0
    loops = []
    calls = []
    seen = {}          # a command's offset -> the tick it first ran at (music: the loop start)
    parse_track.loop = None
    wait_notes = True
    steps = 0
    while i < len(d) and steps < (200000 if music else 4000):
        if music and i not in seen:
            seen[i] = t
        steps += 1
        op = d[i]
        i += 1
        prefix = None
        if op in (0xa0, 0xa3):
            prefix = op
            op = d[i]
            i += 1
        if op < 0x80:
            vel = d[i]
            i += 1
            length, i = varlen(d, i)
            ev.append((t, 'note', (op, vel, length)))
            if wait_notes:
                t += length
        elif op == 0x80:
            w, i = varlen(d, i)
            t += w
        elif op == 0x81:
            p, i = varlen(d, i)
            ev.append((t, 'prg', p))
        elif op == 0x88:
            opens.append((d[i], (d[i + 1] << 16) | (d[i + 2] << 8) | d[i + 3]))
            i += 4
        elif op in (0x89, 0x8a) and music:
            to = (d[i] << 16) | (d[i + 1] << 8) | d[i + 2]
            i += 3
            if op == 0x8a:
                calls.append(i)
                i = to
            elif to in seen:
                parse_track.loop = (seen[to], t)
                break
            else:
                i = to
        elif op in (0x89, 0x8a):
            i += 3
        elif op == 0xfd and music:
            if not calls:
                break
            i = calls.pop()
        elif op in ARG1:
            if prefix == 0xa0:
                lo, hi = struct.unpack_from('>hh', d, i)
                i += 4
                v = rng.range(lo, hi)
            else:
                v = d[i]
                i += 1
            dur = 0
            if prefix == 0xa3:
                dur = struct.unpack_from('>h', d, i)[0]
                i += 2
            if op == 0xc7:
                wait_notes = v != 0
            elif op == 0xd4:
                loops.append((i, v))
            else:
                if op in (0xc3, 0xc4):
                    v = v - 256 if v > 127 and prefix != 0xa0 else v
                ev.append((t, 'set', (op, v, dur)))
        elif op in ARG2:
            v = struct.unpack_from('>h', d, i)[0]
            i += 2
            ev.append((t, 'set', (op, v, 0)))
        elif op == 0xfc:
            if loops:
                at, n = loops[-1]
                if n == 0 or n > 1:
                    loops[-1] = (at, n - 1 if n else 0)
                    i = at
                    if n == 0 and t > MAX_SECONDS * TEMPO * TIMEBASE / 60:
                        loops.pop()
                else:
                    loops.pop()
        elif op == 0xfe:
            i += 2
        elif op == 0xff:
            break
        else:
            raise ValueError('sequence command %02x at %d' % (op, i - 1))
    ev.append((t, 'end', None))
    return ev, opens


ATTACK_TABLE = [0x00, 0x01, 0x05, 0x0e, 0x1a, 0x26, 0x33, 0x3f, 0x49, 0x54, 0x5c, 0x64, 0x6d,
                0x74, 0x7b, 0x7f, 0x84, 0x89, 0x8f]


def attack_rate(a):
    return 255 - a if a < 109 else ATTACK_TABLE[127 - a]


def release_rate(v):
    """dB lost per envelope step (DS / NW: the envelope is in 1/128 dB, 723 dB = silence)"""
    if v == 127:
        return 0xffff
    if v == 126:
        return 0x3c00
    if v < 50:
        return v * 2 + 1
    return 0x1e00 // (126 - v)


def sustain_db(s):
    """sustain level 0..127 -> dB*128 (0 at 127)"""
    if s >= 127:
        return 0
    if s == 0:
        return -92544
    return int(40 * math.log10(s / 127) * 128)


ENV_FLOOR = -92544


# the track parameters a sounding voice follows live (set or swept after its note began)
LIVE = {0xc0: 'pan', 0xc1: 'vol', 0xc2: 'mvol', 0xc4: 'bend', 0xc5: 'range', 0xca: 'mdepth', 0xcb: 'mspeed',
        0xcd: 'mrange', 0xe0: 'mdelay', 0xd5: 'vol2'}
LIVE_DEFAULT = {'pan': 64, 'vol': 127, 'mvol': 127, 'bend': 0, 'range': 2, 'mdepth': 0, 'mspeed': 16,
                'mrange': 1, 'mdelay': 0, 'vol2': 127}
MUSIC_TAIL_S = 3.0   # a song is rendered this far past its loop's end, the tail folded onto the loop
# set at a note's start (the envelope and the instrument)
AT_NOTE = {0xd0: 'attack', 0xd1: 'decay', 0xd2: 'sustain', 0xd3: 'release', 0xb1: 'hold', 0xc3: 'transpose'}


class Timeline:
    """a track's live parameters over ticks: each change (tick, value, sweep ticks, from)"""
    def __init__(self):
        self.ch = {k: [] for k in LIVE_DEFAULT}
        self.cur = dict(LIVE_DEFAULT)

    def set(self, key, t, v, dur):
        self.ch[key].append((t, v, dur, self.cur[key]))
        self.cur[key] = v

    def at(self, key, tick):
        val = LIVE_DEFAULT[key]
        for t, v, dur, frm in self.ch[key]:
            if t > tick:
                break
            if dur and tick < t + dur:
                val = frm + (v - frm) * (tick - t) / dur
            else:
                val = v
        return val


def render(sound, archive, seed=12345, music=False, tempo_scale=1.0):
    """a sound effect -> (left, right) float lists at OUT_RATE. music: a song (parse_track's
    music mode) rendered to its loop's end; render.loop is then (loop start, loop end) in samples,
    the release tails past the end folded onto the loop's start so it repeats seamlessly. Only a
    song reads the expression volume (d5); the effects render as they were matched."""
    render.loop = None
    seq = sound['seq']
    data, _ = section(seq, 0, b'DATA')
    d = seq[data + 8:]
    rng = Rng(seed)
    tracks = {}
    song_loop = None
    pending = [(0, 0)]
    while pending:
        idx, off = pending.pop(0)
        if idx in tracks:
            continue
        ev, opens = parse_track(d, off, rng, music)
        tracks[idx] = ev
        if idx == 0 and music:
            song_loop = parse_track.loop
        pending.extend(opens)
    bank = sound['banks'][0]
    insts = bank_regions(bank) if bank else {}
    wavecache = {}
    # the sequence's own timebase (b0) and tempo (e1), set once at the start
    timebase, tempo = TIMEBASE, TEMPO
    for idx in sorted(tracks):
        for t, kind, args in tracks[idx]:
            if kind == 'set' and args[0] == 0xb0 and args[1] > 0:
                timebase = args[1]
            elif kind == 'set' and args[0] == 0xe1 and args[1] > 0:
                tempo = args[1]
    tick_s = 60.0 / (tempo * (tempo_scale if music else 1.0) * timebase)
    sound_gain = sound['volume'] / 127.0
    if music:
        end_tick = song_loop[1] if song_loop else max(e[0] for ev in tracks.values() for e in ev)
        L = [0.0] * int((end_tick * tick_s + MUSIC_TAIL_S) * OUT_RATE)
    else:
        L = [0.0] * int(MAX_SECONDS * OUT_RATE)
    R = [0.0] * len(L)
    last = 0
    for idx in sorted(tracks):
        # the whole track's live parameters first, then its notes play against them
        tl = Timeline()
        for t, kind, args in tracks[idx]:
            if kind == 'set' and args[0] in LIVE and (music or args[0] != 0xd5):
                tl.set(LIVE[args[0]], t, args[1], args[2])
        st = {'prg': 0, 'transpose': 0}
        for t, kind, args in tracks[idx]:
            if kind == 'prg':
                st['prg'] = args
            elif kind == 'set' and args[0] in AT_NOTE:
                st[AT_NOTE[args[0]]] = args[1]
            elif kind == 'note':
                key, vel, length = args
                regions = insts.get(st['prg'], [])
                k = key + st['transpose']
                reg = next((r for lo, hi, r in regions if lo <= k <= hi), None)
                if not reg:
                    continue
                w = reg['wave']
                if w not in wavecache:
                    wavecache[w] = cwav(archive.wave(*w))
                end = mix_voice(L, R, wavecache[w], reg, dict(st), tl, t, k, vel, length, tick_s, sound_gain)
                last = max(last, end)
    if music and song_loop:
        ls, le = (int(math.floor(x * tick_s * OUT_RATE + 0.5)) for x in song_loop)
        for k in range(le, len(L)):
            L[ls + k - le] += L[k]
            R[ls + k - le] += R[k]
        render.loop = (ls, le)
        return L[:le], R[:le]
    n = min(len(L), last + 1)
    return L[:n], R[:n]


def mix_voice(L, R, wav, reg, st, tl, t0, key, vel, length, tick_s, sound_gain):
    a = st['attack'] if st.get('attack') is not None else reg['adsr'][0]
    dcy = st['decay'] if st.get('decay') is not None else reg['adsr'][1]
    sus = st['sustain'] if st.get('sustain') is not None else reg['adsr'][2]
    hold = st['hold'] if st.get('hold') is not None else reg['adsr'][3]
    rel = st['release'] if st.get('release') is not None else reg['adsr'][4]
    src = wav['samples']
    nsrc = len(src)
    vel_gain = sound_gain * (vel / 127) ** 2 * (reg['volume'] / 127) ** 2
    start = int(math.floor(t0 * tick_s * OUT_RATE + 0.5))   # half up, as the Lua twin
    off_at = (t0 + length) * tick_s if length > 0 else None
    pos = 0.0
    env = ENV_FLOOR if a < 127 else 0
    phase = 'attack' if a < 127 else ('hold' if hold else 'decay')
    hold_left = hold * ENV_STEP * 8
    sus_db = sustain_db(sus)
    step_n = max(1, int(ENV_STEP * OUT_RATE))
    i = start
    last = start
    base_ratio = wav['rate'] / OUT_RATE * reg['pitch']
    lfo_phase = 0.0
    lfo_t = None
    while i < len(L):
        t = i / OUT_RATE
        if i % step_n == 0 or i == start:
            tick = t / tick_s
            # the track's live parameters, swept where a sweep is running
            bend, brange = tl.at('bend', tick), tl.at('range', tick)
            vol, mvol, pan = tl.at('vol', tick), tl.at('mvol', tick), tl.at('pan', tick)
            vol2 = tl.at('vol2', tick)
            mdepth, mspeed, mrange = tl.at('mdepth', tick), tl.at('mspeed', tick), tl.at('mrange', tick)
            semis = key - reg['key'] + bend / 128 * brange
            # vibrato: its phase runs on from when it may start (the delay after the note)
            since = t - t0 * tick_s - tl.at('mdelay', tick) * tick_s
            if since > 0:
                if lfo_t is not None:
                    lfo_phase += 2 * math.pi * mspeed * LFO_HZ_PER_SPEED * (t - lfo_t)
                lfo_t = t
                if mdepth:
                    semis += math.sin(lfo_phase) * mdepth / 128 * mrange
            ratio = base_ratio * 2 ** (semis / 12)
            p = (pan + reg['pan'] - 64)
            p = 0 if p < 0 else 127 if p > 127 else p
            # 64 is the exact centre: 0..64 and 64..127 each span half the field
            x = (p - 64) / 64 if p <= 64 else (p - 64) / 63
            lg = math.cos((x + 1) * math.pi / 4)
            rg = math.sin((x + 1) * math.pi / 4)
            # the envelope
            if off_at is not None and t >= off_at and phase != 'release':
                phase = 'release'
            if phase == 'attack':
                env = env * attack_rate(a) // 255
                if env > -16:
                    env = 0
                    phase = 'hold' if hold else 'decay'
            elif phase == 'hold':
                hold_left -= ENV_STEP
                if hold_left <= 0:
                    phase = 'decay'
            elif phase == 'decay':
                env -= release_rate(dcy)
                if env <= sus_db:
                    env = sus_db
                    phase = 'sustain'
            elif phase == 'release':
                env -= release_rate(rel)
            if env <= ENV_FLOOR:
                break
            amp = vel_gain * (vol / 127) ** 2 * (mvol / 127) ** 2 * (vol2 / 127) ** 2 * 10 ** (env / 128 / 20)
        ip = int(pos)
        if ip >= nsrc - 1:
            if wav['loop'] and wav['loopStart'] < nsrc - 1:
                pos -= nsrc - wav['loopStart']
                ip = int(pos)
            else:
                break
        fr = pos - ip
        v = src[ip] + (src[ip + 1] - src[ip]) * fr
        L[i] += v * amp * lg
        R[i] += v * amp * rg
        last = i
        pos += ratio
        i += 1
    return last


LEVEL_CEIL = 0.95
LEVEL_ATTACK = 1 / 64
LEVEL_RELEASE = 1 / 2618


def level(L, R, gain_db):
    """a song's level (recipe gain, dB): raised, the peaks past LEVEL_CEIL turned down by a
    limiter with both channels linked (the twin of seqsynth's M.level)"""
    k = 10 ** (gain_db / 20)
    if k == 1:
        return
    n = len(L)
    g = [1.0] * n
    for i in range(n):
        l, r = L[i] * k, R[i] * k
        L[i], R[i] = l, r
        p = max(abs(l), abs(r))
        g[i] = LEVEL_CEIL / p if p > LEVEL_CEIL else 1
    for i in range(1, n):
        up = g[i - 1] + LEVEL_RELEASE
        if g[i] > up:
            g[i] = up
    for i in range(n - 2, -1, -1):
        up = g[i + 1] + LEVEL_ATTACK
        if g[i] > up:
            g[i] = up
    for i in range(n):
        L[i] *= g[i]
        R[i] *= g[i]


def write_wav(path, L, R):
    mono = all(abs(a - b) < 1e-6 for a, b in zip(L, R))
    frames = bytearray()
    for a, b in zip(L, R):
        for v in ((a,) if mono else (a, b)):
            x = int(math.floor(v * 32767 + 0.5))
            frames += struct.pack('<h', -32768 if x < -32768 else 32767 if x > 32767 else x)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1 if mono else 2)
        w.setsampwidth(2)
        w.setframerate(OUT_RATE)
        w.writeframes(bytes(frames))


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[0]
    if cmd in ('list', 'render', 'renderall', 'music'):
        ar = Archive(open(argv[1], 'rb').read())
    if cmd == 'list':
        prefix = 'SEQ_' + (argv[2] if len(argv) > 2 else '')
        for name in sorted(n for n in ar.names if n.startswith(prefix)):
            s = ar.sound(name)
            data, _ = section(s['seq'], 0, b'DATA')
            d = s['seq'][data + 8:]
            ev, opens = parse_track(d, 0, Rng())
            notes = sum(1 for e in ev if e[1] == 'note')
            print('%-22s vol %3d notes %d tracks %d' % (name, s['volume'], notes, 1 + len(opens)))
        return 0
    if cmd in ('render', 'music'):
        scale = float(argv[4]) if cmd == 'music' and len(argv) > 4 else 1.0
        L, R = render(ar.sound(argv[2]), ar, music=cmd == 'music', tempo_scale=scale)
        if cmd == 'music' and len(argv) > 5:
            level(L, R, float(argv[5]))
        write_wav(argv[3], L, R)
        print('wrote', argv[3], '%.2f s' % (len(L) / OUT_RATE), 'loop (samples)', render.loop)
        return 0
    if cmd == 'renderall':
        os.makedirs(argv[3], exist_ok=True)
        for name in sorted(n for n in ar.names if n.startswith('SEQ_' + argv[2])):
            L, R = render(ar.sound(name), ar)
            write_wav(os.path.join(argv[3], name + '.wav'), L, R)
            print('%-22s %.2f s' % (name, len(L) / OUT_RATE))
        return 0
    if cmd == 'match':
        return match(argv[1], argv[2], int(argv[3]) if len(argv) > 3 else 8000)
    print(__doc__)
    return 2


def match(folder, capture, rate):
    import numpy as np
    v = np.fromfile(capture, dtype=np.int16).astype(np.float64)

    def load(path):
        with wave.open(path, 'rb') as w:
            n, ch, sr = w.getnframes(), w.getnchannels(), w.getframerate()
            x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64)
        if ch == 2:
            x = x.reshape(-1, 2).mean(axis=1)
        idx = np.arange(0, len(x) - 1, sr / rate)
        return np.interp(idx, np.arange(len(x)), x)

    for fn in sorted(os.listdir(folder)):
        if not fn.endswith('.wav'):
            continue
        x = load(os.path.join(folder, fn))
        x = x - x.mean()
        if np.linalg.norm(x) < 1:
            continue
        W = len(x)
        nfft = 1 << int(np.ceil(np.log2(len(v) + W)))
        c = np.fft.irfft(np.fft.rfft(v, nfft) * np.conj(np.fft.rfft(x, nfft)), nfft)[:len(v) - W]
        cs = np.concatenate([[0], np.cumsum(v * v)])
        e = np.sqrt(np.maximum(cs[W:len(v)] - cs[:len(v) - W], 1e-9)) * np.linalg.norm(x)
        r = c / np.maximum(e, 0.05 * np.sqrt(np.mean(v * v) * W) * np.linalg.norm(x))
        hits = []
        order = np.argsort(-r)
        for i in order[:2000]:
            if r[i] < 0.6 or len(hits) >= 6:
                break
            if all(abs(i - j) > W for j, _ in hits):
                hits.append((i, r[i]))
        if hits:
            print('%-26s %s' % (fn[:-4], '  '.join('%.2fs r=%.2f' % (i / rate, rr) for i, rr in sorted(hits))))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
