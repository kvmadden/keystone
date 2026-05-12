extends Node2D
class_name SpeciesEntity
# A wandering creature/plant. Procedural movement on valid tiles for its kind.
# Drawn as a colored shape (placeholder) — swapped for PixelLab sprite if loaded.

const G := preload("res://scripts/game.gd")

@export var kind: String = "willow"
@export var world_path: NodePath
@export var habitat: Array = []

var world: Node
var move_speed := 18.0
var target_pos: Vector2
var _wander_clock := 0.0
var _hop_clock := 0.0
var _hop_offset := 0.0
var _sprite_tex: Texture2D

# Static = doesn't move (willow).
var stationary := false

func _ready() -> void:
	world = get_node(world_path)
	stationary = (kind == "willow")
	target_pos = position
	_wander_clock = randf() * 2.0
	_try_load_sprite()

func _process(delta: float) -> void:
	if stationary:
		queue_redraw()
		return
	_wander_clock -= delta
	if _wander_clock <= 0.0:
		_pick_new_target()
		_wander_clock = randf_range(1.0, 3.0)
	var to_target := target_pos - position
	if to_target.length() > 1.0:
		var step := to_target.normalized() * move_speed * delta
		if step.length() > to_target.length():
			position = target_pos
		else:
			position += step
	_hop_clock += delta * 4.0
	# Tiny hop bob for frog/fish/duck — looks alive
	_hop_offset = sin(_hop_clock) * (3.0 if kind == "frog" else 1.5)
	queue_redraw()

func _pick_new_target() -> void:
	var current := _tile_at(position)
	var options: Array = []
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var p = current + d
		if not world.in_bounds(p):
			continue
		if habitat.has(world.tiles[p.y][p.x]):
			options.append(p)
	if options.is_empty():
		# Find ANY habitat tile globally
		for y in range(Game.MAP_H):
			for x in range(Game.MAP_W):
				if habitat.has(world.tiles[y][x]):
					options.append(Vector2i(x, y))
				if options.size() > 8:
					break
	if options.is_empty():
		return
	var pick: Vector2i = options[randi() % options.size()]
	target_pos = Vector2(pick.x * Game.TILE_SIZE + Game.TILE_SIZE / 2.0, pick.y * Game.TILE_SIZE + Game.TILE_SIZE / 2.0)

func _draw() -> void:
	if _sprite_tex != null:
		var sz := _sprite_tex.get_size()
		var dest := Rect2(-sz / 2.0 + Vector2(0, -_hop_offset), sz)
		draw_texture_rect(_sprite_tex, dest, false)
		return
	# Placeholder draw — small distinct silhouette per kind.
	match kind:
		"willow":
			# Tall thin canopy
			draw_rect(Rect2(-3, -2, 6, 10), Game.COL_STUMP)
			draw_rect(Rect2(-8, -14, 16, 14), Game.COL_WILLOW)
			draw_rect(Rect2(-10, -10, 4, 4), Game.COL_WILLOW)
			draw_rect(Rect2(6, -10, 4, 4), Game.COL_WILLOW)
		"frog":
			draw_rect(Rect2(-5, -3 - _hop_offset, 10, 6), Game.COL_FROG)
			draw_rect(Rect2(-3, -7 - _hop_offset, 6, 4), Game.COL_FROG)
			draw_rect(Rect2(-2, -6 - _hop_offset, 1, 1), Color.BLACK)
			draw_rect(Rect2(1, -6 - _hop_offset, 1, 1), Color.BLACK)
		"fish":
			draw_rect(Rect2(-6, -2, 10, 4), Game.COL_FISH)
			draw_rect(Rect2(4, -3, 4, 6), Game.COL_FISH)  # tail
			draw_rect(Rect2(-5, -1, 1, 1), Color.BLACK)
		"duck":
			draw_rect(Rect2(-5, -3, 10, 6), Game.COL_DUCK)
			draw_rect(Rect2(3, -7, 4, 5), Game.COL_DUCK)
			draw_rect(Rect2(6, -5, 2, 1), Game.COL_ACCENT)
			draw_rect(Rect2(4, -6, 1, 1), Color.BLACK)
		"heron":
			draw_rect(Rect2(-2, -12, 4, 12), Game.COL_HERON)
			draw_rect(Rect2(-6, -16, 12, 4), Game.COL_HERON)
			draw_rect(Rect2(4, -14, 6, 2), Game.COL_ACCENT)  # beak
			draw_rect(Rect2(-3, -2, 2, 8), Game.COL_HERON)  # leg
			draw_rect(Rect2(1, -2, 2, 8), Game.COL_HERON)  # leg
		"otter":
			draw_rect(Rect2(-8, -3, 14, 6), Game.COL_OTTER)
			draw_rect(Rect2(5, -5, 5, 4), Game.COL_OTTER)
			draw_rect(Rect2(8, -4, 1, 1), Color.BLACK)
		_:
			draw_circle(Vector2.ZERO, 6, Color.MAGENTA)

func _try_load_sprite() -> void:
	var path := "res://assets/sprites/%s.png" % kind
	if ResourceLoader.exists(path):
		_sprite_tex = load(path) as Texture2D

func _tile_at(p: Vector2) -> Vector2i:
	return Vector2i(int(p.x / Game.TILE_SIZE), int(p.y / Game.TILE_SIZE))
