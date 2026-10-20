#!/usr/bin/env python3
"""バルカン連邦の国旗 (TGA) を生成する。PIL 不要。
使い方: python3 tools/make_flags.py  (mod ルートで実行)
"""
import os, struct, math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZES = {"": (82, 52), "medium": (41, 26), "small": (10, 7)}

BLUE = (20, 60, 140); WHITE = (240, 240, 240); RED = (200, 30, 40)
GOLD = (235, 185, 40); BLACK = (25, 25, 25); DARKRED = (140, 20, 30); GREEN = (20, 110, 60)

def star(nx, ny, cx=0.5, cy=0.5, r=0.22):
    """正規化座標 (nx,ny) が五芒星の内側か（偶奇判定）"""
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.42
        pts.append((cx + rr * math.cos(ang) * 52 / 82, cy + rr * math.sin(ang)))
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]; xj, yj = pts[j]
        if (yi > ny) != (yj > ny) and nx < (xj - xi) * (ny - yi) / (yj - yi + 1e-9) + xi:
            inside = not inside
        j = i
    return inside

def tricolor(nx, ny, top, mid, bot):
    return top if ny < 1/3 else (mid if ny < 2/3 else bot)

def design(variant):
    def px(nx, ny):
        if variant in ("", "neutrality"):
            base = tricolor(nx, ny, BLUE, WHITE, RED)
            return GOLD if star(nx, ny) else base
        if variant == "democratic":
            base = tricolor(nx, ny, BLUE, WHITE, RED)
            return BLUE if star(nx, ny) else base
        if variant == "fascism":
            base = tricolor(nx, ny, DARKRED, WHITE, DARKRED)
            return BLACK if star(nx, ny) else base
        if variant == "communism":
            return GOLD if star(nx, ny, 0.3, 0.5, 0.3) else RED
        if variant.startswith("kingdom"):
            # 王国：三色＋金星＋金の王冠帯（上端）
            base = tricolor(nx, ny, BLUE, WHITE, RED)
            if ny < 0.08:
                return GOLD
            return GOLD if star(nx, ny) else base
        if variant.startswith("republic"):
            # 共和国：三色＋白星（青地に白縁）
            base = tricolor(nx, ny, BLUE, WHITE, RED)
            return BLUE if star(nx, ny, 0.5, 0.5, 0.26) and not star(nx, ny, 0.5, 0.5, 0.18) else (WHITE if star(nx, ny, 0.5, 0.5, 0.18) and ny >= 1/3 and ny < 2/3 else base)
        if variant.startswith("greater"):
            sub = variant[len("greater"):].lstrip("_")
            if sub == "communism":
                return GOLD if star(nx, ny, 0.5, 0.5, 0.34) else RED
            border = nx < 0.04 or nx > 0.96 or ny < 0.06 or ny > 0.94
            if border:
                return GOLD
            if sub == "fascism":
                base = tricolor(nx, ny, DARKRED, WHITE, DARKRED)
                return BLACK if star(nx, ny, 0.5, 0.5, 0.3) else base
            base = tricolor(nx, ny, BLUE, WHITE, RED)
            return GOLD if star(nx, ny, 0.5, 0.5, 0.3) else base
        return GOLD if star(nx, ny) else tricolor(nx, ny, BLUE, WHITE, RED)
    return px

def write_tga(path, w, h, fn):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 24, 0x20)  # 0x20 = 左上原点
    data = bytearray()
    for y in range(h):
        for x in range(w):
            r, g, b = fn((x + 0.5) / w, (y + 0.5) / h)
            data += bytes((b, g, r))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(header + data)

VARIANTS = ["", "neutrality", "democratic", "fascism", "communism",
            "greater", "greater_neutrality", "greater_democratic", "greater_fascism", "greater_communism",
            "kingdom", "kingdom_neutrality", "republic", "republic_democratic"]

if __name__ == "__main__":
    for v in VARIANTS:
        name = "BLK" + ("_" + v if v else "")
        for sub, (w, h) in SIZES.items():
            out = os.path.join(ROOT, "gfx", "flags", sub, name + ".tga")
            write_tga(out, w, h, design(v))
            print("wrote", os.path.relpath(out, ROOT))
