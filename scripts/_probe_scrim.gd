## 压光度对比探针：同一张背景 × 多档 scrim，用来选"背景可见 / 文字可读"的平衡点。
## 跑法：python godot_run.py _probe_scrim.gd <log> --render
extends SceneTree

const OUT := "E:/goodot_work/地牢冒险记/preview/"
const STEPS := [0.45, 0.55, 0.65, 0.75, 0.85]


func _init() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)


func _run() -> void:
	await create_timer(0.5).timeout
	var gd: Node = root.get_node_or_null("/root/GameData")
	gd.pending_initial_tab = "卡牌大全"
	gd.last_battle_result = {}
	gd.pending_encounter = {}
	change_scene_to_file("res://scenes/town/town_scene.tscn")
	await create_timer(1.0).timeout
	var town: Node = current_scene
	town._switch_tab(4)
	await create_timer(0.5).timeout
	var bd: Node = town.get_node("SceneBackdrop")
	for a in STEPS:
		bd.set_scrim(a)
		await create_timer(0.35).timeout
		var p := OUT + "scrim_%d.png" % int(a * 100)
		await _shot(p)
		print("scrim %.2f -> %s" % [a, p])
	quit(0)
