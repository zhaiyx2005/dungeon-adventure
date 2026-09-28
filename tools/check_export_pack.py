# -*- coding: utf-8 -*-
"""导出包体检：确认 `res://` 下的每个资源在 `.pck` 里都有"落点"。

**为什么需要这个工具**：导出会把项目资源改写成另一种形态，而改写在运行期可能
静默失效 —— 最典型的就是 `.tres` 被转成二进制、原路径只留 `<id>.tres.remap` 存根，
于是"按 `.tres` 后缀扫目录"的代码在导出版扫到 0 个文件，**整个游戏没有任何卡牌，
却一条错都不报**（实测踩过）。

本工具直接解析 `.pck` 的文件表，然后逐条核对：

  1. **贴图 / 音频 / 字体**（`.import`）：`[remap] path=` 指向的 `.ctex` / `.sample`
     / `.fontdata` 必须在包里
  2. **文本资源**（`.tres`）：每个都要同时有
     * `.remap` 存根（原路径，供 `load("res://x.tres")` 解析）
     * `.godot/exported/<seed>/export-<md5>-<basename>.res` 落点（真正的二进制资源）

用法：
    python tools/check_export_pack.py <导出的.pck 或 .exe>
    python tools/check_export_pack.py ../新建文件夹/地牢冒险记.pck

退出码 0 = 全部有落点；1 = 有缺失（会逐条列出）。
"""

from __future__ import annotations

import glob
import io
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_pck_entries(path: str) -> set[str]:
    """解析 Godot 4 PCK 的文件表，返回条目名集合（不含 `res://` 前缀）。"""
    d = open(path, "rb").read()
    if d[:4] != b"GDPC":
        raise ValueError("不是 PCK 文件（magic 应为 GDPC）：%s" % path)
    # 头：magic(4) + format(4) + major/minor/patch(12) + pack_flags(4) + file_base(8)
    #     + dir_offset(8) + reserved(60)   —— dir_offset 落在"reserved"的第一个 8 字节
    dir_off = struct.unpack_from("<I", d, 32)[0]
    count, = struct.unpack_from("<I", d, dir_off)
    off = dir_off + 4
    out: set[str] = set()
    for _ in range(count):
        plen, = struct.unpack_from("<I", d, off)
        off += 4
        name = d[off:off + plen].split(b"\x00")[0].decode("utf-8", "replace")
        off += plen
        offset, _size = struct.unpack_from("<QQ", d, off)
        off += 16
        off += 16                      # md5
        if offset & (1 << 63):         # 加密块标记
            off += 4
        off += 4                       # per-file flags
        out.add(name)
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    pack = sys.argv[1]
    if not os.path.exists(pack):
        print("找不到文件：%s" % pack)
        return 2

    entries = read_pck_entries(pack)
    print("PCK：%s" % pack)
    print("文件表条目：%d\n" % len(entries))

    bad: list[str] = []

    # ---- 1. 贴图 / 音频 / 字体：.import 的 remap 目标必须在包里 ----
    imports = glob.glob(os.path.join(ROOT, "assets", "**", "*.import"), recursive=True)
    for imp in imports:
        text = io.open(imp, encoding="utf-8").read()
        m = re.search(r'^path="res://(.+)"', text, re.M)
        rel = os.path.relpath(imp, ROOT).replace("\\", "/")
        if not m:
            bad.append("%s：没有 [remap] path 字段" % rel)
        elif m.group(1) not in entries:
            bad.append("%s：remap 目标不在包里 -> %s" % (rel, m.group(1)))
    print("[贴图/音频/字体] %d 个 .import，异常 %d" % (len(imports), len([b for b in bad])))

    # ---- 2. 文本资源：存根 + 二进制落点，缺一不可 ----
    tres = glob.glob(os.path.join(ROOT, "data", "**", "*.tres"), recursive=True)
    tres += glob.glob(os.path.join(ROOT, "assets", "**", "*.tres"), recursive=True)
    n_bad_before = len(bad)
    for t in tres:
        rel = os.path.relpath(t, ROOT).replace("\\", "/")
        base = os.path.basename(t)[:-len(".tres")]
        stub = rel + ".remap"
        landing = any(
            p.startswith(".godot/exported/") and p.endswith("-" + base + ".res")
            for p in entries
        )
        if stub not in entries:
            bad.append("%s：缺少 .remap 存根（导出后 load() 找不到它）" % rel)
        if not landing:
            bad.append("%s：缺少 .godot/exported/*-%s.res 落点" % [rel, base])
    print("[文本资源]   %d 个 .tres，异常 %d\n" % (len(tres), len(bad) - n_bad_before))

    if bad:
        print("缺失明细：")
        for b in bad[:40]:
            print("  ✗ " + b)
        if len(bad) > 40:
            print("  … 另有 %d 条" % (len(bad) - 40))
        print("\n结论：导出包不完整 ✗")
        return 1

    # ---- 3. 提醒代码侧的目录扫描：包内数据资源全是 `.remap` 存根 ----
    # 这一条不是"包不完整"，而是**代码风险**：
    # 包里的 `data/cards/` 只会出现 `<id>.tres.remap`，不会出现 `<id>.tres`。
    # 所以任何形如 `DirAccess` + `ends_with(".tres")` 的扫描在导出版都会扫到 0 个，
    # 且不报错。正确写法见 scripts/core/game_database.gd 的 `list_data_files()`。
    plain = [p for p in entries
             if p.startswith(("data/", "assets/")) and p.endswith(".tres")]
    stubs = [p for p in entries
             if p.startswith(("data/", "assets/")) and p.endswith(".tres.remap")]
    print("\n[目录扫描风险] 包内 .tres 实体 %d 个 / .remap 存根 %d 个" % (len(plain), len(stubs)))
    if stubs and not plain:
        print("  ⚠ 数据资源**全部**是 `.remap` 存根 —— 按 `.tres` 后缀扫目录的代码在导出版会扫到 0 个。")
        print("    请确认走的是 GameDatabase.list_data_files()（它会剥掉 .remap）。")
    print("\n结论：全部资源在包里都有落点 ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
