extends Area2D

const SPEED = 250.0

# --- MỚI: Biến lưu giá trị điểm của ngôi sao này (mặc định để 10) ---
var point_value = 10 

func _process(delta):
	position.x -= (SPEED * Global.speed_multiplier) * delta
	if position.x < -100:
		queue_free()

func _on_body_entered(body):
	if body.name == "Player":
		# Cộng đúng số điểm của ngôi sao này vào biến star_score bên Main_Level
		get_tree().current_scene.star_score += point_value
		print("Đã ăn sao loại: ", point_value, " điểm!") 
		queue_free()
