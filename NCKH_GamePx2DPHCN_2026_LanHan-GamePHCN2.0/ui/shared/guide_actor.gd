extends "res://maps/shared/characters/player/mk2_actor.gd"
const Pose = preload("res://ui/shared/guide_pose.gd")
var map_id := 1
var side_view := false
var other_side := false

func endpoints(side: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point in Pose.arm(map_id,side,amount,other_side):
		result.append(Pose.project(point,side_view))
	return result

func refresh() -> void:
	# Swapping arms is handled in 3D, not by mirroring the side camera.
	queue_redraw()

func _limb(side: int) -> void:
	var p := endpoints(side)
	var tint := Color("ffc99a") if side == 1 else Color("b88d74")
	_segment(UPPER_ARM,p[0],p[1],true,tint)
	_segment(FOREARM,p[1],p[2],true,tint)
	draw_texture_rect(HAND,Rect2(p[2]-Vector2(2,2),Vector2(5,4)),false,tint)

func _profile() -> void:
	# Code-native pixel silhouette, authored for this view; no squashed frontal head.
	# Forward is right. Keep Mk2's 12px head / 26px trunk proportions and palette.
	var body := PackedVector2Array([Vector2(-3,-55),Vector2(2,-55),Vector2(3,-52),Vector2(6,-49),Vector2(6,-44),Vector2(4,-39),Vector2(5,-34),Vector2(4,-28),Vector2(-5,-28),Vector2(-5,-34),Vector2(-4,-41),Vector2(-5,-48),Vector2(-3,-52)])
	draw_colored_polygon(body,Color("28443f"))
	draw_colored_polygon(PackedVector2Array([Vector2(-2,-54),Vector2(1,-54),Vector2(2,-50),Vector2(5,-48),Vector2(5,-45),Vector2(3,-39),Vector2(4,-33),Vector2(3,-29),Vector2(-3,-29),Vector2(-3,-42),Vector2(-4,-48)]),Color("65a89d"))
	draw_rect(Rect2(-2,-47,2,15),Color("40796e"))
	draw_rect(Rect2(2,-47,2,5),Color("92c5b3"))
	draw_rect(Rect2(1,-37,2,7),Color("79b5a5"))
	var head := PackedVector2Array([Vector2(-4,-67),Vector2(3,-67),Vector2(5,-65),Vector2(5,-62),Vector2(7,-60),Vector2(7,-59),Vector2(5,-59),Vector2(5,-56),Vector2(2,-55),Vector2(-2,-56),Vector2(-5,-59),Vector2(-5,-64)])
	draw_colored_polygon(head,Color("68594b"))
	draw_rect(Rect2(-3,-64,7,6),Color("c1a081"))
	draw_rect(Rect2(0,-65,4,4),Color("dfba91"))
	draw_rect(Rect2(4,-61,2,2),Color("dfba91"))
	draw_rect(Rect2(1,-59,3,3),Color("a78768"))
	draw_rect(Rect2(3,-63,1,1),Color("302e2b"))
	draw_rect(Rect2(-2,-62,2,3),Color("8e7159"))
	draw_rect(Rect2(-4,-66,7,2),Color("80715e"))
	draw_rect(Rect2(3,-57,2,1),Color("68594b"))

func _draw() -> void:
	if side_view and map_id == 2:
		# Rear reference wall: not an obstacle and not used for scoring.
		draw_rect(Rect2(-10,-81,2,55),Color("87958a"))
		for y in range(-78,-26,6): draw_line(Vector2(-12,y),Vector2(-10,y-2),Color("87958a"),0.5)
	if side_view: _limb(-1)
	if side_view:
		_profile()
	else:
		draw_texture(TORSO,Vector2(-8,-54),Color("72c7bf"))
		draw_texture(HEAD,Vector2(-6,-67),Color("ffd4ad"))
		_limb(-1)
	_limb(1)
	if not side_view and map_id == 5 and other_side: _limb(-1)
	if not side_view and map_id == 4:
		# Palms are behind the head, not covering the face.
		draw_texture(HEAD,Vector2(-6,-67),Color("ffd4ad"))
	# Both sets of joints remain readable even when the far arm is behind the torso.
	if joints_visible:
		for side in [-1,1]:
			var p := endpoints(side)
			var color := Color("ffcf70") if side == 1 else Color("79d9f2")
			for i in range(2):
				if side == -1: draw_dashed_line(p[i],p[i+1],color,0.55,1.5)
				else: draw_line(p[i],p[i+1],color,0.55)
			for point in p:
				# Far joints use a ring so coincident near joints do not erase them.
				if side == -1: draw_arc(point,1.9,0,TAU,16,color,0.55)
				else: draw_circle(point,1.05,color)
		draw_line(Vector2(-6,-28),Vector2(6,-28),Color("77edbd"),0.5)
