## 全量完整性诊断（静态）
##   1. 所有 .gd 脚本能否加载解析
##   2. 所有 .tscn 场景能否加载并实例化
##   3. 所有 .tres 数据资源能否加载
##   4. 场景/资源文本里引用的 res:// 路径是否都存在（抓素材被删/改名）
##   5. ValidateData 数据校验 + GameData 数据摘要
## 跑法：python godot_run.py _t_integrity.gd <log>
extends SceneTree


var _errors: Array[String] = []
var _warns: Array[String] = []
var _n_gd := 0
var _n_tscn := 0
var _n_tres := 0
var _n_ref := 0


func _init() -> void:
	call_deferred("_run")


func _collect(dir_path: String, ext: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var fname: String = d.get_next()
	while fname != "":
		var full: String = dir_path.path_join(fname)
		if d.current_is_dir():
			if not fname.begins_with("."):
				_collect(full, ext, out)
		elif fname.ends_with(ext):
			out.append(full)
		fname = d.get_next()
	d.list_dir_end()


## 扫文本里的 res:// 引用，检查目标存在
func _check_refs(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var re := RegEx.new()
	re.compile("path=\"(res://[^\"]+)\"")
	for m in re.search_all(text):
		var ref: String = m.get_string(1)
		_n_ref += 1
		if not FileAccess.file_exists(ref):
			_errors.append("缺失引用：%s -> %s" % [path, ref])


func _run() -> void:
	await process_frame

	# ---- 1. 脚本 ----
	var gd_files: Array = []
	_collect("res://scripts", ".gd", gd_files)
	for p in gd_files:
		_n_gd += 1
		var r: Resource = load(p)
		if r == null:
			_errors.append("脚本加载失败：%s" % p)

	# ---- 2. 场景 ----
	var tscn_files: Array = []
	_collect("res://scenes", ".tscn", tscn_files)
	for p in tscn_files:
		_n_tscn += 1
		_check_refs(p)
		var packed: Resource = load(p)
		if packed == null:
			_errors.append("场景加载失败：%s" % p)
			continue
		var inst: Node = null
		if packed is PackedScene:
			inst = (packed as PackedScene).instantiate()
		if inst == null:
			_errors.append("场景实例化失败：%s" % p)
		else:
			inst.free()

	# ---- 3. 数据资源 ----
	var tres_files: Array = []
	_collect("res://data", ".tres", tres_files)
	for p in tres_files:
		_n_tres += 1
		var r: Resource = load(p)
		if r == null:
			_errors.append("数据资源加载失败：%s" % p)

	# ---- 4. 主题 / 字体 ----
	_check_refs("res://assets/theme_main.tres")
	var th: Theme = load("res://assets/theme_main.tres")
	if th == null:
		_errors.append("主题加载失败：res://assets/theme_main.tres")
	else:
		# 浅色主题必须是深字；缺失字色会退回引擎默认白色 → 白底白字看不见
		for pair in [["Label", "font_color"], ["Button", "font_color"], ["RichTextLabel", "default_color"]]:
			var tname: String = pair[0]
			var cname: String = pair[1]
			if not th.has_color(cname, tname):
				_errors.append("主题缺少字色 %s/%s（会退回默认白色，浅色底看不见）" % [tname, cname])
			else:
				var tc: Color = th.get_color(cname, tname)
				if tc.get_luminance() > 0.6:
					_errors.append("主题字色过亮 %s/%s = %s" % [tname, cname, tc])
				else:
					print("主题字色 OK：%s/%s = %s" % [tname, cname, tc])
	for p in ["res://assets/fonts/msyh.ttc", "res://assets/fonts/simhei.ttf",
			"res://assets/images/card/card_border_model.png",
			"res://assets/images/splash/splash_morning.png",
			"res://assets/images/splash/splash_noon.png",
			"res://assets/images/splash/splash_afternoon.png",
			"res://assets/images/splash/splash_evening.png",
			"res://icon.svg"]:
		if not FileAccess.file_exists(p):
			_errors.append("必备素材缺失：%s" % p)

	# ---- 5. 数据校验 + GameData ----
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		_errors.append("autoload GameData 未加载")
	else:
		if gd.db == null:
			_errors.append("GameData.db 为空")
		else:
			print("数据摘要：", gd.db.summary())
		var vd: GDScript = load("res://scripts/core/validate_data.gd")
		if vd != null:
			var ok: bool = vd.run_all()
			print("ValidateData.run_all() = ", ok)
			if not ok:
				for e in vd.get_errors():
					_errors.append("数据校验：" + str(e))

	# ---- 6. 界面约定（9-22 修改意见 1/3）----
	var sp_packed: PackedScene = load("res://scenes/splash_scene.tscn")
	if sp_packed != null:
		var sp: Node = sp_packed.instantiate()
		var title: Label = sp.get_node_or_null("%GameTitle")
		var hint: Label = sp.get_node_or_null("%ClickHint")
		if title != null:
			# 意见1：标题要落在画面中间偏上（按 720 高换算约 y=200–290），不挡主画面
			var ty: float = title.offset_top
			if ty < 160.0 or ty > 330.0:
				_errors.append("开屏标题位置不符（offset_top=%.0f，应约 200 左右，意见1）" % ty)
			else:
				print("开屏标题位置 OK：offset_top=%.0f" % ty)
		else:
			_errors.append("开屏页缺少 %GameTitle")
		if hint != null:
			# 意见1：点击提示要更靠下
			if hint.anchor_top < 0.75:
				_errors.append("开屏点击提示位置偏上（anchor_top=%.2f，应 ≥0.75，意见1）" % hint.anchor_top)
			else:
				print("开屏提示位置 OK：anchor_top=%.2f" % hint.anchor_top)
		else:
			_errors.append("开屏页缺少 %ClickHint")
		# 节点级纹理过滤（比 project.godot 更抗被编辑器覆盖）
		for nname in ["%ImageFront", "%ImageBack"]:
			var tex_node: TextureRect = sp.get_node_or_null(nname) as TextureRect
			if tex_node == null:
				_errors.append("开屏页缺少 %s" % nname)
			elif tex_node.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
				_errors.append("开屏图 %s 未用「线性+Mipmap」过滤（意见3）" % nname)
			else:
				print("开屏图 %s 过滤 OK" % nname)
		sp.free()
	# 开屏图贴图需开 mipmap
	for sn in ["morning", "noon", "afternoon", "evening"]:
		var sip := "res://assets/images/splash/splash_%s.png.import" % sn
		var sim: String = FileAccess.get_file_as_string(sip)
		if not sim.contains("mipmaps/generate=true"):
			_errors.append("开屏图 %s 未开启 mipmap（意见3）" % sn)

	# 意见3：手牌/卡面清晰度 —— 全局纹理过滤 + 卡面 mipmap
	var proj_text := ""
	var pf := FileAccess.open("res://project.godot", FileAccess.READ)
	if pf != null:
		proj_text = pf.get_as_text()
		pf.close()
	# 全局纹理过滤：只作提示 —— Godot 编辑器保存时会重写 project.godot 抹掉这行，
	# 真正可靠的保证是节点级过滤（下面单独校验）
	if not proj_text.contains("textures/canvas_textures/default_texture_filter=1"):
		_warns.append("project.godot 的全局纹理过滤非线性（可能被编辑器覆盖，节点级过滤已兜底）")
	else:
		print("全局纹理过滤 OK：线性")
	var imp_text := ""
	var imp := FileAccess.open("res://assets/images/card/card_border_model.png.import", FileAccess.READ)
	if imp != null:
		imp_text = imp.get_as_text()
		imp.close()
	if not imp_text.contains("mipmaps/generate=true"):
		_errors.append("卡面贴图未开启 mipmap（缩小到 100×132 会发虚，意见3）")
	else:
		print("卡面 mipmap OK")
	var cf := CardFrame.new()
	root.add_child(cf)
	await process_frame
	var frame_node: TextureRect = cf.get_child(0) as TextureRect
	if frame_node == null:
		_errors.append("CardFrame 结构异常：第一个子节点不是 TextureRect")
	elif frame_node.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		_errors.append("卡面纹理过滤未用「线性+Mipmap」（意见3）")
	else:
		print("卡面纹理过滤 OK：线性 + Mipmap")
	cf.free()

	# ---- 汇总 ----
	print("-----------------------------")
	print("检查：脚本 %d / 场景 %d / 数据 %d / 路径引用 %d" % [_n_gd, _n_tscn, _n_tres, _n_ref])
	if _warns.size() > 0:
		print("警告 %d：" % _warns.size())
		for w in _warns:
			print("  [WARN] " + w)
	if _errors.size() == 0:
		print("完整性诊断：全部通过，0 错误")
	else:
		print("完整性诊断：%d 个错误" % _errors.size())
		for e in _errors:
			print("  [ERR] " + e)
	quit(0)
