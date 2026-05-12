extends CanvasLayer
# Main in-game HUD. Top-left stamina + carrying chip. Top-right day + species panel.
# Bottom-center action prompt. Esc → pause menu.

const G := preload("res://scripts/game.gd")

@onready var stamina_bar: ProgressBar = $TopLeft/StaminaBar
@onready var stamina_label: Label = $TopLeft/StaminaLabel
@onready var carry_chip: Label = $TopLeft/CarryChip
@onready var day_label: Label = $TopRight/DayLabel
@onready var species_panel: HBoxContainer = $TopRight/Species
@onready var prompt_label: Label = $BottomCenter/PromptLabel
@onready var message_label: Label = $BottomLeft/MessageLabel
@onready var pause_menu: Control = $PauseMenu
@onready var win_card: Control = $WinCard
@onready var win_stats: Label = $WinCard/Panel/VBox/Stats
@onready var lose_card: Control = $LoseCard
@onready var lose_reason: Label = $LoseCard/Panel/VBox/Reason

const SPECIES_ORDER := ["willow", "frog", "fish", "duck", "heron", "otter"]
const SPECIES_GLYPH := {
	"willow": "W",
	"frog":   "F",
	"fish":   "f",
	"duck":   "D",
	"heron":  "H",
	"otter":  "O",
}

var _msg_clock := 0.0
var _species_lights: Dictionary = {}
var _peak_species_count := 0
var _day_overlay: Label
var _day_overlay_t := 0.0

func _ready() -> void:
	_build_species_panel()
	_add_hud_backdrops()
	_build_day_overlay()
	Game.stamina_changed.connect(_on_stamina)
	Game.species_changed.connect(_on_species)
	Game.day_advanced.connect(_on_day)
	Game.phase_changed.connect(_on_phase)
	Game.log_message.connect(_on_message)
	Game.carrying_changed.connect(_on_carry)
	Game.game_won.connect(_on_win)
	Game.game_lost.connect(_on_lose)
	pause_menu.visible = false
	win_card.visible = false
	lose_card.visible = false
	_on_day(Game.current_day)
	_on_stamina(Game.stamina)
	_on_species(Game.species)

func _process(delta: float) -> void:
	# Pause
	if Input.is_action_just_pressed("pause") and not Game.game_over:
		pause_menu.visible = not pause_menu.visible
		get_tree().paused = pause_menu.visible
	# Hide messages after a few seconds
	if _msg_clock > 0.0:
		_msg_clock -= delta
		if _msg_clock <= 0.0:
			message_label.text = ""
	# Day overlay: hold ~1.5s, then fade ~1.5s (t counts 1.0 → 0.0 over 3.0s)
	if _day_overlay != null and _day_overlay_t > 0.0:
		_day_overlay_t = max(0.0, _day_overlay_t - delta / 3.0)
		var t: float = _day_overlay_t
		var alpha: float = 1.0 if t > 0.5 else t * 2.0
		_day_overlay.modulate = Color(1, 1, 1, alpha)
	# Update action prompt every frame
	prompt_label.text = _build_prompt()

func _build_day_overlay() -> void:
	_day_overlay = Label.new()
	_day_overlay.anchor_left = 0.5
	_day_overlay.anchor_top = 0.5
	_day_overlay.anchor_right = 0.5
	_day_overlay.anchor_bottom = 0.5
	_day_overlay.offset_left = -300.0
	_day_overlay.offset_top = -60.0
	_day_overlay.offset_right = 300.0
	_day_overlay.offset_bottom = 60.0
	_day_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_day_overlay.add_theme_font_size_override("font_size", 64)
	_day_overlay.add_theme_color_override("font_color", Game.COL_ACCENT)
	_day_overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_day_overlay.add_theme_constant_override("outline_size", 6)
	_day_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_day_overlay.modulate = Color(1, 1, 1, 0)
	_day_overlay.text = ""
	add_child(_day_overlay)

func _add_hud_backdrops() -> void:
	# Insert a translucent dark panel BEHIND the top-left + top-right HUD groups
	# so text reads against bright wetland or dark water alike.
	var tl_bg := ColorRect.new()
	tl_bg.color = Color(0.06, 0.10, 0.08, 0.55)
	tl_bg.anchor_left = 0.0
	tl_bg.anchor_right = 0.0
	tl_bg.offset_left = 8.0
	tl_bg.offset_top = 8.0
	tl_bg.offset_right = 8.0 + 280.0
	tl_bg.offset_bottom = 8.0 + 76.0
	tl_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tl_bg)
	move_child(tl_bg, 0)  # behind everything

	var tr_bg := ColorRect.new()
	tr_bg.color = Color(0.06, 0.10, 0.08, 0.55)
	tr_bg.anchor_left = 1.0
	tr_bg.anchor_right = 1.0
	tr_bg.offset_left = -348.0
	tr_bg.offset_top = 8.0
	tr_bg.offset_right = -8.0
	tr_bg.offset_bottom = 8.0 + 140.0
	tr_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr_bg)
	move_child(tr_bg, 1)

	var bc_bg := ColorRect.new()
	bc_bg.color = Color(0.06, 0.10, 0.08, 0.55)
	bc_bg.anchor_left = 0.5
	bc_bg.anchor_right = 0.5
	bc_bg.anchor_top = 1.0
	bc_bg.anchor_bottom = 1.0
	bc_bg.offset_left = -220.0
	bc_bg.offset_top = -70.0
	bc_bg.offset_right = 220.0
	bc_bg.offset_bottom = -28.0
	bc_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bc_bg)
	move_child(bc_bg, 2)

func _build_species_panel() -> void:
	for k in SPECIES_ORDER:
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		# Prefer a PixelLab icon if present; otherwise fall back to a letter glyph.
		var icon_path := "res://assets/sprites/icon_%s.png" % k
		var icon_widget: Control
		var icon_tex: Texture2D = null
		if ResourceLoader.exists(icon_path):
			icon_tex = load(icon_path) as Texture2D
		if icon_tex != null:
			var tr := TextureRect.new()
			tr.texture = icon_tex
			tr.custom_minimum_size = Vector2(32, 32)
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_widget = tr
		else:
			var lbl := Label.new()
			lbl.text = SPECIES_GLYPH.get(k, "•")
			lbl.add_theme_color_override("font_color", _species_color(k))
			lbl.add_theme_font_size_override("font_size", 22)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			icon_widget = lbl
		var pop := Label.new()
		pop.text = "0"
		pop.add_theme_color_override("font_color", Game.COL_TEXT)
		pop.add_theme_font_size_override("font_size", 11)
		pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(icon_widget)
		v.add_child(pop)
		species_panel.add_child(v)
		_species_lights[k] = {"glyph": icon_widget, "pop": pop}

func _species_color(k: String) -> Color:
	match k:
		"willow": return Game.COL_WILLOW
		"frog": return Game.COL_FROG
		"fish": return Game.COL_FISH
		"duck": return Game.COL_DUCK
		"heron": return Game.COL_HERON
		"otter": return Game.COL_OTTER
	return Game.COL_TEXT

func _on_stamina(v: float) -> void:
	stamina_bar.value = v
	stamina_label.text = "Stamina  %d" % int(v)
	if v > 60.0:
		stamina_bar.modulate = Color("#5BA84A")
	elif v > 25.0:
		stamina_bar.modulate = Game.COL_ACCENT
	else:
		stamina_bar.modulate = Game.COL_DANGER

func _on_species(counts: Dictionary) -> void:
	var total := 0
	for k in SPECIES_ORDER:
		var n := int(counts.get(k, 0))
		var light = _species_lights[k]
		light.pop.text = str(n)
		# Highlight the count gold when present so the player sees the lit lineup
		if n > 0:
			light.pop.add_theme_color_override("font_color", Game.COL_ACCENT)
		else:
			light.pop.add_theme_color_override("font_color", Color(Game.COL_TEXT.r, Game.COL_TEXT.g, Game.COL_TEXT.b, 0.50))
		var c := _species_color(k)
		if n > 0:
			light.glyph.modulate = Color(1, 1, 1, 1.0)
			if light.glyph is Label:
				(light.glyph as Label).add_theme_color_override("font_color", c)
		else:
			# Dim — keep enough alpha to clearly see the lineup at game start
			light.glyph.modulate = Color(0.6, 0.6, 0.6, 0.75)
			if light.glyph is Label:
				(light.glyph as Label).add_theme_color_override("font_color", Color(c.r, c.g, c.b, 0.6))
		total += (1 if n > 0 else 0)
	if total > _peak_species_count:
		_peak_species_count = total

func _on_day(d: int) -> void:
	_refresh_day_label()
	_show_day_overlay(d)

func _show_day_overlay(d: int) -> void:
	if _day_overlay == null:
		return
	_day_overlay.text = "Day  %d" % d
	_day_overlay_t = 1.0

func _on_phase(_p: int, _t: float) -> void:
	_refresh_day_label()

func _refresh_day_label() -> void:
	day_label.text = "Day  %d  ·  %s" % [Game.current_day, Game.phase_name(Game.phase)]

func _on_message(t: String) -> void:
	message_label.text = t
	# Ecology messages with Latin names need longer dwell.
	_msg_clock = 8.0 if t.find("(") >= 0 else 4.0

func _on_carry(c: bool) -> void:
	carry_chip.visible = c

func _build_prompt() -> String:
	if Game.game_over:
		return ""
	var beaver = get_tree().get_first_node_in_group("beaver")
	if not beaver:
		return ""
	var world = get_node("/root/Main/World")
	var dam = get_node("/root/Main/Dam")
	var here := Vector2i(int(beaver.position.x / Game.TILE_SIZE), int(beaver.position.y / Game.TILE_SIZE))
	if world.get_tile(here) == Game.Tile.LODGE:
		return "Sleep until dawn  [E]"
	if Game.carrying_log and world.is_in_dam_zone(here):
		return "Place segment  [Space]"
	if dam.needs_repair_nearby(here):
		return "Repair dam  [Space]"
	if not Game.carrying_log:
		# log under feet?
		var logs = get_node("/root/Main/Logs")
		for child in logs.get_children():
			if child is Node2D:
				var lp := Vector2i(int(child.position.x / Game.TILE_SIZE), int(child.position.y / Game.TILE_SIZE))
				if lp == here:
					return "Pick up log  [Space]"
		# tree nearby?
		var tp = world.find_tree_near(here)
		if tp.x >= 0:
			return "Chew tree  [Space]"
	# If near the dam without a damaged segment, surface a hint
	if dam.is_near_dam(here):
		if Game.dam_segments.is_empty():
			return "Build a dam — bring logs to the gold zone"
		if Game.carrying_log:
			return "Walk onto the gold zone to place"
		return "Dam is solid"
	return ""

func _on_win() -> void:
	win_card.visible = true
	get_tree().paused = true
	win_stats.text = (
		"Six trophic levels held for three consecutive days.\n"
		+ "Wetland integrity stable — the pond will outlive you.\n\n"
		+ "Days  %d   ·   Dam  %d segments   ·   Peak species  %d"
	) % [Game.current_day, Game.dam_segments.size(), _peak_species_count]

func _on_lose(reason: String) -> void:
	lose_card.visible = true
	get_tree().paused = true
	lose_reason.text = (
		"%s\n\n"
		+ "Without the engineer, the wetland reverts.\n"
		+ "Days held  %d   ·   Peak species  %d"
	) % [reason, Game.current_day, _peak_species_count]

# Button callbacks (wired in scene)
func _on_resume_pressed() -> void:
	pause_menu.visible = false
	get_tree().paused = false

func _on_restart_pressed() -> void:
	get_tree().paused = false
	Game.reset()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_title_pressed() -> void:
	get_tree().paused = false
	Game.reset()
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
