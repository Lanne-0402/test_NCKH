extends "res://maps/shared/characters/player/mk2_actor.gd"
func endpoints(side: int) -> Array[Vector2]:
	if pose_id == 4:
		# Forward upper arms project short before opening sideways.
		var shoulder := Vector2(side*8,-49)
		var elbow := Vector2(side*lerpf(2,22,amount),-49)
		return [shoulder,elbow,elbow+Vector2(0,-14)]
	return super.endpoints(side)
## Display-only 2D poses. Never used to derive angles or score a user.
func arm_angles(side: int) -> Vector2:
	if pose_id == 3:
		var start := Vector2(150,-90) if side < 0 else Vector2(30,-90)
		var end := Vector2(175,-90) if side < 0 else Vector2(5,-90)
		return start.lerp(end,amount)*PI/180
	if pose_id == 4:
		var start := Vector2(-55,-100) if side < 0 else Vector2(-125,-80)
		var end := Vector2(-175,-90) if side < 0 else Vector2(-5,-90)
		return start.lerp(end,amount)*PI/180
	if pose_id == 0:
		var start := Vector2(-175,-90) if side < 0 else Vector2(-5,-90)
		var end := Vector2(-110,-100) if side < 0 else Vector2(-70,-80)
		return start.lerp(end,amount)*PI/180
	return super.arm_angles(side)
