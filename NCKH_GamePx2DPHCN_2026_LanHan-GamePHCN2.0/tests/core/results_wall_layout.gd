extends Node
func _ready() -> void: call_deferred("_run")
func _run() -> void:
	assert(not Global.persistence_enabled)
	PoseInput.begin_offline_preview()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152,648)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var sample := {"patient_id":"BN001","status":"completed","map_id":5,"difficulty":2,"completed_reps":2,"target_reps":2,"completed_sets":2,"target_sets":2,"active_seconds":91,"rest_seconds":30,"paused_seconds":8,"tracking_lost_seconds":4,"valid_reps":2,"rejected_reps":0,"evaluation":"HOÀN THÀNH","bonus_points":100,"duration_source":"godot_state_timer"}
	for map_id in range(1,6):
		Global.selected_action = map_id
		var map = load("res://maps/map_%d/main_level.tscn" % map_id).instantiate()
		viewport.add_child(map)
		await get_tree().create_timer(0.06).timeout
		map.instruction_panel.hide()
		if map_id == 3:
			var ctrl = map.map3_controller
			ctrl.current_direction = ctrl.WallDirection.HORIZONTAL
			for close in [0.0,0.5,1.0]:
				for retreat in [0.0,0.5,1.0]:
					ctrl._apply_wall_positions(close,retreat)
					for wall in [ctrl.wall_a,ctrl.wall_b]:
						assert(is_equal_approx(wall.position.y+120.0,320.0))
						assert(wall.position.y-120.0 >= 0)
			ctrl._apply_wall_positions(1.0,0.0)
			await _capture(viewport,"walls-grounded")
		var results: Node
		for child in map.get_children():
			if child.get_script() != null and child.get_script().resource_path == "res://ui/shared/session_results.gd": results = child
		assert(results != null)
		results.summary = sample.duplicate(true)
		results.summary.map_id = map_id
		map.result_label.text = "HOÀN THÀNH\nCấp độ tiếp theo đã sẵn sàng."
		map.result_panel.show()
		for dimensions in [Vector2i(1152,648),Vector2i(800,600),Vector2i(1600,900)]:
			viewport.size = dimensions
			results._refresh()
			await get_tree().create_timer(0.2).timeout
			var column = results.content
			assert(not column.get_node("ResultButton").visible)
			var actions: HBoxContainer = column.get_node("ResultActions")
			assert(actions.get_child_count() == 3)
			var width: float = actions.get_child(0).size.x
			for button in actions.get_children():
				assert(absf(button.size.x-width) <= 1)
				assert(button.get_global_rect().end.x <= map.result_panel.get_global_rect().end.x)
				assert(button.get_global_rect().end.y <= dimensions.y)
			assert(absf(actions.get_child(2).get_global_rect().end.x-actions.get_global_rect().end.x) <= 1)
			var body = column.get_node("SummaryScroll").get_child(0)
			var toggle: Button = body.get_node("DetailsToggle")
			var detail = body.get_node("AdditionalDetails")
			assert(not detail.visible)
			if map_id == 5 and dimensions.x < 1600: await _capture(viewport,"results-compact-%d" % dimensions.x)
			toggle.button_pressed = true
			assert(detail.visible and toggle.text == "THU GỌN")
			var extra_text := ""
			for label in detail.find_children("*","Label",true,false): extra_text += label.text + "\n"
			assert(not extra_text.contains("Số lần") and not extra_text.contains("Số hiệp"))
			assert(not extra_text.contains("00:01:31"))
			assert(extra_text.contains("BN001") and extra_text.contains("00:00:30"))
			await get_tree().create_timer(0.2).timeout
			assert(map.result_panel.get_global_rect().end.y <= dimensions.y)
			if map_id == 5 and dimensions.x < 1600: await _capture(viewport,"results-details-%d" % dimensions.x)
			toggle.button_pressed = false
			assert(not detail.visible and toggle.text == "XEM CHI TIẾT")
		# Missing legacy fields remain explicitly unavailable, rather than zero.
		results.summary = {"status":"interrupted"}
		results._refresh()
		await get_tree().process_frame
		var labels := ""
		for label in results.content.find_children("*","Label",true,false): labels += label.text
		assert(labels.contains("Chưa có dữ liệu"))
		results.summary = {}
		results._refresh()
		assert(results.content.get_node("SummaryScroll").find_children("DetailsToggle").is_empty())
		map.queue_free()
		await get_tree().process_frame
		viewport.size = Vector2i(1152,648)
	viewport.queue_free()
	await get_tree().process_frame
	print("RESULTS_WALL_LAYOUT_PASS: walls on ground, five maps x three viewport sizes, equal actions, nonduplicated details, legacy data")
	get_tree().quit()
func _capture(viewport: SubViewport, filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://"+filename+".png")
