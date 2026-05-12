extends Node2D
# A dropped log on the ground. Picked up by the beaver.
const G := preload("res://scripts/game.gd")

var _tex: Texture2D

func _ready() -> void:
	if ResourceLoader.exists("res://assets/sprites/log.png"):
		_tex = load("res://assets/sprites/log.png") as Texture2D
	queue_redraw()

func _draw() -> void:
	if _tex != null:
		var sz := _tex.get_size()
		draw_texture_rect(_tex, Rect2(-sz / 2.0, sz), false)
		return
	# Placeholder: a small horizontal log
	draw_rect(Rect2(-10, -3, 20, 6), Game.COL_LOG)
	draw_line(Vector2(-9, -2), Vector2(9, -2), Color(0, 0, 0, 0.4), 1.0)
	draw_line(Vector2(-9, 1), Vector2(9, 1), Color(0, 0, 0, 0.4), 1.0)
	draw_circle(Vector2(-9, 0), 2.5, Game.COL_STUMP)
	draw_circle(Vector2(9, 0), 2.5, Game.COL_STUMP)
