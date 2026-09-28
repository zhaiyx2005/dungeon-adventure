## 导出包资源探针（headless 可跑）
##
## 用途：**每次导出后**确认导出版真的能加载到全部资源。
## 编辑器里一切正常、导出版集体失踪的情况是真实存在的，而且**不报任何错** ——
## 例如 `.tres` 被导出成 `<id>.tres.remap`，只按 `.tres` 后缀扫目录就会扫到 0 个，
## 于是"所有卡牌不见了"（实测踩过）。
##
## 跑法（编辑器）：
##   python godot_run.py _probe_export.gd <log>
## 跑法（导出版，**这是关键用法**）：
##   地牢冒险记.exe --headless --quit-after 300  →  看日志里的统计行
##   或直接看本探针的输出（把本脚本一起导出，用 --script 跑）
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _line(ok: bool, text: String) -> void:
	print("  [%s] %s" % ["OK" if ok else "!!", text])


func _run() -> void:
	await create_timer(0.4).timeout
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		print("[导出探针] GameData 未加载")
		quit(1)
		return

	print("\n===== 导出包资源探针 =====")
	var bad := 0

	# ---- 1. 目录扫描（导出后退化的重灾区）----
	print("\n-- 目录扫描 --")
	for pair in [["res://data/cards/", "卡牌"], ["res://data/monsters/", "怪物"],
			["res://data/items/", "物品"], ["res://data/dungeons/", "关卡"]]:
		var files: PackedStringArray = GameDatabase.list_data_files(String(pair[0]))
		var ok: bool = files.size() > 0
		if not ok:
			bad += 1
		_line(ok, "%s：扫到 %d 个文件%s" % [pair[1], files.size(),
			"" if ok else "  ← 目录扫描失效（导出 remap？）"])

	# ---- 2. 数据库装载量 ----
	print("\n-- 数据库 --")
	for pair in [["cards", 54, "卡牌"], ["monsters", 26, "怪物"],
			["items", 67, "物品"], ["dungeons", 5, "关卡"]]:
		var n: int = gd.db.get(String(pair[0])).size()
		var ok: bool = n >= int(pair[1])
		if not ok:
			bad += 1
		_line(ok, "%s %d（应 ≥%d）" % [pair[2], n, int(pair[1])])

	# ---- 3. 贴图 / 音频是否真的解析得到（走 remap）----
	print("\n-- 资源解析 --")
	var probes := [
		["卡面 fireball", ArtRegistry.card("fireball"), 96, 75],
		["物品 iron_helm", ArtRegistry.item("iron_helm"), 100, 68],
		["立绘 boar", ArtRegistry.unit("boar"), 96, 96],
		["立绘 hero", ArtRegistry.unit("hero"), 96, 96],
	]
	for p in probes:
		var t: Texture2D = p[1]
		var ok: bool = t != null and t.get_width() == int(p[2]) and t.get_height() == int(p[3])
		if not ok:
			bad += 1
		_line(ok, "%s → %s" % [p[0], "缺失" if t == null
			else "%dx%d" % [t.get_width(), t.get_height()]])

	var n_art: int = ArtRegistry.available_count()
	if n_art < 155:
		bad += 1
	_line(n_art >= 155, "素材计数 %d（应 ≥155）" % n_art)

	var thm := load("res://assets/theme_main.tres")
	if thm == null:
		bad += 1
	_line(thm != null, "主题 theme_main.tres 可加载")

	var sfx := load("res://assets/audio/sfx_ui_click.wav")
	if sfx == null:
		bad += 1
	_line(sfx != null, "音效 sfx_ui_click.wav 可加载")

	# ---- 4. 默认卡组是否真的组起来了（0 卡时这里会空）----
	print("\n-- 默认卡组 --")
	var deck: Array = gd.deck
	var ok_deck: bool = deck.size() > 0
	if not ok_deck:
		bad += 1
	_line(ok_deck, "默认卡组 %d 张" % deck.size())
	var owned: int = gd.owned_cards.size()
	if owned <= 0:
		bad += 1
	_line(owned > 0, "持有卡池 %d 张" % owned)

	print("\n===== %s（%d 项异常）=====" % ["通过" if bad == 0 else "有问题", bad])
	quit(1 if bad > 0 else 0)
