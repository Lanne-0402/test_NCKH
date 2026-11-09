extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var notice: Node
	var keyboard: Node
	for child in Global.get_children():
		if child.get_script().resource_path.ends_with("save_notice.gd"): notice = child
		if child.get_script().resource_path.ends_with("screen_keyboard.gd"): keyboard = child
	var old_path := Global.save_path
	Global.persistence_enabled = true
	Global.save_path = "user://missing_polish_directory/progress.json"
	assert(not Global.save_progress())
	assert(notice.box.visible and notice.retry.visible)
	Global.save_path = "user://polish_test_%d.json" % Time.get_ticks_usec()
	notice.retry.pressed.emit()
	assert(Global.last_save_error.is_empty())
	assert(notice.message.text == "Đã lưu trên máy" and not notice.retry.visible)
	Global.persistence_enabled = false
	Global.save_path = old_path
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://ui/screens/map_selection/level_selection.tscn")
	await get_tree().scene_changed
	assert(get_viewport().gui_get_focus_owner() == get_tree().current_scene.get_node("MapRows/TopRow/Button"))
	get_tree().change_scene_to_file("res://ui/screens/history/history_screen.tscn")
	await get_tree().scene_changed
	assert(get_viewport().gui_get_focus_owner() == get_tree().current_scene.get_node("BackButton"))
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	keyboard._unhandled_key_input(event)
	await get_tree().scene_changed
	assert(get_tree().current_scene.scene_file_path.ends_with("start_screen.tscn"))
	print("FINAL_POLISH_PASS: failed save, retry, focus, Escape")
	get_tree().quit()
