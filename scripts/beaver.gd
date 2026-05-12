extends CharacterBody2D
# Beaver. Tile-aligned movement (smooth between tiles), facing, action handling.
# Stamina drains on actions and night; refilled by sleeping in lodge.

const G := preload("res://scripts/game.gd")

@onready var world: Node2D = get_node("/root/Main/World")
@onready var dam: Node2D = get_node("/root/Main/Dam")
@onready var day_cycle: CanvasModulate = get_node("/root/Main/DayCycle")
@onready var logs_root: Node2D = get_node("/root/Main/Logs")
@onready var sprite_root: Node2D = $SpriteRoot
@onready var placeholder: Node2D = $SpriteRoot/Placeholder
@onready var sprite: Sprite2D = $SpriteRoot/Sprite
@onready var carry_placeholder: ColorRect = $SpriteRoot/CarryPlaceholder
@onready var carry_sprite: Sprite2D = $SpriteRoot/CarrySprite

const SPEED := 110.0
const SPRINT_MULT := 2.0
const CHEW_DURATION := 2.0
const REPAIR_DURATION := 1.0
const PLACE_DURATION := 0.4

var facing := Vector2(1, 0)
var sprinting := false

# Action state — a tiny FSM: idle / chewing / repairing / placing / sleeping
var action_state := "idle"
var action_timer := 0.0
var action_target := Vector2i(-1, -1)

# Sprite asset state — flipped in once PixelLab generation lands
var have_pixel_sprites := false

func _ready() -> void:
	add_to_group("beaver")
	position = _tile_center(world.find_lodge_tile())
	_try_load_pixel_sprites()
	_update_carry_visual()

func _physics_process(delta: float) -> void:
	if Game.game_over:
		velocity = Vector2.ZERO
		return
	_handle_input(delta)
	_drain_passive_stamina(delta)
	move_and_slide()
	Game.stamina_changed.emit(Game.stamina)
	if Game.stamina <= 0.0:
		Game.stamina = 0.0
		Game.game_over = true
		Game.game_lost.emit("Exhaustion. The pond drained.")

func _handle_input(delta: float) -> void:
	# Resolve current action (multi-frame) first
	if action_state != "idle":
		action_timer -= delta
		if action_timer <= 0.0:
			_finish_action()
		velocity = Vector2.ZERO
		return

	# Movement input
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	if Input.is_action_pressed("move_up"):
		dir.y -= 1
	if Input.is_action_pressed("move_down"):
		dir.y += 1
	if dir.length() > 0.0:
		dir = dir.normalized()
		facing = dir
		_face_sprite(dir)
	sprinting = Input.is_action_pressed("sprint") and dir.length() > 0.0
	var speed := SPEED * (SPRINT_MULT if sprinting else 1.0)
	velocity = dir * speed

	# Sprint drain
	if sprinting:
		Game.stamina = max(0.0, Game.stamina - 2.0 * delta)

	# Action key
	if Input.is_action_just_pressed("action"):
		_try_start_action()

	# Sleep
	if Input.is_action_just_pressed("sleep"):
		_try_sleep()

func _drain_passive_stamina(delta: float) -> void:
	# Night drains stamina 50% faster — except if sleeping (handled by skip).
	if Game.phase == Game.Phase.NIGHT:
		Game.stamina = max(0.0, Game.stamina - 0.6 * delta)
	else:
		Game.stamina = max(0.0, Game.stamina - 0.4 * delta)

func _try_start_action() -> void:
	var here := _tile_at(position)
	# Priority: place log in dam zone → repair dam → pick up log → chew tree.
	# Place log
	if Game.carrying_log and world.is_in_dam_zone(here):
		if dam.can_place():
			action_state = "placing"
			action_timer = PLACE_DURATION
			Game.emit_message("Placing dam segment...")
			return
		else:
			Game.emit_message("Dam is full (10 segments).")
			return
	# Repair dam
	if dam.needs_repair_nearby(here):
		action_state = "repairing"
		action_timer = REPAIR_DURATION
		Game.emit_message("Repairing...")
		return
	# Pick up log: look for a log node at this tile
	if not Game.carrying_log:
		var picked := _try_pick_up_log_at(here)
		if picked:
			return
	# Chew tree: adjacent
	if not Game.carrying_log:
		var tree_p: Vector2i = world.find_tree_near(here)
		if tree_p.x >= 0:
			action_state = "chewing"
			action_target = tree_p
			action_timer = CHEW_DURATION
			_face_sprite(Vector2(tree_p.x - here.x, tree_p.y - here.y))
			Game.emit_message("Chewing tree...")
			return

func _finish_action() -> void:
	match action_state:
		"chewing":
			if Game.stamina >= 10.0:
				Game.stamina -= 10.0
				world.chop_tree(action_target)
				_spawn_log(action_target)
				Game.emit_message("Tree felled. A log drops.")
			else:
				Game.emit_message("Too tired to chew.")
		"placing":
			if Game.stamina >= 5.0 and dam.add_segment():
				Game.stamina -= 5.0
				Game.carrying_log = false
				_update_carry_visual()
				Game.carrying_changed.emit(false)
		"repairing":
			if Game.stamina >= 5.0 and dam.repair_worst():
				Game.stamina -= 5.0
	action_state = "idle"
	action_target = Vector2i(-1, -1)

func _try_pick_up_log_at(here: Vector2i) -> bool:
	for child in logs_root.get_children():
		if child is Node2D:
			var lp := _tile_at(child.position)
			if lp == here:
				logs_root.remove_child(child)
				child.queue_free()
				Game.carrying_log = true
				_update_carry_visual()
				Game.carrying_changed.emit(true)
				Game.emit_message("Picked up a log.")
				return true
	return false

func _spawn_log(at_tile: Vector2i) -> void:
	# Spawn a small Node2D with a Sprite2D / colored rect at the tile
	var log_node := preload("res://scenes/Log.tscn").instantiate()
	log_node.position = _tile_center(at_tile)
	logs_root.add_child(log_node)

func _try_sleep() -> void:
	var here := _tile_at(position)
	if world.get_tile(here) != Game.Tile.LODGE:
		Game.emit_message("Sleep only works inside the lodge.")
		return
	Game.emit_message("Sleeping until dawn...")
	Game.stamina = 100.0
	day_cycle.skip_to_dawn()

# ── Sprite helpers ─────────────────────────────────────────────────────
func _face_sprite(d: Vector2) -> void:
	# Placeholder: scale x for left/right. With pixel sprites we'll swap textures.
	if abs(d.x) > abs(d.y):
		sprite_root.scale.x = -1.0 if d.x < 0 else 1.0
	if abs(d.y) > abs(d.x):
		sprite_root.scale.x = 1.0  # neutral facing for up/down

func _update_carry_visual() -> void:
	if have_pixel_sprites and carry_sprite.texture != null:
		carry_sprite.visible = Game.carrying_log
		carry_placeholder.visible = false
	else:
		carry_placeholder.visible = Game.carrying_log
		carry_sprite.visible = false

func _try_load_pixel_sprites() -> void:
	if ResourceLoader.exists("res://assets/sprites/beaver.png"):
		var tex := load("res://assets/sprites/beaver.png") as Texture2D
		if tex:
			sprite.texture = tex
			sprite.visible = true
			placeholder.visible = false
			have_pixel_sprites = true
	if ResourceLoader.exists("res://assets/sprites/beaver_carrying.png"):
		var tex2 := load("res://assets/sprites/beaver_carrying.png") as Texture2D
		if tex2:
			carry_sprite.texture = tex2

func _tile_at(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / Game.TILE_SIZE), int(world_pos.y / Game.TILE_SIZE))

func _tile_center(t: Vector2i) -> Vector2:
	return Vector2(t.x * Game.TILE_SIZE + Game.TILE_SIZE / 2.0, t.y * Game.TILE_SIZE + Game.TILE_SIZE / 2.0)

# Called by Coyote when it touches the beaver.
func bite() -> void:
	Game.stamina = max(0.0, Game.stamina - 30.0)
	position = _tile_center(world.find_lodge_tile())
	Game.emit_message("A coyote struck! Limped back to the lodge.")
