extends Node2D
## Conceptual sagittal diagram, not a rotated frontal sprite or clinical rig.
## Faces right: negative X indicates backwards. Elbow stays at 90 degrees.
var amount := 0.0

func endpoints() -> Array[Vector2]:
	var shoulder := Vector2(-3*amount,-49)
	var angle := deg_to_rad(90+15*amount)
	var elbow := shoulder+Vector2.from_angle(angle)*14
	var wrist := elbow+Vector2.from_angle(angle-PI/2)*14
	return [shoulder,elbow,wrist]

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	# Code-native profile silhouette, intentionally distinguished from Mk2 art.
	draw_colored_polygon(PackedVector2Array([Vector2(-5,-54),Vector2(4,-54),Vector2(7,-46),Vector2(5,-35),Vector2(5,-28),Vector2(-5,-28),Vector2(-4,-40)]),Color("548d84"))
	draw_rect(Rect2(-4,-65,9,10),Color("bbaa8d"))
	draw_rect(Rect2(5,-61,3,3),Color("bbaa8d"))
	draw_rect(Rect2(3,-63,1,1),Color("182b28"))
	draw_line(Vector2(0,-55),Vector2(0,-28),Color("97c3b0"),0.6)
	var p := endpoints()
	for i in range(2):
		draw_line(p[i],p[i+1],Color("1a302b"),6)
		draw_line(p[i],p[i+1],Color("b99f7a"),4)
		draw_line(p[i],p[i+1],Color("46e6ff"),0.6)
	for joint in p:
		draw_circle(joint,1.8,Color("17251e"))
		draw_circle(joint,1.2,Color("ffe08a"))
	# Show the backwards direction independently of the animation phase.
	draw_line(Vector2(-3,-54),Vector2(-13,-54),Color("f3d489"),0.7)
	draw_line(Vector2(-13,-54),Vector2(-10,-56),Color("f3d489"),0.7)
	draw_line(Vector2(-13,-54),Vector2(-10,-52),Color("f3d489"),0.7)
