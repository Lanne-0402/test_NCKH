extends CanvasLayer
var box: PanelContainer
var message: Label
var retry: Button
var remaining := 0.0
var failed := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	box = PanelContainer.new()
	box.theme = preload("res://assets/shared/ui/game_theme.tres")
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -330
	box.offset_right = 330
	box.offset_top = 8
	add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	message = Label.new()
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.add_theme_font_size_override("font_size", 18)
	row.add_child(message)
	retry = Button.new()
	retry.text = "THỬ LẠI"
	retry.pressed.connect(func(): Global.save_progress())
	row.add_child(retry)
	box.hide()
	Global.save_finished.connect(_saved)

func _saved(success: bool) -> void:
	# Keep routine settings saves quiet; acknowledge session saves and retries.
	if success and not failed:
		var scene := get_tree().current_scene
		if scene == null or not scene.scene_file_path.begins_with("res://maps/"): return
	failed = not success
	message.text = "Chưa lưu được trên máy. Hãy thử lại." if failed else "Đã lưu trên máy"
	retry.visible = failed
	box.show()
	remaining = 0.0 if failed else 3.0

func _process(delta: float) -> void:
	if remaining > 0:
		remaining -= delta
		if remaining <= 0: box.hide()
