extends Control

const Preview = preload("res://ui/screens/map_selection/map_preview.gd")
var previews: Array[TextureRect] = []


func _ready() -> void:
	_build_previews()
	$MapRows/TopRow/Button3.disabled = not Global.is_map_implemented(3)
	$MapRows/BottomRow/Button4.disabled = not Global.is_map_implemented(4)
	$MapRows/BottomRow/Button5.disabled = not Global.is_map_implemented(5)

func _on_back_button_pressed():
	# Nút Quay lại đưa về Start Screen
	get_tree().change_scene_to_file("res://ui/screens/calibration/calibration_screen.tscn")

func _on_button_pressed():
	Global.selected_action = 1
	get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")

func _on_button_2_pressed():
	Global.selected_action = 2
	get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")
	
func _on_button_3_pressed():
	if not Global.is_map_implemented(3):
		return
	Global.selected_action = 3
	get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")

func _on_button_4_pressed():
	if not Global.is_map_implemented(4):
		return
	Global.selected_action = 4
	get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")

func _on_button_5_pressed():
	if not Global.is_map_implemented(5):
		return
	Global.selected_action = 5
	get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")

func _build_previews() -> void:
	# Local tooltip styling; keep the tan-button text elsewhere unchanged.
	theme = Theme.new()
	theme.set_color("font_color", "TooltipLabel", Color("fff8e7"))
	theme.set_color("font_outline_color", "TooltipLabel", Color("101c18"))
	theme.set_constant("outline_size", "TooltipLabel", 2)
	$ColorRect.hide()
	var backdrop := Preview.new()
	backdrop.name = "SceneryBackdrop"
	backdrop.scenery_only = true
	backdrop.map_id = 1
	add_child(backdrop)
	move_child(backdrop,0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$Label.add_theme_color_override("font_color",Color("f5edcf"))
	$Label.add_theme_color_override("font_outline_color",Color("14251e"))
	$Label.add_theme_constant_override("outline_size",6)
	for action in range(1,6):
		var path := "MapRows/" + ("TopRow/" if action <= 3 else "BottomRow/") + ("Button" if action == 1 else "Button%d" % action)
		var card: Button = get_node(path)
		var title := card.text
		card.text = ""
		card.tooltip_text = title.replace("\n"," · ") + "\nDi chuột để xem thử · Nhấn để chọn"
		for state in ["normal","hover","pressed","focus","disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("172c29")
			style.border_color = Color("d9c58b") if state in ["hover","focus"] else Color("69857b")
			style.set_border_width_all(3 if state in ["hover","focus"] else 2)
			card.add_theme_stylebox_override(state,style)
		var preview := Preview.new()
		preview.name = "MapPreview"
		preview.map_id = action
		card.add_child(preview)
		preview.position = Vector2(3,3)
		preview.size = Vector2(290,163)
		previews.append(preview)
		var caption := Label.new()
		caption.name = "Caption"
		caption.text = title.get_slice("\n",0)
		caption.position = Vector2(5,166)
		caption.size = Vector2(286,22)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_theme_font_size_override("font_size",18)
		caption.add_theme_color_override("font_color",Color("f5edcf"))
		card.add_child(caption)
		var subtitle: Label = caption.duplicate()
		subtitle.name = "MapName"
		subtitle.text = title.get_slice("\n",1)
		subtitle.position.y = 189
		card.add_child(subtitle)
		card.mouse_entered.connect(func(): _activate_preview(preview))
		card.mouse_exited.connect(func(): preview.set_active(false))
		card.focus_entered.connect(func(): _activate_preview(preview))
		card.focus_exited.connect(func(): preview.set_active(false))

func _activate_preview(selected: TextureRect) -> void:
	for preview in previews:
		preview.set_active(preview == selected)
