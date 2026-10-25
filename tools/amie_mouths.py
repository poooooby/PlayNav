"""Where each species' mouth is on its front sprite, for Pokemon-Amie's feeding (data/amie_mouths.lua).

usage:
  python tools/amie_mouths.py sheets <atlas_index.lua> <Front dir> <out dir> [per-sheet]
      contact sheets of every species 1..1025's Gen 9 Pack front sprite, cropped to its opaque
      box and drawn large over a 0..10 grid (x across, y down, the box's edges 0 and 10), with
      its National Dex number: someone reads each mouth off them (index.json lists the cells)
  python tools/amie_mouths.py sheets-pics <pics dir> <out dir> <dex,dex,...> [per-sheet]
      the same from the pictures PLAY draws (tests/drivers/front_dump_probe.lua's <dex>.png),
      for the species listed (those whose pose differs from the Gen 9 Pack's)
  python tools/amie_mouths.py check <out dir> <answers.txt>
      the answers ("dex x y", grid units) drawn back as red dots on the sheets (check_*.png)
  python tools/amie_mouths.py lua <answers.txt> <pics dir> > data/amie_mouths.lua
      the answers as fractions of the opaque box (0..1, x from the left, y from the top), and
      the side the head leans to (head_side: the middle of the opaque pixels in the box's top
      HEAD_BAND, as a fraction across): PLAY measures the same on the sprite it draws and turns
      the mouth over when that faces the other way (a sprite mod's art can be mirrored)

The sprites' names come from g9-battle-sprites-gen3's data/atlas_index.lua (name -> dex); the
Gen 9 Pack's files use Essentials' ids (NIDORANfE, MRMIME), matched loosely. The mouths were
read on the Gen 9 Pack's fronts, then again on the pictures PLAY draws (g9-battle-sprites-gen3's
still pose) for the species whose silhouette differs (box-normalised overlap under 0.85: 329 of
1025); the head side is measured on the pictures PLAY draws.
"""
import json
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

CELL = 180          # a cell's picture area (px)
PAD = 26            # room for the grid's labels and the caption
SPECIAL = {'NIDORAN_F': 'NIDORANfE', 'NIDORAN_M': 'NIDORANmA'}


def species(index_path):
    """dex -> the index's base name (the shortest name with that dex)"""
    src = open(index_path, encoding='utf-8').read()
    out = {}
    for name, dex in re.findall(r'\["([A-Z0-9_]+)"\] = \{ dex = (\d+)', src):
        dex = int(dex)
        if dex not in out or len(name) < len(out[dex]):
            out[dex] = name
    return out


def sprite_file(front, name):
    for cand in (SPECIAL.get(name), name, name.replace('_', '')):
        if cand and os.path.exists(os.path.join(front, cand + '.png')):
            return os.path.join(front, cand + '.png')
    return None


def font(size):
    for f in ('arial.ttf', 'DejaVuSans.ttf'):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def sheets(index_path, front, outdir, per=16):
    names = species(index_path)
    cells, missing = [], []
    for dex in range(1, 1026):
        name = names.get(dex)
        path = name and sprite_file(front, name)
        if not path:
            missing.append((dex, name))
            continue
        cells.append((dex, name, path))
    draw_sheets(cells, outdir, per)
    print('missing', missing)


def sheets_pics(pics, outdir, dexes, per=16):
    cells = [(d, str(d), os.path.join(pics, '%d.png' % d)) for d in dexes
             if os.path.exists(os.path.join(pics, '%d.png' % d))]
    draw_sheets(cells, outdir, per)


def draw_sheets(cells, outdir, per):
    os.makedirs(outdir, exist_ok=True)
    cols = 4
    f_small, f_cap = font(11), font(14)
    index = []
    for s in range(0, len(cells), per):
        batch = cells[s:s + per]
        rows = (len(batch) + cols - 1) // cols
        W, H = cols * (CELL + 2 * PAD), rows * (CELL + 2 * PAD)
        sheet = Image.new('RGB', (W, H), (236, 236, 236))
        d = ImageDraw.Draw(sheet)
        for i, (dex, name, path) in enumerate(batch):
            im = Image.open(path).convert('RGBA')
            box = im.getbbox()
            if not box:
                continue
            crop = im.crop(box)
            bw, bh = crop.size
            k = CELL / max(bw, bh)
            dw, dh = max(1, round(bw * k)), max(1, round(bh * k))
            crop = crop.resize((dw, dh), Image.NEAREST)
            cx, cy = (i % cols) * (CELL + 2 * PAD) + PAD, (i // cols) * (CELL + 2 * PAD) + PAD
            # the box drawn at its own shape, centred in the cell; the grid over the box
            ox, oy = cx + (CELL - dw) // 2, cy + (CELL - dh) // 2
            d.rectangle([ox, oy, ox + dw, oy + dh], fill=(255, 255, 255))
            sheet.paste(crop, (ox, oy), crop)
            for g in range(11):
                gx, gy = ox + dw * g / 10, oy + dh * g / 10
                col = (120, 160, 255) if g % 5 else (60, 90, 220)
                d.line([gx, oy, gx, oy + dh], fill=col, width=1)
                d.line([ox, gy, ox + dw, gy], fill=col, width=1)
                if g % 2 == 0:
                    d.text((gx - 3, oy - 13), str(g), fill=(40, 40, 160), font=f_small)
                    d.text((ox - 14, gy - 6), str(g), fill=(40, 40, 160), font=f_small)
            d.text((cx, cy + CELL + 6), '#%d %s' % (dex, name), fill=(0, 0, 0), font=f_cap)
            index.append({'sheet': s // per, 'cell': i, 'dex': dex, 'name': name, 'box': box,
                          'draw': [ox, oy, dw, dh]})
        sheet.save(os.path.join(outdir, 'sheet_%02d.png' % (s // per)))
    json.dump(index, open(os.path.join(outdir, 'index.json'), 'w'))
    print('%d species on %d sheets' % (len(cells), (len(cells) + per - 1) // per))


HEAD_BAND = 0.35


def head_side(path):
    """the middle of the opaque pixels (alpha > 25) in the top HEAD_BAND of the opaque box,
    as a fraction of the box's width"""
    im = Image.open(path).convert('RGBA')
    box = im.getbbox()
    if not box:
        return 0.5
    x0, y0, x1, y1 = box
    a = im.getchannel('A').load()
    band = y0 + max(1, round((y1 - y0) * HEAD_BAND))
    sx = n = 0
    for y in range(y0, band):
        for x in range(x0, x1):
            if a[x, y] > 25:
                sx += x + 0.5
                n += 1
    return ((sx / n) - x0) / (x1 - x0) if n else 0.5


def answers(path):
    out = {}
    for line in open(path, encoding='utf-8'):
        m = re.match(r'\s*#?(\d+)\s+([-\d.]+)\s+([-\d.]+)', line)
        if m:
            out[int(m.group(1))] = (float(m.group(2)), float(m.group(3)))
    return out


def check(outdir, path):
    index = json.load(open(os.path.join(outdir, 'index.json')))
    got = answers(path)
    by_sheet = {}
    for c in index:
        by_sheet.setdefault(c['sheet'], []).append(c)
    for s, cs in by_sheet.items():
        im = Image.open(os.path.join(outdir, 'sheet_%02d.png' % s)).convert('RGB')
        d = ImageDraw.Draw(im)
        for c in cs:
            a = got.get(c['dex'])
            if not a:
                continue
            ox, oy, dw, dh = c['draw']
            x, y = ox + dw * a[0] / 10, oy + dh * a[1] / 10
            d.ellipse([x - 6, y - 6, x + 6, y + 6], outline=(255, 0, 0), width=3)
            d.ellipse([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill=(255, 0, 0))
        im.save(os.path.join(outdir, 'check_%02d.png' % s))
    print('%d answers over %d cells' % (len(got), len(index)))


def lua(path, pics):
    got = answers(path)
    print('-- generated by tools/amie_mouths.py: where each species\' mouth is on its Gen 9 front sprite,')
    print('-- as fractions of the sprite\'s opaque box (x from its left, y from its top), read off the')
    print('-- sprites by eye, and the side its head leans to (the middle of the opaque pixels in the')
    print('-- box\'s top %d%%, across); Pokemon-Amie holds a Poke Puff there. Numbers only.' % round(HEAD_BAND * 100))
    print('return {')
    for dex in sorted(got):
        x, y = got[dex]
        p = os.path.join(pics, '%d.png' % dex)
        hs = head_side(p) if os.path.exists(p) else 0.5
        print('  [%d] = { %.2f, %.2f, %.2f },' % (dex, x / 10, y / 10, hs))
    print('}')


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    if argv[0] == 'sheets':
        sheets(argv[1], argv[2], argv[3], int(argv[4]) if len(argv) > 4 else 16)
    elif argv[0] == 'check':
        check(argv[1], argv[2])
    elif argv[0] == 'sheets-pics':
        sheets_pics(argv[1], argv[2], [int(d) for d in argv[3].split(',') if d], int(argv[4]) if len(argv) > 4 else 16)
    elif argv[0] == 'lua':
        lua(argv[1], argv[2])
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
