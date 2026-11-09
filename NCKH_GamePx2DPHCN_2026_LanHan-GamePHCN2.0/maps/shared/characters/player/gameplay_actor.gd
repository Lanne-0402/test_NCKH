extends "res://maps/shared/characters/player/mk2_actor.gd"
## Game-only fantasy poses. Instruction/rehabilitation rigs are not modified.
var map_id := 1
var animation_clock := 0.0
var running := false
var charging := false
var visual_active := false
var jump_progress := -1.0
var burst := 0.0

func advance(delta: float) -> void:
	animation_clock += delta
	burst = maxf(0.0, burst-delta*2.8)
	refresh()

func endpoints(side: int) -> Array[Vector2]:
	var shoulder := Vector2(side*8,-49)
	var elbow: Vector2
	var wrist: Vector2
	match map_id:
		1:
			elbow = Vector2(side*13,-35).lerp(Vector2(14,-46+side*3),amount)
			wrist = Vector2(side*8,-43).lerp(Vector2(31,-46+side*3),amount)
		2:
			var reach := clampf(amount/0.35,0,1)
			var lift := clampf((amount-0.35)/0.65,0,1)
			wrist = Vector2(side*lerpf(9,18,reach),lerpf(-21,-60,reach)-lift*12)
			elbow = Vector2(side*lerpf(9,22,reach),lerpf(-35,-47,reach)-lift*13)
		3:
			elbow = Vector2(side*22,-43-amount*6)
			wrist = Vector2(side*lerpf(17,36,amount),-56+amount*7)
		4:
			var tuck := 1.0 if jump_progress >= 0.0 else amount*0.5
			elbow = Vector2(side*13,-35-tuck*4)
			wrist = Vector2(side*10,-45-tuck*10)
		_:
			elbow = Vector2(side*12,-36)
			wrist = Vector2(side*16,-26)
	return [shoulder,elbow,wrist]

func leg_points(side: int) -> Array[Vector2]:
	var hip := Vector2(side*4,-28)
	if map_id == 5:
		return [hip,Vector2(side*19,-23),Vector2(-side*7,-22)]
	if map_id == 4 and jump_progress >= 0.0:
		# Deliberate three key poses: takeoff, tucked flight, landing.
		var tuck := 1.0 if jump_progress > 0.15 and jump_progress < 0.85 else 0.45
		return [hip,Vector2(side*12,-15-tuck*6),Vector2(side*7,-3-tuck*11)]
	var stride := sin(animation_clock*10.0)*float(side) if running else 0.0
	return [hip,Vector2(side*5+stride*3,-15),Vector2(side*5+stride*5,-3-maxf(stride,0)*5)]

func _trousers(hip: Vector2, knee: Vector2, ankle: Vector2, side: int) -> void:
	var tint := cloth("494743").darkened(0.12 if side < 0 else 0.0)
	for pair in [[hip,knee],[knee,ankle]]:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		draw_set_transform(a,(b-a).angle()-PI/2)
		draw_rect(Rect2(-4,-1,8,a.distance_to(b)+2),cloth("252c31"))
		draw_rect(Rect2(-3,0,6,a.distance_to(b)),tint)
		draw_rect(Rect2(-2,1,1,maxf(1,a.distance_to(b)-2)),cloth("6e6a5e"))
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(ankle+Vector2(-3,-4),Vector2(6,4)),cloth("b19a72"))
	draw_rect(Rect2(ankle+Vector2(-5,0),Vector2(10,3)),cloth("29343b"))
	draw_rect(Rect2(ankle+Vector2(-5,2),Vector2(10,1)),cloth("81959b"))

func _draw() -> void:
	points.clear()
	_effects()
	for side in [-1,1]:
		var leg := leg_points(side)
		_trousers(leg[0],leg[1],leg[2],side)
	_tunic()
	draw_texture(HEAD,Vector2(-6,-67),Color("ffd4ad"))
	_headwear()
	_arm(-1)
	_arm(1)
	if joints_visible:
		for side in [-1,1]:
			var p := endpoints(side)
			draw_line(p[0],p[1],Color("77edbd"),0.6)
			draw_line(p[1],p[2],Color("77edbd"),0.6)
			for joint in p: draw_circle(joint,1.2,Color("ffe08a"))

func _effects() -> void:
	if not visual_active and burst <= 0.0: return
	if map_id == 5:
		for i in range(9):
			var phase := fmod(animation_clock*0.22+float(i)/9.0,1.0)
			var x := sin(float(i)*2.4+phase*3.0)*23.0
			var y := -22-phase*65
			var opacity := sin(phase*PI)*0.35
			draw_rect(Rect2(x,y,3+phase*3,3+phase*3),Color(0.8,0.95,0.94,opacity))
	elif map_id == 2 and amount >= 0.35:
		for side in [-1,1]:
			var palm := endpoints(side)[2]
			for i in range(4):
				var angle := animation_clock*4+float(i)*PI/2
				draw_rect(Rect2(palm+Vector2.from_angle(angle)*5,Vector2(2,2)),Color(1,0.9,0.52,0.7))
	elif map_id == 1 and (charging or burst > 0):
		for i in range(8):
			var phase := fmod(animation_clock+float(i)/8.0,1.0)
			var at := Vector2(cos(float(i)*TAU/8)*(23+burst*15),-30-phase*32)
			draw_rect(Rect2(at,Vector2(2,3)),Color(0.7,0.93,1,0.25+burst*0.6))
		if burst > 0:
			var center := Vector2(40,-46)
			draw_arc(center,5+(1-burst)*15,0,TAU,12,Color(1,0.9,0.6,burst),2)
			for i in range(8):
				var ray := Vector2.from_angle(float(i)*TAU/8)
				draw_line(center+ray*5,center+ray*(10+(1-burst)*12),Color(1,0.76,0.35,burst),2)
