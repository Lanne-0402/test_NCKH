extends Panel
var show_body := true
func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("142b27")
	style.border_color = Color("8b9d80")
	style.set_border_width_all(2)
	add_theme_stylebox_override("panel", style)
func _draw() -> void:
	if not show_body: return
	var scale_factor := minf(size.x / 640.0, size.y / 360.0)
	draw_set_transform(Vector2((size.x - 640 * scale_factor) / 2.0, 0), 0, Vector2.ONE * scale_factor)
	var ink := Color("799b8c")
	ink.a = 0.65
	draw_arc(Vector2(320,117),26,0,TAU,48,ink,3,true)
	draw_polyline(PackedVector2Array([Vector2(224,242),Vector2(240,184),Vector2(283,158),Vector2(357,158),Vector2(400,184),Vector2(416,242)]),ink,3,true)
	draw_line(Vector2(276,187),Vector2(270,244),ink,3,true)
	draw_line(Vector2(364,187),Vector2(370,244),ink,3,true)
	for x in [140,500]:
		var dx := 24 if x == 140 else -24
		for y in [78,248]:
			var dy := 24 if y == 78 else -24
			draw_line(Vector2(x,y),Vector2(x+dx,y),ink,2)
			draw_line(Vector2(x,y),Vector2(x,y+dy),ink,2)
