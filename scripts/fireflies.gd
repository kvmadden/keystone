extends Node2D
# Subtle firefly drift over the wetland at night.
# Cheap: a small fixed-size pool of points, each picks a random wetland tile
# at spawn and meanders within a small radius. Pulses opacity, fades at dawn.

const G := preload("res://scripts/game.gd")

const COUNT := 28
const PULSE_HZ := 1.2

@onready var world: Node2D = get_node("/root/Main/World")

var flies: Array = []  # each: {pos: Vector2, anchor: Vector2, phase: float, drift: Vector2, t: float}
var alpha := 0.0

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(COUNT):
		flies.append({
			"pos": Vector2.ZERO,
			"anchor": Vector2.ZERO,
			"phase": rng.randf() * TAU,
			"drift": Vector2.ZERO,
			"t": rng.randf() * 10.0,
		})
	set_process(true)

func _process(delta: float) -> void:
	# Visible only at night, ramps in over a couple seconds at night start.
	var want_alpha: float = 1.0 if Game.phase == Game.Phase.NIGHT else 0.0
	# Smooth toward want_alpha
	alpha = move_toward(alpha, want_alpha, delta * 0.6)
	if alpha < 0.01:
		queue_redraw()
		return

	# Pick a wetland tile-center anchor for each fly if it doesn't have one yet
	# (or re-anchor occasionally to keep coverage fresh).
	for f in flies:
		f.t -= delta
		if f.anchor == Vector2.ZERO or f.t <= 0.0:
			var tile := _random_wetland_tile()
			if tile.x < 0:
				continue
			f.anchor = Vector2(tile.x * Game.TILE_SIZE + Game.TILE_SIZE / 2.0,
				tile.y * Game.TILE_SIZE + Game.TILE_SIZE / 2.0)
			f.pos = f.anchor
			f.t = randf_range(5.0, 12.0)
		# Lissajous-style drift around the anchor, slow.
		var s: float = Time.get_ticks_msec() / 700.0 + float(f.phase)
		f.pos = f.anchor + Vector2(cos(s * 0.9) * 14.0, sin(s * 1.3) * 10.0)
	queue_redraw()

func _random_wetland_tile() -> Vector2i:
	# Cheap: random sample 8 tries; fall back to global scan.
	for _i in range(8):
		var x := randi() % Game.MAP_W
		var y := randi() % Game.MAP_H
		if world.tiles[y][x] == Game.Tile.WETLAND:
			return Vector2i(x, y)
	# Global scan fallback
	for y in range(Game.MAP_H):
		for x in range(Game.MAP_W):
			if world.tiles[y][x] == Game.Tile.WETLAND:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _draw() -> void:
	if alpha <= 0.01:
		return
	var t := Time.get_ticks_msec() / 1000.0
	for f in flies:
		if f.anchor == Vector2.ZERO:
			continue
		var pulse: float = (sin(t * TAU * PULSE_HZ + f.phase) * 0.5 + 0.5)
		var a := alpha * (0.35 + pulse * 0.65)
		# Halo
		draw_circle(f.pos, 3.0, Color(0.95, 0.85, 0.45, a * 0.35))
		# Core
		draw_circle(f.pos, 1.2, Color(1.0, 0.95, 0.7, a))
