extends "res://tests/visual/mk2_actor.gd"

func arm_angles(side: int) -> Vector2:
	if pose_id != 3:
		return super.arm_angles(side)
	# Visual approximation of Map 1's bent-elbow shoulder movement, not scoring angles.
	var start := Vector2(150,-90) if side < 0 else Vector2(30,-90)
	var end := Vector2(175,-90) if side < 0 else Vector2(5,-90)
	return start.lerp(end,amount)*PI/180.0
