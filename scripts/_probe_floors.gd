## 量一下出征准备面板的可用宽度，给「层阶梯」行定宽用
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await create_timer(0.5).timeout
	var gd: Node = root.get_node_or_null("/root/GameData")
	gd.gold = 50000
	change_scene_to_file("res://scenes/dungeon/run_scene.tscn")
	await create_timer(0.9).timeout
	var rs: Node = current_scene
	rs._on_prep_tab("overview")
	await process_frame
	await process_frame

	var scroll: Control = rs.get_node("%SelectScroll")
	var list: Control = rs.get_node("%SelectList")
	var panel: Control = rs.get_node("%SelectPanel")
	print("\n[量宽] SelectPanel = %.0f x %.0f" % [panel.size.x, panel.size.y])
	print("[量宽] SelectScroll = %.0f x %.0f  (横向滚动条 max=%.0f)" % [
		scroll.size.x, scroll.size.y, (scroll as ScrollContainer).get_h_scroll_bar().max_value])
	print("[量宽] SelectList  = %.0f x %.0f" % [list.size.x, list.size.y])

	# 逐行打印层阶梯的宽度预算
	for row in list.get_children():
		if not (row is HBoxContainer):
			continue
		var sum := 0.0
		var parts: Array = []
		for ch in row.get_children():
			var c := ch as Control
			sum += c.custom_minimum_size.x
			var t := ""
			if ch is Button:
				t = (ch as Button).text
			elif ch is Label:
				t = (ch as Label).text
			parts.append("%.0f|%s" % [c.custom_minimum_size.x, t.substr(0, 14)])
		print("[行 %d] min 合计 %.0f / 可用 %.0f -> %s" % [
			row.get_index(), sum, scroll.size.x, ", ".join(parts)])

	quit(0)
