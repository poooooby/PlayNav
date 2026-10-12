# clyt.py <blob> <clyt offset> [--json out.json]: print a BCLYT's pane tree with absolute
# centre positions (screen space: origin top-left, y down; the layout is 320x240), sizes,
# materials and their first texture.
import sys, struct, json


def cstr(b, p, n=None):
    e = b.index(b"\0", p) if n is None else p + n
    return b[p:e].split(b"\0")[0].decode("latin-1")


def parse(b, base):
    assert b[base:base + 4] == b"CLYT"
    hsize = struct.unpack_from("<H", b, base + 6)[0]
    fsize = struct.unpack_from("<I", b, base + 12)[0]
    p, end = base + hsize, base + fsize
    textures, materials = [], []
    root, stack, last = None, [], None
    W = H = None
    groups = []
    while p < end:
        magic = b[p:p + 4]
        size = struct.unpack_from("<I", b, p + 4)[0]
        if size == 0:
            break
        d = p + 8
        if magic == b"lyt1":
            W, H = struct.unpack_from("<ff", b, d + 4)
        elif magic == b"txl1":
            n = struct.unpack_from("<I", b, d)[0]
            for i in range(n):
                off = struct.unpack_from("<I", b, d + 4 + i * 4)[0]
                textures.append(cstr(b, d + 4 + off))
        elif magic == b"mat1":
            n = struct.unpack_from("<I", b, d)[0]
            for i in range(n):
                off = struct.unpack_from("<I", b, d + 4 + i * 4)[0]
                m = p + off
                name = cstr(b, m, 20)
                flags = struct.unpack_from("<I", b, m + 20 + 4 + 24)[0]
                ntex = flags & 3
                texs = []
                for t in range(ntex):
                    ti = struct.unpack_from("<H", b, m + 20 + 4 + 24 + 4 + t * 4)[0]
                    texs.append(textures[ti] if ti < len(textures) else ti)
                materials.append((name, texs))
        elif magic in (b"pan1", b"pic1", b"txt1", b"wnd1", b"bnd1"):
            flags, origin, alpha = b[d], b[d + 1], b[d + 2]
            name = cstr(b, d + 4, 16)
            tx, ty, tz = struct.unpack_from("<fff", b, d + 28)
            rx, ry, rz = struct.unpack_from("<fff", b, d + 40)
            sx, sy = struct.unpack_from("<ff", b, d + 52)
            w, h = struct.unpack_from("<ff", b, d + 60)
            node = {"type": magic.decode()[:3], "name": name, "visible": bool(flags & 1), "origin": origin,
                    "alpha": alpha, "t": (tx, ty), "rz": rz, "s": (sx, sy), "size": (w, h), "children": []}
            if magic == b"pic1":
                cols = [tuple(b[d + 68 + i * 4: d + 72 + i * 4]) for i in range(4)]
                mi = struct.unpack_from("<H", b, d + 84)[0]
                node["mat"] = materials[mi][0] if mi < len(materials) else mi
                node["tex"] = materials[mi][1] if mi < len(materials) else []
                node["colors"] = cols
            if magic == b"wnd1":
                node["mat"] = "(window)"
            if stack:
                stack[-1]["children"].append(node)
            else:
                root = node
            last = node
        elif magic == b"pas1":
            stack.append(last)
        elif magic == b"pae1":
            stack.pop()
        elif magic == b"grp1":
            # name[16], member count, then the member pane names (16 bytes each)
            n = struct.unpack_from("<H", b, d + 16)[0]
            groups.append({"name": cstr(b, d, 16), "panes": [cstr(b, d + 20 + 16 * i, 16) for i in range(n)]})
        p += size
    return W, H, root, groups


def walk(node, W, H, px=0.0, py=0.0, psx=1.0, psy=1.0, depth=0, out=None, visible=True):
    # translations are relative to the parent's centre, y up; scales multiply
    x = px + node["t"][0] * psx
    y = py + node["t"][1] * psy
    sx, sy = psx * node["s"][0], psy * node["s"][1]
    w, h = node["size"][0] * sx, node["size"][1] * sy
    # origin: horizontal = origin % 3 (0 left, 1 centre, 2 right), vertical = origin // 3 (0 top..)
    ox, oy = node["origin"] % 3, node["origin"] // 3
    cx = x + (0.5 - ox * 0.5) * w
    cy = y - (0.5 - oy * 0.5) * h
    vis = visible and node["visible"]
    sxs, sys_ = W / 2 + cx, H / 2 - cy
    row = dict(depth=depth, type=node["type"], name=node["name"], vis=vis, cx=round(sxs, 1), cy=round(sys_, 1),
               w=round(w, 1), h=round(h, 1), rz=node["rz"], alpha=node["alpha"],
               mat=node.get("mat"), tex=node.get("tex"), colors=node.get("colors"),
               flipx=node["s"][0] < 0, flipy=node["s"][1] < 0)
    out.append(row)
    for c in node["children"]:
        walk(c, W, H, x, y, sx, sy, depth + 1, out, vis)
    return out


if __name__ == "__main__":
    b = open(sys.argv[1], "rb").read()
    W, H, root, groups = parse(b, int(sys.argv[2]))
    rows = walk(root, W, H, out=[])
    if "--json" in sys.argv:
        json.dump(dict(W=W, H=H, rows=rows, groups=groups), open(sys.argv[sys.argv.index("--json") + 1], "w"), indent=1)
    print("layout", W, H)
    for r in rows:
        tex = ",".join(str(t) for t in (r["tex"] or []))
        print("%s%s %s%s c(%.0f,%.0f) %gx%g%s%s %s %s" % ("  " * r["depth"], r["type"], r["name"], "" if r["vis"] else " [hidden]",
              r["cx"], r["cy"], r["w"], r["h"], " rz%g" % r["rz"] if r["rz"] else "",
              (" flip" + ("x" if r["flipx"] else "") + ("y" if r["flipy"] else "")) if (r["flipx"] or r["flipy"]) else "",
              r["mat"] or "", tex))
