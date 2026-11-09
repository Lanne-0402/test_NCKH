extends Node
func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(not Global.persistence_enabled)
	get_tree().current_scene = null
	for action in range(1,6):
		Global.selected_action = action
		Global.unlocked_levels_by_action[action] = 2
		get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")
		await get_tree().scene_changed
		await get_tree().process_frame
		await get_tree().process_frame
		var screen = get_tree().current_scene
		var bg = screen.get_node("SceneryBackdrop")
		assert(bg.map_id == action and bg.world.map_id == action)
		assert(bg.scenery_only and not bg.active)
		assert(not bg.world.is_processing())
		assert(bg.material is ShaderMaterial)
		assert(not screen.get_node("ColorRect").visible)
		assert(not screen.get_node("VBoxContainer/Button2").disabled)
		assert(screen.get_node("VBoxContainer/Button3").disabled)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://difficulty_map_%d.png" % action)
		screen.get_node("BackButton").pressed.emit()
		await get_tree().scene_changed
		assert(get_tree().current_scene.scene_file_path == "res://ui/screens/map_selection/level_selection.tscn")
		print("PASS difficulty backdrop map ", action)
	get_tree().quit()
