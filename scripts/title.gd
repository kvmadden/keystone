extends Control
# Title screen — dark forest gradient, big "KEYSTONE" headline, START button.

const G := preload("res://scripts/game.gd")

@onready var title_label: Label = $Center/Title
@onready var subtitle: Label = $Center/Subtitle
@onready var start_btn: Button = $Center/StartButton
@onready var hint: Label = $Center/Hint
@onready var attribution: Label = $Bottom/Attribution

func _ready() -> void:
	Game.reset()
	start_btn.pressed.connect(_on_start)
	title_label.add_theme_color_override("font_color", Game.COL_TEXT)
	subtitle.add_theme_color_override("font_color", Game.COL_ACCENT)
	hint.add_theme_color_override("font_color", Color(Game.COL_TEXT.r, Game.COL_TEXT.g, Game.COL_TEXT.b, 0.55))
	attribution.add_theme_color_override("font_color", Color(Game.COL_TEXT.r, Game.COL_TEXT.g, Game.COL_TEXT.b, 0.45))

func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_on_start()

func _process(_delta: float) -> void:
	# Subtle pulse on the START button so it feels alive
	var t := Time.get_ticks_msec() / 1000.0
	start_btn.modulate = Color(1, 1, 1, 0.85 + 0.15 * sin(t * 2.0))
