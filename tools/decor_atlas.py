"""Bake Pokemon-Amie's Decor sprites into one indexed atlas (Wilds of Hoenn's colour-number trick).

The 172 cushions and objects come from a sprite page provided via The Spriters Resource
("Amie-Page.png"; attribution in assets/credits.txt): a teal grid of cells, each item's texture
at the cell's top left at its own size (data/decor_catalog.lua's w / h). CELLS below says which
cell holds which item. Each sprite is stored as COLOUR NUMBERS: 0 transparent, 1..n an entry of
that sprite's own palette; a few sprites hold more than 255 colours, so the numbers are 16-bit.
Out:
  assets/amie_decor.png   one 16-bit greyscale image, the sprites packed in shelves
  data/amie_decor.lua     { depth = 16, cells = { [id] = { x, y, w, h, pal } } }, "rrggbbaa"
src/amie/decor_art.lua expands a cell into a full-colour image the first time it is drawn.

  python tools/decor_atlas.py <Amie-Page.png>
"""
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WIDTH = 512

# the page's cells (their top-left corners) and the item each holds
CELLS = [
    (2, 2, "object/normal_heart_object"),
    (68, 2, "object/fire_heart_object"),
    (134, 2, "object/water_heart_object"),
    (200, 2, "object/electric_heart_object"),
    (266, 2, "object/grass_heart_object"),
    (2, 68, "object/ice_heart_object"),
    (68, 68, "object/fighting_heart_object"),
    (134, 68, "object/poison_heart_object"),
    (200, 68, "object/ground_heart_object"),
    (266, 68, "object/flying_heart_object"),
    (2, 134, "object/psychic_heart_object"),
    (68, 134, "object/bug_heart_object"),
    (134, 134, "object/rock_heart_object"),
    (200, 134, "object/ghost_heart_object"),
    (266, 134, "object/dragon_heart_object"),
    (2, 200, "object/dark_heart_object"),
    (68, 200, "object/steel_heart_object"),
    (134, 200, "object/fairy_heart_object"),
    (2, 266, "cushion/cocoa_treat_cushion"),
    (68, 266, "cushion/chocolate_treat_cushion"),
    (134, 266, "cushion/mint_ring_cushion"),
    (200, 266, "cushion/cream_ring_cushion"),
    (266, 266, "object/decorative_treat_object"),
    (2, 332, "cushion/blue_fire_cushion"),
    (68, 332, "cushion/red_fire_cushion"),
    (134, 332, "cushion/hot_lava_cushion"),
    (200, 332, "cushion/cooled_lava_cushion"),
    (266, 332, "object/campfire_object"),
    (2, 398, "cushion/white_seashell_cushion"),
    (68, 398, "cushion/pink_seashell_cushion"),
    (134, 398, "cushion/green_drop_cushion"),
    (200, 398, "cushion/blue_drop_cushion"),
    (266, 398, "object/sparkling_pearl_object"),
    (2, 464, "cushion/light_cushion"),
    (68, 464, "cushion/blue_light_cushion"),
    (134, 464, "cushion/shock_cushion"),
    (200, 464, "cushion/blue_shock_cushion"),
    (266, 464, "object/lightbulb_object"),
    (2, 530, "cushion/leaf_cushion"),
    (68, 530, "cushion/leaflet_cushion"),
    (134, 530, "cushion/stump_cushion"),
    (200, 530, "cushion/white_stump_cushion"),
    (266, 530, "object/flower_object"),
    (2, 596, "cushion/frozen_cushion"),
    (68, 596, "cushion/ice_chunk_cushion"),
    (134, 596, "cushion/snowball_cushion"),
    (200, 596, "cushion/ice_ball_cushion"),
    (266, 596, "object/snowman_object"),
    (2, 662, "cushion/blue_target_cushion"),
    (68, 662, "cushion/red_target_cushion"),
    (134, 662, "cushion/training_log_cushion"),
    (200, 662, "cushion/trial_log_cushion"),
    (266, 662, "object/substitute_cushion"),
    (2, 728, "cushion/rising_smoke_cushion"),
    (68, 728, "cushion/dangerous_smoke_cushion"),
    (134, 728, "cushion/green_poison_cushion"),
    (200, 728, "cushion/pink_poison_cushion"),
    (266, 728, "object/deadly_poison_object"),
    (2, 794, "cushion/deep_hole_cushion"),
    (68, 794, "cushion/shallow_hole_cushion"),
    (134, 794, "cushion/hard_ground_cushion"),
    (200, 794, "cushion/soft_ground_cushion"),
    (266, 794, "object/mysterious_cactus"),
    (2, 860, "cushion/white_feather_cushion"),
    (68, 860, "cushion/black_feather_cushion"),
    (134, 860, "cushion/blue_flag_perch"),
    (200, 860, "cushion/red_flag_perch"),
    (266, 860, "object/mysterious_eggs"),
    (2, 990, "cushion/blue_circle_cushion"),
    (68, 990, "cushion/red_circle_cushion"),
    (134, 990, "cushion/bent_spoon_cushion"),
    (200, 990, "cushion/twisted_spoon_cushion"),
    (266, 990, "object/mystery_crystal"),
    (2, 1056, "cushion/withered_leaf_cushion"),
    (68, 1056, "cushion/fallen_leaf_cushion"),
    (134, 1056, "cushion/gray_yarn_cushion"),
    (200, 1056, "cushion/yellow_yarn_cushion"),
    (266, 1056, "object/honey_object"),
    (2, 1122, "cushion/gray_rock_cushion"),
    (68, 1122, "cushion/black_rock_cushion"),
    (134, 1122, "cushion/iron_ore_cushion"),
    (200, 1122, "cushion/gold_ore_cushion"),
    (266, 1122, "object/sparkling_mineral_object"),
    (2, 1188, "cushion/ghostly_pumpkin_cushion"),
    (68, 1188, "cushion/cursed_pumpkin_cushion"),
    (134, 1188, "cushion/spooky_sheet_cushion"),
    (200, 1188, "cushion/monstrous_sheet_cushion"),
    (266, 1188, "object/will_o_the_wisp_candle"),
    (2, 1254, "cushion/dragon_hill_cushion"),
    (68, 1254, "cushion/dragon_rock_cushion"),
    (134, 1254, "cushion/blue_gem_cushion"),
    (200, 1254, "cushion/purple_gem_cushion"),
    (266, 1254, "object/dragon_castle"),
    (2, 1384, "cushion/cool_black_cushion"),
    (68, 1384, "cushion/cool_red_cushion"),
    (134, 1384, "cushion/shredded_black_cushion"),
    (200, 1384, "cushion/shredded_red_cushion"),
    (266, 1384, "object/nocturnal_chair"),
    (2, 1450, "cushion/cross_top_screw_cushion"),
    (68, 1450, "cushion/slot_top_screw_cushion"),
    (134, 1450, "cushion/iron_cushion"),
    (200, 1450, "cushion/cast_iron_cushion"),
    (266, 1450, "object/crown_object"),
    (2, 1516, "cushion/pink_arch_cushion"),
    (68, 1516, "cushion/blue_arch_cushion"),
    (134, 1516, "cushion/pretty_ball_cushion"),
    (200, 1516, "cushion/lovely_ball_cushion"),
    (266, 1516, "object/rainbow_parasol"),
    (2, 1582, "cushion/pink_egg_cushion"),
    (68, 1582, "cushion/pink_pillar_cushion"),
    (134, 1582, "object/pink_star_object"),
    (200, 1582, "object/pink_cube_object"),
    (2, 1648, "cushion/blue_egg_cushion"),
    (68, 1648, "cushion/blue_pillar_cushion"),
    (134, 1648, "object/blue_star_object"),
    (200, 1648, "object/blue_cube_object"),
    (2, 1714, "cushion/orange_egg_cushion"),
    (68, 1714, "cushion/orange_pillar_cushion"),
    (134, 1714, "object/orange_star_object"),
    (200, 1714, "object/orange_cube_object"),
    (2, 1780, "cushion/green_egg_cushion"),
    (68, 1780, "cushion/green_pillar_cushion"),
    (134, 1780, "object/green_star_object"),
    (200, 1780, "object/green_cube_object"),
    (2, 1846, "cushion/purple_egg_cushion"),
    (68, 1846, "cushion/purple_pillar_cushion"),
    (134, 1846, "object/purple_star_object"),
    (200, 1846, "object/purple_cube_object"),
    (2, 1912, "cushion/brown_egg_cushion"),
    (68, 1912, "cushion/brown_pillar_cushion"),
    (134, 1912, "object/brown_star_object"),
    (200, 1912, "object/brown_cube_object"),
    (2, 1978, "cushion/yellow_egg_cushion"),
    (68, 1978, "cushion/yellow_pillar_cushion"),
    (134, 1978, "object/yellow_star_object"),
    (200, 1978, "object/yellow_cube_object"),
    (2, 2044, "cushion/white_egg_cushion"),
    (68, 2044, "cushion/white_pillar_cushion"),
    (134, 2044, "object/white_star_object"),
    (200, 2044, "object/white_cube_object"),
    (2, 2110, "cushion/black_egg_cushion"),
    (68, 2110, "cushion/black_pillar_cushion"),
    (134, 2110, "object/black_star_object"),
    (200, 2110, "object/black_cube_object"),
    (2, 2176, "cushion/pink_cloud_cushion"),
    (68, 2176, "cushion/hot_pink_cloud_cushion"),
    (134, 2176, "object/pink_star_cloud"),
    (200, 2176, "object/peach_cloud_table"),
    (2, 2242, "cushion/blue_cloud_cushion"),
    (68, 2242, "cushion/light_blue_cloud_cushion"),
    (134, 2242, "object/blue_star_cloud"),
    (200, 2242, "object/sky_blue_cloud_table"),
    (2, 2308, "cushion/orange_cloud_cushion"),
    (68, 2308, "cushion/soft_orange_cushion"),
    (134, 2308, "object/orange_star_cloud"),
    (200, 2308, "object/orange_cloud_table"),
    (2, 2374, "cushion/polka_dot_candy_cushion"),
    (68, 2374, "cushion/polka_dot_pillar_cushion"),
    (134, 2374, "object/polka_dot_star_object"),
    (200, 2374, "object/polka_dot_cube_object"),
    (2, 2440, "cushion/punk_candy_cushion"),
    (68, 2440, "cushion/punk_pillar_cushion"),
    (134, 2440, "object/punk_star_object"),
    (200, 2440, "object/punk_cube_object"),
    (2, 2506, "cushion/checkered_candy_cushion"),
    (68, 2506, "cushion/checkered_pillar_cushion"),
    (134, 2506, "object/checkered_star_object"),
    (200, 2506, "object/checkered_cube_object"),
    (2, 2572, "cushion/homey_wooden_chair"),
    (68, 2572, "cushion/comfy_wooden_chair"),
    (134, 2572, "object/wooden_table"),
    (200, 2572, "object/wooden_bed"),
]


def sizes():
    src = open(os.path.join(ROOT, "data", "decor_catalog.lua"), encoding="utf-8").read()
    out = {}
    for m in re.finditer(r'id = "((?:cushion|object)/[^"]+)".*?w = (\d+), h = (\d+)', src):
        out[m.group(1)] = (int(m.group(2)), int(m.group(3)))
    return out


def unrip(im):
    """The page's 4-bit channels back to the game's levels: it expanded a 4-bit value n as
    n * 16 (white 240, opaque 240) where the game uses n * 17. A sprite whose every channel
    value is a multiple of 16 is such a texture throughout; one whose alpha alone is (a 4-bit
    alpha over full colour) has only its alpha put back."""
    px = list(im.getdata())
    seen = [p for p in px if p[3] > 0]
    def x16(vals): return all(v % 16 == 0 for v in vals)
    rgb = x16(c for p in seen for c in p[:3])
    alpha = x16(p[3] for p in seen)
    if not (rgb or alpha):
        return im
    up = lambda v: v + v // 16
    out = []
    for p in px:
        if p[3] == 0:
            out.append(p)
        elif rgb:
            out.append((up(p[0]), up(p[1]), up(p[2]), up(p[3]) if alpha else p[3]))
        else:
            out.append((p[0], p[1], p[2], up(p[3])))
    im = im.copy()
    im.putdata(out)
    return im


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    page = Image.open(sys.argv[1]).convert("RGBA")
    size = sizes()
    missing = sorted(set(size) - {c[2] for c in CELLS})
    if missing:
        sys.exit(f"no cell for {missing}")
    # shelves: tallest first, left to right
    items = sorted(CELLS, key=lambda c: (-size[c[2]][1], c[2]))
    places, x, y, shelf = {}, 0, 0, 0
    for _, _, id_ in items:
        w, h = size[id_]
        if x + w > WIDTH:
            x, y, shelf = 0, y + shelf, 0
        places[id_] = (x, y)
        x += w
        shelf = max(shelf, h)
    atlas = Image.new("I;16", (WIDTH, y + shelf), 0)
    rows = []
    for cx, cy, id_ in CELLS:
        w, h = size[id_]
        im = unrip(page.crop((cx, cy, cx + w, cy + h)))
        px = im.load()
        pal, index = [], {}
        ax, ay = places[id_]
        for yy in range(h):
            for xx in range(w):
                p = px[xx, yy]
                if p[3] == 0:
                    continue
                if p not in index:
                    pal.append(p)
                    index[p] = len(pal)
                atlas.putpixel((ax + xx, ay + yy), index[p])
        if len(pal) > 65535:
            sys.exit(f"{id_}: {len(pal)} colours")
        rows.append((id_, ax, ay, w, h, pal))

    png = os.path.join(ROOT, "assets", "amie_decor.png")
    atlas.save(png, optimize=True)
    lines = [
        "-- generated by tools/decor_atlas.py: Pokemon-Amie's Decor sprites in assets/amie_decor.png",
        "-- (grey value = colour number, 0 transparent) and their palettes. Art: see assets/credits.txt",
        "-- (Pokemon-Amie Decoration sprites).",
        "return {",
        "  depth = 16,",
        "  cells = {",
    ]
    for id_, ax, ay, w, h, pal in sorted(rows):
        hexes = ", ".join('"%02x%02x%02x%02x"' % p for p in pal)
        lines.append(f'    ["{id_}"] = {{ x = {ax}, y = {ay}, w = {w}, h = {h}, pal = {{ {hexes} }} }},')
    lines += ["  },", "}", ""]
    with open(os.path.join(ROOT, "data", "amie_decor.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print(f"{len(rows)} sprites; {png} {atlas.size} {os.path.getsize(png)} bytes")


if __name__ == "__main__":
    main()
