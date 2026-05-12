extends Node2D
# Dam: owns the segment array, decay, repair, water-sim trigger, drawing.
# Each segment is a float 0..1 integrity. Visible as a small block on the
# dam-zone column. ≥0 segments stack vertically (max 10).

const G := preload("res://scripts/game.gd")

@onready var world: Node2D = get_node("/root/Main/World")
@onready var water: Node = get_node("/root/Main/WaterSim")

var decay_per_day := 0.25      # −25% integrity per in-game day
var _decay_clock := 0.0        # accumulates real seconds → applies decay across all segments

var tex_dam_new: Texture2D
var tex_dam_worn: Texture2D
var tex_dam_broken: Texture2D

func _ready() -> void:
	if ResourceLoader.exists("res://assets/sprites/dam_new.png"):
		tex_dam_new = load("res://assets/sprites/dam_new.png") as Texture2D
	if ResourceLoader.exists("res://assets/sprites/dam_worn.png"):
		tex_dam_worn = load("res://assets/sprites/dam_worn.png") as Texture2D
	if ResourceLoader.exists("res://assets/sprites/dam_broken.png"):
		tex_dam_broken = load("res://assets/sprites/dam_broken.png") as Texture2D

func _process(delta: float) -> void:
	# Decay at the same rate as one in-game day = 90 real seconds.
	# Apply incrementally so the visuals smoothly transition new→worn→broken.
	if Game.dam_segments.is_empty():
		return
	var dt_norm := delta / 90.0   # fraction of one day
	var changed := false
	for i in range(Game.dam_segments.size()):
		Game.dam_segments[i] = max(0.0, Game.dam_segments[i] - decay_per_day * dt_norm)
	# Remove fully-broken segments (integrity == 0)
	var before := Game.dam_segments.size()
	var kept: Array = []
	for v in Game.dam_segments:
		if v > 0.0:
			kept.append(v)
	if kept.size() != before:
		Game.dam_segments = kept
		changed = true
		Game.emit_message("A dam segment broke.")
	queue_redraw()
	if changed:
		water.recalc_water_from_dam(Game.dam_segments.size())
		Game.dam_changed.emit(Game.dam_segments.size(), Game.dam_segments.duplicate())

func _draw() -> void:
	# Stack visible blocks on the dam zone column, bottom-to-top.
	var x: int = int(world.dam_zone_x) * Game.TILE_SIZE
	for i in range(Game.dam_segments.size()):
		var y_tile: int = int(world.dam_zone_y_bot) - i
		if y_tile < int(world.dam_zone_y_top):
			break
		var integrity: float = Game.dam_segments[i]
		var rect_full := Rect2(x, y_tile * Game.TILE_SIZE, Game.TILE_SIZE, Game.TILE_SIZE)
		var tex: Texture2D = null
		if integrity > 0.66:
			tex = tex_dam_new
		elif integrity > 0.33:
			tex = tex_dam_worn
		else:
			tex = tex_dam_broken
		if tex != null:
			draw_texture_rect(tex, rect_full, false)
		else:
			# Fallback rectangle
			var c := Game.COL_DAM_NEW if integrity > 0.66 else (Game.COL_DAM_WORN if integrity > 0.33 else Game.COL_DAM_BROK)
			var rect := Rect2(x + 2, y_tile * Game.TILE_SIZE + 4, Game.TILE_SIZE - 4, Game.TILE_SIZE - 8)
			draw_rect(rect, c)
			for k in range(3):
				var ly := rect.position.y + (k + 1) * (rect.size.y / 4.0)
				draw_line(Vector2(rect.position.x, ly), Vector2(rect.position.x + rect.size.x, ly), Color(0, 0, 0, 0.4), 1.0)

func can_place() -> bool:
	return Game.dam_segments.size() < 10

func add_segment() -> bool:
	if not can_place():
		return false
	Game.dam_segments.append(1.0)
	queue_redraw()
	water.recalc_water_from_dam(Game.dam_segments.size())
	Game.dam_changed.emit(Game.dam_segments.size(), Game.dam_segments.duplicate())
	Game.emit_message("Dam segment placed.")
	return true

func find_worst_segment_index() -> int:
	if Game.dam_segments.is_empty():
		return -1
	var worst := 0
	for i in range(Game.dam_segments.size()):
		if Game.dam_segments[i] < Game.dam_segments[worst]:
			worst = i
	return worst

func repair_worst() -> bool:
	var i := find_worst_segment_index()
	if i < 0 or Game.dam_segments[i] >= 1.0:
		return false
	Game.dam_segments[i] = min(1.0, Game.dam_segments[i] + 0.5)
	queue_redraw()
	Game.dam_changed.emit(Game.dam_segments.size(), Game.dam_segments.duplicate())
	Game.emit_message("Repaired a dam segment.")
	return true

func needs_repair_nearby(p: Vector2i) -> bool:
	# Beaver is adjacent to dam if x-distance ≤ 1 AND y in zone.
	if abs(p.x - int(world.dam_zone_x)) > 1:
		return false
	if p.y < int(world.dam_zone_y_top) - 1 or p.y > int(world.dam_zone_y_bot) + 1:
		return false
	# Any segment with integrity < 1.0?
	for v in Game.dam_segments:
		if v < 1.0:
			return true
	return false

func drought_drain() -> void:
	# Drought: water drops 1 unless dam has ≥7 segments. We model "water drops 1"
	# by removing the bottom (oldest) segment.
	if Game.dam_segments.size() >= 7:
		Game.emit_message("Drought — dam held strong.")
		return
	if Game.dam_segments.size() > 0:
		Game.dam_segments.pop_front()
		queue_redraw()
		water.recalc_water_from_dam(Game.dam_segments.size())
		Game.dam_changed.emit(Game.dam_segments.size(), Game.dam_segments.duplicate())
		Game.emit_message("Drought — a dam segment was lost.")
