# -*- coding: utf-8 -*-
"""修正 assets/audio 下 WAV 的 Godot 导入参数

**为什么需要这一步**：Godot 4.7 的 WAV 导入器默认
  compress/mode=2      → Quite OK Audio（有损压缩）
  edit/loop_mode=0     → Detect From WAV，而脚本合成的裸 PCM 没有 smpl 块
                         → 判定为"不循环"，BGM 放一遍就停
这两个默认值对"游戏 BGM 要无缝循环 + 打击音效要干净"都不合适。

Godot 只在**首次导入**时写 .import，之后会沿用文件里已有的参数，
所以流程是：

    python tools/generate_audio.py            # 1. 合成 WAV
    godot --headless --path . --import        # 2. 首次导入，生成 .import
    python tools/patch_audio_import.py        # 3. 修正参数（本脚本）
    godot --headless --path . --import        # 4. 按新参数重新导入

参数策略：
  * 全部改成 PCM（compress/mode=0）—— 音效保真、BGM 循环接缝不会有压缩噪声
  * BGM（bgm_*.wav）额外打上前向循环

⚠️ **`.import` 里的 `edit/loop_mode` 不是 `AudioStreamWAV.LoopMode` 那套枚举**，
这是本项目踩过的一个真坑：

    导入器枚举：0=Disabled  1=Detect From WAV  2=Forward  3=Ping-Pong  4=Backward
    运行时枚举：AudioStreamWAV.LOOP_DISABLED=0  LOOP_FORWARD=1  LOOP_PINGPONG=2

	写 `edit/loop_mode=1` 想表达"前向循环"→ 实际是"从 WAV 里自动检测" →
	脚本合成的 WAV 没有 smpl 块 → 判定为**不循环**，BGM 放一遍就停，而且不报任何错。
	必须写 **2**。

	验证手法（探针 `scripts/_probe_wav.gd`）：导入后读
	`(load(path) as AudioStreamWAV).loop_mode`，前向循环时应等于
	`AudioStreamWAV.LOOP_FORWARD`（1），且 `loop_end` 被引擎写成实际帧数而不是 0。
"""

from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")

# 需要改成 PCM 的参数行
PCM_LINE = "compress/mode=0"
# 2 = Forward（见文件头关于两套枚举的说明；写成 1 会变成"自动检测"= 不循环）
LOOP_PARAMS = {
    "edit/loop_mode": "2",
    "edit/loop_begin": "0",
    "edit/loop_end": "-1",
}


def patch_one(path: str, with_loop: bool) -> list[str]:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    wanted = dict(LOOP_PARAMS) if with_loop else {}
    changes = []
    seen = set()
    out = []
    for ln in lines:
        key = ln.split("=", 1)[0].strip() if "=" in ln else ""
        if key == "compress/mode":
            seen.add(key)
            if ln != PCM_LINE:
                changes.append("%s → %s" % (ln, PCM_LINE))
                ln = PCM_LINE
        elif key in wanted:
            seen.add(key)
            want = "%s=%s" % (key, wanted[key])
            if ln != want:
                changes.append("%s → %s" % (ln, want))
                ln = want
        out.append(ln)

    # 缺行就补在 [params] 段末（只补需要的）
    missing = [k for k in (["compress/mode"] + list(wanted)) if k not in seen]
    if missing and "[params]" in out:
        extra = [PCM_LINE if k == "compress/mode" else "%s=%s" % (k, wanted[k])
                 for k in missing]
        out.extend(extra)
        changes.append("补写 %s" % ", ".join(missing))

    if changes:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(out) + "\n")
    return changes


def main() -> int:
    if not os.path.isdir(AUDIO_DIR):
        print("没有 %s" % AUDIO_DIR)
        return 1
    names = sorted(f for f in os.listdir(AUDIO_DIR) if f.endswith(".wav.import"))
    if not names:
        print("没有 .import —— 先跑一次 godot --headless --path . --import")
        return 1

    touched = 0
    for nm in names:
        is_bgm = nm.startswith("bgm_")
        path = os.path.join(AUDIO_DIR, nm)
        ch = patch_one(path, is_bgm)
        if ch:
            touched += 1
        flag = " (PCM+LOOP)" if is_bgm else " (PCM)"
        print("%-26s%s%s" % (nm, flag, ("  " + "; ".join(ch)) if ch else "  已是目标参数"))

    print("-" * 60)
    print("共 %d 个导入配置，%d 个被修正" % (len(names), touched))
    print("下一步：godot --headless --path . --import")
    return 0


if __name__ == "__main__":
    sys.exit(main())
