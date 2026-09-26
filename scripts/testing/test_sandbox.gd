## Shared harness for element test scenes: owns the room (the engine quartet,
## aliased as stone/water for the scenes' existing reads), renderer, tick
## heartbeat, input plumbing, and paint/carve helpers. Scenes override hooks.

class_name TestSandbox
extends Node2D

const GRID_W := 15        # tiles across
const GRID_H := 15        # tiles down
const TILE := 16          # pixels per tile
const TEST_TICKS := 3000  # ticks each self-test runs before checking
const SANDBOX_SEED := 1   # the lab room's PRNG seed -- no consumer until the bridge lab (E4)

# materials any sandbox can lay down; a scene exposes the subset it wants (the fire lab added wood, the gases, and damp authoring)
enum Paint { STONE, WATER, SOIL, OIL, WOOD, STEAM, SMOKE, DAMP }

var room: Room
var stone: GridStone   # aliases into room -- every existing scene read keeps working
var water: GridWater
var renderer: ElementRenderer
var sprite: Sprite2D

var paint := Paint.WATER
var paused := false
var run_ticks := TEST_TICKS   # ticks per self-test; timing tests run short and restore
var drift_watch := true       # per-engine pool+damp attribution; scenes with in-tick matter creation (fire's smoke) turn it off
var _last_info := ""  # last HUD text; skips label writes when unchanged

## Build the shared world, wire timer and signals, then hand off to _setup.
func _ready() -> void:
	room = Room.new(GRID_W, GRID_H, SANDBOX_SEED)
	stone = room.stone
	water = room.water
	renderer = ElementRenderer.new(stone, water)
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture = renderer.texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	$TickTimer.timeout.connect(_on_tick)
	water.levels_changed.connect(_on_levels_changed)
	_setup()

## Override: load the scene's initial state.
func _setup() -> void:
	pass

## Fixed-step heartbeat: dose held-mouse input, advance the sim, redraw.
func _on_tick() -> void:
	if paused:
		return
	_dose()
	_tick_world()
	renderer.redraw()

## Override: apply held-mouse dosing that must land on tick boundaries.
func _dose() -> void:
	pass

## Override: advance the sim one tick -- the default runs the full engine ruling, owned by Room.tick (scenes no longer duplicate it).
func _tick_world() -> void:
	room.tick()

## Override: reset beyond the blank world; the default is Room.reset (every column, book, overlay, counter).
func _clear_world() -> void:
	room.reset()

## Override: handle held-mouse strokes; return true when the picture changed.
func _paint_stroke(_t: Vector2i) -> bool:
	return false

## Track the hover tile; run held strokes; refresh the HUD.
func _process(_delta: float) -> void:
	var t := _hover_tile()
	var dirty := t != renderer.hover
	renderer.hover = t
	if t.x >= 0:
		dirty = _paint_stroke(t) or dirty
	if dirty:
		renderer.redraw()
	_update_info(t)

## Override: extend key handling; return true when the key was consumed.
func _handle_key(_k: int) -> bool:
	return false

## Universal hotkeys (SPC pause, T step, X clear, G debug); the rest go to _handle_key.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var k: int = key.keycode
	match k:
		KEY_SPACE:
			paused = not paused
		KEY_T:
			if paused:
				_tick_world()
				renderer.redraw()
		KEY_X:
			_clear_world()
			renderer.redraw()
		KEY_G:
			renderer.debug = not renderer.debug
			renderer.redraw()
		_:
			_handle_key(k)

## Tile under the mouse, or (-1, -1) when off the grid.
func _hover_tile() -> Vector2i:
	var p := get_global_mouse_position()
	var t := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
	if t.x < 0 or t.y < 0 or t.x >= GRID_W or t.y >= GRID_H:
		return Vector2i(-1, -1)
	return t

## Carve a diagram (s stone, w water 255, o oil 255, d soil 15, t soil 12, W wood + fuel 255, v steam 255, m smoke 255, . air) wrapped in a stone U-shell; returns its origin.
func _carve_preset(p_stone: GridStone, p_water: GridWater, rows: Array) -> Vector2i:
	var first: String = rows[0]
	var pw := first.length()
	var ph := rows.size()
	var ox := int((GRID_W - (pw + 2)) / 2.0)
	var oy := GRID_H - (ph + 1)
	for x in range(ox - 1, ox + pw + 1):
		p_stone.set_terrain(x, oy + ph, GridStone.Terrain.STONE)
	for y in range(oy, oy + ph):
		p_stone.set_terrain(ox - 1, y, GridStone.Terrain.STONE)
		p_stone.set_terrain(ox + pw, y, GridStone.Terrain.STONE)
	for y in ph:
		var row: String = rows[y]
		for x in pw:
			var i := p_stone.idx(ox + x, oy + y)
			match row[x]:
				"s":
					p_stone.set_terrain(ox + x, oy + y, GridStone.Terrain.STONE)
				"w":
					p_water.set_water(ox + x, oy + y, 255)
				"d":
					p_stone.packet.set_sub(i, TilePacket.K_SOIL, 15)
				"t":
					p_stone.packet.set_sub(i, TilePacket.K_SOIL, 12)
				"o":
					p_water.add_liquid(ox + x, oy + y, TilePacket.Mat.OIL, 255)
				"W":
					p_stone.set_terrain(ox + x, oy + y, GridStone.Terrain.WOOD)
					p_stone.packet.set_fuel(i, 255)
				"v":
					p_water.add_liquid(ox + x, oy + y, TilePacket.Mat.STEAM, 255)
				"m":
					p_water.add_liquid(ox + x, oy + y, TilePacket.Mat.SMOKE, 255)
				_:
					pass
	return Vector2i(ox, oy)

## Rebuild the HUD line (pause state, hover readout) when it changes.
func _update_info(t: Vector2i) -> void:
	var info := _info_line(t)
	if info != _last_info:
		_last_info = info
		$UI/Hint.text = _hint_header() + info

## Override: the scene's controls listing shown above the live readout.
func _hint_header() -> String:
	return ""

## Override: the live readout for the hover tile.
func _info_line(t: Vector2i) -> String:
	var info := "PAUSED (T steps)" if paused else ""
	if t.x >= 0:
		var w := water.get_water(t.x, t.y)
		var bands := ["DRY", "WET", "HALF", "FULL"]
		if info != "":
			info += "   "
		info += "tile %d,%d   water %3d   lines %2d   %s" % [t.x, t.y, w, w >> 4, bands[water.get_level(t.x, t.y)]]
	return info

## No-op: redraws already ride the tick; keeps the signal wiring visible.
func _on_levels_changed(_cells) -> void:
	pass

## Headless example runner, shared by every acceptance suite: carve rows into a fresh full engine stack, run optional god-hand setup before the snapshot, tick to equilibrium under a per-engine drift watch, then check + pool legality + policy-driven conservation + subtile mass. Drift reports on every failure, so expectation bugs and leaks never mask each other.
@warning_ignore("shadowed_variable_base_class")
func _run_example(name: String, rows: Array, check: Callable, setup: Callable) -> void:
	var t_room := Room.new(GRID_W, GRID_H, SANDBOX_SEED)
	var t_stone := t_room.stone
	var t_water := t_room.water
	var t_sand := t_room.sand
	var t_react := t_room.react
	var o := _carve_preset(t_stone, t_water, rows)
	if setup.is_valid():
		setup.call([t_stone, t_water, o, t_sand, t_react])
	var w0 := PackedInt32Array()
	for m in TilePacket.MAT_COUNT:
		w0.append(t_stone.packet.mat_total(m))
	w0.append(t_stone.packet.damp_total())
	w0.append(t_stone.packet.fuel_total())
	var s0 := PackedInt32Array()
	for k in 3:
		s0.append(t_sand.total(k))
		# the ruling's instrumented fork: attribution needs the engines called separately
	for t in run_ticks:
		var before := t_stone.packet.pool_damp_total()
		t_sand.tick()
		if drift_watch and t_stone.packet.pool_damp_total() != before:
			print("FIRST DRIFT tick %d: SAND %d" % [t, before - t_stone.packet.pool_damp_total()])
			break
		t_water.tick()
		if drift_watch and t_stone.packet.pool_damp_total() != before:
			print("FIRST DRIFT tick %d: WATER %d" % [t, before - t_stone.packet.pool_damp_total()])
			break
		t_react.tick()
		if drift_watch and t_stone.packet.pool_damp_total() != before:
			print("FIRST DRIFT tick %d: REACT %d" % [t, before - t_stone.packet.pool_damp_total()])
			break
	var err: String = check.call([t_stone, t_water, o, t_sand])
	if err == "":
		var pk := t_stone.packet
		for i in GRID_W * GRID_H:
			if pk.pool_total(i) > pk.pool_capacity(i):
				err = "pool over capacity at %s" % pk.xy_of(i)
				break
	var drift_txt := drift_report(w0, t_stone.packet)
	var sub_txt := ""
	for k in 3:
		if t_sand.total(k) != s0[k]:
			sub_txt = " [subtile mass kind %d: %d -> %d]" % [k, s0[k], t_sand.total(k)]
	if err == "" and drift_txt == "" and sub_txt == "":
		print("PASS  %s" % name)
		return
	var why := err
	if why == "" and drift_txt != "":
		why = "conservation drifted"
	elif why == "" and sub_txt != "":
		why = "subtile mass changed"
	print("FAIL  %s -- %s%s%s" % [name, why, drift_txt, sub_txt])
	

## Conservation policy for the acceptance runner: every material but water is individually constant, and water pairs with damp (soak's sanctioned 1:1 channel). Scenes whose reactions transform matter override with their own sanctioned channels.
func drift_report(w0: PackedInt32Array, pk: TilePacket) -> String:
	var parts := PackedStringArray()
	for m in range(1, TilePacket.MAT_COUNT):
		var dm := w0[m] - pk.mat_total(m)
		if dm != 0:
			parts.append("%s %d" % [TilePacket.Mat.keys()[m].to_lower(), dm])
	var dwd := (w0[TilePacket.Mat.WATER] - pk.mat_total(TilePacket.Mat.WATER)) \
			+ (w0[TilePacket.MAT_COUNT] - pk.damp_total())
	if dwd != 0:
		parts.append("water+damp %d" % dwd)
	if parts.is_empty():
		return ""
	return " [drift: " + ", ".join(parts) + "]"
	
