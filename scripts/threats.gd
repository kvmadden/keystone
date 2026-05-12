extends Node
# Threats manager: schedules coyote spawns at night + random droughts every ~3 days.

const G := preload("res://scripts/game.gd")
const CoyoteScript := preload("res://scripts/coyote.gd")

@onready var world: Node = get_node("/root/Main/World")
@onready var dam: Node = get_node("/root/Main/Dam")
@onready var entities_root: Node = get_node("/root/Main/Entities")

var _last_coyote_day := 0
var _coyote_spawn_clock := 0.0
var _drought_check_day := 0
var _last_drought_day := -2

func _ready() -> void:
	Game.day_advanced.connect(_on_day)

func _process(delta: float) -> void:
	# Spawn a coyote ~midway through every night
	if Game.phase == Game.Phase.NIGHT and Game.current_day > _last_coyote_day:
		_coyote_spawn_clock += delta
		if _coyote_spawn_clock >= 8.0:
			_spawn_coyote()
			_coyote_spawn_clock = 0.0
			_last_coyote_day = Game.current_day

func _on_day(day: int) -> void:
	# Drought roll: ~every 3 days, with min gap of 2 days
	if day - _last_drought_day >= 3 and randf() < 0.55:
		_trigger_drought()
		_last_drought_day = day

func _spawn_coyote() -> void:
	# Pick a dry-edge tile (left or right column, on grass/dry/dirt)
	var candidates: Array = []
	for y in range(2, Game.MAP_H - 2):
		for x in [0, 1, Game.MAP_W - 2, Game.MAP_W - 1]:
			var t = world.tiles[y][x]
			if t == Game.Tile.GRASS or t == Game.Tile.DRY or t == Game.Tile.DIRT:
				candidates.append(Vector2i(x, y))
	if candidates.is_empty():
		return
	var tile: Vector2i = candidates[randi() % candidates.size()]
	var c := Node2D.new()
	c.set_script(CoyoteScript)
	c.position = Vector2(tile.x * Game.TILE_SIZE + Game.TILE_SIZE / 2.0, tile.y * Game.TILE_SIZE + Game.TILE_SIZE / 2.0)
	entities_root.add_child(c)
	Game.emit_message("A coyote is on the prowl.")

func _trigger_drought() -> void:
	Game.drought_active = true
	Game.drought_days_left = 1
	Game.emit_message("Drought! Water level falling.")
	var had_dam: bool = Game.dam_segments.size() > 0
	dam.drought_drain()
	# Lose condition: had a dam before the drought, and it's all gone now.
	# (This catches "drought wiped out a 1-segment dam" — true catastrophe.)
	if had_dam and Game.dam_segments.is_empty() and not Game.game_over:
		Game.game_over = true
		Game.game_lost.emit("The drought took the last dam segment. The pond drained.")
