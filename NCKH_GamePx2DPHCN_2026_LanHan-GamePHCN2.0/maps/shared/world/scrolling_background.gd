extends Node2D

@export var segment_width := 1152.0
@export var far_scroll_speed := 32.0
@export var near_scroll_speed := 85.0
@export var scroll_fade_speed := 4.0

var scrolling_enabled := true
var _scroll_blend := 0.0

@onready var far_layer: Node2D = $FarLayer
@onready var near_layer: Node2D = $NearLayer

func _ready() -> void:
	# The previous forest crop contained opaque vertical cut edges, not a seamless
	# panorama. Replace it with complete isolated silhouettes until new BG arrives.
	var tree = preload("res://assets/map_4/goal/summit_tree.png")
	var landscape := get_node_or_null("Landscape")
	var map_id := int(landscape.map_id) if landscape != null else 1
	var colors := [Color("638d81"),Color("778777"),Color("7c7c92"),Color("899b9b"),Color("70a28e")]
	for segment in far_layer.get_children():
		for child in segment.get_children(): child.hide()
		for i in range(5):
			var sprite := Sprite2D.new()
			sprite.texture = tree
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2.ONE * (4 if map_id == 4 else 3)
			sprite.position = Vector2(100+i*240,160 if map_id == 4 else 152)
			sprite.modulate = colors[map_id-1]
			sprite.modulate.a = 0.35
			segment.add_child(sprite)
	if map_id == 4: near_layer.hide()


func _process(delta: float) -> void:
	var target_blend := 1.0 if scrolling_enabled else 0.0
	_scroll_blend = move_toward(_scroll_blend, target_blend, scroll_fade_speed * delta)
	if _scroll_blend <= 0.001:
		return
	_scroll_layer(far_layer, far_scroll_speed * Global.speed_multiplier * _scroll_blend, delta)
	_scroll_layer(near_layer, near_scroll_speed * Global.speed_multiplier * _scroll_blend, delta)


func set_scrolling(enabled: bool) -> void:
	scrolling_enabled = enabled
	if not enabled:
		_scroll_blend = 0.0


func _scroll_layer(layer: Node2D, speed: float, delta: float) -> void:
	layer.position.x -= speed * delta
	if layer.position.x <= -segment_width:
		layer.position.x += segment_width
