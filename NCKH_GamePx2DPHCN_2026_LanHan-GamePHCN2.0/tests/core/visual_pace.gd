extends Node
const Pace = preload("res://ui/shared/visual_pace.gd")
func _ready() -> void: call_deferred("_run")
func _run() -> void:
	assert(not Global.persistence_enabled)
	PoseInput.begin_offline_preview()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152,648)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	for map_id in range(1,6):
		Global.selected_action = map_id
		Global.unlocked_levels_by_action[map_id] = 1
		var menu = load("res://ui/screens/level_selection/main_menu.tscn").instantiate()
		viewport.add_child(menu)
		await get_tree().create_timer(0.15).timeout
		assert(not menu.get_node("VBoxContainer/Button").disabled)
		assert(menu.get_node("VBoxContainer/Button2").disabled)
		assert(menu.get_node("VBoxContainer/Button3").disabled)
		assert(menu.get_node("VBoxContainer").get_global_rect().end.y <= 648)
		for button_name in ["Button", "Button2", "Button3"]:
			var choice: Button = menu.get_node("VBoxContainer/" + button_name)
			assert(choice.text.is_empty())
			for decoration in choice.find_children("*", "Control", true, false):
				assert(decoration.mouse_filter == Control.MOUSE_FILTER_IGNORE)
				assert(decoration.get_global_rect().end.x <= choice.get_global_rect().end.x)
				assert(decoration.get_global_rect().end.y <= choice.get_global_rect().end.y, str([decoration.name, decoration.get_global_rect(),choice.get_global_rect()]))
			var status_label: Label = choice.find_child("ChoiceStatus",true,false)
			assert(status_label.text.begins_with("ĐANG KHÓA" if choice.disabled else "SẴN SÀNG"))
			assert(status_label.get_theme_color("font_color") == (Color("5b5441") if choice.disabled else Color("245b35")))

		await _capture(viewport, "pace-menu-map%d" % map_id)
		menu.queue_free()
		await get_tree().process_frame
		for multiplier in [1.0,1.5,2.0]:
			Global.speed_multiplier = multiplier
			var map = load("res://maps/map_%d/main_level.tscn" % map_id).instantiate()
			viewport.add_child(map)
			await get_tree().create_timer(0.15).timeout
			map.instruction_panel.hide()
			assert(map.exercise_session.start_session(map._session_config))
			var request: Dictionary = PoseInput.last_exercise_request
			var expected_hold := 700 if map_id == 1 else (30000 if map_id == 5 else 5000)
			assert(request.hold_duration_ms == expected_hold)
			assert(request.minimum_movement_duration_ms == 2000)
			assert(request.maximum_movement_duration_ms == (8000 if map_id == 5 else 5000))
			assert(map._session_config.rest_duration_seconds == 30.0)
			assert(is_equal_approx(request.target_rom_ratio, ([0.75,0.78,0.8] if map_id == 1 else [0.7,0.8,0.9])[Pace.level_index()]))
			var ctrl = map.get_node("Map%dController" % map_id)
			ctrl.set_process(false)
			var player = map.get_node("Player")
			player.set_process(false)
			var old_clock: float = player.mk2.animation_clock
			player._process(0.25)
			assert(is_equal_approx(player.mk2.animation_clock - old_clock, 0.25 * multiplier))
			match map_id:
				1:
					var rock = ctrl._current_rock
					rock.set_process(false)
					var before: float = rock.position.x
					rock._process(0.1)
					assert(is_equal_approx(before-rock.position.x,170.0*multiplier*0.1))
					rock._process(20.0)
					assert(ctrl.is_action_window_open())
				2:
					var before: float = ctrl.slab.position.y
					ctrl._process(0.1)
					assert(is_equal_approx(ctrl.slab.position.y-before,120.0*multiplier*0.1))
					ctrl._process(20.0)
					assert(ctrl.is_action_window_open())
				3:
					var before: float = ctrl._close_progress
					ctrl._process(0.1)
					assert(is_equal_approx(ctrl._close_progress-before,140.0*multiplier*0.1/400.0))
					ctrl._process(20.0)
					assert(ctrl.is_action_window_open())
				4:
					ctrl._run_tween.pause()
					ctrl._run_tween.custom_step(5.0/multiplier*0.49)
					assert(not ctrl.is_action_window_open())
					ctrl._run_tween.custom_step(5.0/multiplier*0.52)
					assert(ctrl.is_action_window_open())
					ctrl._play_jump_to(1)
					ctrl._jump_tween.pause()
					ctrl._jump_tween.custom_step(0.55/multiplier*0.49)
					assert(player.mk2.jump_progress > 0.0)
					ctrl._jump_tween.custom_step(0.55/multiplier*0.52)
					assert(player.mk2.jump_progress == -1.0)
				5:
					assert(ctrl.is_action_window_open())
					assert(map.exercise_session.total_valid_reps == 0)
			map.exercise_session.hold_progress_changed.emit(0.4,int(expected_hold*0.4),expected_hold)
			var hud = map.get_node("GamePresentation")
			assert(not hud.session_hud.has_node("VisualPaceLabel"))
			assert(hud.session_hud.get_node("Heading/MapLevelTitle").get_parsed_text() == "MAP %d · MỨC %d" % [map_id, Pace.level_index()+1])
			assert(hud.session_hud.has_node("HeadingDivider"))
			assert(hud.session_hud.get_node("Heading/MapLevelTitle").text.contains("[color=#ffd85a]MỨC %d[/color]" % (Pace.level_index()+1)))
			assert(is_equal_approx(player.mk2.amount,0.4))
			await get_tree().create_timer(0.03).timeout
			assert(hud.session_hud.get_global_rect().end.y <= 648)
			assert(hud.session_hud.get_global_rect().position.y >= 366)
			if multiplier == 2.0: await _capture(viewport,"pace-hud-map%d" % map_id)
			map.exercise_session.stop_session("scene_changed")
			map.queue_free()
			await get_tree().process_frame
			print("PACE_CASE_PASS map=",map_id," multiplier=",multiplier)
	viewport.queue_free()
	await get_tree().process_frame
	print("VISUAL_PACE_PASS: 15 map/level combinations; motion ratios, unchanged BE config/hold/rest, locks, UI bounds")
	get_tree().quit()
func _capture(viewport: SubViewport, filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://"+filename+".png")
