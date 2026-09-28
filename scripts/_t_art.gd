## 像素插画系统测试（9-26）
##
## 覆盖：
##   1. 素材齐全性 —— 数据库里的每一张卡 / 每一件物品 / 每一只怪都要有插画
##                    （新增卡或物品忘了出图 = 直接红）
##   2. 规格 —— 卡面 96×75、立绘 96×96、物品图标 100×68、RGBA
##   3. 缺失回落 —— 未出图的 id 一律返回 null，卡面回落占位色块，不崩、不留半成品
##   4. 职业原型派发 —— 招募池随机属性 → 原型的判定规则与确定性
##   5. 立绘取用规则 —— 主角用专属（含战斗姿态）、招募者用原型、怪物用自己
##   6. 显示设置 —— 插画节点必须 NEAREST（线性插值会把像素块糊掉）
##   7. 物品卡面 —— 插画挂得上、描述装得下（曾把三加成装备的描述挤掉一行）
extends SceneTree

const CARD_W := 96
const CARD_H := 75
const UNIT_W := 96
const UNIT_H := 96
## 物品图标：100×68 —— 与人物卡图片区（归一化 0.107–0.891 × 0.130–0.508 落在 128×179 上）
## 完全一致。尺寸对齐是硬要求：CardFrame 用 KEEP_ASPECT_COVERED，比例不符就裁边角。
const ITEM_W := 100
const ITEM_H := 68
## 场景背景：铺满 1280×720 逻辑分辨率
const BG_W := 1280
const BG_H := 720

var _pass := 0
var _fail := 0
var _db: GameDatabase = null


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(90.0).timeout
	print("[看门狗] 超时")
	quit(1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


func _run() -> void:
	_watchdog()
	print("\n===== 像素插画（9-26）=====\n")

	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		_ok(false, "GameData autoload 未加载")
		_finish()
		return
	_db = gd.db

	# ⚠️ 含 `await` 的测试函数**必须 await**：GDScript 里不 await 就只是挂起那个协程，
	# 调用方会继续往下走到 _finish()，断言会跑到"汇总打印"之后 —— 数字看着对了，
	# 其实晚到的那些断言根本没被计入。
	await _test_all_cards_have_art()
	await _test_all_items_have_art()
	await _test_all_backgrounds_have_art()
	await _test_all_monsters_have_art()
	await _test_adventurer_art()
	await _test_specs_and_fallbacks()
	await _test_archetype_dispatch()
	await _test_display_settings()
	await _test_item_card_face()

	_finish()


func _finish() -> void:
	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------------------

func _test_all_cards_have_art() -> void:
	print("-- 卡面插画齐全性 --")
	var total := _db.cards.size()
	_ok(total >= 54, "数据库里有 %d 张卡（≥54）" % total)

	var missing: Array = []
	var wrong_size: Array = []
	for id in _db.cards.keys():
		var t: Texture2D = ArtRegistry.card(String(id))
		if t == null:
			missing.append(String(id))
			continue
		if t.get_width() != CARD_W or t.get_height() != CARD_H:
			wrong_size.append("%s(%dx%d)" % [id, t.get_width(), t.get_height()])
	_ok(missing.is_empty(), "全部 %d 张卡都有卡面插画（缺 %d 张：%s）"
		% [total, missing.size(), str(missing.slice(0, 6))])
	_ok(wrong_size.is_empty(), "全部卡面都是 %dx%d（异常 %s）"
		% [CARD_W, CARD_H, str(wrong_size.slice(0, 5))])


## 物品图标（9-26）：装备 + 道具全部要出图，且原生网格必须与人物卡图片区**完全一致**
func _test_all_items_have_art() -> void:
	print("\n-- 物品图标齐全性 --")
	var total := _db.items.size()
	_ok(total >= 67, "数据库里有 %d 件物品（≥67）" % total)

	var missing: Array = []
	var wrong_size: Array = []
	for id in _db.items.keys():
		var t: Texture2D = ArtRegistry.item(String(id))
		if t == null:
			missing.append(String(id))
			continue
		if t.get_width() != ITEM_W or t.get_height() != ITEM_H:
			wrong_size.append("%s(%dx%d)" % [id, t.get_width(), t.get_height()])
	_ok(missing.is_empty(), "全部 %d 件物品都有图标（缺 %d：%s）"
		% [total, missing.size(), str(missing.slice(0, 6))])
	# 尺寸错就会被 KEEP_ASPECT_COVERED 裁掉边角 —— 剑/弓被裁掉一头一尾就废了
	_ok(wrong_size.is_empty(), "全部物品图标都是 %dx%d（异常 %s）"
		% [ITEM_W, ITEM_H, str(wrong_size.slice(0, 5))])

	# 五个大类都要有图，不能只出了装备
	var by_class := {}
	for id in _db.items.keys():
		var it: ItemData = _db.get_item(String(id))
		if it != null:
			by_class[it.item_class] = int(by_class.get(it.item_class, 0)) + 1
	_ok(by_class.size() == 5, "物品覆盖 5 个大类（实际 %d 类：%s）" % [by_class.size(), str(by_class)])

	# 透明底：不透明像素占比不能接近 100%（那说明抠底整个失败了，图标会带一整块底色）
	var opaque_leak: Array = []
	for id in _db.items.keys():
		var t: Texture2D = ArtRegistry.item(String(id))
		if t == null:
			continue
		var img: Image = t.get_image()
		if img == null:
			continue
		var op := 0
		var n := img.get_width() * img.get_height()
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				if img.get_pixel(x, y).a > 0.5:
					op += 1
		var ratio := float(op) / float(maxi(1, n))
		if ratio > 0.85:
			opaque_leak.append("%s(%.0f%%)" % [id, ratio * 100.0])
	_ok(opaque_leak.is_empty(), "物品图标都是透明底（不透明 ≥85%% 的异常：%s）" % str(opaque_leak))


## 物品卡面（person 版式）：插画要真的挂上、显示要 NEAREST、描述不能溢出
func _test_item_card_face() -> void:
	print("\n-- 物品卡面 --")
	# 挑一个三加成 + 长描述的最坏情况（这四件实测曾把描述挤掉一行）
	for iid in ["warlord_blade", "archmage_staff", "dragon_scale", "eye_of_fate"]:
		var it: ItemData = _db.get_item(iid)
		if it == null:
			_ok(false, "%s 不存在" % iid)
			continue
		var f := CardFrame.new()
		f.custom_minimum_size = Vector2(128, 179)
		root.add_child(f)
		f.setup(it.display_name, it.get_card_desc_cn(), it.get_rarity_color(),
			{"badge_l": it.get_rarity_name_cn(), "badge_r": it.get_slot_name_cn(),
			 "image": ArtRegistry.item(it.id)})
		await process_frame
		await process_frame
		_ok(f._art_image.texture != null and f._art_image.visible,
			"%s 卡面挂上了插画" % iid)
		_ok(f._art_image.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"%s 插画用 NEAREST 过滤" % iid)
		# 描述不能溢出（溢出即静默丢行）
		var lbl: Label = f._desc_label
		var rect: Rect2 = lbl.get_rect()
		var font: Font = lbl.get_theme_font("font")
		var fs: int = lbl.get_theme_font_size("font_size")
		var need: Vector2 = font.get_multiline_string_size(
			lbl.text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, fs)
		var lsp: int = lbl.get_theme_constant("line_spacing")
		var n_lines: int = maxi(1, int(round(need.y / maxf(1.0, font.get_height(fs)))))
		var real_h: float = need.y + float(lsp) * float(n_lines - 1)
		_ok(real_h <= rect.size.y + 0.5,
			"%s 描述装得下（需 %.0f / 有 %.0f，字号 %d）" % [iid, real_h, rect.size.y, fs])
		f.queue_free()
		await process_frame

	# 缺素材的物品必须回落色块，不能渲染成白框
	var ghost := ItemData.new()
	ghost.id = "no_such_item_xyz"
	ghost.display_name = "幽灵物品"
	ghost.description = "没有图标。"
	var f2 := CardFrame.new()
	f2.custom_minimum_size = Vector2(128, 179)
	root.add_child(f2)
	f2.setup(ghost.display_name, ghost.get_card_desc_cn(), ghost.get_rarity_color(),
		{"image": ArtRegistry.item(ghost.id)})
	await process_frame
	await process_frame
	_ok(not f2._art_image.visible and f2._art_color.visible,
		"缺素材的物品回落占位色块（插画隐藏、色块可见）")
	f2.queue_free()
	await process_frame


## 场景背景（9-28）：8 张齐全、1280×720、能挂进场景且压光层生效
func _test_all_backgrounds_have_art() -> void:
	print("\n-- 场景背景齐全性 --")
	var want := ["menu_town", "guild_hall", "armory", "shop", "storage", "library",
		"dungeon_gate", "dungeon_battle"]
	var missing: Array = []
	var wrong_size: Array = []
	for id in want:
		var t: Texture2D = ArtRegistry.bg(String(id))
		if t == null:
			missing.append(id)
			continue
		if t.get_width() != BG_W or t.get_height() != BG_H:
			wrong_size.append("%s(%dx%d)" % [id, t.get_width(), t.get_height()])
	_ok(missing.is_empty(), "%d 张场景背景齐全（缺 %s）" % [want.size(), str(missing)])
	_ok(wrong_size.is_empty(), "背景都是 %dx%d（异常 %s）" % [BG_W, BG_H, str(wrong_size)])
	_ok(not ArtRegistry.has_bg("no_such_bg_xyz"), "未知背景 id → null")

	# 背景板：插在第一个子节点（垫底）、压光层 alpha 在合理区间
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var bd := SceneBackdrop.attach(host, "guild_hall", 0.7)
	await process_frame
	_ok(host.get_child(0) == bd, "背景板插在 index 0（垫在所有 UI 底下）")
	_ok(bd.has_image() and String(bd.current_id()) == "guild_hall", "背景贴图已加载")
	_ok(bd._scrim.color.a > 0.3 and bd._scrim.color.a < 0.95,
		"压光层 alpha %.2f 在 0.3–0.95（太小读不清字、太大看不到背景）" % bd._scrim.color.a)
	_ok(bd._tex.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
		"背景用 LINEAR_WITH_MIPMAPS（它是大图、还要被窗口缩放，不是 1:1 像素素材）")
	_ok(bd._scrim.mouse_filter == Control.MOUSE_FILTER_IGNORE, "压光层不拦鼠标")
	bd.show_image("no_such_bg_xyz")
	_ok(not bd.has_image() or String(bd.current_id()) != "no_such_bg_xyz",
		"换成不存在的背景不会崩")
	host.queue_free()
	await process_frame


func _test_all_monsters_have_art() -> void:
	print("\n-- 怪物立绘齐全性 --")
	var total := _db.monsters.size()
	_ok(total >= 26, "数据库里有 %d 只怪（≥26）" % total)
	var missing: Array = []
	for id in _db.monsters.keys():
		if ArtRegistry.monster_battle(_make_instance(String(id))) == null:
			missing.append(String(id))
	_ok(missing.is_empty(), "全部 %d 只怪都有战斗立绘（缺 %d：%s）"
		% [total, missing.size(), str(missing.slice(0, 6))])

	# 头目层级也要有（Boss 最显眼，缺了最扎眼）
	var bosses: Array = []
	for id in _db.monsters.keys():
		var md: MonsterData = _db.get_monster(String(id))
		if md != null and md.monster_tier == MonsterData.MonsterTier.BOSS:
			if ArtRegistry.monster_battle(_make_instance(String(id))) == null:
				bosses.append(String(id))
	_ok(bosses.is_empty(), "首领级怪物立绘齐全（缺 %s）" % str(bosses))


func _test_adventurer_art() -> void:
	print("\n-- 冒险者立绘 --")
	var gd: Node = root.get_node_or_null("/root/GameData")
	_ok(gd.team.size() == 3, "起始队伍 3 人")
	var no_art: Array = []
	for a in gd.team:
		if ArtRegistry.adventurer_bust(a) == null or ArtRegistry.adventurer_battle(a) == null:
			no_art.append(a.display_name)
	_ok(no_art.is_empty(), "起始 3 人都有立绘（缺 %s）" % str(no_art))

	# 主角的两种姿态必须是**不同**的纹理（正面用于人物卡、侧身用于战场）
	var hero: Adventurer = gd.team[0]
	var bust: Texture2D = ArtRegistry.adventurer_bust(hero)
	var battle: Texture2D = ArtRegistry.adventurer_battle(hero)
	_ok(bust != null and battle != null and bust != battle,
		"主角正面与战斗姿态是两张不同纹理（%s / %s）"
		% [bust.resource_path.get_file() if bust else "无",
		   battle.resource_path.get_file() if battle else "无"])
	_ok(battle != null and (battle as AtlasTexture) != null
			and String((battle as AtlasTexture).atlas.resource_path).contains("hero_battle"),
		"主角战斗姿态取的是 hero_battle"
		+ ("（%s）" % (battle as AtlasTexture).atlas.resource_path if (battle as AtlasTexture) != null else ""))

	# 招募者（随机属性、无专属立绘）必须能回落到原型立绘
	var rec := _make_adventurer("recruit_probe", 4, 4, 9, 4)
	_ok(String(ArtRegistry.archetype_of(rec)) == "arch_scholar",
		"智力最高的招募者 → arch_scholar（实际 %s）" % ArtRegistry.archetype_of(rec))
	_ok(ArtRegistry.adventurer_bust(rec) != null, "招募者拿得到原型立绘（人物卡用）")
	_ok(ArtRegistry.adventurer_battle(rec) != null, "招募者拿得到原型立绘（战场用）")


func _test_specs_and_fallbacks() -> void:
	print("\n-- 规格与缺失回落 --")
	var gd: Node = root.get_node_or_null("/root/GameData")
	var hero: Adventurer = gd.team[0]
	var bust_src := ArtRegistry.unit(hero.id)
	_ok(bust_src != null and bust_src.get_width() == UNIT_W and bust_src.get_height() == UNIT_H,
		"立绘源尺寸 %dx%d" % [bust_src.get_width(), bust_src.get_height()] if bust_src else "立绘源缺失")

	# 163 = 卡面 54 + 物品 67 + 立绘 34 + 场景背景 8。
	# 用下界而不是等号：新增素材时不该假红，但"被数成 0 或两倍"必须红
	_ok(ArtRegistry.available_count() >= 163, "已就绪素材 %d 个（≥163）" % ArtRegistry.available_count())

	# 未出图的 id 一律 null（不崩、不留半成品）
	_ok(ArtRegistry.card("no_such_card_xyz") == null, "未知卡 id → null")
	_ok(ArtRegistry.unit("no_such_unit_xyz") == null, "未知立绘 id → null")
	_ok(ArtRegistry.unit_bust("no_such_unit_xyz") == null, "未知 id 的半身 → null")
	_ok(ArtRegistry.unit_trimmed("no_such_unit_xyz") == null, "未知 id 的裁边 → null")
	_ok(ArtRegistry.unit_battle("no_such_unit_xyz") == null, "未知 id 的战斗立绘 → null")
	_ok(ArtRegistry.adventurer_bust(null) == null, "传 null 冒险者 → null（不崩）")
	_ok(ArtRegistry.monster_battle(null) == null, "传 null 怪物 → null（不崩）")
	_ok(not ArtRegistry.has_card("no_such_card_xyz"), "has_card 对未知 id 为 false")
	_ok(ArtRegistry.has_card("fireball"), "has_card 对已出图的火球术为 true")

	# 裁边结果必须是原图的子区域（AtlasTexture 零拷贝的前提）
	var trimmed: Texture2D = ArtRegistry.unit_trimmed(hero.id)
	var at := trimmed as AtlasTexture
	_ok(at != null and at.atlas == bust_src, "裁边用 AtlasTexture 指向原图（零拷贝）")
	if at != null:
		_ok(at.region.size.x <= UNIT_W and at.region.size.y <= UNIT_H
				and at.region.size.x >= 20 and at.region.size.y >= 20,
			"裁边区域合理 %dx%d" % [at.region.size.x, at.region.size.y])
	var bust_t: Texture2D = ArtRegistry.unit_bust(hero.id)
	var bat := bust_t as AtlasTexture
	_ok(bat != null and is_equal_approx(bat.region.size.y, float(UNIT_H) * 0.64)
			and is_equal_approx(bat.region.position.y, 0.0),
		"半身取上部 64%%（实际高 %.0f）" % (bat.region.size.y if bat != null else -1.0))


func _test_archetype_dispatch() -> void:
	print("\n-- 职业原型派发规则 --")
	# 参数顺序与 _make_adventurer 一致：(体质, 力量, 智力, 精力)
	var cases := [
		[3, 9, 3, 3, "warrior", "力量最高 → 佣兵"],
		[3, 3, 9, 3, "arch_scholar", "智力最高 → 学者"],
		[3, 3, 3, 9, "arch_rogue", "精力最高 → 盗贼"],
		[9, 3, 3, 3, "arch_priest", "体质最高 → 牧师"],
		[5, 5, 5, 5, "arch_ranger", "四属性全 5（平均）→ 游侠"],
		[6, 6, 5, 5, "arch_ranger", "最高值并列(体质/力量=6) 且极差 1 → 游侠"],
		[5, 5, 6, 5, "arch_scholar", "极差虽为 1 但智力**唯一**最高 → 学者"],
		[8, 8, 5, 5, "warrior", "最高值并列但极差 3 → 按固定顺序取力量 → 佣兵"],
	]
	for c in cases:
		var a := _make_adventurer("t", int(c[0]), int(c[1]), int(c[2]), int(c[3]))
		_ok(String(ArtRegistry.archetype_of(a)) == String(c[4]),
			"%s（实际 %s）" % [c[5], ArtRegistry.archetype_of(a)])

	# 确定性：同一个人算两次必须一样（不能随字典遍历顺序漂）
	var probe := _make_adventurer("t", 4, 9, 4, 4)
	var first := String(ArtRegistry.archetype_of(probe))
	var same := true
	for _i in range(30):
		if String(ArtRegistry.archetype_of(probe)) != first:
			same = false
	_ok(same, "原型判定连算 30 次结果一致（%s）" % first)
	_ok(ArtRegistry.archetype_of(null) == "arch_ranger", "null 冒险者回落游侠（不崩）")

	# 每个原型都必须真有立绘，否则招募到的人会是一块空占位
	var missing: Array = []
	for k in ArtRegistry.ARCHETYPES.keys():
		var aid := String(ArtRegistry.ARCHETYPES[k])
		if not ArtRegistry.has_unit(aid):
			missing.append(aid)
	if not ArtRegistry.has_unit(ArtRegistry.ARCHETYPE_BALANCED):
		missing.append(ArtRegistry.ARCHETYPE_BALANCED)
	_ok(missing.is_empty(), "全部原型立绘都已出图（缺 %s）" % str(missing))


func _test_display_settings() -> void:
	print("\n-- 显示设置 --")
	var f := CardFrame.new()
	root.add_child(f)
	f.setup("测试", "描述", Color("#4A6FB5"),
		{"style": CardFrame.STYLE_BATTLE, "image": ArtRegistry.card("fireball"), "tag": "法术进攻"})
	await process_frame
	await process_frame
	_ok(f._art_image.texture != null and f._art_image.visible, "传 image 后插画可见")
	_ok(f._art_image.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"卡面插画用 NEAREST 过滤（否则像素块被线性插值糊掉）")
	_ok(f._art_image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
		"卡面插画铺满图片区（KEEP_ASPECT_COVERED）")

	var f2 := CardFrame.new()
	root.add_child(f2)
	f2.setup("无图", "描述", Color("#4A6FB5"), {"style": CardFrame.STYLE_BATTLE, "tag": "法术进攻"})
	await process_frame
	_ok(not f2._art_image.visible, "不传 image 时插画隐藏（回落占位色块）")
	_ok(not f2._tag_bg.visible, "不传 image 时不补实底药丸（边框自带）")

	f.queue_free()
	f2.queue_free()
	await process_frame


# ---------------------------------------------------------------------------

func _make_adventurer(nm: String, con: int, str_: int, intel: int, vit: int) -> Adventurer:
	var a := Adventurer.new()
	a.id = nm
	a.display_name = nm
	a.constitution = con
	a.strength = str_
	a.intelligence = intel
	a.vitality = vit
	a.base_luck = 3
	return a


func _make_instance(id: String) -> MonsterInstance:
	var md: MonsterData = _db.get_monster(id)
	if md == null:
		return null
	return MonsterInstance.new(md)
