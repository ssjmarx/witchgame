## Water sandbox — element sim v2.
## 1 stone / 2 water select material, LMB paints, RMB erases.
## K runs the six acceptance examples headlessly and reports PASS/FAIL.

extends Node2D

const GRID_W := 15        # tiles across
const GRID_H := 15        # tiles down
const TILE := 16          # pixels per tile
const PAINT_DOSE := 64    # water units added per tick while painting
const TEST_TICKS := 3000  # ticks each self-test runs before checking

# materials the mouse can lay down
enum Paint { STONE, WATER }

# F1-F6 acceptance diagrams: s stone, w water (255 units), a air
const PRESETS := {
	KEY_F1: [
		"saaas",
		"swsas",
		"swsas",
		"swsas",
		"swaas",
		"sssss",
	],
	KEY_F2: [
		"sssss",
		"swsas",
		"swsas",
		"swsas",
		"swaas",
		"sssss",
	],
	KEY_F3: [
		"wwwwwww",
		"wsssssw",
		"wsaaasw",
		"wwwwwww",
	],
	KEY_F4: [
		"wwwwwww",
		"wssassw",
		"wsaaasw",
		"wsaaasw",
		"wwwwwww",
	],
	KEY_F5: [
		"wsa",
		"wsa",
		"wsa",
		"wsw",
		"waw",
	],
	KEY_F6: [
		"sssss",
		"swaas",
		"swsas",
		"swaas",
		"sssss",
	],
}

# the sim trio and its display
var stone: GridStone
var water: GridWater
var renderer: ElementRenderer
var sprite: Sprite2D

# editor state
var paint := Paint.WATER
var paused := false
var _last_info := ""  # last HUD text; skips label writes when unchanged

## Build the grids and renderer, wire timer and signals, load demo F1.
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
	_load_preset(KEY_F1)

## Fixed-step heartbeat: dose held-mouse water, tick the sim, redraw.
func _on_tick() -> void:
	if paused:
		return
	# tick-driven painting keeps water doses deterministic
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and paint == Paint.WATER:
		var t := _hover_tile()
		if t.x >= 0:
			water.add_water(t.x, t.y, PAINT_DOSE)
	water.tick()
	renderer.redraw()

## Track the hover tile; RMB erases, LMB lays stone; refresh the HUD.
func _process(_delta: float) -> void:
	var t := _hover_tile()
	var dirty := t != renderer.hover
	renderer.hover = t
	# RMB erases both layers; LMB paints stone (water dosing happens on tick)
	if t.x >= 0:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			water.set_water(t.x, t.y, 0)
			stone.set_terrain(t.x, t.y, GridStone.Terrain.AIR)
			dirty = true
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and paint == Paint.STONE:
			water.set_water(t.x, t.y, 0)
			dirty = stone.set_terrain(t.x, t.y, GridStone.Terrain.STONE) or dirty
	if dirty:
		renderer.redraw()
	_update_info(t)

## Hotkeys: F1-F6 presets, 1/2 material, SPC pause, T step, X clear, G debug, K tests.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var k: int = key.keycode
	if PRESETS.has(k):
		_load_preset(k)
		return
	match k:
		KEY_1:
			paint = Paint.STONE
		KEY_2:
			paint = Paint.WATER
		KEY_SPACE:
			paused = not paused
		KEY_T:
			if paused:
				water.tick()
				renderer.redraw()
		KEY_X:
			stone.clear()
			water.clear()
			renderer.redraw()
		KEY_G:
			renderer.debug = not renderer.debug
			renderer.redraw()
		KEY_K:
			run_self_tests()
			run_packet_tests()

## Tile under the mouse, or (-1, -1) when off the grid.
func _hover_tile() -> Vector2i:
	var p := get_global_mouse_position()
	var t := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
	if t.x < 0 or t.y < 0 or t.x >= GRID_W or t.y >= GRID_H:
		return Vector2i(-1, -1)
	return t

## Carve a diagram wrapped in a stone U-shell (open top); returns its origin.
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
			match row[x]:
				"s":
					p_stone.set_terrain(ox + x, oy + y, GridStone.Terrain.STONE)
				"w":
					p_water.set_water(ox + x, oy + y, 255)
				_:
					pass
	return Vector2i(ox, oy)

## Reset both grids and carve the demo bound to a preset key.
func _load_preset(keycode: int) -> void:
	stone.clear()
	water.clear()
	_carve_preset(stone, water, PRESETS[keycode])
	paused = false
	renderer.redraw()

## Run the six acceptance examples headlessly and report PASS/FAIL.
func run_self_tests() -> void:
	print("── water self-tests, %d ticks each ──" % TEST_TICKS)
	# each check receives [stone, water, origin] and returns "" on pass, else the failure
	var check_ex1 := func(s: Array) -> String:
		var w: GridWater = s[1]
		var o: Vector2i = s[2]
		var l := w.get_water(o.x + 1, o.y + 3)
		var r := w.get_water(o.x + 3, o.y + 3)
		if absi(l - r) > 8:
			return "arms unequal: %d vs %d" % [l, r]
		if l + r < 250 or l + r > 260:
			return "arms hold %d, want 255" % (l + r)
		for x in 3:
			if w.get_water(o.x + 1 + x, o.y + 4) != 255:
				return "bottom row not full at x=%d" % x
		return ""
	var check_ex2 := func(s: Array) -> String:
		var w: GridWater = s[1]
		var o: Vector2i = s[2]
		for c in [[2, 4], [3, 4], [3, 1], [3, 2], [3, 3]]:
			if w.get_water(o.x + c[0], o.y + c[1]) != 0:
				return "sealed pocket took water at %s" % c
		for y in range(1, 5):
			if w.get_water(o.x + 1, o.y + y) != 255:
				return "column drained at y=%d" % y
		return ""
	var check_ex3a := func(s: Array) -> String:
		var w: GridWater = s[1]
		var o: Vector2i = s[2]
		for x in [2, 3, 4]:
			if w.get_water(o.x + x, o.y + 2) != 0:
				return "sealed cave took water at x=%d" % x
		for x in 7:
			if w.get_water(o.x + x, o.y) != 255:
				return "ceiling row changed at x=%d" % x
		return ""
	var check_ex3b := func(s: Array) -> String:
		var w: GridWater = s[1]
		var o: Vector2i = s[2]
		for x in 7:
			if w.get_water(o.x + x, o.y) >= GridWater.LINE:
				return "ceiling row not drained at x=%d" % x
		for y in range(1, 5):
			for x in 7:
				if not w.stone.is_solid(o.x + x, o.y + y) \
						and w.get_water(o.x + x, o.y + y) < 240:
					return "cell x=%d y=%d only %d" % [x, y, w.get_water(o.x + x, o.y + y)]
		return ""
	var check_ex5 := func(s: Array) -> String:
		var w: GridWater = s[1]
		var o: Vector2i = s[2]
		if w.get_water(o.x + 1, o.y + 4) < 240:
			return "bottom pocket only %d" % w.get_water(o.x + 1, o.y + 4)
		for p in [[0, 2], [2, 2], [0, 3], [2, 3], [0, 4], [2, 4]]:
			if w.get_water(o.x + p[0], o.y + p[1]) < 240:
				return "cell %s underfilled" % p
		for y in 2:
			if w.get_water(o.x, o.y + y) >= GridWater.LINE \
					or w.get_water(o.x + 2, o.y + y) >= GridWater.LINE:
				return "water stranded above the common level at y=%d" % y
		return ""
	var check_ex6 := func(s: Array) -> String:
		var w: GridWater = s[1]
		var o: Vector2i = s[2]
		for y in 4:
			for x in 5:
				if s[0].is_solid(o.x + x, o.y + y):
					continue
				var v := w.get_water(o.x + x, o.y + y)
				if y < 3 and v >= GridWater.LINE:
					return "water above the floor at %d,%d" % [x, y]
				if y == 3 and v < 250:
					return "floor cell %d,%d only %d" % [x, y, v]
		return ""
	_test("Ex1  U-tube equalizes", KEY_F1, check_ex1)
	_test("Ex2  sealed pocket frozen", KEY_F2, check_ex2)
	_test("Ex3a sealed cave stays dry", KEY_F3, check_ex3a)
	_test("Ex3b cave floods, ceiling drains", KEY_F4, check_ex3b)
	_test("Ex5  bottom pocket floods, columns level", KEY_F5, check_ex5)
	_test("Ex6  rotation around stone", KEY_F6, check_ex6)
	print("── done ──")

## Packet unit tests — pure TilePacket behavior, no carving, instant.
func run_packet_tests() -> void:
	print("── packet unit tests ──")
	var check_drain := func() -> String:
		var pk := TilePacket.new(4, 4)
		var i := pk.idx(2, 2)
		if pk.add_pool(i, TilePacket.Mat.WATER, 10) != 10:
			return "water add refused"
		if pk.add_pool(i, TilePacket.Mat.STEAM, 30) != 30:
			return "steam add refused"
		var got := pk.drain_lightest(i, 25)
		if got != 25:
			return "first drain took %d, want 25" % got
		if pk.get_pool(i, TilePacket.Mat.STEAM) != 5:
			return "steam left %d, want 5" % pk.get_pool(i, TilePacket.Mat.STEAM)
		got = pk.drain_lightest(i, 999)
		if got != 5:
			return "second drain took %d, want 5" % got
		if pk.get_pool(i, TilePacket.Mat.WATER) != 10:
			return "water disturbed: %d" % pk.get_pool(i, TilePacket.Mat.WATER)
		if not pk.assert_all():
			return "ledger drifted"
		return ""
		
	var check_displace := func() -> String:
		var pk := TilePacket.new(4, 4)
		var i := pk.idx(1, 1)
		if pk.add_pool(i, TilePacket.Mat.WATER, 255) != 255:
			return "fill refused"
		var deficit := pk.set_sub(i, 0, 1)
		if deficit != 64:
			return "deficit %d, want 64" % deficit
		# ejection loop from the drain_lightest ruling — the flow engine's eventual job, rehearsed here
		var guard := 0
		while deficit > 0 and guard < TilePacket.MAT_COUNT:
			deficit -= pk.drain_lightest(i, deficit)
			guard += 1
		if deficit != 0:
			return "ejection stalled, %d left" % deficit
		if pk.pool_total(i) != 191:
			return "pool %d after ejection, want 191" % pk.pool_total(i)
		if not pk.assert_all():
			return "ledger drifted"
		return ""
		
	var check_clearmat := func() -> String:
		var pk := TilePacket.new(4, 4)
		pk.add_pool(pk.idx(1, 1), TilePacket.Mat.WATER, 100)
		pk.add_pool(pk.idx(2, 2), TilePacket.Mat.WATER, 50)
		if pk.mat_total(TilePacket.Mat.WATER) != 150:
			return "setup total wrong"
		pk.clear_mat(TilePacket.Mat.WATER)
		if pk.mat_total(TilePacket.Mat.WATER) != 0:
			return "column not empty"
		if not pk.assert_all():
			return "ledger drifted"
		return ""
		
	var check_clamp := func() -> String:
		var pk := TilePacket.new(4, 4)
		var i := pk.idx(1, 1)
		var got := pk.add_pool(i, TilePacket.Mat.WATER, 300)
		if got != 255:
			return "add_pool returned %d, want 255" % got
		if pk.add_pool(i, TilePacket.Mat.OIL, 10) != 0:
			return "full tile accepted oil"
		if pk.pool_total(i) != 255:
			return "tile holds %d, want 255" % pk.pool_total(i)
		if not pk.assert_all():
			return "ledger drifted"
		return ""
		
	_ptest("PT1  drain_lightest grader", check_drain)
	_ptest("PT2  set_sub reports displacement deficit", check_displace)
	_ptest("PT3  clear_mat books the removal", check_clearmat)
	_ptest("PT4  > 255 capacity rejected", check_clamp)
	print("── done ──")

## PASS/FAIL runner for the packet tests (mirror of _test, no carving).
func _ptest(name: String, fn: Callable) -> void:
	var err: String = fn.call()
	if err == "":
		print("PASS  %s" % name)
	else:
		print("FAIL  %s — %s" % [name, err])

## Carve one example fresh, run it to equilibrium, report PASS/FAIL/leak.
@warning_ignore("shadowed_variable_base_class")
func _test(name: String, preset_key: int, check: Callable) -> void:
	var t_stone := GridStone.new(GRID_W, GRID_H)
	var t_water := GridWater.new(GRID_W, GRID_H, t_stone)
	var o := _carve_preset(t_stone, t_water, PRESETS[preset_key])
	var t0 := t_water.total()
	for t in TEST_TICKS:
		t_water.tick()
	var err: String = check.call([t_stone, t_water, o])
	if err != "":
		print("FAIL  %s — %s" % [name, err])
	elif t_water.total() != t0:
		print("FAIL  %s — leaked %d units" % [name, t0 - t_water.total()])
	else:
		print("PASS  %s" % name)

## Rebuild the HUD line (pause state, hover tile, band) when it changes.
func _update_info(t: Vector2i) -> void:
	var info := "PAUSED (T steps)" if paused else ""
	if t.x >= 0:
		var w := water.get_water(t.x, t.y)
		var bands := ["DRY", "WET", "HALF", "FULL"]
		if info != "":
			info += "   "
		info += "tile %d,%d   water %3d   lines %2d   %s" % [t.x, t.y, w, w >> 4, bands[water.get_level(t.x, t.y)]]
	if info != _last_info:
		_last_info = info
		$UI/Hint.text = "1 stone  2 water  LMB paint  RMB erase\nSPC pause  T step  X clear  G debug  K tests  F1-F6 demos\n" + info

## No-op: redraws already ride the tick; keeps the signal wiring visible.
func _on_levels_changed(_cells) -> void:
	pass
