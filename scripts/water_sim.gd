extends Node
# Water flood-fill + wetland conversion.
# Called by Dam whenever segments change, and once per second to age wetlands.

const G := preload("res://scripts/game.gd")

@onready var world: Node2D = get_node("/root/Main/World")

var _wetland_clock := 0.0

func _process(delta: float) -> void:
	_wetland_clock += delta
	if _wetland_clock >= 0.5:
		_wetland_clock = 0.0
		_age_wetlands(0.5)

func recalc_water_from_dam(intact_segments: int) -> void:
	# 1. Reset all SHALLOW/DEEP back to baseline (the stream is always at least
	#    shallow up to the dam; upstream of the dam grows with intact segments).
	for y in range(Game.MAP_H):
		for x in range(Game.MAP_W):
			var t: int = int(world.tiles[y][x])
			if t == Game.Tile.SHALLOW or t == Game.Tile.DEEP:
				# Reset to dirt; we'll repaint stream below.
				world.tiles[y][x] = Game.Tile.DIRT

	# 2. Repaint stream baseline (always present)
	_repaint_stream_baseline()

	# 3. Flood-fill upstream of the dam — depth proportional to segments.
	# Upstream = x < dam_zone_x. We expand the water vertically per "level".
	# Level 1: stream tiles widen by 1 row each side, marked SHALLOW.
	# Level 3+: middle two rows become DEEP. Higher levels widen further.
	var level: int = clamp(intact_segments, 0, 10)
	if level > 0:
		_flood_upstream(level)

	world.queue_redraw()
	Game.water_changed.emit()

func _repaint_stream_baseline() -> void:
	for x in range(Game.MAP_W):
		var yoff: int = int(round(sin(x * 0.4) * 1.0))
		var top: int = int(clamp(int(world.stream_y_top) + yoff, 1, Game.MAP_H - 3))
		var bot: int = int(clamp(int(world.stream_y_bot) + yoff, top + 1, Game.MAP_H - 2))
		# Downstream of dam stays SHALLOW only (1 tile-ish trickle)
		# Upstream gets re-flooded by _flood_upstream
		world.tiles[top][x] = Game.Tile.SHALLOW
		world.tiles[bot][x] = Game.Tile.SHALLOW

func _flood_upstream(level: int) -> void:
	# Determine widening band around the stream center upstream of dam.
	# We just walk every tile upstream of the dam_zone_x and convert tiles
	# within `band` rows of the stream center to SHALLOW (and DEEP for inner).
	var band: int = 1 + int(round(level / 2.0))   # rows on each side of center
	var deep_band: int = int(max(0, int(round((level - 2) / 2.0))))
	for x in range(0, int(world.dam_zone_x) + 1):
		var yoff: int = int(round(sin(x * 0.4) * 1.0))
		var center: int = int((int(world.stream_y_top) + int(world.stream_y_bot)) / 2) + yoff
		for dy in range(-band, band + 1):
			var y: int = center + dy
			if y < 0 or y >= Game.MAP_H:
				continue
			var t = world.tiles[y][x]
			if t == Game.Tile.TREE or t == Game.Tile.LODGE:
				continue  # do not flood trees/lodge
			if abs(dy) <= deep_band and level >= 3:
				world.tiles[y][x] = Game.Tile.DEEP
			else:
				if world.tiles[y][x] != Game.Tile.DEEP:
					world.tiles[y][x] = Game.Tile.SHALLOW

func _age_wetlands(dt: float) -> void:
	# Tile adjacent to water for 1 in-game day becomes wetland.
	# We approximate "1 in-game day" as 90 real seconds → 0.0111 per real second.
	# We let the threshold be `~1.0` and increment by dt/90 per tick.
	var inc: float = dt / 90.0
	var changed: bool = false
	for y in range(Game.MAP_H):
		for x in range(Game.MAP_W):
			var t: int = int(world.tiles[y][x])
			# Only land that can become wetland: dry/grass/dirt
			if t != Game.Tile.DRY and t != Game.Tile.GRASS and t != Game.Tile.DIRT:
				continue
			if not world.is_adjacent_water(Vector2i(x, y)):
				continue
			world.wet_age[y][x] = float(world.wet_age[y][x]) + inc
			if float(world.wet_age[y][x]) >= 1.0:
				world.tiles[y][x] = Game.Tile.WETLAND
				changed = true
	if changed:
		world.queue_redraw()
		Game.water_changed.emit()
