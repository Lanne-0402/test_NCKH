extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	for id in range(1, 6):
		Global.selected_action = id
		var level = load("res://maps/map_%d/main_level.tscn" % id).instantiate()
		add_child(level)
		await get_tree().process_frame
		await get_tree().process_frame
		var presentation = level.get_node("GamePresentation")
		for code in ["SESSION_READY", "ACTION_ZONE_READY", "HOLD_PROGRESS", "TRACKING_LOST", "PHASE_REST", "HOLD_INTERRUPTED"]:
			var raw: String = level._feedback_text(code)
			level.feedback_label.text = raw
			presentation._sync_subtitle()
			assert(level.feedback_label.text.replace("\n", " ") == raw)
			for line in level.feedback_label.text.split("\n"):
				if " " in raw: assert(line.split(" ", false).size() > 1)
			print("MAP ", id, " ", code, ": ", level.feedback_label.text.replace("\n", " | "))
		level.queue_free()
		await get_tree().process_frame
	print("SUBTITLE_PASS")
	get_tree().quit()
