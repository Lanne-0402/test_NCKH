extends Node
const Display := preload("res://ui/shared/session_display.gd")
class SessionStub extends Node:
	signal session_completed(summary: Dictionary)

func _ready() -> void: call_deferred("_run")
func _run() -> void:
	assert(not Global.persistence_enabled)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1152,760))
	var now := Time.get_unix_time_from_datetime_string("2026-11-01T12:00:00")
	var sample := {"session_id":"FE-TEST","patient_id":"BN001","status":"completed","map_id":2,"difficulty":1,"ended_at_utc":"2026-11-01T08:00:00","completed_reps":10,"target_reps":10,"completed_sets":2,"target_sets":2,"active_seconds":126,"rest_seconds":30,"paused_seconds":8,"tracking_lost_seconds":4,"valid_reps":10,"rejected_reps":1,"evaluation":"HOÀN THÀNH","duration_source":"godot_state_timer"}
	var stopped := sample.duplicate(true)
	stopped.status = "stopped_early"
	stopped.map_id = 3
	stopped.ended_at_utc = "2026-10-01T08:00:00"
	assert(Display.filter_history([sample,stopped],2,"completed",7,now).size() == 1)
	assert(Display.filter_history([sample,stopped],0,"stopped_early",7,now).is_empty())
	assert(Display.filter_history([sample,stopped],0,"stopped_early",0,now).size() == 1)
	assert(Display.progress_ratio({}) == -1)
	assert(Display.progress_ratio({"completed_reps":0,"target_reps":0}) == -1)
	Global.session_history = [sample,stopped]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152,760)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var history = load("res://ui/screens/history/history_screen.tscn").instantiate()
	viewport.add_child(history)
	await get_tree().process_frame
	history._map_filter.select(2)
	history._refresh_all()
	assert(history._filter_count.text.contains("1/2"))
	if DisplayServer.get_name() != "headless":
		history.get_node("Margin/Column/Scroll").scroll_vertical = 10000
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://session-fe-history.png")
	history.queue_free()
	await get_tree().process_frame
	var level := Control.new()
	viewport.add_child(level)
	level.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ui := Control.new()
	ui.name = "UI"
	level.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "ResultPanel"
	panel.hide()
	ui.add_child(panel)
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "VBoxContainer"
	margin.add_child(column)
	var label := Label.new()
	label.name = "ResultLabel"
	column.add_child(label)
	var button := Button.new()
	button.name = "ResultButton"
	column.add_child(button)
	var session := SessionStub.new()
	session.name = "ExerciseSession"
	level.add_child(session)
	var results = preload("res://ui/shared/session_results.gd").new()
	level.add_child(results)
	session.session_completed.emit(sample)
	panel.show()
	await get_tree().process_frame
	assert(results.summary.completed_reps == 10)
	assert(column.has_node("SummaryScroll"))
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://session-fe-results.png")
		viewport.size = Vector2i(800,600)
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://session-fe-small.png")
	assert(panel.position.y + panel.size.y <= viewport.size.y)
	viewport.queue_free()
	await get_tree().process_frame
	for id in range(1,6):
		Global.selected_action = id
		var map = load("res://maps/map_%d/main_level.tscn" % id).instantiate()
		add_child(map)
		await get_tree().process_frame
		var found := false
		for child in map.get_children():
			if child.get_script() != null and child.get_script().resource_path == "res://ui/shared/session_results.gd":
				child.summary = sample.duplicate(true)
				child.summary.map_id = id
				map.result_panel.show()
				child._refresh()
				found = true
		assert(found)
		map.queue_free()
		await get_tree().process_frame
	print("SESSION_FE_PASS")
	get_tree().quit()
