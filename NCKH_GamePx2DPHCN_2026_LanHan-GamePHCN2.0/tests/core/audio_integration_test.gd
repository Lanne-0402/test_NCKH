extends Node
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")
func _run() -> void:
	for id in range(6):
		AudioManager.play_music(id)
		assert(AudioManager.music.playing)
		assert(AudioManager.music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
		assert(AudioManager.music.stream.loop_end > 0)
	for id in range(1,6):
		Global.selected_action = id
		var level = load("res://maps/map_%d/main_level.tscn" % id).instantiate()
		add_child(level)
		await get_tree().process_frame
		await get_tree().process_frame
		var audio = level.get_node("GameplayAudio")
		assert(AudioManager.current_track == id)
		var s = level.get_node("ExerciseSession")
		s.hold_started.emit({})
		if id in [2,3]: assert(audio.action.playing)
		s.hold_interrupted.emit({})
		assert(not audio.action.playing)
		s.repetition_accepted.emit({})
		assert(audio.effects.playing)
		get_tree().paused = true
		await get_tree().process_frame
		await get_tree().process_frame
		assert(AudioManager.music.stream_paused)
		assert(not audio.action.playing)
		AudioManager.play_sfx("ui_click")
		get_tree().paused = false
		await get_tree().process_frame
		await get_tree().process_frame
		assert(not AudioManager.music.stream_paused)
		Global.set_audio_settings(35, true)
		assert(AudioServer.is_bus_mute(0))
		assert(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), .35))
		Global.set_audio_settings(100, false)
		level.queue_free()
		await get_tree().process_frame
		assert(not AudioManager.music.playing)
	print("AUDIO_INTEGRATION: PASS (6 music loops, 5 maps, effects, pause, mute, cleanup)")
	get_tree().quit()
