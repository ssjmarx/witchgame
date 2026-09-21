## Shared harness for element test scenes: owns the grid trio, renderer, tick
## heartbeat, input plumbing, and paint/carve helpers. Element scenes extend
## this class and override the hooks (_setup, _dose, _tick_world, ...).

class_name TestSandbox
extends Node2D

const GRID_W := 15        # tiles across
const GRID_H := 15        # tiles down
const TILE := 16          # pixels per tile
const TEST_TICKS := 3000  # ticks each self-test runs before checking

# materials any sandbox can lay down; a scene exposes the subset it wants
enum Paint { STONE, WATER, SOIL, OIL }

var stone: GridStone
var water: GridWater
var renderer: ElementRenderer
var sprite: Sprite2D

var paint := Paint.WATER
var paused := false
var _last_info := ""  # last HUD text; skips label writes when unchanged

## Build the shared world, wire timer and signals, then hand off to _setup.
func _ready() -> void:
	stone = GridStone.new(GRID_W, GRID_H)
	water = GridWater.new(GRID_W, GRID_H, stone)
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

## Override: advance the sim one tick in fixed order (order is a ruling).
func _tick_world() -> void:
	water.tick()

## Override: reset everything the scene owns beyond the base pair.
func _clear_world() -> void:
	stone.clear()
	water.clear()

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

## Carve a diagram (s stone, w water 255, o oil 255, d soil 15, t soil 12, . air) wrapped in a stone U-shell; returns its origin.
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

## Headless example runner, shared by every acceptance suite: carve rows into a fresh full engine stack, run optional god-hand setup before the snapshot, tick to equilibrium under a per-engine drift watch, then check + pool legality + per-material conservation + subtile mass. Drift reports on every failure, so expectation bugs and leaks never mask each other.
@warning_ignore("shadowed_variable_base_class")
func _run_example(name: String, rows: Array, check: Callable, setup: Callable) -> void:
	var t_stone := GridStone.new(GRID_W, GRID_H)
	var t_water := GridWater.new(GRID_W, GRID_H, t_stone)
	var t_sand := GridSand.new(GRID_W, GRID_H, t_stone, t_water)
	var t_react := GridReactions.new(GRID_W, GRID_H, t_stone)
	var o := _carve_preset(t_stone, t_water, rows)
	if setup.is_valid():
		setup.call([t_stone, t_water, o, t_sand])
	var w0 := PackedInt32Array()
	for m in TilePacket.MAT_COUNT:
		w0.append(t_stone.packet.mat_total(m))
	w0.append(t_stone.packet.damp_total())
	var s0 := PackedInt32Array()
	for k in 3:
		s0.append(t_sand.total(k))
	for t in TEST_TICKS:
		var before := t_stone.packet.pool_damp_total()
		t_sand.tick()
		if t_stone.packet.pool_damp_total() != before:
			print("FIRST DRIFT tick %d: SAND %d" % [t, before - t_stone.packet.pool_damp_total()])
			break
		t_water.tick()
		if t_stone.packet.pool_damp_total() != before:
			print("FIRST DRIFT tick %d: WATER %d" % [t, before - t_stone.packet.pool_damp_total()])
			break
		t_react.tick()
		if t_stone.packet.pool_damp_total() != before:
			print("FIRST DRIFT tick %d: REACT %d" % [t, before - t_stone.packet.pool_damp_total()])
			break
	var err: String = check.call([t_stone, t_water, o, t_sand])
	if err == "":
		var pk := t_stone.packet
		for i in GRID_W * GRID_H:
			if pk.pool_total(i) > pk.pool_capacity(i):
				err = "pool over capacity at %s" % pk.xy_of(i)
				break
	var parts := PackedStringArray()
	var drift := 0
	for m in range(1, TilePacket.MAT_COUNT):   # water pairs with damp below -- soak is the sanctioned 1:1 channel
		var dm := w0[m] - t_stone.packet.mat_total(m)
		if dm != 0:
			drift += dm
			parts.append("%s %d" % [TilePacket.Mat.keys()[m].to_lower(), dm])
	var dwd := (w0[TilePacket.Mat.WATER] - t_stone.packet.mat_total(TilePacket.Mat.WATER)) \
			+ (w0[TilePacket.MAT_COUNT] - t_stone.packet.damp_total())
	if dwd != 0:
		drift += dwd
		parts.append("water+damp %d" % dwd)
	var drift_txt := "" if parts.is_empty() else " [drift: " + ", ".join(parts) + "]"
	var sub_txt := ""
	for k in 3:
		if t_sand.total(k) != s0[k]:
			sub_txt = " [subtile mass kind %d: %d -> %d]" % [k, s0[k], t_sand.total(k)]
	if err == "" and drift == 0 and sub_txt == "":
		print("PASS  %s" % name)
		return
	var why := err
	if why == "" and drift != 0:
		why = "conservation drifted"
	elif why == "" and sub_txt != "":
		why = "subtile mass changed"
	print("FAIL  %s -- %s%s%s" % [name, why, drift_txt, sub_txt])
