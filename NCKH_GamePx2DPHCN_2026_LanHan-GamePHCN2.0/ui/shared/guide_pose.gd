extends RefCounted
## Display coordinates only: X lateral, Y down, Z anterior. Not patient thresholds.
## Source: gamescripts_DesignGameplay.docx, sections I and III.
const LENGTH := 14.0

static func elbow_for(s: Vector3, w: Vector3, hint: Vector3, upper_length := LENGTH, lower_length := LENGTH) -> Vector3:
	var axis := (w-s).normalized()
	var distance := s.distance_to(w)
	var along := (upper_length*upper_length-lower_length*lower_length+distance*distance)/(2*distance)
	var middle := s+axis*along
	var radial := hint-middle
	radial -= axis*radial.dot(axis)
	if radial.length_squared() < 0.00001:
		radial = axis.cross(Vector3.RIGHT)
		if radial.length_squared() < 0.00001: radial = axis.cross(Vector3.FORWARD)
	return middle+radial.normalized()*sqrt(maxf(0,upper_length*upper_length-along*along))

static func arm(map_id: int, side: int, progress: float, other_side := false) -> Array[Vector3]:
	var a := clampf(progress,0,1)
	# Map 5 swaps anatomical sides, never reverses the direction of the side camera.
	var canonical_side := -side if other_side and map_id == 5 else side
	var s := Vector3(canonical_side*8,-49,0)
	var e: Vector3
	var w: Vector3
	match map_id:
		1:
			# Start with both arms extended forward at shoulder height.
			# Pull the elbows back while bending them to 90 degrees; reversing
			# progress extends the arms again. Segment lengths stay constant.
			s.z = -2*a
			var upper_angle := deg_to_rad(lerpf(90,-15,a))
			var lower_angle := deg_to_rad(lerpf(90,75,a))
			e = s+Vector3(0,cos(upper_angle),sin(upper_angle))*LENGTH
			w = e+Vector3(0,cos(lower_angle),sin(lower_angle))*LENGTH
		2:
			var upper := deg_to_rad(lerpf(20,80,a))
			var lower := deg_to_rad(lerpf(110,85,a))
			e = s+Vector3(canonical_side*cos(upper),-sin(upper),0)*LENGTH
			w = e+Vector3(canonical_side*cos(lower),-sin(lower),0)*LENGTH
		3:
			# Reference photo: elbows close together AND upright parallel forearms.
			# Previous pose only brought wrists together, creating a wrong triangle.
			var yaw := lerpf(asin(-6.0/LENGTH),PI/2,a)
			e = s+Vector3(canonical_side*sin(yaw),0,cos(yaw))*LENGTH
			w = e+Vector3(0,-LENGTH,0)
		4:
			# Hands stay behind the head while elbows move forward to the midline.
			w = Vector3(canonical_side*3,-60,-5)
			e = elbow_for(s,w,Vector3(canonical_side*lerpf(25,2,a),-52,lerpf(0,25,a)))
		_:
			var direction := Vector3(0,1,0).lerp(Vector3(1,0,0.45).normalized(),a).normalized()
			if canonical_side == -1:
				e = s+direction*LENGTH
				w = e+direction*LENGTH
			else:
				# MID-FOREARM cradles the upper arm, not hand pulling on the elbow.
				var contact := Vector3(-8,-49,0)+Vector3(1,0,0.45).normalized()*LENGTH*0.6+Vector3(0,0,1)
				var target_elbow := elbow_for(s,contact,Vector3(12,-31,8),LENGTH,LENGTH*0.5)
				var target_wrist := contact*2-target_elbow
				var upper_direction := Vector3(0,1,0).lerp((target_elbow-s).normalized(),a).normalized()
				var fore_direction := Vector3(0,1,0).lerp((target_wrist-target_elbow).normalized(),a).normalized()
				e = s+upper_direction*LENGTH
				w = e+fore_direction*LENGTH
	if other_side and map_id == 5:
		s.x = -s.x
		e.x = -e.x
		w.x = -w.x
	return [s,e,w]

static func project(point: Vector3, side_view: bool) -> Vector2:
	# Front camera shows the person's anatomical left on the viewer's right.
	return Vector2(point.z,point.y) if side_view else Vector2(-point.x,point.y)
