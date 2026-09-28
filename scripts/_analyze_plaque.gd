## 用描边色定位战斗卡「名字牌」轮廓 bbox（一次性分析）
## 跑法：python godot_run.py _analyze_plaque.gd <log>
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var img: Image = Image.load_from_file("res://assets/images/card/battle_card_border.png")
	var w := img.get_width()
	var h := img.get_height()
	# 深棕描边 #7b5928 附近
	var target := Color("#7b5928")
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -1
	var y1 := -1
	var rowcount := {}
	for y in range(int(h * 0.02), int(h * 0.22)):
		for x in range(w):
			var c := img.get_pixel(x, y)
			if c.a < 0.6:
				continue
			if absf(c.r - target.r) < 0.12 and absf(c.g - target.g) < 0.12 and absf(c.b - target.b) < 0.12:
				x0 = mini(x0, x); y0 = mini(y0, y)
				x1 = maxi(x1, x); y1 = maxi(y1, y)
				rowcount[y] = int(rowcount.get(y, 0)) + 1
	if x1 < 0:
		print("未找到描边色")
		quit(1)
		return
	print("描边色 bbox: x %.4f..%.4f  y %.4f..%.4f"
		% [float(x0) / w, float(x1) / w, float(y0) / h, float(y1) / h])
	# 找出描边像素最密集的行（= 名字牌的上下横边）
	var rows := rowcount.keys()
	rows.sort()
	var dense := []
	for r in rows:
		if int(rowcount[r]) > int(w * 0.5):
			dense.append(r)
	print("横边候选行（描边像素 > 半宽）：")
	for r in dense:
		print("  y %.4f  (像素 %d)" % [float(r) / h, int(rowcount[r])])
	if dense.size() >= 2:
		print("→ 名字牌上边 y %.4f / 下边 y %.4f" % [float(dense[0]) / h, float(dense[dense.size() - 1]) / h])
	quit(0)
