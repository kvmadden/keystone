extends Node2D
# The world: owns the tile grid + draws it.
# Stores tile codes in `tiles[y][x]` and exposes accessors for other systems.
# Also draws the dam-zone outline + tracks the wetland-aging counter per tile.

const G := preload("res://scripts/game.gd")

var tiles: Array = []          # tiles[y][x] : int (Game.Tile)
var tile_seeds: Array = []     # tile_seeds[y][x] : int  (0..3 rotation hint, 0..N variant)
var wet_age: Array = []        # seconds adjacent-to-water for wetland conversion
var tree_positions: Array = [] # Vector2i list of tree tiles (for chew lookups)
var stream_y_top := 9
var stream_y_bot := 10
var dam_zone_x := 18           # column where the dam sits
var dam_zone_y_top := 8
var dam_zone_y_bot := 11       # 4-tall zone (stream + 1 above/below)

# Per-tile cached display tint (refresh on water update)
var _display: Array = []

# Cached sprite textures (loaded once in _ready)
var tex_tree: Texture2D
var tex_lodge: Texture2D
var tex_stump: Texture2D
var tree_variants: Array = []        # additional tree textures
var tile_tex: Dictionary = {}        # Game.Tile -> Texture2D
var grass_variants: Array = []       # additional grass textures for variety

func _ready() -> void:
	_generate()
	Game.carrying_changed.connect(func(_c): queue_redraw())
	set_process(true)

func _process(_delta: float) -> void:
	# Re-queue redraw while the pulse animation is active
	if Game.carrying_log:
		queue_redraw()
	if ResourceLoader.exists("res://assets/sprites/tree.png"):
		tex_tree = load("res://assets/sprites/tree.png") as Texture2D
	if ResourceLoader.exists("res://assets/sprites/lodge.png"):
		tex_lodge = load("res://assets/sprites/lodge.png") as Texture2D
	if ResourceLoader.exists("res://assets/sprites/tree_stump.png"):
		tex_stump = load("res://assets/sprites/tree_stump.png") as Texture2D
	# Tile textures — keyed by Game.Tile enum value
	var tile_map := {
		Game.Tile.DRY:     "res://assets/sprites/tile_dry.png",
		Game.Tile.GRASS:   "res://assets/sprites/tile_grass.png",
		Game.Tile.DIRT:    "res://assets/sprites/tile_dirt.png",
		Game.Tile.SHALLOW: "res://assets/sprites/tile_shallow.png",
		Game.Tile.DEEP:    "res://assets/sprites/tile_deep.png",
		Game.Tile.WETLAND: "res://assets/sprites/tile_wetland.png",
	}
	for k in tile_map.keys():
		var p: String = tile_map[k]
		if ResourceLoader.exists(p):
			tile_tex[k] = load(p) as Texture2D
	# Optional grass variants — picked deterministically per-tile via tile_seeds
	for variant in ["res://assets/sprites/tile_grass_2.png", "res://assets/sprites/tile_grass_3.png"]:
		if ResourceLoader.exists(variant):
			grass_variants.append(load(variant) as Texture2D)
	for tv in ["res://assets/sprites/tree_2.png", "res://assets/sprites/tree_3.png"]:
		if ResourceLoader.exists(tv):
			tree_variants.append(load(tv) as Texture2D)
	queue_redraw()

func _generate() -> void:
	# Empty grid → dry/grass mix with a 2-tile stream + dam zone + scattered trees.
	tiles.resize(Game.MAP_H)
	wet_age.resize(Game.MAP_H)
	tile_seeds.resize(Game.MAP_H)
	for y in range(Game.MAP_H):
		var row := []
		var wrow := []
		var srow := []
		row.resize(Game.MAP_W)
		wrow.resize(Game.MAP_W)
		srow.resize(Game.MAP_W)
		for x in range(Game.MAP_W):
			# Base: mostly grass with a light dry/dirt speckle
			var r := randf()
			if r < 0.08:
				row[x] = Game.Tile.DRY
			elif r < 0.14:
				row[x] = Game.Tile.DIRT
			else:
				row[x] = Game.Tile.GRASS
			wrow[x] = 0.0
			# 16 bits of seed per tile: low byte = variant pick, high byte = rotation
			srow[x] = randi() & 0xFFFF
		tiles[y] = row
		wet_age[y] = wrow
		tile_seeds[y] = srow

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
			# Base tile: prefer PixelLab texture, fall back to solid color
			# For TREE / LODGE the underlying tile is grass (sprite drawn on top)
			var base_t: int = t
			if t == Game.Tile.TREE or t == Game.Tile.LODGE:
				base_t = Game.Tile.GRASS
			_draw_tile(rect, base_t, int(tile_seeds[y][x]))

			# Tree: prefer sprite, fall back to placeholder shape
			if t == Game.Tile.TREE:
				var tree_tex: Texture2D = tex_tree
				# Pick variant deterministically from tile_seeds
				if not tree_variants.is_empty():
					var pick: int = (int(tile_seeds[y][x]) >> 12) & 0x03
					if pick == 1 and tree_variants.size() >= 1:
						tree_tex = tree_variants[0]
					elif pick == 2 and tree_variants.size() >= 2:
						tree_tex = tree_variants[1]
				if tree_tex != null:
					# Slight drop shadow underneath for visibility against grass
					draw_rect(Rect2(rect.position + Vector2(6, 26), Vector2(20, 5)), Color(0, 0, 0, 0.18))
					draw_texture_rect(tree_tex, rect, false)
				else:
					var inner := Rect2(rect.position + Vector2(6, 4), Vector2(20, 24))
					draw_rect(inner, Game.COL_TREE)
					draw_rect(Rect2(inner.position + Vector2(-2, -3), Vector2(24, 12)), Game.COL_TREE_CR)
					draw_rect(Rect2(rect.position + Vector2(13, 24), Vector2(6, 6)), Game.COL_STUMP)
			elif t == Game.Tile.LODGE:
				if tex_lodge != null:
					draw_rect(Rect2(rect.position + Vector2(3, 26), Vector2(26, 5)), Color(0, 0, 0, 0.22))
					draw_texture_rect(tex_lodge, rect, false)
				else:
					var lr := Rect2(rect.position + Vector2(2, 2), Vector2(28, 28))
					draw_rect(lr, Game.COL_LODGE)
					var door := Rect2(rect.position + Vector2(13, 18), Vector2(6, 10))
					draw_rect(door, Game.COL_LODGE_DR)

	# Dam-zone outline (gold) — pulses when the beaver is carrying a log
	var dz_rect := Rect2(
		dam_zone_x * Game.TILE_SIZE,
		dam_zone_y_top * Game.TILE_SIZE,
		Game.TILE_SIZE,
		(dam_zone_y_bot - dam_zone_y_top + 1) * Game.TILE_SIZE,
	)
	var base_a: float = 0.55 if Game.carrying_log else 0.30
	var pulse: float = 0.0
	if Game.carrying_log:
		pulse = (sin(Time.get_ticks_msec() / 220.0) * 0.5 + 0.5) * 0.35
	var alpha: float = clamp(base_a + pulse, 0.0, 1.0)
	draw_rect(dz_rect, Color(Game.COL_DAM_ZONE.r, Game.COL_DAM_ZONE.g, Game.COL_DAM_ZONE.b, alpha), false, 2.0)
	# When carrying, draw a faint gold fill so the eye snaps to the target
	if Game.carrying_log:
		draw_rect(dz_rect, Color(Game.COL_DAM_ZONE.r, Game.COL_DAM_ZONE.g, Game.COL_DAM_ZONE.b, 0.10), true)

func _draw_tile(rect: Rect2, base_t: int, seed: int) -> void:
	# Pick the texture (variant for grass) and an optional 90° rotation.
	var tex: Texture2D = null
	if base_t == Game.Tile.GRASS and not grass_variants.is_empty():
		# Bias toward the primary grass to keep coverage cohesive.
		var pick: int = seed & 0xFF
		if pick < 128:
			tex = tile_tex.get(Game.Tile.GRASS) as Texture2D
		elif pick < 192:
			tex = grass_variants[0]
		else:
			tex = grass_variants[1] if grass_variants.size() > 1 else grass_variants[0]
	else:
		tex = tile_tex.get(base_t) as Texture2D

	if tex == null:
		# Fallback solid color
		draw_rect(rect, _tile_color(base_t))
		if base_t != Game.Tile.SHALLOW and base_t != Game.Tile.DEEP:
			draw_rect(rect, Color(0, 0, 0, 0.10), false, 1.0)
		return

	# Apply rotation 0/90/180/270 via canvas transform around the tile center.
	var rot_q: int = (seed >> 8) & 0x03
	if rot_q == 0:
		draw_texture_rect(tex, rect, false)
		return
	var center := rect.position + rect.size * 0.5
	var prev_xform := get_canvas_transform()
	draw_set_transform(center, rot_q * PI / 2.0, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-rect.size * 0.5, rect.size), false)
	draw_set_transform_matrix(Transform2D())  # reset

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
