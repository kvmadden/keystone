extends Node2D
# Species spawner. Once per in-game day, evaluates conditions for each species,
# adjusts populations, and spawns/removes sprites at valid tiles. Each sprite
# does procedural wandering on valid tiles in its own _process.
#
# Ladder (small ints 0..8):
#   willow: ≥3 wetland           → grows on wetland
#   frog:   ≥2 willows AND ≥3 shallow
#   fish:   ≥4 deep water
#   duck:   ≥3 shallow AND ≥2 willows
#   heron:  ≥3 fish OR ≥4 frogs
#   otter:  ≥5 fish AND ≥6 deep tiles

const G := preload("res://scripts/game.gd")
const SpeciesEntity := preload("res://scripts/species_entity.gd")

@onready var world: Node2D = get_node("/root/Main/World")

const MAX_POP := 8

# Tile-type validation for each species (what tile it wanders on)
var habitats := {
	"willow": [Game.Tile.WETLAND],
	"frog":   [Game.Tile.WETLAND, Game.Tile.SHALLOW],
	"fish":   [Game.Tile.DEEP],
	"duck":   [Game.Tile.SHALLOW, Game.Tile.DEEP],
	"heron":  [Game.Tile.SHALLOW, Game.Tile.WETLAND],
	"otter":  [Game.Tile.DEEP, Game.Tile.SHALLOW],
}

# Latin binomial + one-line ecology note — fired when a species first appears.
var species_info := {
	"willow": ["Salix nigra",         "Pioneer woody species — its roots stabilize the new bank."],
	"frog":   ["Lithobates pipiens",  "Amphibian indicator — present water is clean enough to breed."],
	"fish":   ["Lepomis macrochirus", "Bluegill arrive once the pond is deep enough to overwinter."],
	"duck":   ["Aix sponsa",          "Wood duck — nests in the new shoreline willows."],
	"heron":  ["Ardea herodias",      "Great blue heron — apex of the wetland food web has arrived."],
	"otter":  ["Lontra canadensis",   "River otter — only returns once fish populations sustain it."],
}

func _ready() -> void:
	Game.day_advanced.connect(_on_day)
	# Tick once at game start to seed any obvious species
	call_deferred("_evaluate")

func _on_day(_d: int) -> void:
	_evaluate()
	_check_win()

func _evaluate() -> void:
	var wet: int = int(world.count_tile(Game.Tile.WETLAND))
	var shal: int = int(world.count_tile(Game.Tile.SHALLOW))
	var deep: int = int(world.count_tile(Game.Tile.DEEP))
	var willows: int = int(Game.species["willow"])
	var frogs: int = int(Game.species["frog"])
	var fish: int = int(Game.species["fish"])

	_adjust("willow", wet >= 3)
	_adjust("frog",   willows >= 2 and shal >= 3)
	_adjust("fish",   deep >= 4)
	_adjust("duck",   shal >= 3 and willows >= 2)
	_adjust("heron",  fish >= 3 or frogs >= 4)
	_adjust("otter",  fish >= 5 and deep >= 6)
	Game.species_changed.emit(Game.species.duplicate())

	_resync_entities()

func _adjust(species_name: String, conditions_met: bool) -> void:
	if conditions_met:
		var was_zero: bool = int(Game.species[species_name]) == 0
		Game.species[species_name] = min(MAX_POP, int(Game.species[species_name]) + 1)
		if was_zero:
			var info: Array = species_info.get(species_name, [species_name.capitalize(), ""])
			Game.emit_message("%s (%s) arrived. %s" % [species_name.capitalize(), info[0], info[1]])
	else:
		Game.species[species_name] = max(0, int(Game.species[species_name]) - 1)

func _resync_entities() -> void:
	# Sync visible entities to populations. Remove extras, add missing.
	var by_kind := {}
	for child in get_children():
		if child is SpeciesEntity:
			var kind: String = child.kind
			if not by_kind.has(kind):
				by_kind[kind] = []
			by_kind[kind].append(child)
	for kind in Game.species.keys():
		var have: int = (by_kind[kind].size() if by_kind.has(kind) else 0)
		var want: int = int(Game.species[kind])
		while have > want:
			var e = (by_kind[kind] as Array).pop_back()
			e.queue_free()
			have -= 1
		while have < want:
			_spawn_one(kind)
			have += 1

func _spawn_one(kind: String) -> void:
	var habitat = habitats[kind]
	var tile := _find_random_habitat_tile(habitat)
	if tile.x < 0:
		return
	var e := SpeciesEntity.new()
	e.kind = kind
	e.world_path = world.get_path()
	e.habitat = habitat
	e.position = Vector2(tile.x * Game.TILE_SIZE + Game.TILE_SIZE / 2.0, tile.y * Game.TILE_SIZE + Game.TILE_SIZE / 2.0)
	add_child(e)

func _find_random_habitat_tile(habitat: Array) -> Vector2i:
	var candidates: Array = []
	for y in range(Game.MAP_H):
		for x in range(Game.MAP_W):
			if habitat.has(int(world.tiles[y][x])):
				candidates.append(Vector2i(x, y))
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[randi() % candidates.size()]

func _check_win() -> void:
	var all_present := true
	for k in Game.species.keys():
		if int(Game.species[k]) < 1:
			all_present = false
			break
	if all_present:
		Game.consecutive_full_days += 1
		var hold_msg := "Six species coexisting — holding day %d of 3." % Game.consecutive_full_days
		if Game.consecutive_full_days == 1:
			hold_msg = "All six species present. Hold the ecosystem for three days."
		elif Game.consecutive_full_days == 2:
			hold_msg = "Two days holding. One more and the wetland is self-sustaining."
		Game.emit_message(hold_msg)
		if Game.consecutive_full_days >= 3 and not Game.win:
			Game.win = true
			Game.game_over = true
			Game.game_won.emit()
	else:
		if Game.consecutive_full_days > 0:
			Game.emit_message("A species dropped out. The hold resets.")
		Game.consecutive_full_days = 0
