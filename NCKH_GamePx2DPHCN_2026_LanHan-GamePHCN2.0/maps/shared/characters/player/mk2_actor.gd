extends Node2D

const ROOT := "res://assets/characters/mk2_lab/"
const HEAD = preload(ROOT + "head.png")
const TORSO = preload(ROOT + "torso.png")
const UPPER_ARM = preload(ROOT + "upper_arm.png")
const FOREARM = preload(ROOT + "forearm.png")
const HAND = preload(ROOT + "hand.png")
const THIGH = preload(ROOT + "thigh.png")
const SHIN = preload(ROOT + "shin.png")
const FOOT = preload(ROOT + "foot.png")
var pose_id := 0
var amount := 0.0
var joints_visible := true
var mirrored := false
var colored := true
var upper_body_only := false
var outfit_enabled := true
var points: Array[Vector2] = []

func arm_angles(side: int) -> Vector2:
	var target: Vector2
	var start := Vector2(90, 90)
	match pose_id:
		0:
			target = Vector2(-110, -100) if side < 0 else Vector2(-70, -80)
			# Avoid the 180-degree wrap while lifting from the outside.
			if side < 0:
				start = Vector2(-270, -270)
		1:
			start = Vector2(-155, -30) if side < 0 else Vector2(-25, -150)
			target = Vector2(-110, -20) if side < 0 else Vector2(-70, -160)
		_:
			target = Vector2(60, -110) if side < 0 else Vector2(155, 180)
	return start.lerp(target, amount) * PI / 180.0

func endpoints(side: int) -> Array[Vector2]:
	var shoulder := Vector2(side * 8, -49)
	var angles := arm_angles(side)
	var elbow := shoulder + Vector2.from_angle(angles.x) * 14.0
	var wrist := elbow + Vector2.from_angle(angles.y) * 14.0
	return [shoulder, elbow, wrist]

func _segment(tex: Texture2D, a: Vector2, b: Vector2, horizontal: bool, tint: Color) -> void:
	var length := a.distance_to(b)
	if horizontal:
		draw_set_transform(a, (b-a).angle() + PI)
		draw_texture_rect(tex, Rect2(-length, -tex.get_height()/2.0, length, tex.get_height()), false, tint)
	else:
		draw_set_transform(a, (b-a).angle() - PI/2.0)
		draw_texture_rect(tex, Rect2(-tex.get_width()/2.0, -2, tex.get_width(), length+3), false, tint)
	draw_set_transform(Vector2.ZERO)

func _arm(side: int) -> void:
	var p := endpoints(side)
	var tint := Color("ffc99a") if colored else Color.WHITE
	if side < 0:
		tint = tint.darkened(0.16)
	_segment(UPPER_ARM, p[0], p[1], true, tint)
	_segment(FOREARM, p[1], p[2], true, tint)
	draw_texture_rect(HAND, Rect2(p[2] - Vector2(3, 3), Vector2(7, 6)), false, tint)
	if outfit_enabled:
		_sleeve(p[0], p[1], side)
		_wrist_wrap(p[1], p[2])
	points.append_array(p)

func _draw() -> void:
	points.clear()
	var trouser := Color("8498c6") if colored else Color.WHITE
	for side in [-1, 1]:
		if upper_body_only:
			continue
		var hip := Vector2(side * 4, -28)
		var knee := Vector2(side * 5, -15)
		var ankle := Vector2(side * 5, -3)
		if outfit_enabled:
			_trousers(hip, knee, ankle, side)
		else:
			_segment(THIGH, hip, knee, false, trouser)
			_segment(SHIN, knee, ankle, false, trouser)
			draw_texture_rect(FOOT, Rect2(side*5-5, -5, 10, 5), false, Color("ccd7e8"))
	_arm(-1)
	if outfit_enabled:
		_tunic()
	else:
		draw_texture(TORSO, Vector2(-8, -54), Color("72c7bf") if colored else Color.WHITE)
	if pose_id == 1:
		_arm(1)
	draw_texture(HEAD, Vector2(-6, -67), Color("ffd4ad") if colored else Color.WHITE)
	if outfit_enabled:
		_headwear()
	if pose_id != 1:
		_arm(1)
	if pose_id == 2:
		# Supporting arm comes in front of the stretched arm.
		_arm(-1)
	if joints_visible:
		for side in [-1, 1]:
			var p := endpoints(side)
			draw_line(p[0], p[1], Color(0.2, 0.9, 1, 0.65), 0.5)
			draw_line(p[1], p[2], Color(0.2, 0.9, 1, 0.65), 0.5)
			for point in p:
				draw_circle(point, 1.2, Color("ffe08a"))
		var anchor := Vector2(0, -28 if upper_body_only else 0)
		draw_line(anchor + Vector2(-8, 0), anchor + Vector2(8, 0), Color("77edbd"), 0.7)
		draw_circle(anchor, 1, Color("77edbd"))

func refresh() -> void:
	scale.x = -absf(scale.x) if mirrored else absf(scale.x)
	queue_redraw()

# Code-native pixel-shaped clothing layers; source PNGs and pose rig stay intact.
func cloth(hex: String) -> Color:
	var c := Color(hex)
	if not colored:
		var grey := c.get_luminance()
		return Color(grey, grey, grey)
	return c

func _tunic() -> void:
	var outline := PackedVector2Array([Vector2(-3,-54),Vector2(3,-54),Vector2(3,-53),Vector2(8,-51),Vector2(8,-45),Vector2(6,-44),Vector2(6,-35),Vector2(7,-34),Vector2(7,-28),Vector2(-7,-28),Vector2(-7,-34),Vector2(-6,-35),Vector2(-6,-44),Vector2(-8,-45),Vector2(-8,-51),Vector2(-3,-53)])
	draw_colored_polygon(outline,cloth("283841"))
	draw_colored_polygon(PackedVector2Array([Vector2(-3,-53),Vector2(0,-48),Vector2(3,-53),Vector2(7,-50),Vector2(7,-46),Vector2(5,-44),Vector2(5,-34),Vector2(-5,-34),Vector2(-5,-44),Vector2(-7,-46),Vector2(-7,-50)]),cloth("718e9b"))
	draw_colored_polygon(PackedVector2Array([Vector2(3,-52),Vector2(6,-50),Vector2(-3,-37),Vector2(-5,-37)]),cloth("b5b9a4"))
	draw_line(Vector2(-3,-52),Vector2(0,-48),cloth("b5b9a4"),1)
	draw_rect(Rect2(-5,-43,2,7),cloth("526a78"))
	draw_rect(Rect2(3,-42,1,5),cloth("8ca5ad"))
	draw_rect(Rect2(-6,-34,12,4),cloth("b19a72"))
	draw_rect(Rect2(-6,-34,12,1),cloth("d4c4a0"))
	draw_rect(Rect2(2,-34,3,4),cloth("78634d"))
	draw_rect(Rect2(-6,-30,12,2),cloth("526a78"))

func _headwear() -> void:
	# Compact hair/headband; no long tails that could cover the hands.
	draw_rect(Rect2(-5,-67,9,3),cloth("242d32"))
	draw_rect(Rect2(-6,-65,2,5),cloth("242d32"))
	draw_rect(Rect2(4,-65,2,5),cloth("242d32"))
	draw_rect(Rect2(-5,-64,10,2),cloth("647e8e"))
	draw_rect(Rect2(-4,-64,8,1),cloth("a1b2b7"))
	# Keep the eye strip visible; mask follows the head, not the arms.
	draw_rect(Rect2(-5,-59,10,3),cloth("344650"))
	draw_rect(Rect2(-4,-56,8,1),cloth("344650"))
	draw_rect(Rect2(-4,-59,8,1),cloth("8096a0"))
	draw_rect(Rect2(-2,-57,5,1),cloth("526a78"))

func _sleeve(a: Vector2, b: Vector2, side: int) -> void:
	draw_set_transform(a,(b-a).angle())
	var color := cloth("718e9b")
	if side < 0:
		color = color.darkened(0.12)
	draw_rect(Rect2(-2,-4,8,8),cloth("283841"))
	draw_rect(Rect2(-2,-3,7,6),color)
	draw_rect(Rect2(-1,-3,5,1),cloth("a1b2b7"))
	draw_rect(Rect2(4,-3,1,6),cloth("b5b9a4"))
	draw_set_transform(Vector2.ZERO)

func _wrist_wrap(a: Vector2, b: Vector2) -> void:
	draw_set_transform(a,(b-a).angle())
	draw_rect(Rect2(10,-3,3,6),cloth("b19a72"))
	draw_rect(Rect2(10,-3,1,6),cloth("d4c4a0"))
	draw_rect(Rect2(12,-3,1,6),cloth("78634d"))
	draw_set_transform(Vector2.ZERO)

func _trousers(hip: Vector2, knee: Vector2, ankle: Vector2, side: int) -> void:
	var color := cloth("494743")
	if side < 0:
		color = color.darkened(0.12)
	for pair in [[hip,knee],[knee,ankle]]:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		draw_set_transform(a,(b-a).angle()-PI/2)
		draw_rect(Rect2(-4,-1,8,a.distance_to(b)+2),cloth("252c31"))
		draw_rect(Rect2(-3,0,6,a.distance_to(b)),color)
		draw_rect(Rect2(-2,1,1,a.distance_to(b)-2),cloth("6e6a5e"))
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(ankle.x-3,-7,6,4),cloth("8d8065"))
	draw_rect(Rect2(ankle.x-3,-5,6,1),cloth("c1b392"))
	draw_rect(Rect2(ankle.x-5,-3,10,3),cloth("29343b"))
	draw_rect(Rect2(ankle.x-5,-1,10,1),cloth("81959b"))
