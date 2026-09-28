# -*- coding: utf-8 -*-
"""音频素材复核：数值自检 + 波形/能量拼图

听不到声音的时候，"波形形状 + 能量包络 + 循环接缝"就是可验证的替代品。

检查项：
  1. WAV 规格（采样率 / 位深 / 声道 / 时长）
  2. 电平（峰值、RMS）—— 排除静音与削波
  3. 能量包络（切成 N 段算 RMS）—— 排除"一直很响"（没有衰减）这类合成 bug
  4. 过零率（亮度代理）—— 区分低频闷响与高频脆音
  5. BGM 循环接缝：折叠后 |末样本 − 首样本| 必须很小，否则循环处会"啪"
  6. 输出 PNG：每个文件一条波形 + 能量条，一眼看完全部素材

用法：
    python tools/_probe_audio.py
"""

from __future__ import annotations

import math
import os
import struct
import sys
import wave

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")
OUT_PNG = os.path.join(os.path.dirname(ROOT), "preview", "_audio_probe.png")

BUCKETS = 12


def read_wav(path):
    with wave.open(path, "rb") as w:
        nch = w.getnchannels()
        sw = w.getsampwidth()
        sr = w.getframerate()
        nf = w.getnframes()
        raw = w.readframes(nf)
    total = nf * nch
    vals = struct.unpack("<%dh" % total, raw[: total * 2])
    # 混成单声道
    mono = [0.0] * nf
    for i in range(nf):
        s = 0
        for c in range(nch):
            s += vals[i * nch + c]
        mono[i] = s / (nch * 32768.0)
    return {
        "nch": nch, "sampwidth": sw, "sr": sr, "nf": nf,
        "mono": mono,
        "sec": nf / float(sr),
    }


def stats(d):
    m = d["mono"]
    n = d["nf"]
    peak = max((abs(v) for v in m), default=0.0)
    sq = sum(v * v for v in m)
    rms = math.sqrt(sq / max(1, n))
    # 过零率（Hz 量级）
    zc = 0
    for i in range(1, n):
        if (m[i - 1] < 0.0) != (m[i] < 0.0):
            zc += 1
    zcr = zc * d["sr"] / (2.0 * max(1, n))
    # 能量包络
    buckets = []
    step = max(1, n // BUCKETS)
    for b in range(BUCKETS):
        i0 = b * step
        i1 = min(n, i0 + step)
        if i1 <= i0:
            buckets.append(0.0)
            continue
        s = sum(v * v for v in m[i0:i1])
        buckets.append(math.sqrt(s / (i1 - i0)))
    return {"peak": peak, "rms": rms, "zcr": zcr, "buckets": buckets}


def loop_seam(d):
    """循环接缝：末样本与首样本的跳变（越小越无缝）"""
    m = d["mono"]
    if d["nf"] < 4:
        return 0.0
    return abs(m[-1] - m[0])


def draw_grid(entries, out_path):
    CW, CH = 420, 110
    WAVE_H = 74          # 波形区高度
    ENV_H = 26           # 能量条区高度（与波形区分开画，避免互相遮挡）
    COLS = 2
    PAD = 10
    BAR = 22
    rows = (len(entries) + COLS - 1) // COLS
    W = PAD + COLS * (CW + PAD)
    H = PAD + rows * (CH + BAR + PAD)
    img = Image.new("RGB", (W, H), (22, 24, 30))
    dr = ImageDraw.Draw(img)
    font = None
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        if os.path.exists(p):
            font = ImageFont.truetype(p, 13)
            break

    for idx, (name, d, st) in enumerate(entries):
        r, c = divmod(idx, COLS)
        x = PAD + c * (CW + PAD)
        y = PAD + r * (CH + BAR + PAD)
        is_bgm = name.startswith("bgm")
        title = "%s  %.2fs  pk%.2f rms%.3f zcr%.0fHz%s" % (
            name, d["sec"], st["peak"], st["rms"], st["zcr"],
            ("  seam%.4f" % loop_seam(d)) if is_bgm else "")
        dr.rectangle([x, y, x + CW, y + BAR], fill=(48, 52, 62))
        dr.text((x + 6, y + 4), title, fill=(235, 235, 235), font=font)

        n = d["nf"]
        mono = d["mono"]
        wy = y + BAR
        # --- 波形区 ---
        dr.rectangle([x, wy, x + CW, wy + WAVE_H], fill=(28, 31, 38))
        step = max(1, n // CW)
        mid = wy + WAVE_H // 2
        half = WAVE_H // 2 - 4
        col_color = (120, 170, 255) if is_bgm else (255, 170, 110)
        for col in range(CW):
            i0 = col * step
            i1 = min(n, i0 + step)
            if i1 <= i0:
                break
            lo = min(mono[i0:i1])
            hi = max(mono[i0:i1])
            y0 = mid - int(max(-1.0, min(1.0, hi)) * half)
            y1 = mid - int(max(-1.0, min(1.0, lo)) * half)
            dr.line([(x + col, y0), (x + col, y1)], fill=col_color)
        dr.line([(x, mid), (x + CW, mid)], fill=(70, 74, 84))

        # --- 能量条区（独立一条，不盖波形）---
        ey = wy + WAVE_H
        dr.rectangle([x, ey, x + CW, ey + ENV_H], fill=(24, 26, 32))
        bw = CW / float(BUCKETS)
        top = max(st["buckets"]) if max(st["buckets"]) > 0 else 1.0
        for b, e in enumerate(st["buckets"]):
            h = int(min(1.0, e / top) * (ENV_H - 4))
            dr.rectangle([x + b * bw + 1, ey + ENV_H - 2 - h,
                          x + (b + 1) * bw - 1, ey + ENV_H - 2],
                         fill=(90, 200, 130))
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    img.save(out_path)
    return out_path


def main():
    if not os.path.isdir(AUDIO_DIR):
        print("no audio dir")
        return 1
    names = sorted(f for f in os.listdir(AUDIO_DIR) if f.endswith(".wav"))
    if not names:
        print("no wav")
        return 1
    entries = []
    fail = 0
    print("%-22s %6s %5s %6s %6s %8s %8s %9s" %
          ("file", "sec", "ch", "sr", "peak", "rms", "zcr", "seam"))
    print("-" * 78)
    for nm in names:
        d = read_wav(os.path.join(AUDIO_DIR, nm))
        st = stats(d)
        seam = loop_seam(d)
        entries.append((nm.replace(".wav", ""), d, st))
        print("%-22s %6.2f %5d %6d %6.3f %8.4f %8.0f %9.5f" %
              (nm, d["sec"], d["nch"], d["sr"], st["peak"], st["rms"],
               st["zcr"], seam))
        # 断言
        if d["sampwidth"] != 2:
            print("  !! 位深不是 16bit")
            fail += 1
        if st["peak"] < 0.2:
            print("  !! 峰值过低（几乎无声）")
            fail += 1
        if st["peak"] > 0.999:
            print("  !! 削波")
            fail += 1
        if st["rms"] < 0.01:
            print("  !! RMS 过低")
            fail += 1
        if nm.startswith("bgm"):
            if seam > 0.06:
                print("  !! 循环接缝跳变过大（%.4f）" % seam)
                fail += 1
            if d["sec"] < 8.0:
                print("  !! BGM 过短（%.1fs）" % d["sec"])
                fail += 1
        else:
            if d["sec"] > 2.5:
                print("  !! 音效过长（%.2fs）" % d["sec"])
                fail += 1
        # 能量包络：音效不能全程一个电平（说明没有衰减/没有动态）。
        # BGM 是持续音床，本来就该平稳，不做这项检查。
        if not nm.startswith("bgm"):
            bk = st["buckets"]
            if max(bk) > 0 and min(bk) > 0.75 * max(bk):
                print("  !! 能量包络几乎无动态（合成 bug 嫌疑）")
                fail += 1
    print("-" * 78)
    p = draw_grid(entries, OUT_PNG)
    print("拼图：%s" % p)
    print("=== 音频素材复核：%s ===" % ("全部通过" if fail == 0 else "%d 项异常" % fail))
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
