extends Node
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")
func _run() -> void:
	for id in range(1, 6):
		Global.selected_action = id
		var level = load("res://maps/map_%d/main_level.tscn" % id).instantiate()
		add_child(level)
		await get_tree().process_frame
		level.instruction_panel.hide()
		var menu = level.get_node("SettingsMenu")
		menu.open_menu()
		menu._request_navigation(menu.HOME_SCENE)
		await get_tree().process_frame
		assert(menu.confirm.visible and get_tree().paused)
		assert(menu.overlay.get_node("ConfirmationDim").visible)
		assert(menu.confirm.get_cancel_button().can_process())
		if id == 1 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://exit_dialog.png")
		menu.confirm.get_cancel_button().pressed.emit()
		await get_tree().process_frame
		assert(not menu.confirm.visible and menu.overlay.visible and get_tree().paused)
		assert(not menu.overlay.get_node("ConfirmationDim").visible)
		menu.close_menu()
		assert(not get_tree().paused)
		level.queue_free()
		await get_tree().process_frame
	print("EXIT_DIALOG: PASS (5 maps, scrim, cancel, pause)")
	get_tree().quit()
