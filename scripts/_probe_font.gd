extends SceneTree

func _init() -> void:
	await process_frame
	var vp := root
	print("窗口 size=", DisplayServer.window_get_size(), " viewport size=", vp.size)
	print("默认 oversampling=", vp.oversampling)
	vp.content_scale_size = Vector2i(1280, 720)
	vp.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	vp.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await process_frame
	print("[keep] viewport size=", vp.size, " oversampling=", vp.oversampling, " scale=", vp.get_final_transform().get_scale())
	vp.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	print("[expand] viewport size=", vp.size, " oversampling=", vp.oversampling, " scale=", vp.get_final_transform().get_scale())
	quit()
