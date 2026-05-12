extends Node
# Global game-state singleton.
# Holds palette, tile size, the shared map/water/dam state, and signals
# every other system listens to. Kept as a thin coordinator — no heavy logic.

const TILE_SIZE := 32
const MAP_W := 30
const MAP_H := 20

# ── Palette (Keystone brief) ────────────────────────────────────────────
const COL_BG       := Color("#0F1A14")
const COL_PANEL    := Color("#1B2A22")
const COL_WATER_S  := Color("#6FAFD0")  # shallow — lighter
const COL_WATER_D  := Color("#4A8FB8")  # deep
const COL_BEAVER   := Color("#6B4423")
const COL_WETLAND  := Color("#5BA84A")
const COL_GRASS    := Color("#3F6E3A")
const COL_DRY      := Color("#3A4A3A")
const COL_DIRT     := Color("#5A4630")
const COL_TREE     := Color("#244225")
const COL_TREE_CR  := Color("#2F5D2F")
const COL_STUMP    := Color("#3D2A19")
const COL_LOG      := Color("#7A4E2A")
const COL_LODGE    := Color("#5A3A22")
const COL_LODGE_DR := Color("#1B0F08")
const COL_DAM_NEW  := Color("#8A6A3E")
const COL_DAM_WORN := Color("#6E5430")
const COL_DAM_BROK := Color("#3A2F1E")
const COL_ACCENT   := Color("#D4A04A")
const COL_TEXT     := Color("#F0F0E8")
const COL_DANGER   := Color("#C8533E")
const COL_DAM_ZONE := Color("#D4A04A")  # build-zone outline

# Per-species accents (HUD + sprite tint)
const COL_WILLOW   := Color("#7BAE5D")
const COL_FROG     := Color("#5FB44A")
const COL_FISH     := Color("#C9A24A")
const COL_DUCK     := Color("#E6E0C8")
const COL_HERON    := Color("#A8A8B0")
const COL_OTTER    := Color("#8A5A3A")
const COL_COYOTE   := Color("#B59060")

# ── Tile codes ──────────────────────────────────────────────────────────
enum Tile { DRY, GRASS, DIRT, SHALLOW, DEEP, WETLAND, TREE, LODGE, DAM_ZONE }

# ── Day phases ──────────────────────────────────────────────────────────
enum Phase { DAWN, DAY, DUSK, NIGHT }

# ── Signals ─────────────────────────────────────────────────────────────
signal water_changed
signal day_advanced(day_index: int)
signal phase_changed(phase: int, t01: float)
signal stamina_changed(value: float)
signal species_changed(counts: Dictionary)
signal dam_changed(segments: int, integrity: Array)
signal log_message(text: String)
signal carrying_changed(carrying: bool)
signal game_won
signal game_lost(reason: String)

# ── Shared state set/read by systems ────────────────────────────────────
var current_day := 1
var phase: int = Phase.DAWN
var phase_t := 0.0           # 0..1 within phase
var stamina := 100.0
var carrying_log := false
var dam_segments: Array = [] # array of integrity floats 0..1 (max 10)
var species: Dictionary = {  # name -> pop int 0..8
	"willow": 0, "frog": 0, "fish": 0,
	"duck": 0, "heron": 0, "otter": 0,
}
var consecutive_full_days := 0  # for win condition (all 6 species ≥1)
var drought_active := false
var drought_days_left := 0
var game_over := false
var win := false

func _ready() -> void:
	randomize()

func reset() -> void:
	current_day = 1
	phase = Phase.DAWN
	phase_t = 0.0
	stamina = 100.0
	carrying_log = false
	dam_segments = []
	species = { "willow": 0, "frog": 0, "fish": 0, "duck": 0, "heron": 0, "otter": 0 }
	consecutive_full_days = 0
	drought_active = false
	drought_days_left = 0
	game_over = false
	win = false

func emit_message(t: String) -> void:
	log_message.emit(t)

func phase_name(p: int) -> String:
	match p:
		Phase.DAWN: return "dawn"
		Phase.DAY: return "day"
		Phase.DUSK: return "dusk"
		Phase.NIGHT: return "night"
	return "?"
