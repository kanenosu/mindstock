#!/usr/bin/env python3
"""
バルカン連邦 MOD：ゲーム本体のファイルから以下を生成する。

  1. history/states/*.txt      ユーゴ・ブルガリア・アルバニア領ステートの所有者を BLK に書き換えた上書きファイル
  2. history/countries/YUG|BUL|ALB - *.txt   旧三国の history から oob 行を除去した上書きファイル
  3. history/units/BLK_1936.txt   tools/BLK_1936.oob.template の @PLACEHOLDER を実在のプロヴィンスIDに置換
  4. history/units/BLK_1936_naval*.txt   旧三国の海軍編成を連邦のものとして統合（存在する場合）
  5. history/units/BLK_1936_air.txt は作らず、空軍は旧三国の air_wings を BLK_1936.txt に統合する

使い方:
  python3 tools/generate_from_game.py "C:/Program Files (x86)/Steam/steamapps/common/Hearts of Iron IV"

生成物はゲームの著作物（Paradox Interactive）を含むため、MOD を再配布する際は各自の責任で扱うこと。
"""
import os, re, sys, glob, shutil

MOD_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OLD_TAGS = ("YUG", "BUL", "ALB")
NEW_TAG = "BLK"

# プレースホルダ → (ステートID, 優先する勝利点の順位)  最大の victory_points を首都とみなす
CITY_STATES = {
    "@BELGRADE": 107, "@KRAGUJEVAC": 107, "@NIS": 108, "@NOVI_SAD": 45,
    "@SOFIA": 48, "@PLOVDIV": 212, "@PLEVEN": 801, "@VARNA": 211,
    "@ZAGREB": 109, "@LJUBLJANA": 102, "@SARAJEVO": 104, "@SKOPJE": 106,
    "@CETINJE": 105, "@TIRANA": 44, "@SPLIT": 103,
}
# 2番目の勝利点を使うもの（同じステートに2師団置く場合は別都市に）
SECOND_VP = {"@KRAGUJEVAC"}


def read(path):
    with open(path, "r", encoding="utf-8-sig", errors="replace") as f:
        return f.read()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8-sig", newline="\n") as f:
        f.write(text)


def strip_comments(text):
    return re.sub(r"#.*", "", text)


def top_level_history_block(text):
    """state = { ... history = { ... } ... } の history ブロック本文を返す（最初の history のみ）"""
    m = re.search(r"\bhistory\s*=\s*\{", text)
    if not m:
        return None, None, None
    start = m.end()
    depth = 1
    i = start
    while i < len(text) and depth > 0:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    return text[start:i - 1], start, i - 1


def dated_block_spans(body):
    """history 本文中の 1939.1.1 = { ... } などの日付ブロック範囲を返す"""
    spans = []
    for m in re.finditer(r"\b\d{4}\.\d{1,2}\.\d{1,2}\s*=\s*\{", body):
        s = m.end(); depth = 1; i = s
        while i < len(body) and depth > 0:
            if body[i] == "{": depth += 1
            elif body[i] == "}": depth -= 1
            i += 1
        spans.append((m.start(), i))
    return spans


def in_spans(pos, spans):
    return any(a <= pos < b for a, b in spans)


def process_state_file(path):
    text = read(path)
    body, bstart, bend = top_level_history_block(text)
    if body is None:
        return None
    clean = strip_comments(body)
    spans = dated_block_spans(clean)
    # 1936 時点（日付ブロック外）の owner を探す
    owner = None
    for m in re.finditer(r"\bowner\s*=\s*([A-Z]{3})", clean):
        if not in_spans(m.start(), spans):
            owner = m.group(1)
            break
    if owner not in OLD_TAGS:
        return None

    new_body = body
    # 日付ブロック外の owner / controller を書き換え、add_core_of = BLK を追加
    def repl_outside(pattern, repl, s):
        out = []; last = 0
        cl = strip_comments(s); sp = dated_block_spans(cl)
        for m in re.finditer(pattern, s):
            if in_spans(m.start(), sp):
                continue
            out.append(s[last:m.start()]); out.append(m.expand(repl)); last = m.end()
        out.append(s[last:])
        return "".join(out)

    new_body = repl_outside(r"\bowner\s*=\s*(YUG|BUL|ALB)\b", r"owner = BLK\n\t\tadd_core_of = BLK", new_body)
    new_body = repl_outside(r"\bcontroller\s*=\s*(YUG|BUL|ALB)\b", r"controller = BLK", new_body)
    # 日付ブロック内（1939 年など）の旧三国への所有権変更も連邦に揃える
    new_body = re.sub(r"\b(owner|controller)\s*=\s*(YUG|BUL|ALB)\b", r"\1 = BLK", new_body)
    new_text = text[:bstart] + new_body + text[bend:]
    header = ("# バルカン連邦 MOD による上書き（tools/generate_from_game.py が生成）\n"
              "# 元の所有者: %s\n" % owner)
    return header + new_text


def generate_states(game_dir):
    src = os.path.join(game_dir, "history", "states")
    n = 0
    for path in sorted(glob.glob(os.path.join(src, "*.txt"))):
        out = process_state_file(path)
        if out is None:
            continue
        write(os.path.join(MOD_ROOT, "history", "states", os.path.basename(path)), out)
        n += 1
    print("states overridden:", n)


def generate_countries(game_dir):
    src = os.path.join(game_dir, "history", "countries")
    for tag in OLD_TAGS:
        for path in glob.glob(os.path.join(src, tag + " - *.txt")):
            text = read(path)
            # oob / set_naval_oob / set_air_oob 行をコメントアウト（軍は BLK 側で定義）
            text = re.sub(r"^(\s*)(oob|set_naval_oob|set_air_oob)\s*=", r"\1# [BLK] \2 =", text, flags=re.M)
            # if ブロックの中の set_naval_oob も同様（1 行ずつ対象）
            header = "# バルカン連邦 MOD による上書き：%s は 1936 年に連邦へ統合済み（軍編成は BLK_1936 へ移管）\n" % tag
            write(os.path.join(MOD_ROOT, "history", "countries", os.path.basename(path)), header + text)
            print("country overridden:", os.path.basename(path))


def state_victory_points(game_dir):
    """state_id → [(vp, province), ...] 降順"""
    result = {}
    for path in glob.glob(os.path.join(game_dir, "history", "states", "*.txt")):
        text = strip_comments(read(path))
        m = re.search(r"\bid\s*=\s*(\d+)", text)
        if not m:
            continue
        sid = int(m.group(1))
        vps = [(int(v), int(p)) for p, v in re.findall(r"victory_points\s*=\s*\{\s*(\d+)\s+(\d+)\s*\}", text)]
        if not vps:
            provs = re.search(r"provinces\s*=\s*\{([^}]*)\}", text)
            if provs:
                ids = [int(x) for x in provs.group(1).split()]
                if ids:
                    vps = [(0, ids[0])]
        vps.sort(reverse=True)
        result[sid] = vps
    return result


def generate_oob(game_dir):
    vps = state_victory_points(game_dir)
    tmpl = read(os.path.join(MOD_ROOT, "tools", "BLK_1936.oob.template"))
    missing = []
    for ph, sid in CITY_STATES.items():
        lst = vps.get(sid) or []
        idx = 1 if ph in SECOND_VP and len(lst) > 1 else 0
        if not lst:
            missing.append(ph)
            prov = vps.get(107, [(0, 0)])[0][1]
        else:
            prov = lst[idx][1]
        tmpl = tmpl.replace(ph, str(prov))
    if missing:
        print("warning: no province found for", missing, "(placed in Belgrade instead)")

    # 旧三国の air_wings を統合
    wings = []
    for tag in OLD_TAGS:
        p = os.path.join(game_dir, "history", "units", tag + "_1936.txt")
        if not os.path.exists(p):
            continue
        text = read(p)
        m = re.search(r"\bair_wings\s*=\s*\{", text)
        if not m:
            continue
        s = m.end(); depth = 1; i = s
        while i < len(text) and depth > 0:
            if text[i] == "{": depth += 1
            elif text[i] == "}": depth -= 1
            i += 1
        inner = text[s:i - 1]
        inner = re.sub(r'owner\s*=\s*"?(YUG|BUL|ALB)"?', 'owner = "BLK"', inner)
        wings.append("\t# from %s\n%s" % (tag, inner))
    if wings:
        tmpl += "\nair_wings = {\n" + "\n".join(wings) + "\n}\n"
    write(os.path.join(MOD_ROOT, "history", "units", "BLK_1936.txt"), tmpl)
    print("wrote history/units/BLK_1936.txt")


def generate_naval(game_dir):
    """旧三国の海軍 OOB（mtg / legacy 両方）を統合して BLK 用に出力"""
    units_dir = os.path.join(game_dir, "history", "units")
    for suffix in ("_naval_mtg", "_naval_legacy", "_naval"):
        blocks = []
        for tag in OLD_TAGS:
            p = os.path.join(units_dir, "%s_1936%s.txt" % (tag, suffix))
            if not os.path.exists(p):
                continue
            text = read(p)
            m = re.search(r"\bunits\s*=\s*\{", text)
            if not m:
                continue
            s = m.end(); depth = 1; i = s
            while i < len(text) and depth > 0:
                if text[i] == "{": depth += 1
                elif text[i] == "}": depth -= 1
                i += 1
            inner = text[s:i - 1]
            inner = re.sub(r'owner\s*=\s*"?(YUG|BUL|ALB)"?', "owner = BLK", inner)
            blocks.append("\t# from %s\n%s" % (tag, inner))
        if blocks:
            out = "# バルカン連邦 海軍編成（旧三国の編成を統合）\nunits = {\n" + "\n".join(blocks) + "\n}\n"
            write(os.path.join(MOD_ROOT, "history", "units", "BLK_1936%s.txt" % suffix), out)
            print("wrote history/units/BLK_1936%s.txt" % suffix)


def patch_country_history_for_navy():
    """BLK の history に海軍 OOB 読み込みを追記（生成済みなら）"""
    path = os.path.join(MOD_ROOT, "history", "countries", "BLK - Balkan Federation.txt")
    text = read(path)
    if "set_naval_oob" in text:
        return
    has_mtg = os.path.exists(os.path.join(MOD_ROOT, "history", "units", "BLK_1936_naval_mtg.txt"))
    has_legacy = os.path.exists(os.path.join(MOD_ROOT, "history", "units", "BLK_1936_naval_legacy.txt"))
    if not (has_mtg or has_legacy):
        return
    add = "\n# 海軍編成（generate_from_game.py が追記）\n"
    if has_mtg and has_legacy:
        add += ('if = {\n\tlimit = { has_dlc = "Man the Guns" }\n\tset_naval_oob = "BLK_1936_naval_mtg"\n}\n'
                'else = {\n\tset_naval_oob = "BLK_1936_naval_legacy"\n}\n')
    elif has_mtg:
        add += 'set_naval_oob = "BLK_1936_naval_mtg"\n'
    else:
        add += 'set_naval_oob = "BLK_1936_naval_legacy"\n'
    write(path, text + add)
    print("patched BLK history with naval oob")


def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    game_dir = sys.argv[1]
    if not os.path.isdir(os.path.join(game_dir, "history", "states")):
        print("error: history/states が見つかりません:", game_dir); sys.exit(2)
    generate_states(game_dir)
    generate_countries(game_dir)
    generate_oob(game_dir)
    generate_naval(game_dir)
    patch_country_history_for_navy()
    print("done.")


if __name__ == "__main__":
    main()
