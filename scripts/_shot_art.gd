## 9-26 像素插画实装复核截图（真实渲染）
##   A. 战斗：手牌封面插画（烈焰术 / 铁壁）+ 敌方单位立绘（野猪怪 / 巫王）
##   B. 城镇·冒险者工会：人物卡半身立绘（农夫之子 / 见习法师；佣兵尚无素材 → 回落色块）
##   C. 城镇·卡牌大全：卡面插画缩略
##
## 跑法：python godot_run.py _shot_art.gd <log> --render
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
	print("截图已保存 -> %s (err=%d)" % [path, img.save_png(path)])


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

	print("\n-- 插画素材盘点 --")
	print("  已就绪素材数 = %d" % ArtRegistry.available_count())
	for id in ["fireball", "iron_wall"]:
		print("  卡面 %-10s -> %s" % [id, str(ArtRegistry.card(id) != null)])
	for id in ["boar", "witch_king", "hero", "mage", "warrior"]:
		print("  立绘 %-10s -> 整身=%s  半身=%s"
			% [id, str(ArtRegistry.unit(id) != null), str(ArtRegistry.unit_bust(id) != null)])
	var t: Texture2D = ArtRegistry.card("fireball")
	if t != null:
		print("  fireball 纹理尺寸 = %dx%d" % [t.get_width(), t.get_height()])
	var b: Texture2D = ArtRegistry.unit_bust("hero")
	if b != null:
		print("  hero 半身切片 = %dx%d（整身 %d 的 64%%）"
			% [b.get_width(), b.get_height(), ArtRegistry.unit("hero").get_height()])

	# ---------- A. 战斗：手牌插画 + 单位立绘 ----------
	# 手牌里要有 烈焰术 / 铁壁，敌方要有 野猪怪 / 巫王
	var deck: Array[CardData] = []
	for cid in ["fireball", "fireball", "iron_wall", "iron_wall",
			"strike", "strike", "guard_phys", "guard_phys"]:
		var c: CardData = gd.db.get_card(cid)
		if c != null:
			deck.append(c)
	gd.deck = deck
	gd.pending_encounter = {"monster_ids": ["goblin", "dire_wolf", "wyvern"]}

	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(1.1).timeout
	var bs: Node = current_scene
	var bm: BattleManager = bs.battle
	print("\n战斗：手牌 %d 张，敌方 %d 只" % [bm.deck.hand.size(), bm.monsters.size()])
	await _shot(OUT + "art_battle.png")

	# ---------- B. 城镇·冒险者工会（人物卡立绘） ----------
	gd.pending_encounter = {}
	gd.last_battle_result = {}
	# 造一个"高智力"的招募者，用来验证职业原型立绘的回退（招募池是随机属性，没有专属立绘）
	var recruit := Adventurer.new()
	recruit.id = "recruit_probe"
	recruit.display_name = "招募·学者相"
	recruit.constitution = 4
	recruit.strength = 4
	recruit.intelligence = 9
	recruit.vitality = 4
	gd.roster.append(recruit)
	print("招募者原型判定 = %s（智力 9 最高 → 应为 arch_scholar）" % ArtRegistry.archetype_of(recruit))
	var avg := Adventurer.new()
	avg.id = "recruit_avg"
	avg.display_name = "招募·平庸"
	avg.constitution = 5
	avg.strength = 5
	avg.intelligence = 5
	avg.vitality = 5
	print("四属性全 5 的原型判定 = %s（应为 arch_ranger，游侠=万金油）" % ArtRegistry.archetype_of(avg))

	gd.pending_initial_tab = "冒险者工会"
	change_scene_to_file("res://scenes/town/town_scene.tscn")
	await create_timer(1.0).timeout
	await _shot(OUT + "art_town_person.png")

	# ---------- C. 卡牌大全（按"大节"逐个定位滚动，拍三段） ----------
	var town: Node = current_scene
	town._switch_tab(4)
	await create_timer(0.8).timeout
	await _shot(OUT + "art_codex.png")

	# 大节标题都带 "▍" 前缀，直接读它们的 y 坐标当滚动锚点，
	# 比按百分比瞎猜稳（内容高度随卡数变化）
	var content: VBoxContainer = town._content
	var marks: Array = []
	for child in content.get_children():
		var l := child as Label
		if l != null and l.text.begins_with("▍"):
			marks.append([l.text, int(l.position.y)])
	var sc: ScrollContainer = town._scroll
	print("  卡牌大全大节: %s" % str(marks))
	print("  内容高度 = %d  视口高 = %d"
		% [int(sc.get_v_scroll_bar().max_value), int(sc.size.y)])
	var idx := 0
	for m in marks:
		sc.scroll_vertical = maxi(0, int(m[1]) - 6)
		await create_timer(0.45).timeout
		await _shot(OUT + "art_codex_%d.png" % idx)
		print("    -> %s @ y=%d" % [m[0], m[1]])
		idx += 1

	# ---------- D. 商店（物品卡在列表里的观感） ----------
	town._switch_tab(2)
	await create_timer(0.6).timeout
	await _shot(OUT + "art_shop.png")

	print("\n完成")
	quit(0)
