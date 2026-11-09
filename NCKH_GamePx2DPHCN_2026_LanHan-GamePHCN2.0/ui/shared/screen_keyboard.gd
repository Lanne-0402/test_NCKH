extends Node
var back_path := ""
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().scene_changed.connect(_scene_ready)

func _scene_ready() -> void:
	back_path = ""
	var scene := get_tree().current_scene
	if scene == null: return
	var first := ""
	match scene.scene_file_path:
		"res://ui/screens/start/start_screen.tscn": first = "CanvasLayer/StartButton"
		"res://ui/screens/history/history_screen.tscn":
			first = "BackButton"
			back_path = first
		"res://ui/screens/map_selection/level_selection.tscn":
			first = "MapRows/TopRow/Button"
			back_path = "BackButton"
		"res://ui/screens/level_selection/main_menu.tscn":
			first = "VBoxContainer/Button"
			back_path = "BackButton"
		"res://ui/screens/calibration/calibration_screen.tscn": back_path = "%BackButton"
	var control := scene.get_node_or_null(first) as Control if not first.is_empty() else null
	if control != null: control.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo() or back_path.is_empty(): return
	if get_tree().paused: return
	var scene := get_tree().current_scene
	if scene == null: return
	# Settings owns Escape while open; do not navigate behind its modal.
	for item in scene.find_children("SettingsMenu", "", true, false):
		if item.get("overlay") != null and item.overlay.visible: return
	var button := scene.get_node_or_null(back_path) as Button
	if button != null and button.is_visible_in_tree() and not button.disabled:
		get_viewport().set_input_as_handled()
		button.pressed.emit()
