extends Camera2D
# Static center camera + brief screen-shake helper.

const G := preload("res://scripts/game.gd")

var _shake_t := 0.0
var _shake_mag := 0.0
var _base_pos: Vector2

func _ready() -> void:
	_base_pos = position

func _process(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t = max(0.0, _shake_t - delta)
		var falloff: float = _shake_t / 0.5  # 0.5s peak
		var dx: float = (randf() - 0.5) * 2.0 * _shake_mag * falloff
		var dy: float = (randf() - 0.5) * 2.0 * _shake_mag * falloff
		position = _base_pos + Vector2(dx, dy)
		if _shake_t <= 0.0:
			position = _base_pos

func shake(magnitude: float = 8.0, duration: float = 0.45) -> void:
	_shake_mag = magnitude
	_shake_t = duration
