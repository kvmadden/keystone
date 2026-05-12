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
	"willow": "🜨",
	"frog":   "▼",
	"fish":   "◆",
	"duck":   "◗",
	"heron":  "↑",
	"otter":  "≈",
}

var _msg_clock := 0.0
var _species_lights: Dictionary = {}
var _peak_species_count := 0

func _ready() -> void:
	_build_species_panel()
	Game.stamina_changed.connect(_on_stamina)
	Game.species_changed.connect(_on_species)
	Game.day_advanced.connect(_on_day)
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
	# Update action prompt every frame
	prompt_label.text = _build_prompt()

func _build_species_panel() -> void:
	for k in SPECIES_ORDER:
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var lbl := Label.new()
		lbl.text = SPECIES_GLYPH.get(k, "•")
		lbl.add_theme_color_override("font_color", _species_color(k))
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var pop := Label.new()
		pop.text = "0"
		pop.add_theme_color_override("font_color", Game.COL_TEXT)
		pop.add_theme_font_size_override("font_size", 11)
		pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(lbl)
		v.add_child(pop)
		species_panel.add_child(v)
		_species_lights[k] = {"glyph": lbl, "pop": pop}

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
		var c := _species_color(k)
		if n > 0:
			light.glyph.modulate = Color(1, 1, 1, 1)
			light.glyph.add_theme_color_override("font_color", c)
		else:
			# Dim
			light.glyph.add_theme_color_override("font_color", Color(c.r, c.g, c.b, 0.30))
		total += (1 if n > 0 else 0)
	if total > _peak_species_count:
		_peak_species_count = total

func _on_day(d: int) -> void:
	day_label.text = "Day  %d" % d

func _on_message(t: String) -> void:
	message_label.text = t
	_msg_clock = 4.0

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
		return "Repair dam  [hold Space]"
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
			return "Chew tree  [hold Space]"
	return ""

func _on_win() -> void:
	win_card.visible = true
	get_tree().paused = true
	win_stats.text = "Days survived  %d\nDam segments  %d\nPeak species  %d" % [Game.current_day, Game.dam_segments.size(), _peak_species_count]

func _on_lose(reason: String) -> void:
	lose_card.visible = true
	get_tree().paused = true
	lose_reason.text = reason

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
