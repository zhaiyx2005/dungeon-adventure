## 量取战斗卡边框的分区比例（一次性分析脚本）
## 输出：中线/横线颜色分段 + 绿徽章(行动点) / 蓝徽章(蓝量) 的包围盒
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _dist(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


## axis="y"：沿竖直方向扫，fixed 是 x；axis="x"：沿水平方向扫，fixed 是 y
func _scan_line(img: Image, axis: String, fixed: int) -> void:
	if axis == "y":
		var h := img.get_height()
		var prev := img.get_pixel(fixed, 0)
		var start := 0
		for y in range(1, h):
			var c := img.get_pixel(fixed, y)
			if _dist(c, prev) > 0.08:
				print("  竖直 y %4d..%4d (%.3f..%.3f) #%s" % [start, y - 1, float(start) / h, float(y - 1) / h, prev.to_html(false)])
				start = y
			prev = c
		print("  竖直 y %4d..%4d (%.3f..%.3f) #%s" % [start, h - 1, float(start) / h, float(h - 1) / h, prev.to_html(false)])
	else:
		var w := img.get_width()
		var prev2 := img.get_pixel(0, fixed)
		var start2 := 0
		for x in range(1, w):
			var c2 := img.get_pixel(x, fixed)
			if _dist(c2, prev2) > 0.08:
				print("  水平 x %4d..%4d (%.3f..%.3f) #%s" % [start2, x - 1, float(start2) / w, float(x - 1) / w, prev2.to_html(false)])
				start2 = x
			prev2 = c2
		print("  水平 x %4d..%4d (%.3f..%.3f) #%s" % [start2, w - 1, float(start2) / w, float(w - 1) / w, prev2.to_html(false)])


## 找某色系的包围盒（比例）
func _bbox(img: Image, kind: String) -> Rect2:
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -1
	var y1 := -1
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var hit := false
			if kind == "green":
				hit = c.g > 0.55 and c.r < 0.45 and c.b < 0.6 and c.g > c.r + 0.2
			elif kind == "blue":
				hit = c.b > 0.6 and c.r < 0.45 and c.b > c.g + 0.15
			if hit:
				x0 = mini(x0, x); y0 = mini(y0, y)
				x1 = maxi(x1, x); y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2()
	var w := float(img.get_width())
	var h := float(img.get_height())
	return Rect2(x0 / w, y0 / h, (x1 - x0 + 1) / w, (y1 - y0 + 1) / h)


func _run() -> void:
	var img: Image = Image.load_from_file("res://assets/images/card/battle_card_border.png")
	if img == null:
		print("加载失败")
		quit(1)
		return
	var w := img.get_width()
	var h := img.get_height()
	print("尺寸 %dx%d" % [w, h])
	print("-- 中线（x=50%）--")
	_scan_line(img, "y", int(w * 0.5))
	print("-- 图片框横线（y=35%）--")
	_scan_line(img, "x", int(h * 0.35))
	print("-- 描述区横线（y=80%）--")
	_scan_line(img, "x", int(h * 0.80))
	var g := _bbox(img, "green")
	var b := _bbox(img, "blue")
	print("绿徽章(行动点) bbox: x %.3f..%.3f  y %.3f..%.3f  中心(%.3f, %.3f)" % [g.position.x, g.end.x, g.position.y, g.end.y, g.get_center().x, g.get_center().y])
	print("蓝徽章(蓝量)   bbox: x %.3f..%.3f  y %.3f..%.3f  中心(%.3f, %.3f)" % [b.position.x, b.end.x, b.position.y, b.end.y, b.get_center().x, b.get_center().y])
	quit(0)
