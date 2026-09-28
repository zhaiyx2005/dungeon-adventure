## 卡面描述「装不下被截断」探针
##
## CardFrame 的描述用 _autofit() 逐级缩小字号（下限 MIN_FONT_DESC=8），仍装不下就 clip_text 静默截断。
## 卡面是固定尺寸的，所以只要文案变长就可能悄悄被吃掉一截 —— 肉眼很难发现。
## 本脚本对**全部卡牌 + 全部物品**（9-26 起物品也进卡牌大全了）在**每个真实卡面尺寸**下量一次：
##   font.get_multiline_string_size(text, LEFT, rect_w, 实际字号).y > rect_h + 0.5  →  被截断
##
## 物品的文案必须走 `ItemData.get_card_desc_cn()`（UI 也是同一个方法），
## 探针自己另拼一份就一定会漂移 —— 那样"改了文案漏检"是迟早的事。
##
## 跑法：python godot_run.py _probe_descfit.gd <log> --render
extends SceneTree


const SIZES := {
	"hand": Vector2(112, 157),      # CardView.CARD_SIZE
	"town": Vector2(128, 179),      # 城镇战斗卡
	"deck": Vector2(120, 162),      # 卡组编辑卡池
	"codex": Vector2(128, 179),     # 卡牌大全
}

## 物品卡**在任何界面**都是这个尺寸（town_scene._item_card 写死 custom_minimum_size）。
## 手牌 112×157 与卡组 120×162 只用于战斗卡牌，物品根本不会以那两个尺寸出现 ——
## 拿它们去量物品只会产出假告警，把真问题淹掉。
const ITEM_CARD_SIZE := Vector2(128, 179)


func _init() -> void:
	call_deferred("_run")


## 量一张卡面的描述装不装得下。
##
## 返回 1 = 被截断（0 = 装得下），明细追加到 `worst`，并就地递增 `bad` 由调用方处理。
## 抽成函数是为了让**卡牌**与**物品**共用同一套判定 —— 两处各写一遍必然漂移。
func _measure(cf: CardFrame, label: String, worst: Array) -> int:
	var lbl: Label = cf._desc_label
	var rect: Rect2 = lbl.get_rect()
	var font: Font = lbl.get_theme_font("font")
	var fs: int = lbl.get_theme_font_size("font_size")
	var need: Vector2 = font.get_multiline_string_size(
		lbl.text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, fs)
	var line_h: float = font.get_height(fs)
	# Label 的 line_spacing 只作用在行与行之间（n 行有 n-1 个间隙），
	# 而 font.get_multiline_string_size() 不知道这个常量 —— 必须自己补上，
	# 否则探针结论会比实际渲染更悲观。
	var lsp: int = lbl.get_theme_constant("line_spacing")
	var n_lines: int = maxi(1, int(round(need.y / maxf(line_h, 1.0))))
	var real_h: float = need.y + float(lsp) * float(n_lines - 1)
	var over: float = real_h - rect.size.y
	if over <= 0.5:
		return 0
	# 超过一整行 = 直接丢掉一行字（严重）；只超几像素 = 末行底部被切一点点（轻微）
	var sev := "严重(丢行)" if over >= line_h else "轻微(切边)"
	worst.append("%-18s %s  需 %.0f / 有 %.0f（多 %.0f，行高 %.0f，行距 %d，字号 %d）"
		% [label, sev, real_h, rect.size.y, over, line_h, lsp, fs])
	return 1


func _run() -> void:
	await create_timer(0.4).timeout
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		print("拿不到 GameData")
		quit(1)
		return

	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)

	var bad := 0
	var checked := 0
	for key in SIZES.keys():
		var size: Vector2 = SIZES[key]
		print("\n===== %s  %dx%d =====" % [key, int(size.x), int(size.y)])
		var worst := []

		# ---- 战斗卡牌（battle 版式）----
		for cid in gd.db.cards.keys():
			var c: CardData = gd.db.get_card(String(cid))
			if c == null:
				continue
			var cf := CardFrame.new()
			cf.custom_minimum_size = size
			holder.add_child(cf)
			await process_frame
			var cat: String = c.get_category_name_cn()
			var tag_text := "共鸣" if c.has_combo() else cat
			var chead := "%s · %s" % [cat, c.get_rarity_name_cn()]
			if c.has_combo():
				chead = c.get_combo_hint_cn()
			cf.setup(c.display_name, "%s\n%s" % [chead, c.description],
				Color(c.art_placeholder),
				{
					"style": CardFrame.STYLE_BATTLE,
					"tag": tag_text,
					"badge_l": "%d" % c.action_cost,
					"badge_r": "%d" % c.mana_cost if c.mana_cost > 0 else "",
				})
			await process_frame
			checked += 1
			bad += _measure(cf, "卡 " + c.id, worst)
			cf.queue_free()
			await process_frame

		# ---- 物品卡（person 版式）。文案走 ItemData.get_card_desc_cn()，
		#      与 town_scene._item_card 是**同一份拼装**，改文案不会漏检 ----
		# 只在 128×179 量：物品卡在任何界面都是这个尺寸（_item_card 写死 custom_minimum_size），
		# 手牌 112×157 / 卡组 120×162 只用于战斗卡牌 —— 拿它们量物品只会产假告警。
		if size == ITEM_CARD_SIZE:
			for iid in gd.db.items.keys():
				var it: ItemData = gd.db.get_item(String(iid))
				if it == null:
					continue
				var cf2 := CardFrame.new()
				cf2.custom_minimum_size = size
				holder.add_child(cf2)
				await process_frame
				cf2.setup(it.display_name, it.get_card_desc_cn(), it.get_rarity_color(),
					{"badge_l": it.get_rarity_name_cn(), "badge_r": it.get_slot_name_cn()})
				await process_frame
				checked += 1
				bad += _measure(cf2, "物 " + it.id, worst)
				cf2.queue_free()
				await process_frame

		if worst.is_empty():
			print("  全部装得下")
		else:
			print("  截断 %d 张：" % worst.size())
			for w in worst:
				print("    " + w)

	holder.queue_free()
	print("\n===== 共检查 %d 张卡面，截断 %d 处 =====" % [checked, bad])
	quit(0)
