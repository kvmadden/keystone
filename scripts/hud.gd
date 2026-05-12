extends CanvasLayer
# Polished HUD. Four pill panels — stamina (top-left), ecosystem (top-right),
# action prompt (bottom-center), message log (bottom-left). All panels share
# the same StyleBoxFlat language: 8px corners, dark fill, 1px hairline border,
# subtle drop shadow. Section labels are tiny-caps in muted gold. Numbers are
# Plex Sans at the body size, no decoration. Key-binding chips are rounded
# rectangles around the keycap text.

const G := preload("res://scripts/game.gd")

const SPECIES_ORDER := ["willow", "frog", "fish", "duck", "heron", "otter"]
const SPECIES_GLYPH := {
	"willow": "W", "frog": "F", "fish": "f",
	"duck": "D", "heron": "H", "otter": "O",
}

# ── Style tokens ───────────────────────────────────────────────────────
const COL_PANEL_FILL    := Color(0.06, 0.10, 0.08, 0.82)
const COL_PANEL_BORDER  := Color(0.82, 0.62, 0.28, 0.16)
const COL_EYEBROW       := Color(0.83, 0.63, 0.29, 0.85)
const COL_HAIRLINE      := Color(0.82, 0.62, 0.28, 0.20)
const COL_TEXT_DIM      := Color(0.94, 0.94, 0.91, 0.55)
const COL_KEYCAP_FILL   := Color(0.18, 0.22, 0.18, 1.0)
const COL_KEYCAP_BORDER := Color(0.82, 0.62, 0.28, 0.55)

const PANEL_CORNER_RADIUS := 8
const PANEL_BORDER_W := 1
const PANEL_PAD_X := 14
const PANEL_PAD_Y := 12

# ── Cached node refs ───────────────────────────────────────────────────
@onready var root: Control = $Root
@onready var top_left: PanelContainer = $Root/TopLeft
@onready var top_right: PanelContainer = $Root/TopRight
@onready var bottom_center: PanelContainer = $Root/BottomCenter
@onready var bottom_left: PanelContainer = $Root/BottomLeft
@onready var pause_menu: Control = $PauseMenu
@onready var win_card: Control = $WinCard
@onready var win_stats: Label = $WinCard/Panel/VBox/Stats
@onready var lose_card: Control = $LoseCard
@onready var lose_reason: Label = $LoseCard/Panel/VBox/Reason

# ── Dynamic widgets we hold refs to ────────────────────────────────────
var stamina_value: Label
var stamina_bar: ProgressBar
var carry_chip: Control
var carry_chip_label: Label
var day_number: Label
var phase_value: Label
var species_panel: HBoxContainer
var hold_chip: Control
var hold_chip_label: Label
var prompt_text: Label
var prompt_keycap: Control
var message_label: Label

# ── Per-species widget tracking ────────────────────────────────────────
var _species_lights: Dictionary = {}
var _msg_clock := 0.0
var _peak_species_count := 0
var _day_overlay: Label
var _day_overlay_t := 0.0

func _ready() -> void:
	_style_panel(top_left)
	_style_panel(top_right)
	_style_panel(bottom_center)
	_style_panel(bottom_left)
	_style_card_panel($PauseMenu/Panel)
	_style_card_panel($WinCard/Panel)
	_style_card_panel($LoseCard/Panel)
	_style_button_default()

	_build_top_left()
	_build_top_right()
	_build_bottom_center()
	_build_bottom_left()
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

	_refresh_day_label()
	_on_stamina(Game.stamina)
	_on_species(Game.species)
	_on_carry(Game.carrying_log)

# ── Style helpers ──────────────────────────────────────────────────────
func _make_panel_style(border_alpha_mult: float = 1.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL_FILL
	s.corner_radius_top_left = PANEL_CORNER_RADIUS
	s.corner_radius_top_right = PANEL_CORNER_RADIUS
	s.corner_radius_bottom_left = PANEL_CORNER_RADIUS
	s.corner_radius_bottom_right = PANEL_CORNER_RADIUS
	s.border_width_left = PANEL_BORDER_W
	s.border_width_top = PANEL_BORDER_W
	s.border_width_right = PANEL_BORDER_W
	s.border_width_bottom = PANEL_BORDER_W
	s.border_color = Color(
		COL_PANEL_BORDER.r,
		COL_PANEL_BORDER.g,
		COL_PANEL_BORDER.b,
		COL_PANEL_BORDER.a * border_alpha_mult,
	)
	s.content_margin_left = PANEL_PAD_X
	s.content_margin_right = PANEL_PAD_X
	s.content_margin_top = PANEL_PAD_Y
	s.content_margin_bottom = PANEL_PAD_Y
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 2)
	return s

func _style_panel(p: PanelContainer) -> void:
	p.add_theme_stylebox_override("panel", _make_panel_style())

func _style_card_panel(p: PanelContainer) -> void:
	var s := _make_panel_style(2.0)
	s.bg_color = Color(0.06, 0.10, 0.08, 0.98)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 28
	s.content_margin_bottom = 28
	s.corner_radius_top_left = 12
	s.corner_radius_top_right = 12
	s.corner_radius_bottom_left = 12
	s.corner_radius_bottom_right = 12
	p.add_theme_stylebox_override("panel", s)

func _style_button_default() -> void:
	# Style ALL buttons in the HUD consistently (pause + end cards).
	for btn in _find_all_buttons(self):
		_style_button(btn)

func _style_button(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.14, 0.11, 1.0)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.82, 0.62, 0.28, 0.35)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.14, 0.20, 0.16, 1.0)
	hover.border_color = Color(0.82, 0.62, 0.28, 0.85)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.11, 0.09, 1.0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_color", Color(0.94, 0.94, 0.91, 1.0))
	b.add_theme_color_override("font_hover_color", Game.COL_ACCENT)
	b.add_theme_color_override("font_pressed_color", Game.COL_ACCENT)

func _find_all_buttons(node: Node) -> Array:
	var out: Array = []
	if node is Button:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_all_buttons(c))
	return out

# ── Builders ───────────────────────────────────────────────────────────
func _eyebrow(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", COL_EYEBROW)
	l.add_theme_constant_override("outline_size", 0)
	# Letter-spacing — use theme_override for tracking-ish feel
	# (Godot 4 doesn't expose letter-spacing directly; use a non-breaking-space
	# trick or just rely on the bold caps tone)
	return l

func _hairline() -> Control:
	var line := ColorRect.new()
	line.color = COL_HAIRLINE
	line.custom_minimum_size = Vector2(0, 1)
	return line

func _build_top_left() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	top_left.add_child(v)

	# Eyebrow row: "STAMINA" + numeric value right-aligned
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.add_child(head)
	var brow := _eyebrow("Stamina")
	brow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(brow)
	stamina_value = Label.new()
	stamina_value.text = "100"
	stamina_value.add_theme_font_size_override("font_size", 16)
	stamina_value.add_theme_color_override("font_color", Color(0.94, 0.94, 0.91, 1.0))
	stamina_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(stamina_value)

	# Stamina bar — styled
	stamina_bar = ProgressBar.new()
	stamina_bar.max_value = 100.0
	stamina_bar.value = 100.0
	stamina_bar.show_percentage = false
	stamina_bar.custom_minimum_size = Vector2(240, 6)
	_style_progress_bar(stamina_bar, Color("#5BA84A"))
	v.add_child(stamina_bar)

	# Carry chip — visible when carrying a log
	carry_chip = _make_carry_chip()
	carry_chip.visible = false
	v.add_child(carry_chip)

func _make_carry_chip() -> Control:
	# A small pill: tiny log icon + "Carrying" label
	var c := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.40, 0.26, 0.13, 0.85)
	st.corner_radius_top_left = 10
	st.corner_radius_top_right = 10
	st.corner_radius_bottom_left = 10
	st.corner_radius_bottom_right = 10
	st.content_margin_left = 10
	st.content_margin_right = 12
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	c.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	c.add_child(h)
	# Tiny log icon
	if ResourceLoader.exists("res://assets/sprites/log.png"):
		var tex := load("res://assets/sprites/log.png") as Texture2D
		var ti := TextureRect.new()
		ti.texture = tex
		ti.custom_minimum_size = Vector2(20, 20)
		ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(ti)
	carry_chip_label = Label.new()
	carry_chip_label.text = "Carrying log"
	carry_chip_label.add_theme_font_size_override("font_size", 11)
	carry_chip_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.62, 1.0))
	carry_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(carry_chip_label)
	return c

func _style_progress_bar(bar: ProgressBar, fill_color: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.16, 0.13, 1.0)
	bg.corner_radius_top_left = 3
	bg.corner_radius_top_right = 3
	bg.corner_radius_bottom_left = 3
	bg.corner_radius_bottom_right = 3
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.corner_radius_top_left = 3
	fg.corner_radius_top_right = 3
	fg.corner_radius_bottom_left = 3
	fg.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)

func _build_top_right() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	top_right.add_child(v)

	# Eyebrow + big day number
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var day_brow := _eyebrow("Day")
	day_brow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	day_brow.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	head.add_child(day_brow)
	day_number = Label.new()
	day_number.text = "1"
	day_number.add_theme_font_size_override("font_size", 22)
	day_number.add_theme_color_override("font_color", Color(0.94, 0.94, 0.91, 1.0))
	day_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	day_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(day_number)
	phase_value = Label.new()
	phase_value.text = "dawn"
	phase_value.add_theme_font_size_override("font_size", 11)
	phase_value.add_theme_color_override("font_color", Game.COL_ACCENT)
	phase_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(phase_value)

	v.add_child(_hairline())

	# Ecosystem section eyebrow + species panel
	var eco_brow := _eyebrow("Ecosystem")
	v.add_child(eco_brow)
	species_panel = HBoxContainer.new()
	species_panel.add_theme_constant_override("separation", 8)
	species_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	species_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(species_panel)
	_build_species_panel()

	# Holding indicator (hidden until species_count == 6)
	hold_chip = _make_hold_chip()
	hold_chip.visible = false
	v.add_child(hold_chip)

func _build_species_panel() -> void:
	for k in SPECIES_ORDER:
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 0)
		# Icon
		var icon_path := "res://assets/sprites/icon_%s.png" % k
		var icon_widget: Control
		var icon_tex: Texture2D = null
		if ResourceLoader.exists(icon_path):
			icon_tex = load(icon_path) as Texture2D
		if icon_tex != null:
			var tr := TextureRect.new()
			tr.texture = icon_tex
			tr.custom_minimum_size = Vector2(28, 28)
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_widget = tr
		else:
			var lbl := Label.new()
			lbl.text = SPECIES_GLYPH.get(k, "•")
			lbl.add_theme_color_override("font_color", _species_color(k))
			lbl.add_theme_font_size_override("font_size", 18)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			icon_widget = lbl
		var pop := Label.new()
		pop.text = "0"
		pop.add_theme_font_size_override("font_size", 10)
		pop.add_theme_color_override("font_color", COL_TEXT_DIM)
		pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(icon_widget)
		v.add_child(pop)
		species_panel.add_child(v)
		_species_lights[k] = {"glyph": icon_widget, "pop": pop}

func _make_hold_chip() -> Control:
	var c := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.82, 0.62, 0.28, 0.18)
	st.border_width_left = 1
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 1
	st.border_color = Color(0.82, 0.62, 0.28, 0.70)
	st.corner_radius_top_left = 4
	st.corner_radius_top_right = 4
	st.corner_radius_bottom_left = 4
	st.corner_radius_bottom_right = 4
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	c.add_theme_stylebox_override("panel", st)
	hold_chip_label = Label.new()
	hold_chip_label.text = "HOLDING  0/3 days"
	hold_chip_label.add_theme_font_size_override("font_size", 10)
	hold_chip_label.add_theme_color_override("font_color", Game.COL_ACCENT)
	hold_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(hold_chip_label)
	return c

func _build_bottom_center() -> void:
	# A single-line container: prompt text + keycap chip.
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_center.add_child(h)
	prompt_text = Label.new()
	prompt_text.text = ""
	prompt_text.add_theme_font_size_override("font_size", 15)
	prompt_text.add_theme_color_override("font_color", Color(0.94, 0.94, 0.91, 1.0))
	prompt_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(prompt_text)
	prompt_keycap = _make_keycap("Space")
	prompt_keycap.visible = false
	h.add_child(prompt_keycap)
	# Initially hide entire prompt panel until there's content
	bottom_center.modulate.a = 0.0

func _make_keycap(label: String) -> Control:
	var c := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = COL_KEYCAP_FILL
	st.corner_radius_top_left = 4
	st.corner_radius_top_right = 4
	st.corner_radius_bottom_left = 4
	st.corner_radius_bottom_right = 4
	st.border_width_left = 1
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 1
	st.border_color = COL_KEYCAP_BORDER
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 2
	st.content_margin_bottom = 3
	c.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.name = "Label"
	l.text = label
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.98, 0.88, 0.62, 1.0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(l)
	return c

func _set_keycap_text(t: String) -> void:
	if prompt_keycap == null:
		return
	var l := prompt_keycap.get_node_or_null("Label") as Label
	if l != null:
		l.text = t

func _build_bottom_left() -> void:
	message_label = Label.new()
	message_label.text = ""
	message_label.add_theme_font_size_override("font_size", 12)
	message_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.62, 1.0))
	message_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	message_label.clip_text = true
	bottom_left.add_child(message_label)
	bottom_left.modulate.a = 0.0  # hide until first message

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

# ── Tick ───────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	# Pause toggle
	if Input.is_action_just_pressed("pause") and not Game.game_over:
		pause_menu.visible = not pause_menu.visible
		get_tree().paused = pause_menu.visible
	# Message fade out
	if _msg_clock > 0.0:
		_msg_clock -= delta
		bottom_left.modulate.a = lerp(bottom_left.modulate.a, 1.0, delta * 6.0)
		if _msg_clock <= 0.0:
			# Fade out smoothly
			bottom_left.modulate.a = max(0.0, bottom_left.modulate.a - delta * 2.0)
			if bottom_left.modulate.a <= 0.01:
				message_label.text = ""
	else:
		bottom_left.modulate.a = max(0.0, bottom_left.modulate.a - delta * 2.0)

	# Day overlay
	if _day_overlay != null and _day_overlay_t > 0.0:
		_day_overlay_t = max(0.0, _day_overlay_t - delta / 3.0)
		var t: float = _day_overlay_t
		var alpha: float = 1.0 if t > 0.5 else t * 2.0
		_day_overlay.modulate = Color(1, 1, 1, alpha)

	# Action prompt: rebuild + fade in/out
	var raw_prompt := _build_prompt_pair()
	var want_alpha: float = 1.0 if raw_prompt[0] != "" else 0.0
	if raw_prompt[0] != prompt_text.text:
		prompt_text.text = raw_prompt[0]
		if raw_prompt[1] != "":
			_set_keycap_text(raw_prompt[1])
			prompt_keycap.visible = true
		else:
			prompt_keycap.visible = false
	bottom_center.modulate.a = move_toward(bottom_center.modulate.a, want_alpha, delta * 4.0)

	# Hold-chip pulse when active
	if hold_chip.visible and Game.consecutive_full_days > 0:
		var p: float = (sin(Time.get_ticks_msec() / 380.0) * 0.5 + 0.5)
		hold_chip.modulate = Color(1.0, 1.0, 1.0, 0.85 + p * 0.15)

# ── Signal handlers ────────────────────────────────────────────────────
func _on_stamina(v: float) -> void:
	stamina_bar.value = v
	stamina_value.text = str(int(round(v)))
	var fill_color: Color
	if v > 60.0:
		fill_color = Color("#5BA84A")
	elif v > 25.0:
		fill_color = Game.COL_ACCENT
	else:
		fill_color = Game.COL_DANGER
	# Re-apply the fill stylebox color
	var fg := stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fg != null:
		fg.bg_color = fill_color
	# Tint the number too at low stamina
	stamina_value.add_theme_color_override("font_color", Color(0.94, 0.94, 0.91, 1.0) if v > 25.0 else fill_color)

func _on_species(counts: Dictionary) -> void:
	var total := 0
	for k in SPECIES_ORDER:
		var n := int(counts.get(k, 0))
		var light = _species_lights[k]
		light.pop.text = str(n)
		var c := _species_color(k)
		if n > 0:
			light.glyph.modulate = Color(1.0, 1.0, 1.0, 1.0)
			if light.glyph is Label:
				(light.glyph as Label).add_theme_color_override("font_color", c)
			light.pop.add_theme_color_override("font_color", Game.COL_ACCENT)
		else:
			light.glyph.modulate = Color(0.55, 0.55, 0.55, 0.50)
			if light.glyph is Label:
				(light.glyph as Label).add_theme_color_override("font_color", Color(c.r, c.g, c.b, 0.45))
			light.pop.add_theme_color_override("font_color", COL_TEXT_DIM)
		total += (1 if n > 0 else 0)
	if total > _peak_species_count:
		_peak_species_count = total
	# Hold-chip visibility + label
	if total == 6:
		hold_chip.visible = true
		hold_chip_label.text = "HOLDING  %d/3 days" % Game.consecutive_full_days
	else:
		hold_chip.visible = false

func _on_day(d: int) -> void:
	_refresh_day_label()
	_show_day_overlay(d)
	# Refresh hold chip text on day rollover
	if hold_chip.visible:
		hold_chip_label.text = "HOLDING  %d/3 days" % Game.consecutive_full_days

func _show_day_overlay(d: int) -> void:
	if _day_overlay == null:
		return
	_day_overlay.text = "Day  %d" % d
	_day_overlay_t = 1.0

func _on_phase(_p: int, _t: float) -> void:
	_refresh_day_label()

func _refresh_day_label() -> void:
	if day_number == null:
		return
	day_number.text = str(Game.current_day)
	phase_value.text = Game.phase_name(Game.phase)
	# Phase tint
	match Game.phase:
		Game.Phase.DAWN: phase_value.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45, 1.0))
		Game.Phase.DAY: phase_value.add_theme_color_override("font_color", Color(0.94, 0.94, 0.78, 0.85))
		Game.Phase.DUSK: phase_value.add_theme_color_override("font_color", Color(0.95, 0.55, 0.32, 1.0))
		Game.Phase.NIGHT: phase_value.add_theme_color_override("font_color", Color(0.62, 0.74, 0.95, 1.0))

func _on_message(t: String) -> void:
	message_label.text = t
	_msg_clock = 8.0 if t.find("(") >= 0 else 4.0

func _on_carry(c: bool) -> void:
	carry_chip.visible = c

func _build_prompt_pair() -> Array:
	# Returns [prompt_text, keycap_text]. Keycap "" means no key chip shown.
	if Game.game_over:
		return ["", ""]
	var beaver = get_tree().get_first_node_in_group("beaver")
	if not beaver:
		return ["", ""]
	var world = get_node("/root/Main/World")
	var dam = get_node("/root/Main/Dam")
	var here := Vector2i(int(beaver.position.x / Game.TILE_SIZE), int(beaver.position.y / Game.TILE_SIZE))
	if world.get_tile(here) == Game.Tile.LODGE:
		return ["Sleep until dawn", "E"]
	if Game.carrying_log and world.is_in_dam_zone(here):
		return ["Place dam segment", "Space"]
	if dam.needs_repair_nearby(here):
		return ["Repair dam", "Space"]
	if not Game.carrying_log:
		var logs = get_node("/root/Main/Logs")
		for child in logs.get_children():
			if child is Node2D:
				var lp := Vector2i(int(child.position.x / Game.TILE_SIZE), int(child.position.y / Game.TILE_SIZE))
				if lp == here:
					return ["Pick up log", "Space"]
		var tp = world.find_tree_near(here)
		if tp.x >= 0:
			return ["Chew tree", "Space"]
	if dam.is_near_dam(here):
		if Game.dam_segments.is_empty():
			return ["Walk a log to the gold zone to build the dam", ""]
		if Game.carrying_log:
			return ["Step onto the gold zone to place", ""]
		return ["Dam is solid", ""]
	return ["", ""]

# ── Win / lose ─────────────────────────────────────────────────────────
func _on_win() -> void:
	win_card.visible = true
	get_tree().paused = true
	win_stats.text = (
		"Six trophic levels held for three consecutive days.\n"
		+ "Wetland integrity stable — the pond will outlive you.\n\n"
		+ "DAYS  %d   ·   DAM  %d segments   ·   PEAK SPECIES  %d"
	) % [Game.current_day, Game.dam_segments.size(), _peak_species_count]

func _on_lose(reason: String) -> void:
	lose_card.visible = true
	get_tree().paused = true
	lose_reason.text = (
		"%s\n\n"
		+ "Without the engineer, the wetland reverts.\n"
		+ "DAYS HELD  %d   ·   PEAK SPECIES  %d"
	) % [reason, Game.current_day, _peak_species_count]

# ── Species helpers ────────────────────────────────────────────────────
func _species_color(k: String) -> Color:
	match k:
		"willow": return Game.COL_WILLOW
		"frog": return Game.COL_FROG
		"fish": return Game.COL_FISH
		"duck": return Game.COL_DUCK
		"heron": return Game.COL_HERON
		"otter": return Game.COL_OTTER
	return Game.COL_TEXT

# ── Button callbacks (wired in scene) ──────────────────────────────────
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
