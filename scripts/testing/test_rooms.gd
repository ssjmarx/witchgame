## The rooms lab: two CA domains in one scene. TAB switches which one the
## harness observes (the aliases repoint; the unobserved room is never
## ticked); R restores both to their preset-load baselines; K runs RT1-RT4.

class_name TestRooms
extends TestSandbox

const ROOM_B_SEED := 2   # distinct from SANDBOX_SEED -- two rooms, two PRNGs (world.md §1)

var room_b: Room
var renderer_b: ElementRenderer
var sprite_b: Sprite2D
var rooms: Array[Room] = []
var renderers: Array[ElementRenderer] = []
var sprites: Array[Sprite2D] = []
var baselines: Array[RoomState] = []
var observed := 0

## Build room B with its renderer and sprite beside the sandbox's room A, then load the first preset -- the baseline is taken after the carve, before any tick.
func _setup() -> void:
	room_b = Room.new(GRID_W, GRID_H, ROOM_B_SEED)
	renderer_b = ElementRenderer.new(room_b.stone, room_b.water)
	sprite_b = Sprite2D.new()
	sprite_b.centered = false
	sprite_b.texture = renderer_b.texture
	sprite_b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite_b)
	rooms = [room, room_b]
	renderers = [renderer, renderer_b]
	sprites = [sprite, sprite_b]
	_observe()
	_load_preset(KEY_F1)

## Only the observed room ticks -- the other is frozen by absence, not by a flag (world.md §1: the room containing the camera simulates).
func _tick_world() -> void:
	rooms[observed].tick()

## Clear both worlds and drop the baselines with them (a stale baseline over a blank world is a trap, not a feature).
func _clear_world() -> void:
	for r in rooms:
		r.reset()
	baselines.clear()

## Scene keys: TAB switches the observed room, R restores both to baseline, F-keys load presets, I ignites at hover, K runs the RT suite, 1/2/3 pick material.
func _handle_key(k: int) -> bool:
	match k:
		KEY_TAB:
			_switch_room()
			return true
		KEY_R:
			_restore_all()
			return true
		KEY_F1, KEY_F2:
			_load_preset(k)
			return true
		KEY_I:
			_god_ignite()
			return true
		KEY_K:
			run_suite()
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
	return false

## Held strokes need a held button: RMB erases; LMB paints -- solids refuse occupied ground (the shared verbs, aimed at the observed room).
func _paint_stroke(t: Vector2i) -> bool:
	if t.x < 0:
		return false
	# hover is not a verb -- a stroke needs a held button, and the override owns that gate
	if not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		return false
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_erase_tile(t)
		return true
	match paint:
		Paint.STONE:
			return _lay_solid(t, GridStone.Terrain.STONE)
		Paint.WATER:
			water.set_water(t.x, t.y, 255)
			return true
		Paint.WOOD:
			return _lay_solid(t, GridStone.Terrain.WOOD)
	return false

## Re-point the harness aliases at the observed room, hide the other sprite, redraw once -- a TAB while paused must show the frozen truth.
func _observe() -> void:
	var r := rooms[observed]
	stone = r.stone
	water = r.water
	renderer = renderers[observed]
	for s in sprites.size():
		sprites[s].visible = s == observed
	renderer.redraw()

## Switch which room the harness observes -- alias repointing, nothing else.
func _switch_room() -> void:
	observed = 1 - observed
	_observe()

## Restore both rooms to their baselines -- the unobserved one restores without ticking (the assert inside restore is the proof it landed sound).
func _restore_all() -> void:
	if baselines.size() != rooms.size():
		return
	for i in rooms.size():
		rooms[i].restore(baselines[i])
	renderer.redraw()

## Reset both rooms, carve the preset into each, snapshot both as the baseline -- order is the grammar: carve, snapshot, run.
func _load_preset(keycode: int) -> void:
	for r in rooms:
		r.reset()
	baselines.clear()
	var rows := _preset_rows(keycode)
	for i in rooms.size():
		_carve_preset(rooms[i].stone, rooms[i].water, rows)
		baselines.append(rooms[i].snapshot())
	renderer.redraw()

## The demo diagrams: F1 a four-tall water column above the shell floor (the twin falls), F2 a wood platform (the burn).
func _preset_rows(keycode: int) -> Array:
	match keycode:
		KEY_F2:
			return ["WWWW", "WWWW"]
		_:
			return ["ww", "ww", "ww", "ww"]

## God-hand ignite at the hover tile in the observed room (test_fire's pattern: fuel catches, bare air sparks, wet fuel refuses).
func _god_ignite() -> void:
	var t := _hover_tile()
	if t.x < 0:
		return
	rooms[observed].react.ignite(t.x, t.y)

## Controls listing for the rooms lab.
func _hint_header() -> String:
	return "ROOMS LAB   TAB observe other room   R restore both to baseline   I ignite at hover   K RT suite\n" \
			+ "F1 twin falls   F2 the burn   1 stone / 2 water / 3 wood   LMB paint   RMB erase\n" \
			+ "SPC pause   T step observed   X clear both   G debug\n"

## Live readout: the observed room's age (the freeze, countable) plus the hover tile's water, fuel, fire, and ignition timer.
func _info_line(t: Vector2i) -> String:
	var info := "PAUSED (T steps)" if paused else ""
	var r := rooms[observed]
	info += "   ROOM %s (t=%d)" % ["A" if observed == 0 else "B", r.water.tick_count]
	if t.x >= 0:
		var pk := r.stone.packet
		var i := r.stone.idx(t.x, t.y)
		info += "   tile %d,%d   water %3d" % [t.x, t.y, pk.get_pool(i, TilePacket.Mat.WATER)]
		if pk.get_fuel(i) > 0 or pk.get_fire(i) != 0:
			info += "   fuel %3d   fire %d   ign %d" % [pk.get_fuel(i), pk.get_fire(i), r.react.get_ignition(t.x, t.y)]
	return info

## The rooms lab's example set: the room-machinery examples in order.
func run_tests() -> void:
	run_room_tests()

## Room-machinery acceptance examples: fresh Rooms built and driven directly -- these test the container (restore, freeze, determinism), not matter equilibria, so they bypass _run_example.
func run_room_tests() -> void:
	print("== room self-tests ==")
	_example("RT1  restore is byte-exact mid-drift", _rt_restore_exact)
	_example("RT2  fire forgiveness: spent fuel returns", _rt_fire_forgive)
	_example("RT3  the unobserved room is frozen", _rt_freeze)
	_example("RT4  same seed, same bytes", _rt_same_seed)
	print("== done ==")

## RT1: soak water into soil for 300 ticks, restore, and prove three things -- the ledger lands green outside a tick, the census returns byte-exact, and the baseline survives later ticks (the aliasing canary: a restore that pointed at stored arrays instead of copies would drift with the world).
func _rt_restore_exact() -> String:
	var r := Room.new(GRID_W, GRID_H, 11)
	_carve_preset(r.stone, r.water, ["ww", "ww", "dd", "dd"])
	var base := r.snapshot()
	for _t in 300:
		r.tick()
	if r.snapshot().same_bytes(base):
		return "300 ticks changed nothing -- vacuous"
	r.restore(base)
	var landed := r.snapshot()
	if not r.stone.packet.assert_all():
		return "ledger red after restore"
	if not landed.same_bytes(base):
		return "restore not byte-exact"
	for _t in 20:
		r.tick()
	if not landed.same_bytes(base):
		return "baseline drifted with later ticks -- restore aliased the census"
	if not r.stone.packet.assert_all():
		return "ledger red after post-restore ticks"
	return ""

## RT2: ignite a wood platform, burn 150 ticks -- holes open, smoke vents -- then restore: fuel, terrain, fire bits, and ignition progress all return to the authored state.
func _rt_fire_forgive() -> String:
	var r := Room.new(GRID_W, GRID_H, 12)
	var origin := _carve_preset(r.stone, r.water, ["WWWW", "WWWW"])
	var base := r.snapshot()
	if not r.react.ignite(origin.x, origin.y):
		return "god-hand ignite refused"
	for _t in 150:
		r.tick()
	if r.stone.packet.fuel_total() >= 8 * 255:
		return "nothing burned -- vacuous"
	r.restore(base)
	if r.stone.packet.fuel_total() != 8 * 255:
		return "spent fuel did not return"
	if r.stone.packet.has_fire():
		return "fire bits survived the restore"
	if r.react.get_ignition(origin.x, origin.y) != 0:
		return "ignition progress survived the restore"
	if not r.snapshot().same_bytes(base):
		return "restore not byte-exact"
	return ""

## RT3: two rooms carved alike; B ticks once (labels built, mid-life), then A runs 100 ticks alone -- B's census must be byte-frozen and both ledgers green.
func _rt_freeze() -> String:
	var a := Room.new(GRID_W, GRID_H, 13)
	var b := Room.new(GRID_W, GRID_H, 14)
	_carve_preset(a.stone, a.water, ["www", "www"])
	_carve_preset(b.stone, b.water, ["www", "www"])
	var a0 := a.snapshot()
	b.tick()
	var frozen := b.snapshot()
	for _t in 100:
		a.tick()
	if a.snapshot().same_bytes(a0):
		return "the observed room never drifted -- vacuous"
	if not b.snapshot().same_bytes(frozen):
		return "the unobserved room moved"
	if not a.stone.packet.assert_all() or not b.stone.packet.assert_all():
		return "a ledger went red"
	return ""

## RT4: two rooms, one seed, identical carve, 500 interleaved ticks -- byte-identical censuses. The canary: nothing consumes the PRNG yet, so this is cheap today and load-bearing the day the bridge's stochastic rates land.
func _rt_same_seed() -> String:
	var r1 := Room.new(GRID_W, GRID_H, 7)
	var r2 := Room.new(GRID_W, GRID_H, 7)
	_carve_preset(r1.stone, r1.water, ["www", "www"])
	_carve_preset(r2.stone, r2.water, ["www", "www"])
	for _t in 500:
		r1.tick()
		r2.tick()
	if not r1.snapshot().same_bytes(r2.snapshot()):
		return "same seed diverged"
	if not r1.stone.packet.assert_all():
		return "ledger red"
	return ""
