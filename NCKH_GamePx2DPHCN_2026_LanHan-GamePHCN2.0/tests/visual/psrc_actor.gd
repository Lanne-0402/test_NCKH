extends Node2D

const ROOT := "res://assets/characters/psrc_lab/"
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
		# Original PSRC arms are vertical, unlike the horizontal Mk2 exports.
		# Keep native width and the same 14px joint spacing for comparison.
		draw_set_transform(a, (b-a).angle() - PI/2.0)
		draw_texture_rect(tex, Rect2(-tex.get_width()/2.0, 0, tex.get_width(), length), false, tint)
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
	draw_texture(HAND, p[2] - HAND.get_size()/2, tint)
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
		_segment(THIGH, hip, knee, false, trouser)
		_segment(SHIN, knee, ankle, false, trouser)
		draw_texture(FOOT, Vector2(side*5-FOOT.get_width()/2.0, -FOOT.get_height()), Color("ccd7e8"))
	_arm(-1)
	draw_texture(TORSO, Vector2(-TORSO.get_width()/2.0, -54), Color("72c7bf") if colored else Color.WHITE)
	if pose_id == 1:
		_arm(1)
	draw_texture(HEAD, Vector2(-HEAD.get_width()/2.0, -67), Color("ffd4ad") if colored else Color.WHITE)
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
