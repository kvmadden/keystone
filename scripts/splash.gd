extends Node2D
# Splash effect — small radial droplets fading out.
# Used by dam-placement; can be reused for water-rise events.

const G := preload("res://scripts/game.gd")

const DURATION := 0.7
var _t := 0.0
var _droplets: Array = []  # array of {pos:Vector2, vel:Vector2}

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(12):
		var ang: float = rng.randf_range(-PI, PI)
		var speed: float = rng.randf_range(60.0, 130.0)
		_droplets.append({"pos": Vector2.ZERO, "vel": Vector2(cos(ang), sin(ang)) * speed})

func _process(delta: float) -> void:
	_t += delta
	for d in _droplets:
		# Drag + gravity
		d.vel *= (1.0 - delta * 1.6)
		d.vel.y += 240.0 * delta
		d.pos += d.vel * delta
	queue_redraw()
	if _t >= DURATION:
		queue_free()

func _draw() -> void:
	var fade: float = clamp(1.0 - (_t / DURATION), 0.0, 1.0)
	for d in _droplets:
		var c := Color(0.42, 0.65, 0.85, fade)
		draw_circle(d.pos, 2.5 * fade + 0.5, c)
