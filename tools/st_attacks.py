"""Super Training's balloon attacks, from the game's own course data, as numbers for PlayNav.

Reads a decrypted Alpha Sapphire / Omega Ruby card image (.cci) and writes data/training_attacks.lua:
every course's balloons (phases) with their looping attack scripts, the steps, the volleys and
projectiles they fire, and the bitbots. Only numbers go in (no art, no text).

GARCs (DllSparring.cro's loader at 0x8300, ArcIDs 0x75..0x7e in order):
  a/1/1/7 courses (32 B): u16 +0 level, +2 seconds, +0xc + 4k phase id k (ffff none)
  a/1/1/8 phases (236 B): +0 species, +2 target, +4 f32 balloon scale, +8 f32 script rate (units a
          frame), +0xc damage, +0x18 sway, +0xb0 f32 middle height, +0xe4 f32 yaw,
          +0x10 list A, +0x19 / +0x1a / +0x1b / +0x1c second-form test (0 score left %, 1 time %,
          2 never) and thresholds, +0x20 f32 rate B, +0x24 damage B, +0x28 list B, +0xd6 bit record
  a/1/1/9 bit records (216 B): +2 hp, +0xc shot damage, +0x10 list (1 = fires)
  a/1/2/0 steps (36 B): +0 cmd (0 wait, 2 timed routine, 3 bits, 84.. volley cmd - 84), +2 telegraph,
          +4 pose, +6 s16 pose -> fire (-1 = the pose's fire key), +8 s16 recovery, +0xc count
          (cmd 2 frames, cmd 3 bits), +0x1c f32 cmd 2's target turn a frame, +0x18 extra repeats, +0x1a units between, +0x20 warning mark
  a/1/2/2 step lists (10 x 12 B): u16 +8 step id, ffff ends; loops
  a/1/2/5 volleys (244 B): u16 +0 shots (<= 10), +4 + 24j: u16 projectile, u16 frames to the next,
          f32 launch dx, dy, f32 aim yaw, pitch (degrees), u16 aim at the trainee's x, y
  a/1/2/6 projectiles (64 B): f32 +0 speed a frame, +8 / +0xc / +0x10 hit semi-axes, +0x14 / +0x18
          y wave freq / amp, +0x1c / +0x20 x wave, +0x24 / +0x28 y / x amp growth a frame, +0x34
          phase, +0x38 / +0x3c y / x homing k
The final course's line is the version's (a/1/1/7 row 31): Alpha Sapphire phases 40-42 / 31 (the
Larvitar line), Omega Ruby 43-45 / 32 (the Aron line, its row's only difference; both lines'
phases are on either card).

  python tools/st_attacks.py <card.cci> [out.lua]
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import garc_dump as G  # noqa: E402
import romfs_extract as R  # noqa: E402

# a/1/1/7 row -> PlayNav's course id
ROWS = {
    2: "lv1_spa", 3: "lv1_hp", 4: "lv1_atk", 5: "lv1_spd", 6: "lv1_spe", 7: "lv1_def",
    8: "lv2_spa", 9: "lv2_hp", 10: "lv2_atk", 11: "lv2_spd", 12: "lv2_spe", 13: "lv2_def",
    14: "lv3_spa", 15: "lv3_hp", 16: "lv3_atk", 17: "lv3_spd", 18: "lv3_spe", 19: "lv3_def",
    20: "secret_01", 21: "secret_02", 22: "secret_03", 23: "secret_04", 24: "secret_05",
    25: "secret_06", 26: "secret_07", 27: "secret_08", 28: "secret_09", 29: "secret_10",
    30: "secret_11", 31: "secret_12",
}
FINALE_AS = [40, 41, 42, 31]
FINALE_OR = [43, 44, 45, 32]


def u16(b, o): return struct.unpack_from("<H", b, o)[0]
def s16(b, o): return struct.unpack_from("<h", b, o)[0]
def f32(b, o): return struct.unpack_from("<f", b, o)[0]


def garc_entries(blob):
    _ver, off, entries = G.parse_garc(blob)
    out = []
    for ent in entries:
        j, s, e, _l = ent[0]
        raw = blob[off + s:off + e]
        dec = G.lz_decode(raw) if raw[:1] == b"\x11" else None
        out.append(dec or raw)
    return out


def read_card(path):
    img = R.Image(path)
    fs = R.open_romfs(img)
    want = {"a/1/1/7", "a/1/1/8", "a/1/1/9", "a/1/2/0", "a/1/2/1", "a/1/2/2", "a/1/2/3", "a/1/2/5", "a/1/2/6"}
    files = {}
    for p, off, length in R.walk(fs):
        if p in want:
            files[p] = garc_entries(img.read(off, length))
    missing = want - set(files)
    if missing:
        raise SystemExit("not in the card: %s" % ", ".join(sorted(missing)))
    return files


def num(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e9:
            return str(int(v))
        return ("%.6g" % v)
    return str(v)


def lua(v, ind=""):
    if isinstance(v, dict):
        items = ["%s = %s" % (k if k.isidentifier() else "[%r]" % k, lua(x)) for k, x in v.items()]
        return "{ " + ", ".join(items) + " }"
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    if isinstance(v, str):
        return '"%s"' % v
    return num(v)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    out = argv[2] if len(argv) > 2 else os.path.join(os.path.dirname(HERE), "data", "training_attacks.lua")
    F = read_card(argv[1])
    rows, phases_b, bits_b = F["a/1/1/7"], F["a/1/1/8"], F["a/1/1/9"]
    steps_b, lists_b, vol_b, proj_b = F["a/1/2/0"], F["a/1/2/2"], F["a/1/2/5"], F["a/1/2/6"]

    courses, phases, lists, steps, volleys, projs, bits = {}, {}, {}, {}, {}, {}, {}

    def take_list(i):
        if i in lists or i == 0xFFFF:
            return
        b = lists_b[i]
        ids = []
        for k in range(10):
            s = u16(b, 12 * k + 8)
            if s == 0xFFFF:
                break
            ids.append(s)
        lists[i] = ids
        for s in ids:
            take_step(s)

    def take_step(i):
        if i in steps:
            return
        b = steps_b[i]
        st = {"cmd": u16(b, 0), "warn": u16(b, 2), "pose": u16(b, 4), "fire": s16(b, 6),
              "recover": s16(b, 8), "count": u16(b, 0xc), "repeats": u16(b, 0x18),
              "repeatGap": u16(b, 0x1a), "mark": u16(b, 0x20)}
        if st["cmd"] == 2:
            # the shield: +0x1c its target's turn in degrees a frame (0xbacc -> 0xe670)
            st["spin"] = f32(b, 0x1c)
        steps[i] = st
        if st["cmd"] >= 84:
            take_volley(st["cmd"] - 84)

    def take_volley(i):
        if i in volleys:
            return
        b = vol_b[i]
        shots = []
        for j in range(min(10, u16(b, 0))):
            o = 4 + 24 * j
            p = u16(b, o)
            shots.append({"p": p, "next": u16(b, o + 2), "dx": f32(b, o + 4), "dy": f32(b, o + 8),
                          "yaw": f32(b, o + 12), "pitch": f32(b, o + 16), "aimX": u16(b, o + 20),
                          "aimY": u16(b, o + 22)})
            take_proj(p)
        volleys[i] = shots

    def take_proj(i):
        if i in projs:
            return
        b = proj_b[i]
        projs[i] = {"speed": f32(b, 0), "sx": f32(b, 8), "sy": f32(b, 0xc), "sz": f32(b, 0x10),
                    "freqY": f32(b, 0x14), "ampY": f32(b, 0x18), "freqX": f32(b, 0x1c), "ampX": f32(b, 0x20),
                    "growY": f32(b, 0x24), "growX": f32(b, 0x28), "phase": f32(b, 0x34),
                    "homeY": f32(b, 0x38), "homeX": f32(b, 0x3c)}

    def take_phase(i):
        if i in phases:
            return
        b = phases_b[i]
        ph = {"species": u16(b, 0), "target": u16(b, 2), "rate": f32(b, 8), "damage": u16(b, 0xc),
              "list": u16(b, 0x10), "formIn": b[0x19], "formInPct": b[0x1a], "formOut": b[0x1b],
              "formOutPct": b[0x1c], "rateB": f32(b, 0x20), "damageB": u16(b, 0x24), "listB": u16(b, 0x28),
              # the balloon in the game's 3D space (DllSparring.cro): +4 f32 uniform scale (0x1774;
              # it grows to 1.5x as it fills, 0x122e4), +0x18 sway on (12 sin 2t, 6 sin t, 0x11b58),
              # +0xb0 its middle's height in model units (x the scale; 0x127b0), +0xe4 yaw degrees
              "scale": f32(b, 4), "sway": b[0x18], "midY": f32(b, 0xb0), "yaw": f32(b, 0xe4)}
        bit = u16(b, 0xd6)
        if bit != 0xFFFF:
            bb = bits_b[bit]
            bits[bit] = {"hp": u16(bb, 2), "damage": u16(bb, 0xc), "list": u16(bb, 0x10)}
            ph["bits"] = bit
        phases[i] = ph
        take_list(ph["list"])
        if ph["formIn"] in (0, 1):
            take_list(ph["listB"])

    for row, cid in ROWS.items():
        b = rows[row]
        ids = [u16(b, 0xC + 4 * k) for k in range(4)]
        ids = [x for x in ids if x != 0xFFFF]
        courses[cid] = ids
        for x in ids:
            take_phase(x)
    # both finales whichever card it is: secret_12 Alpha Sapphire's, secret_12_omega Omega Ruby's
    courses["secret_12"] = FINALE_AS
    courses["secret_12_omega"] = FINALE_OR
    for x in FINALE_AS + FINALE_OR:
        take_phase(x)

    def block(name, table):
        lines = ["%s = {" % name]
        for k in sorted(table, key=lambda k: (str(type(k)), k)):
            key = ("[%d]" % k) if isinstance(k, int) else k
            lines.append("  %s = %s," % (key, lua(table[k])))
        lines.append("},")
        return "\n".join(lines)

    text = "\n".join([
        "-- generated by tools/st_attacks.py from the game's course data (GARC a/1/1/7 .. a/1/2/6, read",
        "-- by DllSparring.cro): the balloons' attack scripts as numbers. src/training/attacks.lua runs them.",
        "-- courses: id -> phase ids (one a balloon, in order; secret_12_omega = Omega Ruby's finale line).",
        "-- Units: the game's (the trainee on a sphere 240 out from the balloon); script times in units of",
        "-- the phase's rate a frame; volley gaps in frames; 30 frames a second.",
        "return {",
        block("courses", courses),
        block("phases", phases),
        block("lists", lists),
        block("steps", steps),
        block("volleys", volleys),
        block("projectiles", projs),
        block("bits", bits),
        "}",
        "",
    ])
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print("%s: %d courses, %d phases, %d lists, %d steps, %d volleys, %d projectiles, %d bit records, %d bytes" % (
        out, len(courses), len(phases), len(lists), len(steps), len(volleys), len(projs), len(bits), len(text)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
