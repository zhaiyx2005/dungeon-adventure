## 9-28 场景背景复核截图（真实渲染）
##   A. 主菜单（城镇远景） B. 城镇 5 个标签页各自背景 C. 地下城探索 D. 战斗
##
## 跑法：python godot_run.py _shot_bg.gd <log> --render
extends SceneTree


const OUT := "E:/goodot_work/地牢冒险记/preview/"


func _init() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		print("截图失败：拿不到 viewport 图像")
		return
	print("截图已保存 -> %s" % path)
	img.save_png(path)


func _run() -> void:
	await create_timer(0.5).timeout
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		print("拿不到 GameData")
		quit(1)
		return
	gd.gold = 5000
	gd.pending_initial_tab = ""
	gd.last_battle_result = {}
	gd.pending_encounter = {}

	print("\n-- 背景素材盘点 --")
	for id in ["menu_town", "guild_hall", "armory", "shop", "storage", "library",
			"dungeon_gate", "dungeon_battle"]:
		var t: Texture2D = ArtRegistry.bg(id)
		print("  %-16s -> %s" % [id, "缺失" if t == null
			else "%dx%d" % [t.get_width(), t.get_height()]])

	# ---------- A. 主菜单 ----------
	change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(0.9).timeout
	print("\n主菜单背景 = %s" % String((current_scene as Control).get_node("SceneBackdrop").current_id()))
	await _shot(OUT + "bg_menu.png")

	# ---------- B. 城镇 5 个标签页 ----------
	gd.pending_initial_tab = "冒险者工会"
	change_scene_to_file("res://scenes/town/town_scene.tscn")
	await create_timer(1.0).timeout
	var town: Node = current_scene
	var names := ["guild", "armory", "shop", "storage", "library"]
	for i in range(5):
		town._switch_tab(i)
		await create_timer(0.55).timeout
		var bd: Node = town.get_node("SceneBackdrop")
		print("  标签 %d -> 背景 %s / %s" % [i, town.TABS[i], bd.current_id()])
		await _shot(OUT + "bg_town_%d_%s.png" % [i, names[i]])

	# ---------- C. 地下城探索 ----------
	gd.pending_initial_tab = ""
	change_scene_to_file("res://scenes/dungeon/run_scene.tscn")
	await create_timer(1.0).timeout
	await _shot(OUT + "bg_dungeon.png")

	# ---------- D. 战斗 ----------
	# 注意：gd.deck 是 Array[CardData]，赋一个无类型 Array 会运行时报错
	var deck: Array[CardData] = []
	for cid in ["fireball", "iron_wall", "strike", "guard_phys", "heal"]:
		var c: CardData = gd.db.get_card(cid)
		if c != null:
			deck.append(c)
	gd.deck = deck
	gd.pending_encounter = {"monster_ids": ["goblin", "dire_wolf", "wyvern"]}
	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(1.2).timeout
	var bd2 := (current_scene as Control).get_node_or_null("SceneBackdrop")
	print("  战斗背景 = %s" % (String(bd2.current_id()) if bd2 != null else "无"))
	await _shot(OUT + "bg_battle.png")

	print("\n完成")
	quit(0)
