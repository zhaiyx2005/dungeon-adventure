## 手牌排布探针：打印每张卡的位置/尺寸/可见性，定位空档
## 跑法：python godot_run.py _probe_hand.gd <log> --render
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await create_timer(0.5).timeout
	change_scene_to_file("res://scenes/battle/battle_scene.tscn")
	await create_timer(1.2).timeout
	var b: Node = current_scene
	var slot: Control = b._hand_slot
	print("HandSlot rect = %s / 卡牌数 = %d" % [slot.get_rect(), b._card_views.size()])
	for i in range(b._card_views.size()):
		var v = b._card_views[i]
		print("  #%d %-14s pos=(%.1f, %.1f) size=(%.1f, %.1f) rot=%.1f visible=%s mod_a=%.2f z=%d"
			% [i, v.card.display_name if v.card != null else "?", v.position.x, v.position.y,
				v.size.x, v.size.y, v.rotation_degrees, v.visible, v.modulate.a, v.z_index])
	quit(0)
