extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(not Global.persistence_enabled)
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://ui/screens/map_selection/level_selection.tscn")
	await get_tree().scene_changed
	await get_tree().process_frame
	await get_tree().process_frame
	var screen = get_tree().current_scene
	assert(screen.get_node_or_null("ScrollContainer") == null)
	var buttons: Array[Button] = []
	for action in range(1, 6):
		var path := "MapRows/" + ("TopRow/" if action <= 3 else "BottomRow/") + ("Button" if action == 1 else "Button%d" % action)
		var card: Button = screen.get_node(path)
		assert(card.is_visible_in_tree() and not card.disabled)
		assert(card.size == Vector2(296, 216))
		assert(screen.get_global_rect().encloses(card.get_global_rect()))
		for previous in buttons:
			assert(not previous.get_global_rect().intersects(card.get_global_rect()))
		buttons.append(card)
	assert(is_equal_approx(buttons[0].global_position.y, buttons[2].global_position.y))
	assert(is_equal_approx(buttons[3].global_position.y, buttons[4].global_position.y))
	var bottom_center := (buttons[3].global_position.x + buttons[4].global_position.x + buttons[4].size.x) / 2.0
	assert(is_equal_approx(bottom_center, screen.size.x / 2.0))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://map_selection_layout.png")
		print("SCREENSHOT: ", OS.get_user_data_dir(), "/map_selection_layout.png")
	for action in range(1, 6):
		if action > 1:
			get_tree().change_scene_to_file("res://ui/screens/map_selection/level_selection.tscn")
			await get_tree().scene_changed
		var path := "MapRows/" + ("TopRow/" if action <= 3 else "BottomRow/") + ("Button" if action == 1 else "Button%d" % action)
		get_tree().current_scene.get_node(path).pressed.emit()
		await get_tree().scene_changed
		assert(Global.selected_action == action)
		assert(get_tree().current_scene.scene_file_path == "res://ui/screens/level_selection/main_menu.tscn")
	get_tree().change_scene_to_file("res://ui/screens/map_selection/level_selection.tscn")
	await get_tree().scene_changed
	get_tree().current_scene.get_node("BackButton").pressed.emit()
	await get_tree().scene_changed
	assert(get_tree().current_scene.scene_file_path == "res://ui/screens/calibration/calibration_screen.tscn")
	print("MAP_SELECTION_LAYOUT_AND_BUTTONS: PASS")
	get_tree().quit()
