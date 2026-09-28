## 9-28 存档栏位 / 游玩指南复核截图（真实渲染）
##   A. 游玩指南（可滚动面板）
##   B. 存档面板（10 栏位，混有已存档 / 空栏位）
##   C. 读档面板（空栏位置灰）
##   D. 覆盖确认层
##
## 跑法：python godot_run.py _shot_slots.gd <log> --render
##
## 🔴 用**隔离的存档前缀**：截图要展示"有档 / 无档"混合状态，
## 绝不能拿玩家的真实栏位来摆拍，更不能往里面写东西。
extends SceneTree


const OUT := "E:/goodot_work/地牢冒险记/preview/"
const SHOT_PREFIX := "user://_shot_save_"


func _init() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		print("截图失败：拿不到 viewport 图像")
		return
	img.save_png(path)
	print("截图已保存 -> %s" % path)


func _run() -> void:
	await create_timer(0.5).timeout
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		print("拿不到 GameData")
		quit(1)
		return

	# 摆拍用存档：隔离前缀 + 两个不同进度的档
	SaveManager.active_prefix = SHOT_PREFIX
	var sm := SaveManager.new()
	for i in range(SaveManager.SLOT_COUNT):
		sm.erase(i)

	gd.gold = 4820
	gd.playtime_seconds = 4815.0        # 1 小时 20 分
	sm.save(0)

	gd.gold = 12640
	gd.playtime_seconds = 8125.0        # 2 小时 15 分
	sm.save(3)

	gd.gold = 200
	gd.playtime_seconds = 0.0

	change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(1.2).timeout
	var menu: Node = current_scene

	# 摆拍状态：读一下刚写的摘要，确认面板上会显示什么
	for i in [0, 3]:
		var info := sm.slot_info(i)
		print("摆拍栏位 %d：金币 %d · 游玩 %s"
			% [i + 1, int(info["gold"]), SaveManager.format_playtime(int(info["playtime"]))])

	# ---------- A. 游玩指南 ----------
	menu.open_guide()
	await create_timer(0.6).timeout
	var scroll := _find(menu, "OverlayScroll")
	print("指南滚动容器高度 = %d（内容高度 %d）"
		% [int(scroll.size.y) if scroll != null else -1,
		   int(scroll.get_child(0).size.y) if scroll != null else -1])
	await _shot(OUT + "ui_guide.png")
	menu.close_overlay()
	await create_timer(0.3).timeout

	# ---------- B. 存档面板 ----------
	menu.open_save_slots()
	await create_timer(0.5).timeout
	var list := _find(menu, "SlotList")
	print("栏位数 = %d" % (list.get_child_count() if list != null else -1))
	for i in range(SaveManager.SLOT_COUNT):
		var t := _find(menu, "SlotTime_%d" % i) as Label
		if t != null and t.text.contains("最后保存"):
			print("  栏位 %d：%s" % [i + 1, t.text])
	await _shot(OUT + "ui_slots_save.png")

	# ---------- C. 覆盖确认（点一个**已有存档**的栏位）----------
	var slot3 := _find(menu, "Slot_3") as Button
	if slot3 != null:
		slot3.pressed.emit()
		await create_timer(0.4).timeout
		await _shot(OUT + "ui_slots_confirm.png")
		menu.close_confirm()
		await create_timer(0.3).timeout
	menu.close_overlay()
	await create_timer(0.3).timeout

	# ---------- D. 读档面板 ----------
	menu.open_load_slots()
	await create_timer(0.5).timeout
	var enabled := 0
	for i in range(SaveManager.SLOT_COUNT):
		var b := _find(menu, "Slot_%d" % i) as Button
		if b != null and not b.disabled:
			enabled += 1
	print("读档面板可点栏位 = %d（其余置灰）" % enabled)
	await _shot(OUT + "ui_slots_load.png")
	menu.close_overlay()

	# 清理摆拍存档
	for i in range(SaveManager.SLOT_COUNT):
		sm.erase(i)
	print("摆拍存档已清理")

	print("\n完成")
	quit(0)


func _find(node: Node, nm: String) -> Node:
	if node.name == nm:
		return node
	for ch in node.get_children():
		var hit := _find(ch, nm)
		if hit != null:
			return hit
	return null
