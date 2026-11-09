extends TextureRect
const World = preload("res://ui/screens/map_selection/preview_world.gd")
var map_id := 1
var scenery_only := false
var viewport: SubViewport
var world: Node2D
var active := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	viewport = SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.size = Vector2i(592,332)
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.own_world_3d = false
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	world = World.new()
	world.map_id = map_id
	world.scenery_only = scenery_only
	# Crop the gameplay area, excluding HUD; retain native aspect ratio.
	world.scale = Vector2.ONE * (592.0/768.0)
	world.position = Vector2(-192,60) * world.scale
	viewport.add_child(world)
	texture = viewport.get_texture()
	if scenery_only:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;
void fragment() {
	vec4 sum = vec4(0.0);
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			sum += texture(TEXTURE, clamp(UV + vec2(float(x),float(y))*TEXTURE_PIXEL_SIZE*3.0, vec2(0.0),vec2(1.0)));
		}
	}
	COLOR = vec4((sum.rgb/49.0)*0.48,1.0);
}"
		var mat := ShaderMaterial.new()
		mat.shader = shader
		material = mat

func set_active(value: bool) -> void:
	if scenery_only: return
	active = value
	if value:
		world.set_process(true)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		world.reset_demo()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
