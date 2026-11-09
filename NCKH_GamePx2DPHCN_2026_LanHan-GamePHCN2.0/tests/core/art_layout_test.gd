extends Node

var capture := false

func _ready() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _shot(file_name: String) -> void:
	if not capture:
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder := "res://tests/visual_output"
	DirAccess.make_dir_recursive_absolute(folder)
	var error := get_viewport().get_texture().get_image().save_png(folder + "/" + file_name + ".png")
	assert(error == OK)

func _run() -> void:
	var home: Node = load("res://ui/screens/start/start_screen.tscn").instantiate()
	home.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(home)
	await get_tree().process_frame
	await _shot("home")
	var menu = home.get_node("SettingsMenu")
	home.get_node("CanvasLayer/SettingsButton").pressed.emit()
	assert(menu.overlay.visible and get_tree().paused)
	assert(menu.resume.text == "ĐÓNG")
	assert(not menu.get_node("Overlay/Center/Panel/Margin/Contents/Home").visible)
	await _shot("home_settings")
	menu.close_menu()
	assert(not get_tree().paused)
	home.queue_free()
	await get_tree().process_frame
	for map_id in range(1, 6):
		Global.selected_action = map_id
		var level: Node = load("res://maps/map_%d/main_level.tscn" % map_id).instantiate()
		level.process_mode = Node.PROCESS_MODE_PAUSABLE
		level.countdown_step_seconds = 0.03
		add_child(level)
		await get_tree().process_frame
		var player = level.get_node("Player")
		assert(player.get_node("FootAnchor").position == Vector2.ZERO)
		assert(player.get_node("Bone").shape.size == Vector2(42, 72))
		assert(player.get_node("SpriteFrame").size == Vector2(128, 128))
		assert(level.get_node("UI/SettingsButton").icon.resource_path == home_gear())
		await _shot("map%d_intro" % map_id)
		level.get_node("UI/InstructionPanel/MarginContainer/VBoxContainer/StartExerciseButton").pressed.emit()
		await get_tree().create_timer(2.6 if capture else 1.0).timeout
		assert(level.get_node("ExerciseSession").state == ExerciseSession.State.ACTIVE)
		assert(player.position.y < 500, "Player must remain on the playable surface")
		if map_id in [2, 3]:
			assert(level.get_node("Ground") is StaticBody2D)
			assert(player.is_on_floor())
		await _shot("map%d_play" % map_id)
		menu = level.get_node("SettingsMenu")
		menu.open_menu()
		assert(menu.overlay.visible and get_tree().paused)
		await get_tree().process_frame
		var panel: Control = menu.get_node("Overlay/Center/Panel")
		assert(panel.size.y <= 648, "Settings must fit design viewport")
		assert(menu.resume.text == "TIẾP TỤC CHƠI")
		await _shot("map%d_settings" % map_id)
		menu.close_menu()
		level.queue_free()
		await get_tree().process_frame
	print("ART_LAYOUT_TEST: PASS (Home Settings, 5 maps, pivot, collider, menu bounds)")
	get_tree().quit()

func home_gear() -> String:
	return "res://ui/shared/settings_gear.svg"
