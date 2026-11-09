extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(not Global.persistence_enabled)
	get_tree().current_scene = null
	var history := JSON.stringify(Global.session_history)
	var selected: int = Global.selected_action
	var session: String = PoseInput.active_session_id
	get_tree().change_scene_to_file("res://ui/screens/map_selection/level_selection.tscn")
	await get_tree().scene_changed
	await get_tree().process_frame
	await get_tree().process_frame
	var screen = get_tree().current_scene
	assert(screen.previews.size() == 5)
	await _capture("static")
	for i in range(5):
		var preview = screen.previews[i]
		assert(not preview.active)
		assert(preview.world.actor.outfit_enabled)
		preview.get_parent().mouse_entered.emit()
		await get_tree().create_timer(1.6).timeout
		assert(preview.active and preview.world.clock > 1.0)
		for other in screen.previews:
			if other != preview:
				assert(not other.active)
				assert(other.world.clock == 0.0)
		await _capture("hover_map_%d" % (i+1))
		preview.get_parent().mouse_exited.emit()
		await get_tree().process_frame
		assert(not preview.active and preview.world.clock == 0.0)
		assert(not preview.world.is_processing())
		preview.get_parent().focus_entered.emit()
		assert(preview.active)
		preview.get_parent().focus_exited.emit()
	assert(Global.selected_action == selected)
	assert(JSON.stringify(Global.session_history) == history)
	assert(PoseInput.active_session_id == session)
	assert(screen.get_node("SceneryBackdrop").world.clock == 0.0)
	print("MAP_PREVIEW_IDLE_HOVER_RESET_ISOLATION: PASS")
	get_tree().quit()

func _capture(suffix: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := "user://map_preview_%s.png" % suffix
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE: ",ProjectSettings.globalize_path(path))
