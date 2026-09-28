## 边框素材 + 比例网格 叠加渲染（用于目测分区）
## 网格：竖直每 5% 一条细线，水平每 10% 一条，并标出 0.10 / 0.50 / 0.90 的粗线
## 跑法：python godot_run.py _shot_border_grid.gd <log> --render
extends SceneTree


const OUT := "E:/goodot_work/地牢冒险记/preview/"
const CW := 400.0
const CH := 560.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await create_timer(0.4).timeout
	var bg := ColorRect.new()
	bg.color = Color("#1a1a1a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(holder)

	var tex := TextureRect.new()
	tex.texture = load("res://assets/images/card/battle_card_border.png")
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tex.position = Vector2(60, 70)
	tex.size = Vector2(CW, CH)
	holder.add_child(tex)

	for i in range(1, 20):
		var f := float(i) * 0.05
		var l := ColorRect.new()
		l.color = Color(0.1, 0.9, 0.4, 0.85) if i % 2 == 0 else Color(0.9, 0.9, 0.3, 0.45)
		l.position = Vector2(60, 70 + f * CH)
		l.size = Vector2(CW, 1 if i % 2 != 0 else 2)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(l)
		var t := Label.new()
		t.text = "%.2f" % f
		t.position = Vector2(60 + CW + 4, 70 + f * CH - 8)
		t.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
		holder.add_child(t)
	for i in range(1, 10):
		var f2 := float(i) * 0.1
		var l2 := ColorRect.new()
		l2.color = Color(0.3, 0.7, 1.0, 0.45)
		l2.position = Vector2(60 + f2 * CW, 70)
		l2.size = Vector2(1, CH)
		l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(l2)

	await process_frame
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	print("网格图 -> %s (err=%d)" % [OUT + "rev4_border_grid.png", img.save_png(OUT + "rev4_border_grid.png")])
	quit(0)
