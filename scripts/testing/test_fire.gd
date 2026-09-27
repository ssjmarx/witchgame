## Fire sandbox -- the fire lab whole: gases below, the fire solver, ignition
## delay, and condensation, with the gas and fire acceptance suites on K.
## 1 stone / 2 water / 3 oil / 4 wood / 5 steam / 6 smoke / 7 soil / 8 damp, I ignites at hover, LMB doses, RMB erases.

extends TestSandbox

const PAINT_DOSE := 64    # units dosed per tick while the mouse is held
const DAMP_DOSE := 32     # damp units per tick while the damp ink is held

# demos (rows top-to-bottom): s stone, w water 255, o oil 255, W wood + fuel 255, v steam 255, m smoke 255, . air
const PRESETS := {
	KEY_F1: [
		"WWW",
		"W.W",
		"WvW",
	],
	KEY_F2: [
		"WWWWWWWWWW",
		"Wvv......W",
		"..........",
	],
	KEY_F3: [
		"WW",
		"ww",
		"ww",
		"vv",
	],
	KEY_F4: [
		"WWWW....",
		"vv......",
	],
	KEY_F5: [
		"sssss",
		"s...s",
		"s.v.s",
		"sssss",
	],
	KEY_F7: [
		"WWW",
		"WmW",
		"WvW",
		"...",
	],
	KEY_F9: [
		"WW",
	],
	KEY_F10: [
		"WWWWWWW",
		"WvvvvmW",
		"WvvvmmW",
		"WvvmmmW",
		"WvmmmmW",
		"WmmmmmW",
	],
	KEY_F11: [
		"sss",
		"s.s",
		"s.s",
		"sWs",
		"sss",
	],
	KEY_F12: [
		"W.",
		"W.",
		"W.",
		"W.",
		"W.",
	],
}

var sand: GridSand
var react: GridReactions
var mannequin := ThermalBody.new()
var mannequin_tile := Vector2i(7, 7)
var mannequin_sprite: Sprite2D

## Build the full engine stack and load the rise demo.
func _setup() -> void:
	sand = room.sand
	react = room.react
	_load_preset(KEY_F1)
	mannequin_sprite = Sprite2D.new()
	mannequin_sprite.centered = false
	mannequin_sprite.texture = _mannequin_texture()
	mannequin_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(mannequin_sprite)
	_mannequin_place()
	room.bridge.register(mannequin)

## Tick-boundary dosing: held-mouse liquids and gases at PAINT_DOSE, soil one subtile, damp at DAMP_DOSE, wood whole tiles.
func _dose() -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var t := _hover_tile()
	if t.x < 0:
		return
	match paint:
		Paint.WATER:
			water.add_water(t.x, t.y, PAINT_DOSE)
		Paint.OIL:
			water.add_liquid(t.x, t.y, TilePacket.Mat.OIL, PAINT_DOSE)
		Paint.STEAM:
			water.add_liquid(t.x, t.y, TilePacket.Mat.STEAM, PAINT_DOSE)
		Paint.SMOKE:
			water.add_liquid(t.x, t.y, TilePacket.Mat.SMOKE, PAINT_DOSE)
		Paint.WOOD:
			_place_wood(t)
		Paint.SOIL:
			_brush_soil(t)
		Paint.DAMP:
			stone.packet.add_damp(stone.idx(t.x, t.y), DAMP_DOSE)
		_:
			pass

## Reset the sand engine, the damp books, the fire columns, and the reaction overlays along with the shared world.
func _clear_world() -> void:
	super()
	sand.clear()
	react.clear()
	stone.packet.clear_damp()
	stone.packet.clear_fuel()
	stone.packet.clear_fire()

## Held strokes: RMB erases everything the fire lab can author; LMB lays stone over cleared cells.
func _paint_stroke(t: Vector2i) -> bool:
	var i := stone.idx(t.x, t.y)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		stone.packet.set_sub(i, TilePacket.K_SOIL, 0)
		water.set_water(t.x, t.y, 0)
		stone.packet.set_pool(i, TilePacket.Mat.OIL, 0)
		stone.packet.set_pool(i, TilePacket.Mat.STEAM, 0)
		stone.packet.set_pool(i, TilePacket.Mat.SMOKE, 0)
		stone.packet.set_fuel(i, 0)
		stone.packet.set_fire(i, 0)
		stone.set_terrain(t.x, t.y, GridStone.Terrain.AIR)
		return true
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and paint == Paint.STONE:
		stone.packet.set_sub(i, TilePacket.K_SOIL, 0)
		water.set_water(t.x, t.y, 0)
		return stone.set_terrain(t.x, t.y, GridStone.Terrain.STONE)
	return false

## Lay a wood tile with a full fuel tank (god hand -- no flow stamp, no fire; refuses occupied ground).
func _place_wood(t: Vector2i) -> void:
	var i := stone.idx(t.x, t.y)
	if stone.packet.get_terrain(i) != TilePacket.T.AIR or stone.packet.pool_total(i) > 0:
		return
	stone.set_terrain(t.x, t.y, GridStone.Terrain.WOOD)
	stone.packet.set_fuel(i, 255)

## Paint one soil subtile into the lowest empty slot of tile t (brush is a god hand -- no flow stamp).
func _brush_soil(t: Vector2i) -> void:
	var i := stone.idx(t.x, t.y)
	var n: int = stone.packet.get_sub(i, TilePacket.K_SOIL)
	for bit in [GridSand.BL, GridSand.BR, GridSand.TL, GridSand.TR]:
		if (n & bit) == 0:
			stone.packet.set_sub(i, TilePacket.K_SOIL, n | bit)
			return

## God ignite at the hover tile: fuel catches if its gates pass; bare air sparks; wet fuel hisses.
func _god_ignite() -> void:
	var t := _hover_tile()
	if t.x < 0:
		return
	if not react.ignite(t.x, t.y):
		print("hiss -- damp fuel refuses the match")

## Scene keys: F1-F5, F7, F9-F12 demos, 1-8 select material, I ignites at hover, K runs both suites.
func _handle_key(k: int) -> bool:
	if PRESETS.has(k):
		_load_preset(k)
		return true
	match k:
		KEY_1:
			paint = Paint.STONE
		KEY_2:
			paint = Paint.WATER
		KEY_3:
			paint = Paint.OIL
		KEY_4:
			paint = Paint.WOOD
		KEY_5:
			paint = Paint.STEAM
		KEY_6:
			paint = Paint.SMOKE
		KEY_7:
			paint = Paint.SOIL
		KEY_8:
			paint = Paint.DAMP
		KEY_I:
			_god_ignite()
		KEY_K:
			run_suite()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			_step_mannequin(k)
			return true
		KEY_Y:
			mannequin.heat = mini(ThermalBody.HEAT_MAX, mannequin.heat + 16)
		KEY_H:
			mannequin.heat = maxi(0, mannequin.heat - 16)
		KEY_U:
			mannequin.wetness = mini(ThermalBody.WETNESS_MAX, mannequin.wetness + 16)
		KEY_J:
			mannequin.wetness = maxi(0, mannequin.wetness - 16)
		_:
			return false
	return true

## Controls listing for the fire sandbox.
func _hint_header() -> String:
	return "1 stone  2 water  3 oil  4 wood  5 steam  6 smoke  7 soil  8 damp  I ignite  LMB dose  RMB erase\nSPC pause  T step  X clear  G debug  K tests  F1-F5, F7, F9-F12 demos (F6/F8 dead)\narrows move the body   Y/H heat   U/J wetness\n"

## Live readout: the base water line plus the hovered tile's fuel, fire, ignition timer, gases, and damp.
func _info_line(t: Vector2i) -> String:
	var info := super(t)
	if t.x >= 0:
		var i := stone.idx(t.x, t.y)
		info += "   fuel %d   fire %d   ign %d   steam %d   smoke %d   damp %d/%d" % [
			stone.packet.get_fuel(i), stone.packet.get_fire(i), react.get_ignition(t.x, t.y),
			stone.packet.get_pool(i, TilePacket.Mat.STEAM),
			stone.packet.get_pool(i, TilePacket.Mat.SMOKE),
			stone.packet.get_damp(i), stone.packet.damp_capacity(i)]
	info += "   body heat %3d   wet %3d" % [mannequin.heat, mannequin.wetness]
	return info

## Reset the full stack and carve the demo bound to a preset key.
func _load_preset(keycode: int) -> void:
	sand.clear()
	water.clear()
	stone.clear()
	react.clear()
	stone.packet.clear_damp()
	stone.packet.clear_fuel()
	stone.packet.clear_fire()
	_carve_preset(stone, water, PRESETS[keycode])
	paused = false
	renderer.redraw()

## Fire-lab conservation policy: water, steam, and damp are one closed trio (boil and condensation trade inside it); fuel and oil burn to smoke at 4:1 as a production rate -- smoke never shrinks, and never grows faster than four per unit burned.
func drift_report(w0: PackedInt32Array, pk: TilePacket) -> String:
	var trio := (w0[TilePacket.Mat.WATER] - pk.mat_total(TilePacket.Mat.WATER)) \
			+ (w0[TilePacket.Mat.STEAM] - pk.mat_total(TilePacket.Mat.STEAM)) \
			+ (w0[TilePacket.MAT_COUNT] - pk.damp_total())
	var burned := (w0[TilePacket.MAT_COUNT + 1] - pk.fuel_total()) \
			+ (w0[TilePacket.Mat.OIL] - pk.mat_total(TilePacket.Mat.OIL))
	var smoke_made := pk.mat_total(TilePacket.Mat.SMOKE) - w0[TilePacket.Mat.SMOKE]
	var parts := PackedStringArray()
	if trio != 0:
		parts.append("water+steam+damp %d" % trio)
	if smoke_made < 0:
		parts.append("smoke vanished %d" % smoke_made)
	elif smoke_made > 4 * burned:
		parts.append("smoke %d over 4x burned %d" % [smoke_made, burned])
	if parts.is_empty():
		return ""
	return " [drift: " + ", ".join(parts) + "]"

## Gas acceptance examples -- rise, ceiling spread, bubbling, the lip, the sealed cavity, stratification, and (revised for condensation) the rain cycle. Wood-lined where stone would drizzle.
func run_gas_tests() -> void:
	print("== gas self-tests, %d ticks each ==" % TEST_TICKS)
	run_ticks = TEST_TICKS
	drift_watch = true
	var check_fuel_books := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		if pk.fuel_total() != 510:
			return "fuel total %d, want 510 — the carve or the ledger is lying" % pk.fuel_total()
		var o0: Vector2i = s[2]
		for dx in 2:
			if pk.get_terrain(pk.idx(o0.x + dx, o0.y)) != TilePacket.T.WOOD:
				return "wood terrain did not survive the run at column %d" % dx
		return ""

	var check_rise := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_pool(pk.idx(o.x + 1, o.y + 1), TilePacket.Mat.STEAM) != 255:
			return "steam under the wood ceiling is %d, want 255" % pk.get_pool(pk.idx(o.x + 1, o.y + 1), TilePacket.Mat.STEAM)
		if pk.get_pool(pk.idx(o.x + 1, o.y + 2), TilePacket.Mat.STEAM) != 0:
			return "steam left behind below"
		return ""

	var check_spread := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for dx in range(1, 9):
			var v := pk.get_pool(pk.idx(o.x + dx, o.y + 1), TilePacket.Mat.STEAM)
			if v < 48 or v > 80:
				return "ceiling tile %d holds %d, want ~64" % [dx, v]
		return ""

	var check_cycle := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.mat_total(TilePacket.Mat.STEAM) != 0:
			return "steam %d remains -- the rain never finished" % pk.mat_total(TilePacket.Mat.STEAM)
		for dx in 2:
			for ty in [1, 2, 3]:
				var i := pk.idx(o.x + dx, o.y + ty)
				if pk.get_pool(i, TilePacket.Mat.WATER) != 255:
					return "column %d row %d water is %d, want 255" % [dx, ty, pk.get_pool(i, TilePacket.Mat.WATER)]
		return ""

	var check_lip := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var residue := 0
		for y in range(o.y, GRID_H):
			for x in GRID_W:
				var v := pk.get_pool(pk.idx(x, y), TilePacket.Mat.STEAM)
				if v >= GridWater.LINE:
					return "a visible steam pocket stayed at or below the diagram (%d at %d,%d)" % [v, x, y]
				residue += v
		if residue > 16:
			return "stranded film is %d units, want <= 16" % residue
		return ""

	var check_rain := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.mat_total(TilePacket.Mat.STEAM) != 0:
			return "steam %d remains in the cavity" % pk.mat_total(TilePacket.Mat.STEAM)
		for dx in 3:
			var w := pk.get_pool(pk.idx(o.x + 1 + dx, o.y + 2), TilePacket.Mat.WATER)
			if w < 64 or w > 107:
				return "cavity floor tile %d holds %d water, want ~85" % [dx, w]
			if pk.get_pool(pk.idx(o.x + 1 + dx, o.y + 1), TilePacket.Mat.WATER) != 0:
				return "water lingers under the ceiling at column %d" % dx
		return ""

	var check_stratify := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_pool(pk.idx(o.x + 1, o.y + 1), TilePacket.Mat.STEAM) != 255:
			return "steam did not sort above smoke — %d under the ceiling" % pk.get_pool(pk.idx(o.x + 1, o.y + 1), TilePacket.Mat.STEAM)
		if pk.get_pool(pk.idx(o.x + 1, o.y + 2), TilePacket.Mat.SMOKE) != 255:
			return "smoke did not sort below steam — %d remains" % pk.get_pool(pk.idx(o.x + 1, o.y + 2), TilePacket.Mat.SMOKE)
		return ""
		
	var check_level := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var lateral := pk.get_pool(pk.idx(o.x + 1, o.y + 2), TilePacket.Mat.SMOKE) \
				+ pk.get_pool(pk.idx(o.x + 3, o.y + 2), TilePacket.Mat.SMOKE)
		if lateral < 8:
			return "the blocked column spread only %d at its own level — the hop-first cone is back" % lateral
		if pk.get_pool(pk.idx(o.x + 2, o.y + 3), TilePacket.Mat.SMOKE) == 0:
			return "the column pistoned away whole — lateral spread never ran"
		return ""

	var check_diagonal := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var stray := 0
		for dy in 5:
			for dx in 5:
				var i := pk.idx(o.x + 1 + dx, o.y + 1 + dy)
				if dy < 2:
					stray += pk.get_pool(i, TilePacket.Mat.SMOKE)
				else:
					stray += pk.get_pool(i, TilePacket.Mat.STEAM)
		if stray > 8:
			return "the interface holds %d stray units, want <= 8 -- the relaxation stalled" % stray
		return ""

	var check_rim := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var took := pk.get_pool(pk.idx(o.x + 12, o.y + 1), TilePacket.Mat.SMOKE)
		if took != 127:
			return "the rim column took %d on tick one, want 127 -- the lateral export is broken" % took
		if pk.get_pool(pk.idx(o.x + 12, o.y), TilePacket.Mat.SMOKE) != 0:
			return "smoke hopped past the rim on tick one -- the hop outranks lateral again"
		return ""

	_run_example("GT0  fuel books and wood survives a run", PRESETS[KEY_F9], check_fuel_books, Callable())
	_run_example("GT1  steam rises and pools under a ceiling", PRESETS[KEY_F1], check_rise, Callable())
	_run_example("GT2  pinned gas levels along the ceiling", PRESETS[KEY_F2], check_spread, Callable())
	_run_example("GT3  steam bubbles up, then rains back", PRESETS[KEY_F3], check_cycle, Callable())
	_run_example("GT4  gas rounds the lip, a film remains", PRESETS[KEY_F4], check_lip, Callable())
	_run_example("GT5  the sealed stone cavity rains — the C4 chain", PRESETS[KEY_F5], check_rain, Callable())
	_run_example("GT6  steam sorts above smoke", PRESETS[KEY_F7], check_stratify, Callable())
	run_ticks = 3000
	_run_example("GT7  a frozen diagonal relaxes to a flat interface", PRESETS[KEY_F10], check_diagonal, Callable())
	run_ticks = 1   # window: one tick -- the unit differentials read the first move, not the equilibrium
	_run_example("GT8  the pocket exports laterally into its rim column", ["WWWWWWWWWWWW..", "mmmmmmmmmmmm.."], check_rim, Callable())
	_run_example("GT9  a backed-up column spreads at its own level", ["sssss", "..m..", "..m..", "..m.."], check_level, Callable())
	run_ticks = TEST_TICKS
	print("== done ==")

## Fire acceptance examples -- the solver's core: front pace, burnout, the choke, the siege, the ladder, condensation distance, the climb. Timing tests run short and restore.
func run_fire_tests() -> void:
	print("== fire self-tests ==")
	drift_watch = false   # fire creates smoke inside the tick; the end-state policy books it, the per-engine watch cannot
	var setup_ignite_end := func(s: Array) -> void:
		var r: GridReactions = s[4]
		var o: Vector2i = s[2]
		r.ignite(o.x, o.y)
	var setup_wet_log := func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var r: GridReactions = s[4]
		var o: Vector2i = s[2]
		pk.add_damp(pk.idx(o.x + 1, o.y), 64)
		r.ignite(o.x, o.y)
	var setup_siege := func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var r: GridReactions = s[4]
		var o: Vector2i = s[2]
		pk.add_damp(pk.idx(o.x + 1, o.y), 64)
		r.ignite(o.x, o.y)
		r.ignite(o.x + 2, o.y)
	var setup_tier := func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var i := pk.idx(o.x + 1, o.y + 1)
		pk.set_pool(i, TilePacket.Mat.OIL, 6)
		pk.set_pool(i, TilePacket.Mat.WATER, 249)
		pk.set_fire(i, 15)
	var setup_dist := func(s: Array) -> void:
		var r: GridReactions = s[4]
		var o: Vector2i = s[2]
		r.ignite(o.x + 6, o.y + 1)
	var setup_climb := func(s: Array) -> void:
		var r: GridReactions = s[4]
		var o: Vector2i = s[2]
		r.ignite(o.x, o.y + 4)

	var check_burn := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for dx in 8:
			var i := pk.idx(o.x + dx, o.y)
			if pk.get_terrain(i) != TilePacket.T.AIR:
				return "beam tile %d did not burn through to air" % dx
			if pk.get_fuel(i) != 0 or pk.get_fire(i) != 0:
				return "beam tile %d holds fuel %d fire %d" % [dx, pk.get_fuel(i), pk.get_fire(i)]
		if pk.mat_total(TilePacket.Mat.SMOKE) != 8 * 255 * 4:
			return "vented smoke %d, want %d exactly" % [pk.mat_total(TilePacket.Mat.SMOKE), 8 * 255 * 4]
		return ""

	var check_niche := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var iw := pk.idx(o.x + 1, o.y + 3)
		if pk.get_fire(iw) != 0:
			return "fire still alive in the sealed niche"
		if pk.get_terrain(iw) != TilePacket.T.WOOD:
			return "the niche wood burned through — it should have choked first"
		var fuel := pk.get_fuel(iw)
		if fuel < 96 or fuel > 160:
			return "choked fuel %d, want 96..160" % fuel
		if pk.mat_total(TilePacket.Mat.SMOKE) < 480:
			return "the niche holds only %d smoke — it did not fill" % pk.mat_total(TilePacket.Mat.SMOKE)
		return ""

	var check_refuse := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_terrain(pk.idx(o.x, o.y)) != TilePacket.T.AIR:
			return "the dry log did not burn out"
		var iw := pk.idx(o.x + 1, o.y)
		if pk.get_damp(iw) != 0:
			return "the siege never dried the log (damp %d)" % pk.get_damp(iw)
		if pk.get_terrain(iw) != TilePacket.T.WOOD or pk.get_fuel(iw) != 255 or pk.get_fire(iw) != 0:
			return "the wet log did not survive intact (fuel %d fire %d)" % [pk.get_fuel(iw), pk.get_fire(iw)]
		return ""

	var check_siege := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for dx in 3:
			var i := pk.idx(o.x + dx, o.y)
			if pk.get_terrain(i) != TilePacket.T.AIR or pk.get_fuel(i) != 0:
				return "tile %d did not burn through (fuel %d)" % [dx, pk.get_fuel(i)]
		return ""

	var check_tier := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		if pk.mat_total(TilePacket.Mat.WATER) != 217:
			return "water %d, want 217 (four bits boiled 32)" % pk.mat_total(TilePacket.Mat.WATER)
		if pk.mat_total(TilePacket.Mat.STEAM) != 32:
			return "steam %d, want 32" % pk.mat_total(TilePacket.Mat.STEAM)
		if pk.mat_total(TilePacket.Mat.OIL) != 0:
			return "oil %d, want 0" % pk.mat_total(TilePacket.Mat.OIL)
		if pk.mat_total(TilePacket.Mat.SMOKE) != 24:
			return "smoke %d, want 24 (six units at 4:1)" % pk.mat_total(TilePacket.Mat.SMOKE)
		return ""

	var check_dist := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var a := pk.get_pool(pk.idx(o.x + 1, o.y + 1), TilePacket.Mat.STEAM)
		var b := pk.get_pool(pk.idx(o.x + 8, o.y + 1), TilePacket.Mat.STEAM)
		if a != 233:
			return "free steam condensed to %d, want 233 (eleven ticks of drizzle)" % a
		if b != 255:
			return "suppressed steam lost %d, want no loss near fire" % (255 - b)
		return ""

	var check_climb := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		for ty in 5:
			var i := pk.idx(o.x, o.y + ty)
			if pk.get_terrain(i) != TilePacket.T.AIR or pk.get_fuel(i) != 0:
				return "wall row %d did not burn through" % ty
		return ""

	var check_pace := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		var f2 := pk.get_fire(pk.idx(o.x + 2, o.y))
		if f2 != 1:
			return "third tile fire nibble %d, want 1 (caught this tick, no engulf yet)" % f2
		if pk.get_fire(pk.idx(o.x + 3, o.y)) != 0:
			return "fourth tile already carries fire — the front is running hot"
		var fuel0 := pk.get_fuel(pk.idx(o.x, o.y))
		var fuel1 := pk.get_fuel(pk.idx(o.x + 1, o.y))
		if fuel0 != 15 or fuel1 != 135:
			return "pace fuels %d/%d, want 15/135 (ten and five burns)" % [fuel0, fuel1]
		return ""
	
	var setup_niche := func(s: Array) -> void:
		var r: GridReactions = s[4]
		var o: Vector2i = s[2]
		r.ignite(o.x + 1, o.y + 3)
		
	var setup_crack := func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		pk.set_sub(pk.idx(o.x + 3, o.y + 1), TilePacket.K_STONE, 15)
	var check_crack := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_pool(pk.idx(o.x + 2, o.y + 1), TilePacket.Mat.STEAM) != 255:
			return "the sealed slot lost steam — the subtile pillar did not close the corner"
		if pk.get_pool(pk.idx(o.x + 3, o.y), TilePacket.Mat.STEAM) != 0:
			return "the pillar side leaked %d steam up-diagonal" % pk.get_pool(pk.idx(o.x + 3, o.y), TilePacket.Mat.STEAM)
		return ""

	var setup_breath := func(s: Array) -> void:
		var pk: TilePacket = s[0].packet
		var r: GridReactions = s[4]
		var o: Vector2i = s[2]
		pk.set_pool(pk.idx(o.x + 1, o.y + 1), TilePacket.Mat.SMOKE, 200)
		r.ignite(o.x + 1, o.y + 2)
	var check_breath := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_pool(pk.idx(o.x + 1, o.y + 1), TilePacket.Mat.SMOKE) != 200:
			return "the intake took %d smoke — the chimney was the first-choice dump" % (pk.get_pool(pk.idx(o.x + 1, o.y + 1), TilePacket.Mat.SMOKE) - 200)
		if pk.get_pool(pk.idx(o.x + 2, o.y + 2), TilePacket.Mat.SMOKE) != 96:
			return "the open side holds %d smoke, want 96" % pk.get_pool(pk.idx(o.x + 2, o.y + 2), TilePacket.Mat.SMOKE)
		return ""

	var setup_jam := func(s: Array) -> void:
		var r: GridReactions = s[4]
		var o: Vector2i = s[2]
		r.ignite(o.x + 1, o.y + 3)
	var check_jam := func(s: Array) -> String:
		var pk: TilePacket = s[0].packet
		var o: Vector2i = s[2]
		if pk.get_fuel(pk.idx(o.x + 1, o.y + 3)) == 255:
			return "the fire never ran"
		var pocket := pk.get_pool(pk.idx(o.x + 3, o.y + 2), TilePacket.Mat.SMOKE)
		if pocket < 16:
			return "the pocket beside the column holds %d smoke — the traffic jam is back" % pocket
		return ""

	_run_example("FT1  the beam burns through to holes", ["WWWWWWWW"], check_burn, setup_ignite_end)
	_run_example("FT2  a sealed niche smothers on its own smoke", PRESETS[KEY_F11], check_niche, setup_niche)
	_run_example("FT3  a single log cannot light damp wood", ["WW"], check_refuse, setup_wet_log)
	_run_example("FT4  two fires siege the damp out and catch", ["WWW"], check_siege, setup_siege)
	run_ticks = 1
	_run_example("FT5  four bits boil standing water in place", ["...", "s.s", "sss"], check_tier, setup_tier)
	run_ticks = 11
	_run_example("FT6  condensation keeps its distance from fire", ["sss....sss", "svs...Wsvs"], check_dist, setup_dist)
	run_ticks = TEST_TICKS
	_run_example("FT7  the front climbs a wall at two tiles a second", PRESETS[KEY_F12], check_climb, setup_climb)
	run_ticks = 10
	_run_example("FT8  the front walks two tiles per second", ["WWWWWWWW"], check_pace, setup_ignite_end)
	run_ticks = 8
	_run_example("FT9  a fed column fills the pocket beside it", ["sssss", "sssss", ".s...", ".W.W."], check_jam, setup_jam)
	run_ticks = TEST_TICKS
	_run_example("FT10 a subtile pillar seals the diagonal crack", ["..W.", ".Wv.", "..WW"], check_crack, setup_crack)
	run_ticks = 1
	_run_example("FT11 smoke vents into the breath, not the intake", ["sss", "s.s", ".W."], check_breath, setup_breath)
	run_ticks = TEST_TICKS
	drift_watch = true   # the fire family creates matter in-tick; the watch ends after them
	print("== done ==")
	
## The fire lab's whole suite behind one door: gas, fire, and bridge examples; K and run_all both call this.
func run_suite() -> bool:
	suite_pass = 0
	suite_fail = 0
	run_gas_tests()
	run_fire_tests()
	run_bridge_tests()
	return suite_fail == 0

## The mannequin's white 16x16 quad -- modulate carries its state (red heat, blue wetness); the CA image stays the world's picture.
func _mannequin_texture() -> ImageTexture:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)

## Per-frame: the sandbox's pass, then the mannequin's picture -- state lands at tick speed, the color refreshes at frame speed.
func _process(delta: float) -> void:
	super._process(delta)
	mannequin_sprite.position = Vector2(mannequin_tile.x * TILE, mannequin_tile.y * TILE)
	mannequin_sprite.modulate = Color(0.2 + 0.8 * mannequin.heat / float(ThermalBody.HEAT_MAX), 0.25, 0.2 + 0.8 * mannequin.wetness / float(ThermalBody.WETNESS_MAX))
	
## Write the body's frame-side truth: the occupied tile, and the support one below -- the witch's real support resolution arrives with her collision mirror.
func _mannequin_place() -> void:
	mannequin.tiles = [mannequin_tile]
	mannequin.support = mannequin_tile + Vector2i(0, 1)

## One tile per press, clamped to the grid; the body follows.
func _step_mannequin(k: int) -> void:
	match k:
		KEY_LEFT:
			mannequin_tile.x = maxi(0, mannequin_tile.x - 1)
		KEY_RIGHT:
			mannequin_tile.x = mini(GRID_W - 1, mannequin_tile.x + 1)
		KEY_UP:
			mannequin_tile.y = maxi(0, mannequin_tile.y - 1)
		KEY_DOWN:
			mannequin_tile.y = mini(GRID_H - 1, mannequin_tile.y + 1)
	_mannequin_place()

## Bridge acceptance examples: fresh Rooms with registered bodies, driven directly -- the exchanges, the dunk, and the first PRNG-consuming determinism proof.
func run_bridge_tests() -> void:
	print("== bridge self-tests ==")
	_bt("BT1  a full tile drinks to saturation", _bt_soak)
	_bt("BT2  the saturated body drips dry", _bt_drip)
	_bt("BT3  cross-talk steams the wet body", _bt_cross_talk)
	_bt("BT4  the dunk: one tile of steam, budget-neutral", _bt_dunk)
	_bt("BT5  fire dries her out", _bt_fire_loop)
	_bt("BT6  DRY drinks the damp underfoot", _bt_dry)
	_bt("BT7  same seed, same body, same stream", _bt_seed)
	_bt("BT8  the bow wave pushes back through her entry", _bt_bow_wave)
	_bt("BT9  the dunk under volume is partial", _bt_partial_dunk)
	_bt("BT10 the sealed pool splashes over its surface", _bt_splash)
	_bt("BT11 standing in the pool does not pump it over the walls", _bt_no_drain)
	_bt("BT12 the standing claim holds the water out", _bt_standing_claim)
	_bt("BT13 the walking wake keeps the basin and the family", _bt_walk)
	_bt("BT14 the dunk leaves a drink -- boil, then absorb, one tick", _bt_dunk_drink)
	print("== done ==")

## BT14: the exchange order ruling as an assert -- a dry hot body boils the tile first, then drinks what is left, in the same tick.
func _bt_dunk_drink() -> String:
	var r := Room.new(GRID_W, GRID_H, 43)
	var t := Vector2i(7, 7)
	r.water.set_water(t.x, t.y, 255)
	var b := ThermalBody.new()
	b.heat = 64
	b.drip_mul = 0
	b.tiles = [t]
	b.support = t + Vector2i(0, 1)
	r.bridge.register(b)
	var fam0 := _family_total(r, b)
	r.tick()
	if b.heat != 0:
		return "heat %d, expected 0" % b.heat
	if r.stone.packet.mat_total(TilePacket.Mat.STEAM) != 64:
		return "steam %d, expected 64" % r.stone.packet.mat_total(TilePacket.Mat.STEAM)
	if b.wetness < 1 or b.wetness > 2:
		return "wetness %d, expected the deep-tier roll 1-2" % b.wetness
	if r.water.total() + b.wetness != 191:
		return "water + wetness %d, expected 191" % (r.water.total() + b.wetness)
	if _family_total(r, b) != fam0:
		return "family drifted %d" % (fam0 - _family_total(r, b))
	return ""

## BT13: a body pacing a full basin -- the wake pours into the vacated column, so the family never moves and the basin only ever loses the entry splash.
func _bt_walk() -> String:
	var r := Room.new(GRID_W, GRID_H, 42)
	var o := _carve_preset(r.stone, r.water, ["swwws", "swwws"])
	var b := ThermalBody.new()
	b.wetness = 64
	b.drip_mul = 0
	var pos := Vector2i(o.x + 1, o.y + 1)
	b.tiles = [pos + Vector2i(0, -1), pos]
	b.tile_volumes = [1, 2]
	b.support = pos + Vector2i(0, 1)
	b.entered_from = Vector2i(o.x, o.y + 1)
	r.bridge.register(b)
	var fam0 := _family_total(r, b)
	for _tick in 5:
		r.tick()
	for _step in 2:
		b.last_tiles = b.tiles
		b.entered_from = b.tiles[1]
		pos += Vector2i(1, 0)
		b.tiles = [pos + Vector2i(0, -1), pos]
		for _tick in 5:
			r.tick()
	if _family_total(r, b) != fam0:
		return "family drifted %d" % (fam0 - _family_total(r, b))
	var region := 0
	for x in range(o.x + 1, o.x + 4):
		region += r.water.get_water(x, o.y) + r.water.get_water(x, o.y + 1)
	if region < 1300:
		return "the basin drained: %d" % region
	return ""

## BT12: a volume-3 body in a full row reads 63 and stays there -- seek-level cannot refill past the claim; the neighbors hold 255.
func _bt_standing_claim() -> String:
	var r := Room.new(GRID_W, GRID_H, 41)
	var o := _carve_preset(r.stone, r.water, ["www"])
	var b := ThermalBody.new()
	b.wetness = 64
	b.drip_mul = 0
	b.volume_nibbles = 3
	var t := Vector2i(o.x + 1, o.y)
	b.tiles = [t]
	b.support = t + Vector2i(0, 1)
	b.entered_from = Vector2i(o.x, o.y)
	r.bridge.register(b)
	for _tick in 100:
		r.tick()
	var mid := r.water.get_water(t.x, t.y)
	if mid != 63:
		return "claimed tile reads %d, expected 63" % mid
	if r.water.get_water(o.x, o.y) < 200:
		return "the neighbors drained: %d" % r.water.get_water(o.x, o.y)
	return ""

## BT11: entry splashes once (her volume's worth over the brim); tenancy pumps nothing -- the basin keeps its water, where continuous ejection drained it toward half.
func _bt_no_drain() -> String:
	var r := Room.new(GRID_W, GRID_H, 40)
	var o := _carve_preset(r.stone, r.water, ["swwws", "swwws"])
	var t := Vector2i(o.x + 2, o.y + 1)
	var b := ThermalBody.new()
	b.wetness = 254
	b.drip_mul = 0
	b.volume_nibbles = 2
	b.tiles = [t]
	b.support = t + Vector2i(0, 1)
	b.entered_from = Vector2i(o.x + 1, o.y + 1)
	r.bridge.register(b)
	for _tick in 200:
		r.tick()
	var region := 0
	for x in range(o.x + 1, o.x + 4):
		region += r.water.get_water(x, o.y) + r.water.get_water(x, o.y + 1)
	if region < 1300:
		return "the pool drained: %d of 1530" % region
	return ""

## BT10: entry blocked -- the overflow climbs her own column and breaks the surface above (192 up, 63 stays, the family whole).
func _bt_splash() -> String:
	var r := Room.new(GRID_W, GRID_H, 39)
	var t := Vector2i(7, 7)
	r.water.set_water(t.x, t.y, 255)
	r.water.set_water(6, 7, 255)
	var b := ThermalBody.new()
	b.wetness = 254
	b.drip_mul = 0
	b.volume_nibbles = 3
	b.tiles = [t]
	b.support = t + Vector2i(0, 1)
	b.entered_from = Vector2i(6, 7)
	r.bridge.register(b)
	var fam0 := _family_total(r, b)
	r.bridge.tick()
	if r.water.get_water(t.x, t.y) != 63:
		return "tile water %d, expected 63" % r.water.get_water(t.x, t.y)
	if r.water.get_water(7, 6) != 192:
		return "surface splash %d, expected 192" % r.water.get_water(7, 6)
	if _family_total(r, b) != fam0:
		return "family drifted %d" % (fam0 - _family_total(r, b))
	return ""

## PASS/FAIL runner for the BT examples (the RT pattern: a Callable returning "" on success, the reason as the failure).
func _bt(name: String, fn: Callable) -> void:
	var err: String = fn.call()
	if err == "":
		suite_pass += 1
		print("PASS  %s" % name)
	else:
		suite_fail += 1
		print("FAIL  %s -- %s" % [name, err])

## The closed water family across the actor boundary: water + steam + damp + wetness -- one unit since the 1:1 retune, one sum.
func _family_total(r: Room, body: ThermalBody) -> int:
	var pk := r.stone.packet
	return pk.mat_total(TilePacket.Mat.WATER) + pk.mat_total(TilePacket.Mat.STEAM) \
			+ pk.damp_total() + body.wetness

## BT1: a cold body in a 255 tile drinks to saturation in one tick -- 64 water becomes 64 wetness; the tile keeps 191.
func _bt_soak() -> String:
	var r := Room.new(GRID_W, GRID_H, 31)
	var t := Vector2i(7, 7)
	r.water.set_water(t.x, t.y, 255)
	var b := ThermalBody.new()
	b.drip_mul = 0
	b.tiles = [t]
	b.support = t + Vector2i(0, 1)
	r.bridge.register(b)
	var fam0 := _family_total(r, b)
	r.tick()
	if b.wetness != 64:
		return "wetness %d, expected 64" % b.wetness
	if r.water.total() != 191:
		return "water total %d, expected 191" % r.water.total()
	if _family_total(r, b) != fam0:
		return "family drifted %d" % (fam0 - _family_total(r, b))
	return ""

## BT2: the saturated body drips itself dry -- 600 ticks, all 64 wetness returns as 64 water wherever it fell.
func _bt_drip() -> String:
	var r := Room.new(GRID_W, GRID_H, 32)
	var t := Vector2i(7, 7)
	var b := ThermalBody.new()
	b.wetness = 64
	b.tiles = [t]
	b.support = t + Vector2i(0, 1)
	r.bridge.register(b)
	var fam0 := _family_total(r, b)
	for _tick in 600:
		r.tick()
	if b.wetness != 0:
		return "wetness %d after 600 ticks, expected 0" % b.wetness
	if r.water.total() != 64:
		return "water total %d, expected 64" % r.water.total()
	if _family_total(r, b) != fam0:
		return "family drifted %d" % (fam0 - _family_total(r, b))
	return ""

## BT3: cross-talk steams a hot wet body -- totals forced, timing lumpy: 64 steam, heat 64 -> 0, wetness 0.
func _bt_cross_talk() -> String:
	var r := Room.new(GRID_W, GRID_H, 33)
	var t := Vector2i(7, 7)
	var b := ThermalBody.new()
	b.heat = 64
	b.wetness = 64
	b.drip_mul = 0
	b.tiles = [t]
	b.support = t + Vector2i(0, 1)
	r.bridge.register(b)
	var fam0 := _family_total(r, b)
	for _tick in 500:
		r.tick()
	if b.wetness != 0 or b.heat != 0:
		return "body wet %d heat %d, expected 0 and 0" % [b.wetness, b.heat]
	if r.stone.packet.mat_total(TilePacket.Mat.STEAM) != 64:
		return "steam %d, expected 64" % r.stone.packet.mat_total(TilePacket.Mat.STEAM)
	if _family_total(r, b) != fam0:
		return "family drifted %d" % (fam0 - _family_total(r, b))
	return ""

## BT4: the dunk -- 64 heat into a full tile converts min(heat, water) in one tick: 64 steam, 191 stays, heat spent, ledger green; the body arrives saturated, so the drink after the boil is BT14's business.
func _bt_dunk() -> String:
	var r := Room.new(GRID_W, GRID_H, 34)
	var t := Vector2i(7, 7)
	r.water.set_water(t.x, t.y, 255)
	var b := ThermalBody.new()
	b.heat = 64
	b.drip_mul = 0
	b.wetness = 64
	b.tiles = [t]
	b.support = t + Vector2i(0, 1)
	r.bridge.register(b)
	var fam0 := _family_total(r, b)
	r.tick()
	if b.heat != 0:
		return "heat %d, expected 0" % b.heat
	if r.water.total() != 191:
		return "water %d, expected 191" % r.water.total()
	if r.stone.packet.mat_total(TilePacket.Mat.STEAM) != 64:
		return "steam %d, expected 64" % r.stone.packet.mat_total(TilePacket.Mat.STEAM)
	if not r.stone.packet.assert_all():
		return "ledger red after the dunk"
	if _family_total(r, b) != fam0:
		return "family drifted %d" % (fam0 - _family_total(r, b))
	return ""

## BT5: fire dries her out -- a hot soaked body in a burning oil film: contact tops her at 64, cross-talk spends 48, heat survives.
func _bt_fire_loop() -> String:
	var r := Room.new(GRID_W, GRID_H, 35)
	var t := Vector2i(7, 7)
	r.water.add_liquid(t.x, t.y, TilePacket.Mat.OIL, 128)
	var b := ThermalBody.new()
	b.heat = 64
	b.wetness = 48
	b.drip_mul = 0
	b.tiles = [t]
	b.support = t + Vector2i(0, 1)
	r.bridge.register(b)
	var fam0 := _family_total(r, b)
	if not r.react.ignite(t.x, t.y):
		return "god-hand ignite refused"
	for _tick in 300:
		r.tick()
	if b.wetness != 0:
		return "wetness %d after 300 ticks, expected 0" % b.wetness
	if b.heat <= 0:
		return "heat ran dry before the wetness did"
	if _family_total(r, b) != fam0:
		return "family drifted %d" % (fam0 - _family_total(r, b))
	return ""

## BT6: DRY underfoot -- 64 damp in the supported soil steams off as 64 steam, heat 64 -> 0, and the wet tag releases.
func _bt_dry() -> String:
	var r := Room.new(GRID_W, GRID_H, 36)
	var o := _carve_preset(r.stone, r.water, ["dd", "dd"])
	var b := ThermalBody.new()
	b.heat = 64
	b.drip_mul = 0
	b.tiles = [o + Vector2i(0, -1)]
	b.support = o
	r.bridge.register(b)
	var pk := r.stone.packet
	var ground := pk.idx(o.x, o.y)
	pk.add_damp(ground, 64)
	var fam0 := _family_total(r, b)
	for _tick in 500:
		r.tick()
	if pk.get_damp(ground) != 0:
		return "damp %d, expected 0" % pk.get_damp(ground)
	if b.heat != 0:
		return "heat %d, expected 0" % b.heat
	if pk.mat_total(TilePacket.Mat.STEAM) != 64:
		return "steam %d, expected 64" % pk.mat_total(TilePacket.Mat.STEAM)
	if pk.has_tag(ground, TilePacket.TAG_WET):
		return "wet tag survived the drain"
	if _family_total(r, b) != fam0:
		return "family drifted %d" % (fam0 - _family_total(r, b))
	return ""

## BT7: the first PRNG-consuming determinism proof -- two rooms, one seed, identical bodies, identical streams.
func _bt_seed() -> String:
	var r1 := Room.new(GRID_W, GRID_H, 21)
	var r2 := Room.new(GRID_W, GRID_H, 21)
	var bodies: Array[ThermalBody] = []
	for r in [r1, r2]:
		var b := ThermalBody.new()
		b.heat = 48
		b.wetness = 40
		b.tiles = [Vector2i(7, 7)]
		b.support = Vector2i(7, 8)
		r.bridge.register(b)
		bodies.append(b)
	for _tick in 200:
		r1.tick()
		r2.tick()
	if bodies[0].heat != bodies[1].heat or bodies[0].wetness != bodies[1].wetness:
		return "bodies diverged"
	if not r1.snapshot().same_bytes(r2.snapshot()):
		return "same seed diverged"
	return ""

## BT8: the bow wave -- a volume-3 body in a full tile pushes 192 back through its entry tile; the bridge tick runs alone so the water engine cannot level it away before the assert.
func _bt_bow_wave() -> String:
	var r := Room.new(GRID_W, GRID_H, 37)
	var t := Vector2i(7, 7)
	var s := Vector2i(6, 7)
	r.water.set_water(t.x, t.y, 255)
	var b := ThermalBody.new()
	b.wetness = 254
	b.drip_mul = 0
	b.volume_nibbles = 3
	b.tiles = [t]
	b.support = t + Vector2i(0, 1)
	b.entered_from = s
	r.bridge.register(b)
	var fam0 := _family_total(r, b)
	r.bridge.tick()
	if r.water.get_water(t.x, t.y) != 63:
		return "tile water %d, expected 63" % r.water.get_water(t.x, t.y)
	if r.water.get_water(s.x, s.y) != 192:
		return "entry tile water %d, expected 192" % r.water.get_water(s.x, s.y)
	r.tick()
	if _family_total(r, b) != fam0:
		return "family drifted %d" % (fam0 - _family_total(r, b))
	return ""

## BT9: the dunk under volume -- experienced depth is full, the conversion is partial: 63 steam, 192 splashed back, heat 255 -> 192.
func _bt_partial_dunk() -> String:
	var r := Room.new(GRID_W, GRID_H, 38)
	var t := Vector2i(7, 7)
	var s := Vector2i(6, 7)
	r.water.set_water(t.x, t.y, 255)
	var b := ThermalBody.new()
	b.heat = 255
	b.drip_mul = 0
	b.volume_nibbles = 3
	b.tiles = [t]
	b.support = t + Vector2i(0, 1)
	b.entered_from = s
	r.bridge.register(b)
	var fam0 := _family_total(r, b)
	r.bridge.tick()
	if b.heat != 192:
		return "heat %d, expected 192" % b.heat
	var pk := r.stone.packet
	if pk.get_pool(pk.idx(t.x, t.y), TilePacket.Mat.STEAM) != 63:
		return "steam %d, expected 63" % pk.get_pool(pk.idx(t.x, t.y), TilePacket.Mat.STEAM)
	if r.water.get_water(s.x, s.y) != 192:
		return "splash %d, expected 192" % r.water.get_water(s.x, s.y)
	r.tick()
	if _family_total(r, b) != fam0:
		return "family drifted %d" % (fam0 - _family_total(r, b))
	return ""
