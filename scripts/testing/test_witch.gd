## The witch lab: paint the elements, spawn her with N, drive her with WASD
## and Space. The bridge soaks and dries her (heat and wetness in the HUD);
## the collision mirror keeps the floor honest under her feet.

class_name TestWitch
extends TestSandbox

var witch: Witch
var mirror: CollisionMirror

## Build the mirror, load the map -- she comes with it.
func _setup() -> void:
	mirror = CollisionMirror.new(room.stone)
	add_child(mirror)
	_load_preset(KEY_F1)

## One tick: the room rules, the mirror follows, she samples her reads from the settled state.
func _tick_world() -> void:
	room.tick()
	mirror.sync()
	if witch != null:
		witch.sample_liquid()

## Clear the world -- the witch is an actor and survives; the mirror follows immediately.
func _clear_world() -> void:
	room.reset()
	mirror.sync()

## Scene keys: N spawns or teleports her at hover, I ignites, F1 the map, P pause (Space is hers), 1-5 materials.
func _handle_key(k: int) -> bool:
	match k:
		KEY_N:
			var t := _hover_tile()
			if t.x < 0:
				t = Vector2i(8, 13)
			_spawn_witch(t)
			return true
		KEY_I:
			_god_ignite()
			return true
		KEY_F1:
			_load_preset(k)
			return true
		KEY_P:
			paused = not paused
			return true
		KEY_1:
			paint = Paint.STONE
			return true
		KEY_2:
			paint = Paint.WATER
			return true
		KEY_3:
			paint = Paint.WOOD
			return true
		KEY_4:
			paint = Paint.SOIL
			return true
		KEY_5:
			paint = Paint.DAMP
			return true
	return false

## Space is her jump -- swallow it before the harness reads pause; pause lives on P.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_SPACE:
		return
	super._unhandled_key_input(event)

## Held strokes need a held button: RMB erases; LMB paints -- stone and wood refuse occupied ground, soil lays one subtile, damp doses 64.
func _paint_stroke(t: Vector2i) -> bool:
	if t.x < 0:
		return false
	if not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		return false
	var pk := room.stone.packet
	var i := room.stone.idx(t.x, t.y)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		pk.set_fire(i, 0)
		pk.set_fuel(i, 0)
		room.water.set_water(t.x, t.y, 0)
		room.stone.set_terrain(t.x, t.y, GridStone.Terrain.AIR)
		mirror.sync()
		return true
	match paint:
		Paint.STONE:
			if pk.get_terrain(i) == TilePacket.T.AIR and pk.pool_total(i) == 0:
				room.stone.set_terrain(t.x, t.y, GridStone.Terrain.STONE)
				mirror.sync()
				return true
		Paint.WATER:
			room.water.set_water(t.x, t.y, 255)
			return true
		Paint.WOOD:
			if pk.get_terrain(i) == TilePacket.T.AIR and pk.pool_total(i) == 0:
				room.stone.set_terrain(t.x, t.y, GridStone.Terrain.WOOD)
				pk.set_fuel(i, 255)
				return true
		Paint.SOIL:
			var n := pk.get_sub(i, TilePacket.K_SOIL)
			if n < 15 and pk.pool_total(i) <= maxi(0, pk.pool_capacity(i) - 64):
				pk.set_sub(i, TilePacket.K_SOIL, n | (n + 1))
				mirror.sync()
				return true
		Paint.DAMP:
			if pk.add_damp(i, 64) > 0:
				return true
	return false

## Spawn the witch at tile t (feet at the tile's floor edge); an existing witch teleports instead.
func _spawn_witch(t: Vector2i) -> void:
	var pos := Vector2(t.x * 16.0 + 8.0, t.y * 16.0 + 16.0)
	if witch == null:
		witch = Witch.new(room)
		add_child(witch)
		witch.position = pos
	else:
		witch.teleport(pos)

## Reset, carve the map, damp the soil rise, sync the mirror, and drop her in.
func _load_preset(_keycode: int) -> void:
	room.reset()
	var rows: Array = ["............", "............", "............", "............", ".........www", "WWWoottt.www"]
	var o := _carve_preset(room.stone, room.water, rows)
	var pk := room.stone.packet
	for x in range(o.x + 5, o.x + 8):
		pk.add_damp(pk.idx(x, o.y + 5), 64)
	mirror.sync()
	_spawn_witch(Vector2i(o.x + 8, o.y + 5))

## God-hand ignite at the hover tile.
func _god_ignite() -> void:
	var t := _hover_tile()
	if t.x >= 0:
		room.react.ignite(t.x, t.y)

## Controls listing for the witch lab.
func _hint_header() -> String:
	return "TEST_WITCH   WASD move (S crouch)   SPACE jump / swim stroke   N spawn or teleport her\n" \
			+ "I ignite at hover   1 stone / 2 water / 3 wood / 4 soil / 5 damp   LMB paint   RMB erase\n" \
			+ "F1 the map   P pause (Space is hers)   T step   X clear   G debug\n"

## Live readout: pause, her thermal state, and the hover tile.
func _info_line(t: Vector2i) -> String:
	var info := "PAUSED (T steps)" if paused else ""
	if witch != null:
		info += "   witch heat %3d   wet %3d" % [witch.body.heat, witch.body.wetness]
	var pk := room.stone.packet
	var family := pk.mat_total(TilePacket.Mat.WATER) + pk.mat_total(TilePacket.Mat.STEAM) + pk.damp_total()
	if witch != null:
		family += witch.body.wetness
		info += "   family %d" % family
	if t.x >= 0:
		var i := room.stone.idx(t.x, t.y)
		info += "   tile %d,%d   water %3d" % [t.x, t.y, pk.get_pool(i, TilePacket.Mat.WATER)]
		if pk.get_fuel(i) > 0 or pk.get_fire(i) != 0:
			info += "   fuel %3d   fire %d   ign %d" % [pk.get_fuel(i), pk.get_fire(i), room.react.get_ignition(t.x, t.y)]
	return info
