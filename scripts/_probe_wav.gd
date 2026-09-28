extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for p in ["res://assets/audio/bgm_title.wav", "res://assets/audio/sfx_ui_click.wav"]:
		var s: AudioStream = load(p)
		var w := s as AudioStreamWAV
		print("--- ", p)
		if w == null:
			print("  不是 AudioStreamWAV")
			continue
		print("  loop_mode=", w.loop_mode, " loop_begin=", w.loop_begin, " loop_end=", w.loop_end)
		print("  format=", w.format, " stereo=", w.stereo, " mix_rate=", w.mix_rate)
		print("  data.size=", w.data.size(), " length=", s.get_length())
	print("LOOP_FORWARD 枚举值 = ", AudioStreamWAV.LOOP_FORWARD)
	quit(0)
