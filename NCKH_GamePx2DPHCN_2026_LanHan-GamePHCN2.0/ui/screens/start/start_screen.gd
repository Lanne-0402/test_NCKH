extends Control

const Preview = preload("res://ui/screens/map_selection/map_preview.gd")
const DEMO_SECONDS := 10.0
var demo_map := 1
var demo_elapsed := 0.0
var demo: TextureRect
var demo_material: ShaderMaterial

func _ready() -> void:
	$ColorRect.hide()
	$Forest.hide()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;
void fragment() {
	vec4 original = texture(TEXTURE, UV);
	vec4 soft = vec4(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			soft += texture(TEXTURE, clamp(UV+vec2(float(x),float(y))*TEXTURE_PIXEL_SIZE*1.3,vec2(0.0),vec2(1.0)));
		}
	}
	COLOR = vec4(mix(original.rgb,soft.rgb/9.0,0.25)*0.78,1.0);
}"
	demo_material = ShaderMaterial.new()
	demo_material.shader = shader
	$CanvasLayer/Title.add_theme_color_override("font_outline_color",Color("13251f"))
	$CanvasLayer/Title.add_theme_constant_override("outline_size",5)
	_show_demo(1)

func _process(delta: float) -> void:
	demo_elapsed += delta
	if demo_elapsed >= DEMO_SECONDS:
		var steps := int(demo_elapsed / DEMO_SECONDS)
		demo_elapsed = fmod(demo_elapsed,DEMO_SECONDS)
		_show_demo((demo_map-1+steps)%5+1)

func _show_demo(id: int) -> void:
	if is_instance_valid(demo):
		# Only one live demo viewport; no gameplay scenes or pose-provider calls.
		remove_child(demo)
		demo.queue_free()
	demo_map = id
	demo = Preview.new()
	demo.name = "HomeDemo"
	demo.map_id = id
	add_child(demo)
	move_child(demo,0)
	demo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Home-only wider framing: 1024 world pixels instead of the card's 768.
	# Place the foot/ground plane at y=440 in the 1152x648 UI, above Start.
	var zoom := float(demo.viewport.size.x) / 1024.0
	demo.world.scale = Vector2.ONE * zoom
	demo.world.position = Vector2(-64.0*zoom,440.0/648.0*demo.viewport.size.y-320.0*zoom)
	demo.material = demo_material
	demo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	demo.set_active(true)


func _on_history_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/screens/history/history_screen.tscn")

func _on_start_button_pressed():
	# Đổi từ level_selection sang calibration
	get_tree().change_scene_to_file("res://ui/screens/calibration/calibration_screen.tscn")
