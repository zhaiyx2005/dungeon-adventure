## 探针：弃牌模式到底有多少可用空间（决定放大倍率与是否分行）
## 跑法：python godot_run.py _probe_discard.gd <log> --render
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await create_timer(0.5).timeout
	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(1.2).timeout
	var b: Node = current_scene

	var base: Vector2 = b.CARD_VIEW.CARD_SIZE
	print("逻辑分辨率 = %s" % (b as Control).size)
	print("CARD_SIZE = %s" % base)
	print("手牌张数 = %d" % b._card_views.size())

	var bottom: Control = b.get_node("%Bottom")
	print("Bottom 常态高 = %.0f（size=%.0f）" % [bottom.custom_minimum_size.y, bottom.size.y])

	var row: Control = bottom.get_node("BottomMargin/BottomRow")
	print("BottomRow size = %s" % row.size)
	for ch in row.get_children():
		print("  子节点 %s: size=%s visible=%s" % [ch.name, ch.size, ch.visible])

	var slot: Control = b.get_node("%HandSlot")
	print("常态 HandSlot size = %s" % slot.size)

	# 纵向预算：把 Bottom 加高会挤压 Middle，先看清各段高度与单位卡高度
	var root_node: Control = b.get_node("Root")
	for ch in root_node.get_children():
		print("  Root 子节点 %s: size=%s（最小 %s）" % [ch.name, ch.size, ch.custom_minimum_size])
	var field: Control = b.get_node("%Battlefield")
	print("Battlefield size = %s" % field.size)
	var max_unit := 0.0
	for uv in b._unit_views:
		max_unit = maxf(max_unit, uv.size.y + uv.position.y)
	print("单位卡纵向占用最大 = %.0f" % max_unit)
	var panel: Control = b.get_node("%SelectPanel") if b.get_node_or_null("%SelectPanel") != null else null
	print("（无 SelectPanel 属正常）%s" % (panel != null))

	# 进弃牌模式再看一次
	b._on_discard_mode()
	await create_timer(0.3).timeout
	await process_frame
	await process_frame
	print("弃牌模式 HandSlot size = %s" % slot.size)
	print("弃牌模式放大倍率 = %.3f" % (b._card_views[0] as Control).scale.x)

	# 逐档模拟：单行 / 双行 需要多少高度、能放大到多少
	var n: int = b._card_views.size()
	var usable_w: float = maxf(slot.size.x - 8.0, base.x)
	for rows in [1, 2, 3]:
		var per_row: int = int(ceil(float(n) / float(rows)))
		for gap in [6.0, 10.0]:
			var by_w: float = (usable_w - gap * float(per_row - 1)) / (base.x * float(per_row))
			var need_h: float = (base.y * by_w + gap) * float(rows - 1) + base.y * by_w
			print("  %d 行 × %d 张 gap=%.0f → 宽度允许 %.3f 倍，整块高 %.0f px（可用 %.0f）"
				% [rows, per_row, gap, by_w, need_h, maxf(slot.size.y - 6.0, base.y)])
	quit(0)
