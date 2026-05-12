extends Node2D
# The world: owns the tile grid + draws it.
# Stores tile codes in `tiles[y][x]` and exposes accessors for other systems.
# Also draws the dam-zone outline + tracks the wetland-aging counter per tile.

const G := preload("res://scripts/game.gd")

var tiles: Array = []          # tiles[y][x] : int (Game.Tile)
var wet_age: Array = []        # seconds adjacent-to-water for wetland conversion
var tree_positions: Array = [] # Vector2i list of tree tiles (for chew lookups)
var stream_y_top := 9
var stream_y_bot := 10
var dam_zone_x := 18           # column where the dam sits
var dam_zone_y_top := 8
var dam_zone_y_bot := 11       # 4-tall zone (stream + 1 above/below)

# Per-tile cached display tint (refresh on water update)
var _display: Array = []

func _ready() -> void:
	_generate()
	queue_redraw()

func _generate() -> void:
	# Empty grid → dry/grass mix with a 2-tile stream + dam zone + scattered trees.
	tiles.resize(Game.MAP_H)
	wet_age.resize(Game.MAP_H)
	for y in range(Game.MAP_H):
		var row := []
		var wrow := []
		row.resize(Game.MAP_W)
		wrow.resize(Game.MAP_W)
		for x in range(Game.MAP_W):
			# Base: grass with a "dry/dirt" speckle
			var r := randf()
			if r < 0.18:
				row[x] = Game.Tile.DRY
			elif r < 0.30:
				row[x] = Game.Tile.DIRT
			else:
				row[x] = Game.Tile.GRASS
			wrow[x] = 0.0
		tiles[y] = row
		wet_age[y] = wrow

	# Carve the stream (2 tiles tall, slight wobble) — starts as SHALLOW
	for x in range(Game.MAP_W):
		var yoff := int(round(sin(x * 0.4) * 1.0))
		var top: int = clamp(stream_y_top + yoff, 1, Game.MAP_H - 3)
		var bot: int = clamp(stream_y_bot + yoff, top + 1, Game.MAP_H - 2)
		tiles[top][x] = Game.Tile.SHALLOW
		tiles[bot][x] = Game.Tile.SHALLOW
		# Dirt banks
		if top - 1 >= 0 and tiles[top - 1][x] == Game.Tile.GRASS:
			tiles[top - 1][x] = Game.Tile.DIRT
		if bot + 1 < Game.MAP_H and tiles[bot + 1][x] == Game.Tile.GRASS:
			tiles[bot + 1][x] = Game.Tile.DIRT

	# Dam zone: mark 3 tall tiles at dam_zone_x as build zone (visible outline)
	# (build zone overlaps the stream + 1 tile above/below — narrow point)
	for y in range(dam_zone_y_top, dam_zone_y_bot + 1):
		# Keep stream water visible underneath; just mark it logically.
		pass

	# Scatter ~25 trees on grass tiles, biased outside the stream
	var placed := 0
	var attempts := 0
	while placed < 25 and attempts < 500:
		attempts += 1
		var tx := randi() % Game.MAP_W
		var ty := randi() % Game.MAP_H
		if abs(ty - 9) < 2:  # avoid stream
			continue
		if tx >= dam_zone_x - 1 and tx <= dam_zone_x + 1:
			continue
		if tiles[ty][tx] != Game.Tile.GRASS and tiles[ty][tx] != Game.Tile.DRY:
			continue
		tiles[ty][tx] = Game.Tile.TREE
		tree_positions.append(Vector2i(tx, ty))
		placed += 1

	# Lodge — pick a tile next to the stream on the left
	var lodge_x := 3
	var lodge_y := 11
	if tiles[lodge_y][lodge_x] == Game.Tile.SHALLOW:
		lodge_y = 12
	tiles[lodge_y][lodge_x] = Game.Tile.LODGE

func _draw() -> void:
	for y in range(Game.MAP_H):
		for x in range(Game.MAP_W):
			var t = tiles[y][x]
			var rect := Rect2(x * Game.TILE_SIZE, y * Game.TILE_SIZE, Game.TILE_SIZE, Game.TILE_SIZE)
			draw_rect(rect, _tile_color(t))
			# Subtle inner border for grid feel — only on land
			if t != Game.Tile.SHALLOW and t != Game.Tile.DEEP:
				draw_rect(rect, Color(0, 0, 0, 0.10), false, 1.0)

			# Tree top: draw a darker square within the tile
			if t == Game.Tile.TREE:
				var inner := Rect2(rect.position + Vector2(6, 4), Vector2(20, 24))
				draw_rect(inner, Game.COL_TREE)
				draw_rect(Rect2(inner.position + Vector2(-2, -3), Vector2(24, 12)), Game.COL_TREE_CR)
				draw_rect(Rect2(rect.position + Vector2(13, 24), Vector2(6, 6)), Game.COL_STUMP)
			elif t == Game.Tile.LODGE:
				var lr := Rect2(rect.position + Vector2(2, 2), Vector2(28, 28))
				draw_rect(lr, Game.COL_LODGE)
				var door := Rect2(rect.position + Vector2(13, 18), Vector2(6, 10))
				draw_rect(door, Game.COL_LODGE_DR)

	# Dam-zone outline (gold dashed-ish rect)
	var dz_rect := Rect2(
		dam_zone_x * Game.TILE_SIZE,
		dam_zone_y_top * Game.TILE_SIZE,
		Game.TILE_SIZE,
		(dam_zone_y_bot - dam_zone_y_top + 1) * Game.TILE_SIZE,
	)
	draw_rect(dz_rect, Color(Game.COL_DAM_ZONE.r, Game.COL_DAM_ZONE.g, Game.COL_DAM_ZONE.b, 0.45), false, 2.0)

func _tile_color(t: int) -> Color:
	match t:
		Game.Tile.DRY: return Game.COL_DRY
		Game.Tile.GRASS: return Game.COL_GRASS
		Game.Tile.DIRT: return Game.COL_DIRT
		Game.Tile.SHALLOW: return Game.COL_WATER_S
		Game.Tile.DEEP: return Game.COL_WATER_D
		Game.Tile.WETLAND: return Game.COL_WETLAND
		Game.Tile.TREE: return Game.COL_GRASS
		Game.Tile.LODGE: return Game.COL_GRASS
	return Game.COL_DRY

# ── Helpers other systems call ─────────────────────────────────────────
func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < Game.MAP_W and p.y < Game.MAP_H

func get_tile(p: Vector2i) -> int:
	if not in_bounds(p):
		return Game.Tile.DRY
	return tiles[p.y][p.x]

func set_tile(p: Vector2i, t: int) -> void:
	if not in_bounds(p):
		return
	tiles[p.y][p.x] = t
	queue_redraw()

func is_walkable(p: Vector2i) -> bool:
	if not in_bounds(p):
		return false
	var t: int = tiles[p.y][p.x]
	# Beaver swims through shallow + deep, walks everything except trees
	if t == Game.Tile.TREE:
		return false
	return true

func is_adjacent_water(p: Vector2i) -> bool:
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var q = p + d
		if not in_bounds(q):
			continue
		var t: int = tiles[q.y][q.x]
		if t == Game.Tile.SHALLOW or t == Game.Tile.DEEP:
			return true
	return false

func find_tree_near(p: Vector2i) -> Vector2i:
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var q = p + d
		if not in_bounds(q):
			continue
		if tiles[q.y][q.x] == Game.Tile.TREE:
			return q
	return Vector2i(-1, -1)

func chop_tree(p: Vector2i) -> void:
	if not in_bounds(p):
		return
	if tiles[p.y][p.x] != Game.Tile.TREE:
		return
	tiles[p.y][p.x] = Game.Tile.DIRT
	tree_positions.erase(p)
	queue_redraw()

func count_tile(t: int) -> int:
	var n := 0
	for y in range(Game.MAP_H):
		for x in range(Game.MAP_W):
			if tiles[y][x] == t:
				n += 1
	return n

func find_lodge_tile() -> Vector2i:
	for y in range(Game.MAP_H):
		for x in range(Game.MAP_W):
			if tiles[y][x] == Game.Tile.LODGE:
				return Vector2i(x, y)
	return Vector2i(3, 12)

func is_in_dam_zone(p: Vector2i) -> bool:
	return p.x == dam_zone_x and p.y >= dam_zone_y_top and p.y <= dam_zone_y_bot
