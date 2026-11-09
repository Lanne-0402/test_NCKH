extends CanvasLayer

const HOME_SCENE := "res://ui/screens/start/start_screen.tscn"
const CAMERA_SCENE := "res://ui/screens/calibration/calibration_screen.tscn"
const MAP_SELECTION_SCENE := "res://ui/screens/map_selection/level_selection.tscn"

@export var trigger_path: NodePath = ^"UI/SettingsButton"

var _previous_pause := false
var _pending_scene := ""
var _trigger: Button

@onready var overlay: Control = $Overlay
@onready var volume: HSlider = $Overlay/Center/Panel/Margin/Contents/Volume
@onready var volume_label: Label = $Overlay/Center/Panel/Margin/Contents/VolumeLabel
@onready var mute: CheckButton = $Overlay/Center/Panel/Margin/Contents/Mute
@onready var resume: Button = $Overlay/Center/Panel/Margin/Contents/Resume
@onready var confirm: ConfirmationDialog = $Confirm


func _ready() -> void:
	_trigger = get_parent().get_node(trigger_path) as Button
	_trigger.pressed.connect(open_menu)
	volume.value_changed.connect(_on_volume_changed)
	mute.toggled.connect(_on_mute_toggled)
	resume.pressed.connect(close_menu)
	$Overlay/Center/Panel/Margin/Contents/Home.pressed.connect(_request_navigation.bind(HOME_SCENE))
	$Overlay/Center/Panel/Margin/Contents/MapSelection.pressed.connect(_request_navigation.bind(MAP_SELECTION_SCENE))
	$Overlay/Center/Panel/Margin/Contents/Camera.pressed.connect(_request_navigation.bind(CAMERA_SCENE))
	_style_confirmation()
	confirm.confirmed.connect(_navigate)
	confirm.canceled.connect(resume.grab_focus)
	if get_parent().get_node_or_null("ExerciseSession") == null:
		resume.text = "ĐÓNG"
		$Overlay/Center/Panel/Margin/Contents/Hint.text = "Thiết lập chung của trò chơi"
		$Overlay/Center/Panel/Margin/Contents/Home.hide()
	overlay.hide()


func _style_confirmation() -> void:
	# A second scrim separates the confirmation from the Settings panel.
	var dim := ColorRect.new()
	dim.name = "ConfirmationDim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.015, 0.025, 0.02, 0.74)
	dim.visible = false
	overlay.add_child(dim)
	confirm.visibility_changed.connect(func(): dim.visible = confirm.visible)
	confirm.borderless = true
	confirm.unresizable = true
	confirm.size = Vector2i(520, 270)
	confirm.min_size = Vector2i(520, 270)
	var frame := preload("res://assets/shared/ui/game_theme.tres").get_stylebox("panel", "PanelContainer").duplicate()
	frame.content_margin_left = 28
	frame.content_margin_right = 28
	frame.content_margin_top = 26
	frame.content_margin_bottom = 22
	confirm.add_theme_stylebox_override("panel", frame)
	var message := confirm.get_label()
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_color", Color("352716"))
	message.add_theme_font_size_override("font_size", 22)
	for action in [confirm.get_ok_button(), confirm.get_cancel_button()]:
		action.custom_minimum_size = Vector2(180, 48)
	confirm.ok_button_text = "RỜI MÀN CHƠI"
	confirm.cancel_button_text = "Ở LẠI"
	confirm.about_to_popup.connect(_focus_stay.call_deferred)


func _focus_stay() -> void:
	if is_inside_tree() and confirm.visible:
		confirm.get_cancel_button().grab_focus()


func open_menu() -> void:
	if overlay.visible:
		return
	_previous_pause = get_tree().paused
	var session := get_parent().get_node_or_null("ExerciseSession")
	if session != null:
		session.set_menu_paused(true)
	get_tree().paused = true
	volume.set_value_no_signal(Global.volume_percent)
	mute.set_pressed_no_signal(AudioServer.is_bus_mute(0))
	_update_volume_label(volume.value)
	overlay.show()
	resume.grab_focus()


func close_menu() -> void:
	confirm.hide()
	overlay.hide()
	get_tree().paused = _previous_pause
	var session := get_parent().get_node_or_null("ExerciseSession")
	if session != null:
		session.set_menu_paused(false)
	_trigger.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if overlay.visible and event.is_action_pressed("ui_cancel"):
		if confirm.visible:
			confirm.hide()
			resume.grab_focus()
		else:
			close_menu()
		get_viewport().set_input_as_handled()


func _on_volume_changed(value: float) -> void:
	Global.set_audio_settings(value, mute.button_pressed)
	_update_volume_label(value)


func _on_mute_toggled(enabled: bool) -> void:
	Global.set_audio_settings(volume.value, enabled)


func _update_volume_label(value: float) -> void:
	volume_label.text = "Âm lượng tổng: %d%%" % roundi(value)


func _request_navigation(scene_path: String) -> void:
	_pending_scene = scene_path
	if get_parent().get_node_or_null("ExerciseSession") == null:
		_navigate()
		return
	confirm.dialog_text = "RỜI MÀN CHƠI?\n\nLượt tập hiện tại sẽ kết thúc.\nBạn có muốn rời màn chơi?"
	confirm.popup_centered()


func _navigate() -> void:
	# Map _exit_tree() stops its exercise session during the scene change.
	# Cache the tree: a successful scene change detaches this menu immediately.
	var tree := get_tree()
	var error := tree.change_scene_to_file(_pending_scene)
	if error != OK:
		confirm.dialog_text = "Không mở được trang. Hãy đóng bảng và thử lại."
		confirm.popup_centered()
		return
	tree.paused = _previous_pause


func _exit_tree() -> void:
	if is_instance_valid(overlay) and overlay.visible:
		get_tree().paused = _previous_pause
