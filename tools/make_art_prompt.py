# -*- coding: utf-8 -*-
"""拼装像素插画的完整提示词。

风格块只在**这一个文件**里写一份，主体描述放 `tools/art_prompts.json`。
这样"改风格"和"改主体"解耦：调整风格不会被逐条改提示词漏掉，
批量重出也只需要换一次风格块。

用法：
    python tools/make_art_prompt.py fireball          # 卡面（1536x1024）
    python tools/make_art_prompt.py --unit boar       # 单位立绘（1024x1024）
    python tools/make_art_prompt.py --item health_potion   # 道具图标（1536x1024）
    python tools/make_art_prompt.py --bg guild_hall   # 场景背景（1536x1024）
    python tools/make_art_prompt.py --all --unit      # 打印全部单位提示词
    python tools/make_art_prompt.py --all --tsv       # 打印 id<TAB>size<TAB>prompt
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROMPTS = os.path.join(ROOT, "tools", "art_prompts.json")

## 风格块 —— 9-26 按用户参考图定稿。
## 关键：**不要**再写 dark fantasy / atmospheric haze / dramatic rim lighting，
## 那会生成灰暗低饱和的图（实测主体饱和度只有 0.23–0.35，而用户参考图是 0.85）。
STYLE = ("16-bit pixel art {noun} in classic JRPG style, vivid saturated colors, "
         "clean flat color areas with 3-tone shading, crisp 1-pixel dark outline, "
         "no dithering, no texture noise, bright cheerful palette")

CARD_TAIL = ("Centered composition filling the frame, simple dark stone background "
             "with a soft glow. No text, no letters, no numbers, no watermark, "
             "no logo, no frame, no border, no UI overlay.")

UNIT_TAIL = ("Full body, centered, isolated on a flat solid pure magenta background, "
             "no cast shadow, no ground, no scenery. No text, no letters, no numbers, "
             "no watermark, no logo, no frame, no border.")

## 道具图标：物体本身要**斜置且铺满画面**。
## 因为道具卡的图片区是横向的（约 1.47:1），竖着摆的剑会缩得又细又小；
## 斜置后主体包围盒接近横向，contain 进图片区才能拿满可用空间。
## 另外必须显式排除"人/手/穿戴"——否则模型很容易画成一个拿着剑的角色。
ITEM_TAIL = ("The object lies diagonally across the frame at a three-quarter angle, "
             "filling most of the frame, a single object, centered, "
             "isolated on a flat solid pure magenta background, "
             "no character, no hands, no person, not worn, no cast shadow, "
             "no ground, no scenery. No text, no letters, no numbers, "
             "no watermark, no logo, no frame, no border.")

## 场景背景：**全幅场景**，不出现角色，中心留出让 UI 压上去的安静区。
## 背景是铺在界面底下的，所以两点必须写：
##   * 不要角色 —— 否则会有人物盯着你看，而且和界面上的立绘/卡面打架
##   * 中心别太花 —— 深色文字压在浅色 scrim 上，底图太闹会读不出来
BG_TAIL = ("Wide establishing shot, full-bleed background art. "
           "No characters, no people, no creatures, no text, no letters, no numbers, "
           "no watermark, no logo, no frame, no border, no UI overlay, no HUD. "
           "Composition calm and uncluttered in the centre so interface elements "
           "stay readable on top of it.")

CARD_SIZE = "1536x1024"
UNIT_SIZE = "1024x1024"
ITEM_SIZE = "1536x1024"
BG_SIZE = "1536x1024"

## kind → (名词, 收尾块, 尺寸)。加新的一类素材只改这张表 + art_prompts.json。
KINDS = {
    "card": ("illustration", CARD_TAIL, CARD_SIZE),
    "item": ("item icon", ITEM_TAIL, ITEM_SIZE),
    "unit": ("character sprite", UNIT_TAIL, UNIT_SIZE),
    "bg": ("landscape illustration", BG_TAIL, BG_SIZE),
}


def build(kind: str, subject: str) -> str:
    noun, tail, _size = KINDS[kind]
    return "%s. Subject: %s. %s" % (STYLE.format(noun=noun), subject, tail)


def size_for(kind: str) -> str:
    return KINDS[kind][2]


def ids_of(table: dict) -> list:
    """取某个分类下真正的 id —— 跳过 `_comment` 这类说明键。
    不清掉的话 `--all` 会把说明文字也当成一个 id 去查表。"""
    return [k for k in table.keys() if not k.startswith("_")]


def load() -> dict:
    with io.open(PROMPTS, encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*", help="要打印的 id")
    ap.add_argument("--unit", action="store_true", help="按单位立绘处理（默认卡面）")
    ap.add_argument("--item", action="store_true", help="按道具图标处理")
    ap.add_argument("--bg", action="store_true", help="按场景背景处理")
    ap.add_argument("--all", action="store_true", help="打印该类全部")
    ap.add_argument("--tsv", action="store_true", help="输出 id<TAB>size<TAB>prompt")
    args = ap.parse_args()

    picked = [k for k, on in (("unit", args.unit), ("item", args.item), ("bg", args.bg)) if on]
    if len(picked) > 1:
        print("--unit / --item / --bg 只能选一个", file=sys.stderr)
        return 2
    kind = picked[0] if picked else "card"

    data = load()
    table = data.get(kind, {})

    if args.all:
        ids = ids_of(table)
    else:
        ids = args.ids

    missing = [i for i in ids if i not in table]
    if missing:
        print("清单里没有：%s" % ", ".join(missing), file=sys.stderr)
        return 1
    if not ids:
        print("用法：python tools/make_art_prompt.py --all [--unit|--item|--bg] [--tsv]")
        return 0

    for i in ids:
        p = build(kind, table[i])
        if args.tsv:
            print("%s\t%s\t%s" % (i, size_for(kind), p))
        else:
            print("### %s  (%s)" % (i, size_for(kind)))
            print(p)
            print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
