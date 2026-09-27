## The witch: a CharacterBody2D on a ThermalBody. Identical legs (the 10px
## jump is SACRED), wading and swim by tile tier, the sheet driving her anim
## state. She never writes a tile -- everything crosses the bridge.

class_name Witch
extends CharacterBody2D

const SHEET := "res://assets/witch/witch-Sheet-outlined.png"
const WALK := 80
const CROUCH_WALK := 20
const GRAVITY := 480        # shared legs
const JUMP_V := 98          # sqrt(2 * 480 * 10) -- 10px exactly, SACRED
const SWIM_GRAV := 120
const SWIM_VY := 60         # the sink clamp while submerged
const VOLUME := 1           # one nibble: three collides with every authored threshold

var room: Room
var body: ThermalBody
var sprite: Sprite2D
var _anim_t := 0.0
var _last_feet := Vector2i(-999, -999)
var _feet_liquid := 0
var _feet_capacity := 255

## Sample her locomotion read at the tick (world.md §5): the feet tile's liquid and its free capacity, from the settled phase.
func sample_liquid() -> void:
	var feet := _feet_tile()
	_feet_liquid = _liquid(feet)
	_feet_capacity = 255
	if room.stone.in_bounds(feet.x, feet.y):
		_feet_capacity = room.stone.packet.pool_capacity(room.stone.idx(feet.x, feet.y))

## Bind the room, build the thermal body with her volume, register it -- the customs office owns her exchanges from here on.
func _init(p_room: Room) -> void:
	room = p_room
	body = ThermalBody.new()
	body.volume_nibbles = VOLUME
	room.bridge.register(body)

## The sheet sprite and the 8x24 hitbox -- a subtile wide, three tall, centered on the sprite; the origin is her soles' center.
func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.hframes = 8
	sprite.texture = load(SHEET)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(-8.0, -32.0)
	add_child(sprite)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(8.0, 24.0)
	shape.shape = box
	shape.position = Vector2(0.0, -12.0)
	add_child(shape)

## Leave the room, leave the registry.
func _exit_tree() -> void:
	room.bridge.unregister(body)

## Frame-side truth: read input and the tick-sampled feet tile, move, then push her state to the thermal body and the sprite.
func _physics_process(delta: float) -> void:
	var feet := _feet_tile()
	var head := _head_tile()
	# the wade line: the water fills at least half the tile's free space -- capacity-aware, so soil-bottomed pools read true
	var in_liquid := _feet_liquid * 2 >= _feet_capacity - 1
	var crouch := Input.is_key_pressed(KEY_S)
	var dir := 0.0
	if Input.is_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir += 1.0
	var speed := CROUCH_WALK if crouch else WALK
	if in_liquid:
		@warning_ignore("narrowing_conversion")
		speed *= 0.5
	velocity.x = dir * speed
	if dir != 0.0:
		sprite.flip_h = dir < 0.0
	if in_liquid:
		velocity.y = minf(velocity.y + SWIM_GRAV * delta, SWIM_VY)
		if crouch and not is_on_floor():
			velocity.y = SWIM_VY   # the dive: curl and sink at the clamp
	else:
		velocity.y += GRAVITY * delta
	if Input.is_key_pressed(KEY_SPACE):
		if is_on_floor() and not crouch:
			velocity.y = -JUMP_V   # off the floor -- through water at swim gravity, over land at full
		elif in_liquid and velocity.y >= 0.0:
			velocity.y = -JUMP_V   # the stroke: waterborne, gated on sinking
	move_and_slide()
	_sync_body(feet, head)
	_anim(delta, crouch)

## The sheet drives the state machine: the crouch (and dive) pose first, then the air frame, then the ping-pong cycles.
func _anim(delta: float, crouch: bool) -> void:
	_anim_t += delta
	if crouch:
		sprite.frame = 7
	elif not is_on_floor():
		sprite.frame = 6
	elif absf(velocity.x) > 0.5:
		var seq: Array[int] = [3, 4, 5, 4]
		sprite.frame = seq[int(_anim_t * 9.0) % seq.size()]
	else:
		var seq: Array[int] = [0, 1, 2, 1]
		sprite.frame = seq[int(_anim_t * 3.0) % seq.size()]

## Push her frame-side truth to the body: the overlapped column, per-tile volumes from the hitbox's subtile rows (bottom-heavy: 2 at her feet when aligned), the support tile, and the entry tile.
func _sync_body(feet: Vector2i, head: Vector2i) -> void:
	var row_top := floori((position.y - 24.0) / 8.0)
	var row_bottom := floori((position.y - 1.0) / 8.0)
	var tiles: Array[Vector2i] = []
	var vols: Array[int] = []
	for ty in range(head.y, feet.y + 1):
		tiles.append(Vector2i(feet.x, ty))
		var r0 := ty * 2
		if row_bottom < r0 or row_top > r0 + 1:
			vols.append(0)
		else:
			vols.append(clampi(row_bottom, r0, r0 + 1) - clampi(row_top, r0, r0 + 1) + 1)
	body.tiles = tiles
	body.tile_volumes = vols
	body.support = feet + Vector2i(0, 1)
	if feet != _last_feet:
		body.last_tiles = body.tiles
		body.entered_from = _last_feet
		_last_feet = feet

## Place her at pos with a clean slate: no velocity, no stale entry tile (the bow wave forgets).
func teleport(pos: Vector2) -> void:
	position = pos
	velocity = Vector2.ZERO
	_last_feet = Vector2i(-999, -999)
	body.entered_from = _last_feet
	sample_liquid()

## The tile holding the pixel just above her soles.
func _feet_tile() -> Vector2i:
	return Vector2i(floori(position.x / 16.0), floori((position.y - 1.0) / 16.0))

## The tile holding her hitbox's top pixel -- the hat is picture; the hitbox is her body to the engine.
func _head_tile() -> Vector2i:
	return Vector2i(floori(position.x / 16.0), floori((position.y - 24.0) / 16.0))

## Liquid units at tile t -- the pool minus the gases (the renderer's _liquid_total, read for locomotion).
func _liquid(t: Vector2i) -> int:
	if not room.stone.in_bounds(t.x, t.y):
		return 0
	var i := room.stone.idx(t.x, t.y)
	return room.stone.packet.pool_total(i) - room.stone.packet.get_pool(i, TilePacket.Mat.SMOKE) \
			- room.stone.packet.get_pool(i, TilePacket.Mat.STEAM)
