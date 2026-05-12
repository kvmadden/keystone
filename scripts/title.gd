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
	# If a PixelLab title background exists, swap it in for the simple gradient.
	if ResourceLoader.exists("res://assets/sprites/title_bg.png"):
		var tex := load("res://assets/sprites/title_bg.png") as Texture2D
		if tex != null:
			var bg := $Background as ColorRect
			var rect := TextureRect.new()
			rect.texture = tex
			rect.anchor_right = 1.0
			rect.anchor_bottom = 1.0
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(rect)
			move_child(rect, bg.get_index() + 1)  # above the base bg
			# Hide the procedural forest+water rects underneath
			$ForestSilhouette.visible = false
			$Water.visible = false
			# Subtle dark vignette on top so the title text stays readable
			var vignette := ColorRect.new()
			vignette.anchor_right = 1.0
			vignette.anchor_bottom = 1.0
			vignette.color = Color(0, 0, 0, 0.40)
			vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(vignette)
			move_child(vignette, rect.get_index() + 1)

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
