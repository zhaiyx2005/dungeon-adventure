# -*- coding: utf-8 -*-
"""把复核截图拼成联版图（contact sheet），带标题条。

按"套"组织：一套 = 一组同批次的复核截图（rev8 / rev9 / ...）。
每格上方是标题条，下方是原图（左对齐、不拉伸）。

仅用 PIL，跑在 envs/default 那个 python 下。

用法：
    python tools/_make_sheet.py              # 生成全部套
    python tools/_make_sheet.py rev9         # 只生成某一套
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

SRC = r"E:\goodot_work\地牢冒险记\preview"

# 套名 → (输出文件名, [(截图文件名, 中文标题), ...])
SHEETS = {
    "rev8": ("rev8_contact_sheet.png", [
        ("rev8_deck_pool.png", "① 卡组整备：卡池自动换行，无横向拖动"),
        ("rev8_ladder_locked.png", "② 层级直达：第2-5层锁定（未通关）"),
        ("rev8_ladder_unlocked.png", "③ 层级直达：第2层已通关 → 解锁"),
        ("rev8_payoff_locked.png", "④ 联合卡前置不足 → 手牌压暗不可拖"),
        ("rev8_payoff_ready.png", "⑤ 前置齐备 → 联合卡常亮可打出"),
        ("rev8_combo_fired.png", "⑥ 打出联合卡：横幅 + 全体伤害"),
        ("rev8_combo_after.png", "⑦ 发动后部件槽清空、本回合作废"),
        ("rev8_cardface.png", "⑧ 卡面：组件「共鸣」/ 本体「联合」"),
    ]),
    "rev9": ("rev9_contact_sheet.png", [
        ("rev9_splash.png", "① 开屏页：进入即播标题 BGM"),
        ("rev9_menu.png", "② 主菜单：BGM 不重头播，设置项已启用"),
        ("rev9_settings_default.png", "③ 游戏设置面板：初始音量"),
        ("rev9_settings_tuned.png", "④ 拖动滑杆：主85% 乐35% 效65%"),
        ("rev9_settings_muted.png", "⑤ 静音勾选：Master 实测 0.0000"),
        ("rev9_battle.png", "⑥ 战斗场景：一轮打击触发 6 段音效"),
    ]),
}

# 单独输出的整图（不进联版图）
EXTRA = [
    ("_audio_probe.png", "_audio_probe.png"),
]

COLS = 2
PAD = 12
BAR = 34
BG = (24, 26, 32)
BAR_BG = (48, 52, 62)
FG = (240, 240, 240)

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\msyhbd.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
]


def load_font(size):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()


def build(items, out_name):
    cells = []
    for name, title in items:
        path = os.path.join(SRC, name)
        if not os.path.exists(path):
            print("MISSING: %s" % path)
            continue
        cells.append((Image.open(path).convert("RGB"), title))
    if not cells:
        print("no input images for %s" % out_name)
        return None

    cw = max(im.width for im, _ in cells)
    ch = max(im.height for im, _ in cells)
    rows = (len(cells) + COLS - 1) // COLS
    W = PAD + COLS * (cw + PAD)
    H = PAD + rows * (ch + BAR + PAD)

    sheet = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(sheet)
    font = load_font(18)

    for idx, (im, title) in enumerate(cells):
        r, c = divmod(idx, COLS)
        x = PAD + c * (cw + PAD)
        y = PAD + r * (ch + BAR + PAD)
        draw.rectangle([x, y, x + cw, y + BAR], fill=BAR_BG)
        draw.text((x + 10, y + 8), title, fill=FG, font=font)
        sheet.paste(im, (x, y + BAR))

    out = os.path.join(SRC, out_name)
    sheet.save(out)
    print("OK %s  %dx%d  cells=%d" % (out, W, H, len(cells)))
    return out


def main():
    want = sys.argv[1] if len(sys.argv) > 1 else None

    if want is None:
        # 复刻一份音频素材拼图（它本身已经是拼图，直接确保存在）
        for src_name, out_name in EXTRA:
            src = os.path.join(SRC, src_name)
            print(("EXISTS " if os.path.exists(src) else "MISSING ") + src)

    for key, (out_name, items) in SHEETS.items():
        if want is not None and key != want:
            continue
        build(items, out_name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
