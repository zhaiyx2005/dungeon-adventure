# -*- coding: utf-8 -*-
"""把 AI 生成的原始插画处理成游戏可用的**像素画素材**。

原始图是 1024–2304 宽的"看起来像像素画"的插画，直接缩到卡面会把像素块糊掉
（源图 128 个色块映射到 84 个显示像素 → 像素感消失）。所以必须重采样到
**接近显示尺寸的原生网格**，再限色板，才能得到真正的像素画。

处理步骤：
  1. 裁掉右下角的生成水印
  2. （仅单位图 / 道具图）把背景抠成透明
  3. **裁到主体包围盒**（用户给的图主体常常只占画面 1/3，不裁就白扔分辨率）
  4. 用 BOX（面积平均）重采样到目标原生网格 —— 这是"像素化"的正确滤波器
  5. 量化到 N 色调板，恢复受限调色板的观感
  6. 单位图 / 道具图把 alpha 二值化（像素画不该有半透明边）

四类素材（kind）：
  * card —— 卡面插画，**带背景**，cover 铺满 96×75
  * unit —— 单位立绘，透明底，contain 96×96
  * item —— 道具图标，透明底，contain 100×68
  * bg   —— 场景背景，**带背景**，cover 铺满 1280×720（不缩到像素网格，见下方常量注释）

清单文件：`tools/art_sources.json`。每条可以写成两种形式：
  * 字符串      —— 相对 `RAW_DIR` 的文件名（自生成素材的老写法）
  * 对象        —— { "src": ..., "base": "raw"|"asset", "key": "magenta"|"auto",
                     "dir": "art_items" }

    base="asset" 指 `E:\\goodot_work\\地牢冒险记\\图片素材\\...`（用户自己生成的图）
    key="auto"   用于**底色不是洋红**的图（例：豆包生成的奶油底），
                 走"从边界向内、按邻域相似度洪泛"，不依赖特定底色
    dir          放到 `preview/` 下哪个子目录（分批生成的结果分开放）

用法：
    python tools/process_art.py                     # 处理清单里的全部
    python tools/process_art.py --only fireball     # 只处理指定 id
    python tools/process_art.py --preview           # 额外拼一张对比图（原图 vs 处理结果）
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "tools", "art_sources.json")
RAW_DIR = os.path.join(os.path.dirname(ROOT), "preview", "art_raw")
## 用户自己生成的美术素材根目录（豆包生成 / 无水印开屏图 等都在这里）
ASSET_DIR = os.path.join(os.path.dirname(ROOT), "图片素材")
OUT_DIR = os.path.join(ROOT, "assets", "images", "art")
# 目标原生网格（像素块数）。这些值必须贴合游戏里的实际显示尺寸，
# 否则要么像素块被缩掉（太大），要么糊成一片（太小）。
#   card：城镇战斗卡 / 卡牌大全的图片区实测 96×75；手牌 84×66
#   unit：战斗单位视图的立绘带 128×88
#   item：人物/物品卡的图片区实测 —— 归一化 0.107–0.891 × 0.130–0.508，
#         卡体 128×179 → 100×68。**必须与显示尺寸一致**：
#         CardFrame 的插画是 KEEP_ASPECT_COVERED，原生网格比例不一致就会被裁掉边角，
#         而道具（剑/弓/甲）被裁掉一头一尾就废了。
#   bg  ：场景背景，铺满整个 1280×720 逻辑分辨率。**不缩到像素网格** ——
#         背景是给人"看氛围"的，缩成 320×180 再放大 4 倍会变成一堵花花绿绿的墙，
#         和 1:1 显示的小 UI 文字严重打架。保持高分辨率 + 适度限色即可。
CARD_SIZE = (96, 75)
UNIT_SIZE = (96, 96)
ITEM_SIZE = (100, 68)
BG_SIZE = (1280, 720)
## 需要抠底 + 裁主体 + contain 的类别（立绘与道具图标）
CUTOUT_KINDS = ("unit", "item")
SIZE_BY_KIND = {"card": CARD_SIZE, "unit": UNIT_SIZE, "item": ITEM_SIZE, "bg": BG_SIZE}
## 裁到主体后留的边距比例（避免顶天立地）
TRIM_MARGIN = 0.04

WATERMARK_CROP = 0.06      # 底部裁掉的比例（水印所在区）
PALETTE_COLORS = 40        # 16-bit 观感的受限调色板
## 背景要用更大的色板：占满全屏、还要承载光影过渡，40 色会糊成色块
BG_PALETTE_COLORS = 96
DESPILL_STRENGTH = 0.75    # 溢色去除强度

## 输出子目录。分开放是因为 id 命名空间互相独立 ——
## `iron_helm` 是道具而 `iron_wall` 是卡牌，早晚会撞名。
## 背景单独放 `assets/images/bg/`（与 `splash/` 平级）：它是"铺满全屏的场景图"，
## 和挂在卡面上的物件插画不是一类东西。
OUT_SUBDIR = {"card": "card", "unit": "unit", "item": "item"}
BG_OUT_SUBDIR = "bg"


def out_dir_for(kind: str) -> str:
    if kind == "bg":
        return os.path.join(os.path.dirname(OUT_DIR), BG_OUT_SUBDIR)
    return os.path.join(OUT_DIR, OUT_SUBDIR.get(kind, kind))


def resolve_src(spec) -> tuple[str, str]:
    """把清单条目解析成 (绝对路径, 键控方式)。

    对象形式支持 `dir` 子目录，用来分批次放生成结果
    （例：dir="art_raw_v2" 放改了风格提示词后的重发批次）。
    """
    if isinstance(spec, str):
        return os.path.join(RAW_DIR, spec), "magenta"
    base = spec.get("base", "raw")
    path = spec["src"]
    if not os.path.isabs(path):
        root = ASSET_DIR if base == "asset" else RAW_DIR
        sub = spec.get("dir", "")
        if sub and base == "raw":
            root = os.path.join(os.path.dirname(RAW_DIR), sub)
        path = os.path.join(root, path)
    return path, spec.get("key", "magenta")


# ---------------------------------------------------------------------------
# 1. 裁水印
# ---------------------------------------------------------------------------

def crop_watermark(im: Image.Image) -> Image.Image:
    w, h = im.size
    return im.crop((0, 0, w, int(round(h * (1.0 - WATERMARK_CROP)))))


# ---------------------------------------------------------------------------
# 2. 抠洋红底
# ---------------------------------------------------------------------------

def _magenta_amount(r: int, g: int, b: int) -> int:
    """洋红程度：R、B 都明显高于 G。纯洋红 (255,0,255) → 255。

    用 min() 而不是平均值：这样蓝色（R 低）和绿色（R、B 都低）都不会被误判，
    只有"红蓝双高"的洋红系才得分。
    """
    return min(r - g, b - g)


# 洪泛参数
SEED_MAGENTA = 12      # 边界种子像素的最低洋红程度（magenta 模式）
KEEP_MAGENTA = 10      # 扩散时邻居必须仍满足的洋红程度（防止漏进主体）
LOCAL_TOL = 46         # 邻居与当前像素的最大单通道差（允许背景渐变/暗角）
FRINGE_DILATE = 2      # 去溢色作用带宽（像素）

# auto 模式（底色不是洋红时用）——按"与边界底色的距离"判定
AUTO_SEED_TOL = 30     # 边界种子：与取样底色的最大单通道差
## 洋红抠底覆盖低于这个比例就认为"模型没听指示、底不是洋红"，自动改用 auto 重试。
## 实测触发过：goblin_chief 出成了白底，洋红键控对白色完全失效
## （白色 R=G=B → 洋红程度 0 → 连种子都取不到），最后 93.8% 像素保持不透明。
MAGENTA_MIN_COVER = 0.35
## 围堵孤岛的判据：被主体包住、从边界洪泛走不到、但颜色仍是**纯背景色**的像素。
## 洋红模式下用这个阈值（纯洋红 255 → 阈值 100 只吃掉接近纯洋红的）。
## 注意不能设太低：巫王的长袍、命运之眼的紫宝石都是"紫"，把阈值压到 70 以下就开始啃主体。
HARD_MAGENTA = 100
# 扩散上限。这个值必须**大于投影离底色的距离**，否则：
#   投影挡住洪泛 → 腿间那块被围住的底色永远抠不掉（实测就是这样）。
# 豆包这套图的奶油底 (255,250,192) 与投影 #CC9054 的距离是 108，所以放到 126。
# 不能无限放大的原因：主体的橙色外衣离底色 132，再往上就会啃到衣服。
AUTO_BORDER_CAP = 126
# 邻居与当前像素的最大单通道差。奶油 → 投影 的单步差是 51，
# 所以必须 ≥ 55 才能跨过去；投影 → 腿间奶油 同样是 51。
AUTO_LOCAL_TOL = 56
# 投影兜底剔除：投影不完全是"底色 × k"（实测 G/B 压得比 R 多），
# 残差判别会漏掉大部分，所以只当补充手段，主要靠上面两条容差让洪泛穿过去。
SHADOW_K_MIN = 0.45
SHADOW_K_MAX = 0.985
SHADOW_RESID = 22


def _sample_border_color(px, sw, sh) -> tuple[int, int, int]:
    """取四条边中点附近的均值当底色基准（比只取四角更稳，能容忍角部渐变）。"""
    pts = []
    for x in (sw // 8, sw // 2, sw * 7 // 8):
        pts.append(px[x, 1])
        pts.append(px[x, sh - 2])
    for y in (sh // 8, sh // 2, sh * 7 // 8):
        pts.append(px[1, y])
        pts.append(px[sw - 2, y])
    n = float(len(pts))
    return (int(sum(p[0] for p in pts) / n),
            int(sum(p[1] for p in pts) / n),
            int(sum(p[2] for p in pts) / n))


def key_background(im: Image.Image, mode: str = "magenta",
                   work: int = 448) -> tuple[Image.Image, float]:
    """把背景抠成透明，返回 (RGBA, 背景覆盖率)。

    **必须从四条边界向内洪泛**，不能只按颜色阈值全局判定：
    ① 背景常常是带暗角/渐变的，全局阈值会在画面边缘留下一条不透明的边；
    ② 主体内部可能有和背景同色的像素（例：白袍），全局阈值会把它们一起抠掉。

    两种判据：
      * `magenta` —— 洋红程度 `min(R-G, B-G)`。用于我们自己发的"纯洋红底"提示词。
                     洪泛之后再补一道严格色阈兜底（见 `_kill_magenta_residual`），
                     否则弓 / 吊坠 / 王冠这类**闭合成环**的物体环内会留一块洋红。
      * `auto`    —— 先采样边界底色，按"离底色的距离 + 与邻域像素的差"扩散。
                     用于底色不定的图（例：豆包生成的奶油底 #FFFAC0）。

    1024² 以上的逐像素 Python 循环太慢，所以先降到 `work` 宽做键控，
    再把 alpha 用 NEAREST 升回原尺寸（后续重采样本来就要缩小）。
    """
    from collections import deque

    w, h = im.size
    scale = work / float(w)
    sw, sh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
    small = im.convert("RGB").resize((sw, sh), Image.BOX)
    px = small.load()

    bg_mask = bytearray(sw * sh)          # 1 = 背景
    q: deque = deque()

    if mode == "auto":
        base = _sample_border_color(px, sw, sh)
        print("      边界底色取样 rgb=(%d, %d, %d)" % base)

        def dist_base(c) -> int:
            return max(abs(c[0] - base[0]), abs(c[1] - base[1]), abs(c[2] - base[2]))

        def is_seed(c) -> bool:
            return dist_base(c) <= AUTO_SEED_TOL

        def is_bg_like(c) -> bool:
            return dist_base(c) <= AUTO_BORDER_CAP

        local_tol = AUTO_LOCAL_TOL
    else:
        def is_seed(c) -> bool:
            return _magenta_amount(c[0], c[1], c[2]) >= SEED_MAGENTA

        def is_bg_like(c) -> bool:
            return _magenta_amount(c[0], c[1], c[2]) >= KEEP_MAGENTA

        local_tol = LOCAL_TOL

    def try_seed(x: int, y: int) -> None:
        i = y * sw + x
        if bg_mask[i]:
            return
        if is_seed(px[x, y]):
            bg_mask[i] = 1
            q.append((x, y))

    for x in range(sw):
        try_seed(x, 0)
        try_seed(x, sh - 1)
    for y in range(sh):
        try_seed(0, y)
        try_seed(sw - 1, y)

    while q:
        x, y = q.popleft()
        c0 = px[x, y]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if nx < 0 or ny < 0 or nx >= sw or ny >= sh:
                continue
            ni = ny * sw + nx
            if bg_mask[ni]:
                continue
            c = px[nx, ny]
            if not is_bg_like(c):
                continue
            if max(abs(c[0] - c0[0]), abs(c[1] - c0[1]), abs(c[2] - c0[2])) > local_tol:
                continue
            bg_mask[ni] = 1
            q.append((nx, ny))

    filled = sum(bg_mask)

    if mode == "auto":
        # 投影也算进"背景覆盖率"里回报给调用方
        filled += _kill_cast_shadow(px, bg_mask, sw, sh, base)
    else:
        # 兜住"被主体围死、洪泛走不到"的洋红孤岛（弓/吊坠/王冠的环内）
        filled += _kill_magenta_residual(px, bg_mask, sw, sh)

    if mode == "magenta":
        _despill_magenta(px, bg_mask, sw, sh)

    alpha = Image.new("L", (sw, sh), 255)
    ap = alpha.load()
    for y in range(sh):
        for x in range(sw):
            if bg_mask[y * sw + x]:
                ap[x, y] = 0

    total = float(sw * sh)
    out = small.convert("RGBA")
    out.putalpha(alpha)
    return out.resize((w, h), Image.NEAREST), filled / total


def key_background_smart(im: Image.Image, mode: str = "magenta",
                         work: int = 448) -> Image.Image:
    """抠底 + 自动回退。

    模型偶尔会无视"纯洋红底"的指示（实测 goblin_chief 出成了白底），
    此时洋红判据完全失效。所以：洋红模式覆盖不足就自动改用 `auto` 重试，
    覆盖更多就用 `auto` 的结果。

    这样"模型听不听话"不再影响管线 —— 不需要人工发现哪张抠失败了。
    """
    out, cov = key_background(im, mode, work)
    print("      洪泛抠掉 %.1f%% 的像素%s" % (cov * 100.0,
          "（magenta）" if mode == "magenta" else "（auto，含投影）"))
    if mode == "magenta" and cov < MAGENTA_MIN_COVER:
        print("      ⚠ 洋红覆盖仅 %.1f%% < %.0f%%，底色不是洋红 → 改用 auto 重试"
              % (cov * 100.0, MAGENTA_MIN_COVER * 100.0))
        out2, cov2 = key_background(im, "auto", work)
        print("      auto 覆盖 %.1f%%" % (cov2 * 100.0))
        if cov2 > cov:
            return out2
    return out


def _kill_magenta_residual(px, bg_mask, sw: int, sh: int) -> int:
    """洪泛没覆盖到、但颜色仍是**接近纯洋红**的像素，一并判为背景。

    为什么必须单独兜一道：洪泛只能从画布边界向内走，而
    **弓（弓臂 + 弓弦闭合成环）、吊坠、王冠、护符**这类物体中间的背景
    从边界根本走不到 —— 那块背景被主体轮廓围死，会原样留在成品里。
    实测踩过：short_bow / storm_bow / silver_pendant / victory_crown /
    wooden_charm 的中间都留了一块洋红，贴到深色卡面上像一块污渍。

    ⚠️ 这里**不能**用"从边界出发、沿非背景像素能否走到"来判孤岛：
    主体常常贴着画布边缘，孤岛经主体 4 邻域就能连到边界，会被误判成"可达"
    （victory_crown 就是这么漏掉的）。直接上严格色阈最简单可靠。

    严格色阈只对**洋红模式**用：洋红是提示词里的标记色，
    真实主体不会用接近纯洋红 (255,0,255) 的颜色，所以不会误伤；
    而 auto 模式的底色是"图里本来就有的颜色"（例：奶油底），
    主体内部完全可能有同色块（例：米色长袍），全局阈会打洞 —— 那边保持不动。
    """
    killed = 0
    for y in range(sh):
        for x in range(sw):
            i = y * sw + x
            if bg_mask[i]:
                continue
            r, g, b = px[x, y]
            if _magenta_amount(r, g, b) >= HARD_MAGENTA:
                bg_mask[i] = 1
                killed += 1
    return killed


def _kill_cast_shadow(px, bg_mask, sw: int, sh: int,
                      base: tuple[int, int, int]) -> int:
    """把"底色被乘性压暗"的像素也标成背景 —— 也就是脚下的投影。

    判别：求 `k = dot(c, base) / dot(base, base)`，再看 `|c - base*k|` 的残差。
    * 投影（底色 × 0.86 之类的暗黄）→ k 落在区间内、残差极小 → 命中
    * 橙色外衣 (216,132,60) → k≈0.61 但 base*k 与它差 60 以上 → 不会命中
    * 深棕靴子 → k≈0.28，低于下限 → 不会命中

    比"按连通性丢掉小岛"稳：投影和靴子常常是连在一起的，连通性分不开。
    """
    bb = float(base[0] * base[0] + base[1] * base[1] + base[2] * base[2])
    if bb <= 0.0:
        return 0
    killed = 0
    for y in range(sh):
        for x in range(sw):
            i = y * sw + x
            if bg_mask[i]:
                continue
            r, g, b = px[x, y]
            k = (r * base[0] + g * base[1] + b * base[2]) / bb
            if k < SHADOW_K_MIN or k > SHADOW_K_MAX:
                continue
            resid = max(abs(r - base[0] * k), abs(g - base[1] * k), abs(b - base[2] * k))
            if resid <= SHADOW_RESID:
                bg_mask[i] = 1
                killed += 1
    return killed


def _despill_magenta(px, bg_mask, sw: int, sh: int) -> None:
    """把主体边缘的洋红溢出压回与 G 同档。

    只处理"背景外侧 FRINGE_DILATE 像素内"的主体边，避免影响主体内部
    本来就合法的紫色（例：巫王的长袍）。
    """
    fringe = bytearray(sw * sh)
    for y in range(sh):
        for x in range(sw):
            if bg_mask[y * sw + x]:
                continue
            hit = False
            for dy in range(-FRINGE_DILATE, FRINGE_DILATE + 1):
                for dx in range(-FRINGE_DILATE, FRINGE_DILATE + 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < sw and 0 <= ny < sh and bg_mask[ny * sw + nx]:
                        hit = True
                        break
                if hit:
                    break
            if hit:
                fringe[y * sw + x] = 1

    for y in range(sh):
        for x in range(sw):
            i = y * sw + x
            r, g, b = px[x, y]
            if bg_mask[i]:
                nr = int(r + (g - r) * DESPILL_STRENGTH)
                nb = int(b + (g - b) * DESPILL_STRENGTH)
                px[x, y] = (max(0, nr), g, max(0, nb))
            elif fringe[i]:
                amt = _magenta_amount(r, g, b)
                if amt > 4:
                    k = min(1.0, amt / 60.0) * DESPILL_STRENGTH
                    px[x, y] = (int(r + (g - r) * k), g, int(b + (g - b) * k))


# ---------------------------------------------------------------------------
# 3+4. 裁主体 / 拟合 / 像素化 / 限色板
# ---------------------------------------------------------------------------

def trim_subject(im: Image.Image, margin: float = TRIM_MARGIN) -> Image.Image:
    """按 alpha 包围盒裁到主体。

    用户给的图主体常常只占画面 1/3（例：主角人物图主体 823×1313，画布 2304×1728），
    不裁就直接缩放等于把 2/3 的分辨率扔在透明边上。
    """
    bbox = im.split()[3].getbbox()
    if bbox is None:
        return im
    w, h = im.size
    mx = int(round((bbox[2] - bbox[0]) * margin))
    my = int(round((bbox[3] - bbox[1]) * margin))
    box = (max(0, bbox[0] - mx), max(0, bbox[1] - my),
           min(w, bbox[2] + mx), min(h, bbox[3] + my))
    return im.crop(box)


def fit_cover(im: Image.Image, size: tuple[int, int]) -> Image.Image:
    """等比放大到铺满 size，再居中裁掉多余（卡面用：插画本来就带背景，铺满最好看）。"""
    sw, sh = im.size
    tw, th = size
    r = max(tw / float(sw), th / float(sh))
    nw, nh = max(tw, int(round(sw * r))), max(th, int(round(sh * r)))
    im = im.resize((nw, nh), Image.BOX)
    l, t = (nw - tw) // 2, (nh - th) // 2
    return im.crop((l, t, l + tw, t + th))


def fit_contain(im: Image.Image, size: tuple[int, int]) -> Image.Image:
    """等比缩小到完整装进 size，居中放在透明画布上（单位立绘用：不能被裁头脚）。"""
    sw, sh = im.size
    tw, th = size
    r = min(tw / float(sw), th / float(sh))
    nw, nh = max(1, int(round(sw * r))), max(1, int(round(sh * r)))
    im = im.resize((nw, nh), Image.BOX)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.paste(im, ((tw - nw) // 2, (th - nh) // 2))
    return canvas


def pixelate(target: Image.Image, colors: int,
             binary_alpha: bool) -> Image.Image:
    """限色板（+ 单位图 alpha 二值化）。重采样已在 fit_* 里用 BOX 做过。"""
    if binary_alpha:
        a = target.split()[3]
        a = a.point(lambda v: 255 if v >= 128 else 0)
        target = target.convert("RGB").convert("RGBA")
        target.putalpha(a)

    # 限色板：只用不透明像素统计调色板，否则透明区的黑色会污染调色板
    alpha = target.split()[3]
    rgb_only = target.convert("RGB")
    if binary_alpha:
        opaque = [p for p, av in zip(rgb_only.getdata(), alpha.getdata()) if av > 0]
        fill = opaque[0] if opaque else (0, 0, 0)
        quant_src = Image.new("RGB", target.size, fill)
        quant_src.paste(rgb_only, (0, 0), alpha)
    else:
        quant_src = rgb_only

    q = quant_src.quantize(colors=max(2, min(256, colors)),
                           method=Image.MEDIANCUT, dither=Image.NONE)
    result = q.convert("RGBA")
    result.putalpha(alpha)
    return result


# ---------------------------------------------------------------------------

def process_one(kind: str, ident: str, spec, with_loop: bool = False) -> dict | None:
    src, key_mode = resolve_src(spec)
    if not os.path.exists(src):
        print("  跳过 %s：找不到 %s" % (ident, src))
        return None

    im = Image.open(src).convert("RGB")
    print("  %s (%s) 原始 %dx%d  key=%s" % (ident, kind, im.width, im.height, key_mode))

    im = crop_watermark(im)
    if kind in CUTOUT_KINDS:
        im = key_background_smart(im, key_mode)
        before = im.size
        im = trim_subject(im)
        print("      裁到主体 %dx%d -> %dx%d" % (before[0], before[1], im.width, im.height))

    size = SIZE_BY_KIND[kind]
    if kind in CUTOUT_KINDS:
        fitted = fit_contain(im, size)
    else:
        fitted = fit_cover(im.convert("RGBA"), size)
    colors = BG_PALETTE_COLORS if kind == "bg" else PALETTE_COLORS
    out = pixelate(fitted, colors, binary_alpha=(kind in CUTOUT_KINDS))

    os.makedirs(out_dir_for(kind), exist_ok=True)
    dst = os.path.join(out_dir_for(kind), ident + ".png")
    out.save(dst)

    info = {
        "id": ident, "kind": kind, "size": "%dx%d" % out.size,
        "colors": len(set(out.convert("RGB").getdata())),
        "bytes": os.path.getsize(dst),
    }
    if kind in CUTOUT_KINDS:
        a = out.split()[3]
        bbox = a.getbbox()
        covers = sum(1 for v in a.getdata() if v > 0) / float(out.width * out.height)
        info["subject_ratio"] = round(covers, 3)
        if bbox:
            info["subject_box"] = "%dx%d" % (bbox[2] - bbox[0], bbox[3] - bbox[1])
    print("      -> %s  %s  色数≈%d  %dB%s"
          % (dst, info["size"], info["colors"], info["bytes"],
             "  主体占比 %.1f%%  主体框 %s" % (info["subject_ratio"] * 100,
                                              info.get("subject_box", "?"))
             if kind in CUTOUT_KINDS else ""))
    return info


def _checker(size: tuple[int, int], cell: int = 8,
             c1=(58, 58, 68), c2=(78, 78, 90)) -> Image.Image:
    im = Image.new("RGB", size, c1)
    dr = ImageDraw.Draw(im)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if ((x // cell) + (y // cell)) % 2 == 0:
                dr.rectangle([x, y, x + cell - 1, y + cell - 1], fill=c2)
    return im


def make_preview(rows: list[dict]) -> None:
    """原图（缩略）与处理结果（放大到 4×NEAREST）并排，方便肉眼确认像素感。"""
    if not rows:
        return
    SCALE = 4
    CELL_W, CELL_H = 300, 230
    PAD, BAR = 10, 22
    COLS = 2
    n = len(rows)
    rr = (n + COLS - 1) // COLS
    W = PAD + COLS * (CELL_W * 2 + PAD) + PAD
    H = PAD + rr * (CELL_H + BAR + PAD)
    sheet = Image.new("RGB", (W, H), (22, 24, 30))

    font = None
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        if os.path.exists(p):
            font = ImageFont.truetype(p, 13)
            break
    dr = ImageDraw.Draw(sheet)

    for i, row in enumerate(rows):
        raw = Image.open(row["src"]).convert("RGB")
        dst = Image.open(os.path.join(out_dir_for(row["kind"]),
                                      row["id"] + ".png")).convert("RGBA")
        r, c = divmod(i, COLS)
        x0 = PAD + c * (CELL_W * 2 + PAD)
        y0 = PAD + r * (CELL_H + BAR + PAD)

        dr.rectangle([x0, y0, x0 + CELL_W * 2, y0 + BAR], fill=(50, 54, 64))
        dr.text((x0 + 6, y0 + 4), "%s (%s)  处理结果 ×%d  原图" % (row["id"], row["kind"], SCALE),
                fill=(240, 240, 240), font=font)

        # 透明底要铺棋盘再 alpha 合成；直接 paste 会忽略 alpha 把透明区贴成暗块
        big = dst.resize((dst.width * SCALE, dst.height * SCALE), Image.NEAREST)
        board = _checker(big.size, cell=max(4, SCALE * 2))
        board.paste(big, (0, 0), big)
        board.thumbnail((CELL_W, CELL_H), Image.NEAREST)
        sheet.paste(board, (x0, y0 + BAR))

        raw_thumb = raw.copy()
        raw_thumb.thumbnail((CELL_W, CELL_H), Image.LANCZOS)
        sheet.paste(raw_thumb, (x0 + CELL_W, y0 + BAR))

    path = os.path.join(os.path.dirname(ROOT), "preview", "_art_processed_review.png")
    sheet.save(path)
    print("对比图 -> %s" % path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None, help="只处理指定 id（逗号分隔）")
    ap.add_argument("--preview", action="store_true", help="额外输出对比图")
    args = ap.parse_args()

    if not os.path.exists(MANIFEST):
        print("缺少清单：%s" % MANIFEST)
        return 1
    with open(MANIFEST, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    only = set(args.only.split(",")) if args.only else None
    rows = []
    done = 0
    for kind in ("card", "item", "unit", "bg"):
        for ident, spec in manifest.get(kind, {}).items():
            if only is not None and ident not in only:
                continue
            info = process_one(kind, ident, spec)
            if info:
                rows.append({"id": ident, "kind": kind,
                             "src": resolve_src(spec)[0]})
                done += 1

    print("-" * 58)
    print("共处理 %d 个素材 -> %s" % (done, OUT_DIR))
    if args.preview:
        make_preview(rows)
    return 0 if done else 1


if __name__ == "__main__":
    sys.exit(main())
