extends Control
const VisualPace = preload("res://ui/shared/visual_pace.gd")

# Hàm chạy ngay khi mở Menu
func _ready():
	_build_backdrop()
	var highest_level := Global.get_highest_unlocked_level(Global.selected_action)
	Global.highest_unlocked_level = highest_level
	# Giả sử trong VBoxContainer, các nút của bạn tên là Button, Button2, Button3
	# Nếu cấp độ cao nhất < 2, khóa nút Mức 2 (1.5x)
	if highest_level < 2:
		$VBoxContainer/Button2.disabled = true
	else:
		$VBoxContainer/Button2.disabled = false
	# Nếu cấp độ cao nhất < 3, khóa nút Mức 3 (2.0x)
	if highest_level < 3:
		$VBoxContainer/Button3.disabled = true
	else:
		$VBoxContainer/Button3.disabled = false
	_build_level_choices(highest_level)

func _build_level_choices(highest_level: int) -> void:
	theme = preload("res://assets/shared/ui/game_theme.tres")
	var box: VBoxContainer = $VBoxContainer
	box.position = Vector2(226, 80)
	box.size = Vector2(700, 536)
	box.add_theme_constant_override("separation", 10)
	$BackButton.position = Vector2(32, 28)
	$BackButton.size = Vector2(150, 48)
	var title: Label = $VBoxContainer/Label
	title.text = "CHỌN MỨC ĐỘ TẬP LUYỆN"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var names := ["Phá cản mở đường", "Nâng đá", "Đẩy lùi tường", "Leo vách đá cao", "Thiền định"]
	var map_id := clampi(Global.selected_action, 1, 5)
	var subtitle := Label.new()
	subtitle.text = "Map %d · %s" % [map_id, names[map_id - 1]]
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color("fff8e7"))
	box.add_child(subtitle)
	box.move_child(subtitle, 1)
	var note := Label.new()
	note.name = "ExerciseTimingNote"
	note.text = VisualPace.exercise_note(map_id) + "\nNhịp cảnh độc lập với thời gian giữ; tập theo hướng dẫn."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 17)
	note.add_theme_color_override("font_color", Color("fff8e7"))
	note.add_theme_color_override("font_outline_color", Color("14251e"))
	note.add_theme_constant_override("outline_size", 4)
	box.add_child(note)
	box.move_child(note, 2)
	var speeds: Array = VisualPace.SPEEDS
	for index in range(3):
		var item: Button = box.get_node("Button" if index == 0 else "Button%d" % (index + 1))
		item.custom_minimum_size.y = 112
		item.add_theme_font_size_override("font_size", 19)
		var status := "SẴN SÀNG · Nhấn để vào màn chơi"
		if index + 1 > highest_level:
			status = "ĐANG KHÓA · Hoàn thành mức %d để mở" % index
			if TrackingStability.ENABLED:
				status = "ĐANG KHÓA · Hoàn thành mức %d với ít nhất 2 tim" % index
			# Keep disabled text readable without implying that the choice is enabled.
			item.add_theme_color_override("font_disabled_color", Color("463f30"))
		var motion := "HIỆU ỨNG CẢNH" if map_id == 5 else "CHUYỂN ĐỘNG CẢNH"
		_build_choice_content(item, index + 1, "%s %.1fx" % [motion, speeds[index]], VisualPace.motion_description(map_id), status)
	var hint := Label.new()
	hint.text = "Tiến độ mở mức được lưu riêng cho từng map."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color("fff8e7"))
	box.add_child(hint)
	$VBoxContainer/Button.grab_focus()

func _build_choice_content(item: Button, level_number: int, motion: String, description: String, status: String) -> void:
	# The original Button owns input/focus/disabled state; all decoration ignores mouse input.
	item.text = ""
	item.tooltip_text = "MỨC %d · %s\n%s\n%s" % [level_number, motion, description, status]
	var margin := MarginContainer.new()
	margin.name = "ChoiceContent"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]: margin.add_theme_constant_override("margin_" + edge, 20)
	for edge in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 12)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("separation", 12)
	column.add_child(heading)
	var text_color := Color("5b5441") if item.disabled else Color("2e200d")
	var level_label := _choice_label("MỨC %d" % level_number, 20, text_color)
	level_label.name = "LevelTitle"
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(level_label)
	var motion_label := _choice_label(motion, 17, text_color)
	motion_label.name = "MotionLabel"
	motion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(motion_label)
	var description_label := _choice_label(description, 19, text_color)
	description_label.name = "DescriptionLabel"
	column.add_child(description_label)
	var status_label := _choice_label(status, 18, Color("5b5441") if item.disabled else Color("245b35"))
	status_label.name = "ChoiceStatus"
	column.add_child(status_label)

func _choice_label(value: String, font_size: int, color: Color) -> Label:
	var item := Label.new()
	item.text = value
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	return item

func _on_button_pressed():
	Global.speed_multiplier = 1.0 
	_open_selected_map()

func _on_button_2_pressed():
	Global.speed_multiplier = 1.5
	_open_selected_map()
	
func _on_button_3_pressed():
	Global.speed_multiplier = 2.0
	_open_selected_map()


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/screens/map_selection/level_selection.tscn")


func _open_selected_map() -> void:
	var map_scene := Global.get_selected_map_scene()
	if map_scene.is_empty():
		push_warning("Map %d chưa được triển khai." % Global.selected_action)
		return
	get_tree().change_scene_to_file(map_scene)

func _build_backdrop() -> void:
	var backdrop := preload("res://ui/screens/map_selection/map_preview.gd").new()
	backdrop.name = "SceneryBackdrop"
	backdrop.map_id = clampi(Global.selected_action, 1, 5)
	backdrop.scenery_only = true
	add_child(backdrop)
	move_child(backdrop, 0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$ColorRect.hide()
	$VBoxContainer/Label.add_theme_color_override("font_color", Color("fff8e7"))
	$VBoxContainer/Label.add_theme_color_override("font_outline_color", Color("14251e"))
	$VBoxContainer/Label.add_theme_constant_override("outline_size", 6)
