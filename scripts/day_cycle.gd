extends CanvasModulate
# Day/night cycle. Lives as a CanvasModulate so the tint applies to the world
# automatically. Emits Game.day_advanced when a day ticks over (used by dam
# decay, species, drought).
#
# Day = 90s. Phases: dawn 10 → day 40 → dusk 10 → night 30.

const G := preload("res://scripts/game.gd")

const PHASE_DURATIONS := [10.0, 40.0, 10.0, 30.0]  # dawn, day, dusk, night

const COL_DAWN  := Color(1.10, 1.00, 0.78)   # warm yellow
const COL_DAY   := Color(1.00, 1.00, 1.00)   # bright neutral
const COL_DUSK  := Color(1.10, 0.80, 0.55)   # orange
const COL_NIGHT := Color(0.40, 0.45, 0.65)   # dark blue

var _phase_elapsed := 0.0

func _ready() -> void:
	color = COL_DAWN
	Game.phase = Game.Phase.DAWN
	Game.phase_t = 0.0

func _process(delta: float) -> void:
	if Game.game_over:
		return
	_phase_elapsed += delta
	var dur: float = PHASE_DURATIONS[Game.phase]
	Game.phase_t = clamp(_phase_elapsed / dur, 0.0, 1.0)
	color = _phase_color()
	Game.phase_changed.emit(Game.phase, Game.phase_t)
	if _phase_elapsed >= dur:
		_advance_phase()

func _advance_phase() -> void:
	_phase_elapsed = 0.0
	Game.phase = (Game.phase + 1) % 4
	if Game.phase == Game.Phase.DAWN:
		Game.current_day += 1
		Game.day_advanced.emit(Game.current_day)
		Game.emit_message("Day %d. Dawn over the pond." % Game.current_day)
	elif Game.phase == Game.Phase.DUSK:
		Game.emit_message("Dusk. The fireflies will rise over the wetland.")
	elif Game.phase == Game.Phase.NIGHT:
		Game.emit_message("Night. A coyote howls. Sleep in the lodge if you can.")

func _phase_color() -> Color:
	# Smoothly interpolate to the next phase's color over the last 30% of the phase.
	var c_now := _color_for(Game.phase)
	var c_next := _color_for((Game.phase + 1) % 4)
	var t := smoothstep(0.7, 1.0, Game.phase_t)
	return c_now.lerp(c_next, t)

func _color_for(p: int) -> Color:
	match p:
		Game.Phase.DAWN: return COL_DAWN
		Game.Phase.DAY: return COL_DAY
		Game.Phase.DUSK: return COL_DUSK
		Game.Phase.NIGHT: return COL_NIGHT
	return COL_DAY

func skip_to_dawn() -> void:
	# Used by beaver sleeping in the lodge.
	Game.phase = Game.Phase.DAWN
	_phase_elapsed = 0.0
	Game.current_day += 1
	color = COL_DAWN
	Game.day_advanced.emit(Game.current_day)
