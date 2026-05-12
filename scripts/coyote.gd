extends Node2D
# Coyote — spawns at night on a dry-edge tile, walks toward the beaver.
# On contact, calls beaver.bite() and despawns.

const G := preload("res://scripts/game.gd")

var world: Node
var beaver: Node
var speed := 38.0
var _hop_clock := 0.0
var _sprite_tex: Texture2D

func _ready() -> void:
	world = get_node("/root/Main/World")
	beaver = get_tree().get_first_node_in_group("beaver")
	if ResourceLoader.exists("res://assets/sprites/coyote.png"):
		_sprite_tex = load("res://assets/sprites/coyote.png") as Texture2D
	add_to_group("coyote")

func _process(delta: float) -> void:
	if not beaver:
		return
	# Despawn at dawn
	if Game.phase != Game.Phase.NIGHT:
		queue_free()
		return
	# Move toward beaver
	var to_beaver = (beaver.position - position)
	if to_beaver.length() < 24.0:
		if beaver.has_method("bite"):
			beaver.bite()
		queue_free()
		return
	var step = to_beaver.normalized() * speed * delta
	position += step
	_hop_clock += delta * 6.0
	queue_redraw()

func _draw() -> void:
	if _sprite_tex != null:
		var sz := _sprite_tex.get_size()
		draw_texture_rect(_sprite_tex, Rect2(-sz / 2.0, sz), false)
		return
	# Placeholder coyote — small lean tan-colored shape
	var bob := sin(_hop_clock) * 1.2
	draw_rect(Rect2(-10, -4 + bob, 18, 8), Game.COL_COYOTE)
	draw_rect(Rect2(7, -7 + bob, 6, 6), Game.COL_COYOTE)  # head
	draw_rect(Rect2(11, -8 + bob, 2, 3), Game.COL_COYOTE)  # ear
	draw_rect(Rect2(11, -6 + bob, 1, 1), Color.BLACK)  # eye
	# legs
	draw_rect(Rect2(-7, 4 + bob, 2, 4), Game.COL_COYOTE)
	draw_rect(Rect2(4, 4 + bob, 2, 4), Game.COL_COYOTE)
