# -*- coding: utf-8 -*-
"""Godot 测试运行器。

把「起 Godot 跑一个 `extends SceneTree` 的脚本、把 stdout+stderr 落盘」这件事收在一个地方。
放在项目里（而不是临时目录）是为了让它跟着仓库走。

用法
----
    PY = C:/Users/20601/.workbuddy/binaries/python/versions/3.13.12/python.exe

    # 跑单个套件（headless）
    "%PY%" tools/godot_run.py _t_stage1

    # 截图 / 需要真实 GPU 渲染的脚本：加 --render
    "%PY%" tools/godot_run.py _t_smoke --render
    "%PY%" tools/godot_run.py _shot_slots --render

    # 跑全部 11 个单元套件 + 完整性诊断 + 真渲染冒烟，并打印汇总表
    "%PY%" tools/godot_run.py --all

    # 日志默认写到 <工作区>/preview/_log_<脚本>.txt，也可以显式指定
    "%PY%" tools/godot_run.py _t_audio preview/_log_audio.txt

设计要点（都是踩过的坑）
------------------------
* **必须清掉代理环境变量**：本机设了 http_proxy 之类的变量时 Godot 会起不来。
  顺带去掉重复的（大小写不同的同名）环境变量，Windows 下会因此报错。
* **PATH 压到最小**：`C:\\Windows\\System32;C:\\Windows`，避免继承到奇怪的可执行文件。
* `--render` **不加 `--headless`**：headless 用的是 dummy 渲染器，
  `get_image()` 截出来是 64×64 的畸变图，截图脚本必须走真实渲染。
* 退出码：0 = 全部通过；非 0 = 有失败**或**脚本本身崩了（日志里 grep `SCRIPT ERROR`）。
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import time

GODOT = os.environ.get(
    "GODOT_EXE",
    r"D:/100_study/130_game_engine/godot_v4.72/Godot_v4.7.2-stable_win64.exe")

# 本文件在 <项目>/tools/ 下 → 上两级是工作区，上一级是项目
TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(TOOLS_DIR)
PREVIEW = os.path.join(os.path.dirname(PROJECT), "preview")
DEFAULT_LOG = os.path.join(PREVIEW, "_log_{name}.txt")

TIMEOUT = 300

## 全量回归的顺序。前 11 个是纯逻辑 / 渲染单元套件，最后两个是诊断与端到端冒烟。
SUITES = [
    "_t_stage1", "_t_stage2_battle", "_t_stage2_ui", "_t_stage2_flow",
    "_t_stage3", "_t_stage3_flow", "_t_stage4", "_t_stage4_flow",
    "_t_stage5", "_t_audio", "_t_art",
]
INTEGRITY = "_t_integrity"
SMOKE = "_t_smoke"

RESULT_RE = re.compile(r"(\d+)\s*通过\s*/\s*(\d+)\s*失败")


def clean_env() -> dict:
    """去掉代理 + 大小写重复的环境变量（否则 Godot 直接起不来）。"""
    env: dict = {}
    seen = set()
    for k, v in os.environ.items():
        key = k.lower()
        if key in seen or "proxy" in key:
            continue
        seen.add(key)
        env[k] = v
    env["PATH"] = r"C:\Windows\System32;C:\Windows"
    return env


def run(script: str, log_path: str, render: bool = False,
        extra: list | None = None) -> tuple[int, str]:
    """跑一个脚本，返回 (退出码, 日志全文)。`script` 可带或不带 `.gd`。"""
    if not script.endswith(".gd"):
        script += ".gd"
    if render:
        cmd = [GODOT, "--path", PROJECT, "--script", "res://scripts/" + script,
               "--rendering-driver", "opengl3", "--windowed",
               "--resolution", "1280x720"]
    else:
        cmd = [GODOT, "--headless", "--path", PROJECT,
               "--script", "res://scripts/" + script]
    cmd += list(extra or [])

    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    t0 = time.time()
    try:
        p = subprocess.run(cmd, env=clean_env(), capture_output=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired as e:
        raw = (e.stdout or b"") + b"\n---STDERR---\n" + (e.stderr or b"")
        with open(log_path, "wb") as f:
            f.write(raw)
        return 124, raw.decode("utf-8", "replace")

    raw = p.stdout + b"\n---STDERR---\n" + p.stderr
    with open(log_path, "wb") as f:
        f.write(raw)
    print("  exit=%d  %.1fs  -> %s" % (p.returncode, time.time() - t0, log_path))
    return p.returncode, raw.decode("utf-8", "replace")


def counts(text: str) -> tuple[int, int]:
    """从日志里取最后一个「N 通过 / M 失败」。"""
    hits = RESULT_RE.findall(text)
    if not hits:
        return -1, -1
    p, f = hits[-1]
    return int(p), int(f)


def script_errors(text: str) -> int:
    return len(re.findall(r"SCRIPT ERROR", text))


def run_all() -> int:
    total_pass = total_fail = total_err = 0
    rows = []

    for name in SUITES:
        _, text = run(name, DEFAULT_LOG.format(name=name))
        p, f = counts(text)
        e = script_errors(text)
        total_pass += max(p, 0)
        total_fail += max(f, 0)
        total_err += e
        rows.append((name, p, f, e))

    _, int_text = run(INTEGRITY, DEFAULT_LOG.format(name="integrity"))
    int_line = ""
    for line in int_text.splitlines():
        if "完整性诊断" in line or line.startswith("检查："):
            int_line = line.strip()

    _, smoke_text = run(SMOKE, DEFAULT_LOG.format(name="smoke"), render=True)
    sp, sf = counts(smoke_text)
    se = script_errors(smoke_text)
    total_err += se

    print("\n%-20s %8s %8s %6s" % ("套件", "通过", "失败", "err"))
    print("-" * 46)
    for name, p, f, e in rows:
        print("%-20s %8s %8s %6d" % (name, p if p >= 0 else "?", f if f >= 0 else "?", e))
    print("-" * 46)
    print("%-20s %8d %8d %6d" % ("单元合计", total_pass, total_fail, total_err))
    print("%-20s %s" % ("完整性诊断", int_line or "(未取到)"))
    print("%-20s %d 通过 / %d 失败  err=%d" % ("渲染冒烟", sp, sf, se))

    bad = total_fail + total_err + max(sf, 0) + se
    print("\n%s" % ("全部通过 ✓" if bad == 0 else "有 %d 项异常 ✗" % bad))
    return 1 if bad else 0


def main(argv: list) -> int:
    args = list(argv)
    render = "--render" in args
    if render:
        args.remove("--render")

    if not args or args[0] == "--all":
        return run_all()

    script = args[0]
    log = args[1] if len(args) > 1 else DEFAULT_LOG.format(name=script)
    extra = args[2:]
    code, _ = run(script, log, render=render, extra=extra)
    return code


if __name__ == "__main__":
    if not os.path.exists(GODOT):
        print("找不到 Godot：%s\n（可用环境变量 GODOT_EXE 覆盖）" % GODOT, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
