extends CanvasLayer
## Cosmetic reveal only: never pauses the tree or delays navigation/input.
var veil: ColorRect
var fade: Tween

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	veil = ColorRect.new()
	veil.color = Color("101e18")
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.hide()
	get_tree().scene_changed.connect(_reveal)

func _reveal() -> void:
	if fade != null: fade.kill()
	veil.modulate.a = 0.65
	veil.show()
	fade = create_tween()
	fade.tween_property(veil, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.tween_callback(veil.hide)

func _exit_tree() -> void:
	if fade != null: fade.kill()
