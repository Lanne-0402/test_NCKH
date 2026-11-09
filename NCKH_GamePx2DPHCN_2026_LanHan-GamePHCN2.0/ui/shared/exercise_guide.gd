extends Control
signal finished
const Actor = preload("res://ui/shared/guide_actor.gd")
const TITLES := ["ÉP HAI BẢ VAI RA SAU","NÂNG TAY ÁP TƯỜNG","MỞ HAI TAY SANG HAI BÊN","HAI TAY SAU ĐẦU","KÉO TAY NGANG NGỰC"]
const NOTES := ["Duỗi tay ra trước → co khuỷu, ép bả vai · 2 hiệp × 10 lần", "Đứng áp sát tường · giữ 5 giây mỗi lần", "Mở tay từ phía trước sang hai bên · giữ 5 giây", "Hai bàn tay sau đầu · khép khuỷu phía trước · giữ 5 giây", "Giữ 30 giây · thư giãn 30 giây · đổi bên; không tì ép khuỷu"]
const CAPTIONS := [
	["Duỗi hai tay ra trước ngang vai, giữ thân thẳng.","Từ từ co khuỷu, kéo hai khuỷu ra sau để ép bả vai.","Giữ khuỷu gập khoảng 90°, ép hai bả vai ra sau.","Đưa tay ra trước, duỗi khuỷu về tư thế ban đầu."],
	["Đứng áp tường, cẳng tay hướng lên.","Từ từ duỗi khuỷu và nâng hai tay về phía đầu.","Trong bài tập: giữ tư thế đủ 5 giây.","Hạ tay, trở về tư thế ban đầu."],
	["Đưa hai khuỷu gần nhau phía trước; cẳng tay dựng lên, hai bàn tay sát nhau.","Từ từ mở hai cánh tay sang hai bên.","Trong bài tập: giữ tư thế đủ 5 giây.","Khép khuỷu về phía trước, cẳng tay vẫn dựng lên."],
	["Đặt hai bàn tay sau đầu, khuỷu mở hai bên.","Từ từ khép hai khuỷu về phía trước mặt.","Trong bài tập: giữ tư thế đủ 5 giây.","Mở khuỷu về tư thế ban đầu."],
	["Thả lỏng vai, chuẩn bị tay thực hiện và tay hỗ trợ.","Dùng cẳng tay bên kia đỡ tay qua ngực.","Bài thật: giữ 30 giây, nghỉ 30 giây, rồi đổi bên.","Thả lỏng; hình tiếp theo minh họa bên đối diện."]
]
var map_id := 1
var seconds := 0.0
var actor: Node2D
var side_actor: Node2D
var side_label: Label
var caption: Label
var timer_label: Label
var complete := false
var auto_finish := true

func text(value: String, rect: Rect2, font_size: int) -> Label:
	var item := Label.new()
	item.text = value
	item.position = rect.position
	item.size = rect.size
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size",font_size)
	item.add_theme_color_override("font_color",Color("f3f2de"))
	add_child(item)
	return item

func _ready() -> void:
	custom_minimum_size = Vector2(840,486)
	var bg := ColorRect.new()
	bg.color = Color("20392f")
	bg.size = custom_minimum_size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	text("MAP %d · %s" % [map_id,TITLES[map_id-1]],Rect2(16,10,808,34),24)
	text(NOTES[map_id-1],Rect2(16,48,808,48),18)
	actor = Actor.new()
	actor.map_id = map_id
	actor.pose_id = [3,0,4,1,2][map_id-1]
	actor.upper_body_only = true
	actor.outfit_enabled = false
	actor.joints_visible = true
	actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	actor.scale = Vector2(4,4)
	actor.position = Vector2(210,442)
	add_child(actor)
	side_actor = Actor.new()
	side_actor.map_id = map_id
	side_actor.side_view = true
	side_actor.upper_body_only = true
	side_actor.outfit_enabled = false
	side_actor.joints_visible = true
	side_actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	side_actor.scale = Vector2(4,4)
	side_actor.position = Vector2(620,442)
	add_child(side_actor)
	text("TRỰC DIỆN",Rect2(50,96,320,26),16)
	side_label = text("GÓC NGANG · MẶT HƯỚNG →",Rect2(440,96,360,26),16)
	caption = text("",Rect2(20,384,800,45),20)
	timer_label = text("",Rect2(20,435,800,26),16)
	text("Khớp phải: vàng · trái: xanh (nét đứt) · Minh họa cần duyệt chuyên môn.",Rect2(16,463,808,22),16)
	_update()

func _process(delta: float) -> void:
	if complete or not is_visible_in_tree(): return
	seconds = minf(15,seconds+delta)
	_update()
	if seconds >= 15:
		complete = true
		if auto_finish: finished.emit()

func _update() -> void:
	var phase := 0
	var amount := 0.0
	var t := seconds
	# Both sides within 15s, explicitly a shortened preview, not a 30s hold.
	if map_id == 5:
		actor.other_side = seconds >= 7.5
		side_actor.other_side = actor.other_side
		t = minf(15.0,fmod(seconds,7.5)*2.0) if seconds < 15.0 else 15.0
	if t >= 11:
		phase = 3
		amount = 1-smoothstep(11,15,t)
	elif t >= 7:
		phase = 2
		amount = 1
	elif t >= 3:
		phase = 1
		amount = smoothstep(3,7,t)
	actor.amount = amount
	actor.refresh()
	side_actor.amount = amount
	side_actor.refresh()
	caption.text = CAPTIONS[map_id-1][phase]
	if map_id == 5:
		caption.text = ("Tay phải: " if actor.other_side else "Tay trái: ")+caption.text
	timer_label.text = "Xem trước rút gọn · %d giây còn lại" % ceili(15-seconds)
