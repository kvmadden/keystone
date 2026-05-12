extends Control
# Circular phase indicator. Outer ring = the 24-hour wheel divided by
# the 4 phases (dawn/day/dusk/night) in their respective tints. A small
# disc (sun for day, moon for night) travels around the ring.

const G := preload("res://scripts/game.gd")

const PHASE_DURATIONS := [10.0, 40.0, 10.0, 30.0]  # mirrors day_cycle.gd
const TOTAL := 90.0

const COL_DAWN_TINT  := Color(0.95, 0.78, 0.45, 1.0)
const COL_DAY_TINT   := Color(0.95, 0.92, 0.72, 1.0)
const COL_DUSK_TINT  := Color(0.95, 0.55, 0.32, 1.0)
const COL_NIGHT_TINT := Color(0.34, 0.42, 0.62, 1.0)

func _ready() -> void:
	custom_minimum_size = Vector2(36, 36)
	set_process(true)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = min(size.x, size.y) * 0.42

	# Outer dial ring — segmented per phase, full alpha for current phase, dimmed otherwise
	var start := -PI / 2.0  # 12 o'clock
	var cur_phase: int = Game.phase
	for i in range(4):
		var frac: float = PHASE_DURATIONS[i] / TOTAL
		var end := start + frac * TAU
		var col: Color
		match i:
			Game.Phase.DAWN: col = COL_DAWN_TINT
			Game.Phase.DAY: col = COL_DAY_TINT
			Game.Phase.DUSK: col = COL_DUSK_TINT
			Game.Phase.NIGHT: col = COL_NIGHT_TINT
		if i == cur_phase:
			col.a = 1.0
		else:
			col.a = 0.30
		_draw_arc_thick(center, radius, start, end, col, 3.0)
		start = end

	# Compute the cumulative "elapsed within day" 0..1 → angle
	var elapsed: float = 0.0
	for i in range(cur_phase):
		elapsed += PHASE_DURATIONS[i]
	elapsed += PHASE_DURATIONS[cur_phase] * clamp(Game.phase_t, 0.0, 1.0)
	var t01: float = elapsed / TOTAL
	var ang: float = -PI / 2.0 + t01 * TAU
	var marker_pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * radius

	# Sun (day/dawn/dusk) or moon (night) disc at the marker
	var is_night: bool = cur_phase == Game.Phase.NIGHT
	if is_night:
		# Moon: pale disc with a darker bite
		draw_circle(marker_pos, 5.0, Color(0.85, 0.88, 0.95, 1.0))
		draw_circle(marker_pos + Vector2(2.0, -1.0), 4.0, Color(0.20, 0.26, 0.40, 1.0))
	else:
		# Sun: gold disc with halo
		draw_circle(marker_pos, 6.0, Color(0.98, 0.78, 0.32, 0.30))
		draw_circle(marker_pos, 3.5, Color(0.98, 0.82, 0.35, 1.0))

	# Center dot, tiny
	draw_circle(center, 1.5, Color(0.82, 0.62, 0.28, 0.35))

func _draw_arc_thick(c: Vector2, r: float, a0: float, a1: float, color: Color, w: float) -> void:
	# Approximation: stitch line segments around the arc
	var steps: int = max(8, int((a1 - a0) / TAU * 64.0))
	var prev: Vector2 = c + Vector2(cos(a0), sin(a0)) * r
	for i in range(1, steps + 1):
		var a: float = a0 + (a1 - a0) * (float(i) / steps)
		var next: Vector2 = c + Vector2(cos(a), sin(a)) * r
		draw_line(prev, next, color, w, true)
		prev = next
