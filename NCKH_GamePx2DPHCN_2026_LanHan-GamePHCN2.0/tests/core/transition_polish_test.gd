extends Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	var reveal: Node
	for child in Global.get_children():
		if child is CanvasLayer: reveal = child
	assert(reveal != null)
	reveal._reveal()
	assert(reveal.veil.visible)
	assert(reveal.veil.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	await get_tree().create_timer(0.1).timeout
	reveal._reveal()
	get_tree().paused = true
	await get_tree().create_timer(0.4).timeout
	assert(not reveal.veil.visible)
	assert(get_tree().paused)
	get_tree().paused = false
	AudioManager.play_music(1)
	AudioManager.play_music(2)
	await get_tree().create_timer(0.55).timeout
	assert(AudioManager.current_track == 2)
	assert(is_equal_approx(AudioManager.music.volume_db, -14.0))
	for voice in AudioManager.voices: voice.stop()
	AudioManager.play_sfx("ui_hover")
	assert(is_equal_approx(AudioManager.voices[0].volume_db, -18.0))
	AudioManager.voices[0].stop()
	AudioManager.play_sfx("ui_click")
	assert(is_equal_approx(AudioManager.voices[0].volume_db, -12.0))
	print("TRANSITION_POLISH: PASS (reentry, pause, input, music fade, UI gain)")
	get_tree().quit()
