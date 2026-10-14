## The liquid layer (world §9, tileset lab 2b): the state IS the picture -- paint reads
## the settled CA and flow export directly, snaps per tick; the pose model died. Level tiles,
## synchronized crests, the droplet rain field, phase-hashed waves for rapids, rain-through.

class_name Liquids
extends RefCounted

const TILE := 16   # pixels per tile, the renderer's constant mirrored
const BOTTOM_MASK := GridSand.BL | GridSand.BR   # the open-row counts' reads
const TOP_MASK := GridSand.TL | GridSand.TR
const LIQ_DRAW: Array[int] = [TilePacket.Mat.LAVA, TilePacket.Mat.ACID, TilePacket.Mat.WATER, TilePacket.Mat.OIL]   # density order: densest sinks to the bottom band
const SUB_QUADS: Array = [[GridSand.TL, 0, 0], [GridSand.TR, 8, 0], [GridSand.BL, 0, 8], [GridSand.BR, 8, 8]]   # the four cells: bit, px, py within the tile
const FLOW_STREAK := 48     # downflow at or above this draws the waterfall read -- the FLOW_BLOCK telegraph
const CYCLE_WAVE := 8     # one wave roll in ticks (two frames at four-tick steps) -- 0.8 s at 10 Hz; the waterfall's heavy-droplet cycle shares it
const CYCLE_RAIN := 16    # one light-rain descent cycle in ticks (8 frames at two-tick steps)
const RAPID_MIN := 48     # lateral or diagonal flow at or above this draws waves -- rapids, not droplets (world §9)
const KIND: Array[String] = ["water", "oil", "acid", "lava", "", ""]   # Mat id -> atlas kind (the gases read empty)
const CL_NONE := 0   # no special draw
const CL_H := 1      # horizontal wave
const CL_DL := 2     # diagonal wave, down-left
const CL_DR := 3     # diagonal wave, down-right
const CL_RAIN := 4   # the rain field (a falling stream)
const CL_FALL := 5   # the waterfall read (fill + heavy rain)

var stone: GridStone
var water: GridWater
var pk: TilePacket
var wave_kind: PackedByteArray   # the banked picture's material context -- kind index (bits 0-1), heavy bit 2, full bit 3 -- view state beside the bank, written when the bank tops up, cleared when it empties
var _ctx_kind := -1   # dry-gap replay override: the KIND index forced while a banked picture replays on a dry tile (-1 = read live)
var wave_left: PackedByteArray   # the special-draw bank -- view state, one byte per tile, never census (world §9): low 5 bits ticks left, high 3 bits the latched class
var _bank_tick := -1   # the tick frontier -- the bank spends on sim ticks, never paints (the frame loop renders many times per tick)

## Bind the sim pair the renderer binds; the layer reads state, it never writes it. The wave bank rides along, zeroed at birth.
func _init(terrain: GridStone, field: GridWater) -> void:
	stone = terrain
	water = field
	pk = terrain.packet
	wave_left.resize(terrain.width * terrain.height)
	wave_kind.resize(terrain.width * terrain.height)
	wave_kind.fill(255)


## Paint one tile's liquid: resting bodies distribute their volume across the open subtile rows (per-cell compositing: solid cells draw nothing), the crest rides the surface row of a body deeper than one full tile; falling streams draw the rain field, heavy columns the waterfall read (fill plus rain), fast lateral or diagonal flow the phase-hashed waves -- rapids outrank the waterfall read, and the special-draw bank guarantees every special picture plays at least one full animation cycle after its conditions cease (a class-latched byte of view state; the waterline returns only after a quiet cycle).
func paint(x: int, y: int, px: int, py: int, blit: Callable) -> void:
	var i := stone.idx(x, y)
	if water.tick_count != _bank_tick:
		_spend_all()
		_bank_tick = water.tick_count
	if stone.is_solid(x, y):
		return
	var liq := _liquid_total(i)
	var pattern := pk.occlusion_bits(i)
	if liq <= 0:
		# a dry tile draws nothing of live water (a flow stamp with no liquid beneath it is gas in transit -- rain is never made of gas), but a banked picture replays: the holdover guarantee covers the dry gaps of a transit tile (world §9)
		if (wave_left[i] & 31) > 0:
			_ctx_kind = wave_kind[i] & 3
			var heavy := (wave_kind[i] & 4) != 0
			var full := (wave_kind[i] & 8) != 0
			match wave_left[i] >> 5:
				CL_H:
					_draw_wave_h(x, y, px, py, 255 if full else 32, blit, pattern, false)
				CL_DL, CL_DR:
					_draw_wave_d(x, y, px, py, (wave_left[i] >> 5) == CL_DR, blit, pattern)
				CL_FALL:
					_falling_fill(x, y, px, py, 255, blit, pattern)
					_draw_rain(x, y, px, py, 255, 255, blit, pattern)
				CL_RAIN:
					_draw_rain(x, y, px, py, 64 if heavy else 32, 64 if heavy else 32, blit, pattern)
			_ctx_kind = -1
		return
	var mag := water.get_flow_mag(x, y)
	var can_fall := stone.drains_v(x, y) and stone.edge_v_open(x, y + 1)
	var below := i + stone.width if y < stone.height - 1 else -1
	var below_full := below >= 0 and not stone.is_solid(x, y + 1) and _liquid_total(below) >= 240
	var supported := not can_fall or below_full
	var dir := water.get_flow_dir(x, y)
	var rapid := _rapid(dir, mag)
	# the desired special class from live conditions -- rapids outrank the waterfall read: a diagonal-dominant tile is a rapid at any weight
	var desired := CL_NONE
	if rapid == "h":
		desired = CL_H
	elif rapid == "d":
		desired = CL_DR if dir == GridWater.FlowDir.DOWN_RIGHT else CL_DL
	elif not supported and liq >= 128:
		desired = CL_FALL
	elif not supported:
		desired = CL_RAIN
	elif dir == GridWater.FlowDir.DOWN and mag >= FLOW_STREAK:
		desired = CL_FALL   # the pool mouth under strong downflow
	var acl := _bank(i, desired)
	if desired != CL_NONE:
		# the banked picture's material context rides the top-up (bits: kind 0-1, heavy 2, full 3)
		wave_kind[i] = (_band_top(i, liq) & 3) | (4 if liq >= 64 else 0) | (8 if liq >= 128 else 0)
	if not supported:
		match acl:
			CL_H:
				_draw_wave_h(x, y, px, py, liq, blit, pattern, false)
				return
			CL_DL, CL_DR:
				_draw_wave_d(x, y, px, py, acl == CL_DR, blit, pattern)
				return
			CL_FALL:
				_falling_fill(x, y, px, py, liq, blit, pattern)
				_draw_rain(x, y, px, py, liq, mag, blit, pattern)
				return
		if liq >= 16:
			_draw_rain(x, y, px, py, liq, mag, blit, pattern)
		return
	var kind := _kind_now(i, liq)
	var crest_v := (water.tick_count >> 3) & 1   # the synchronized ping-pong: one wave every eight ticks, every crest in lockstep
	var deep := supported and below_full   # the crest means a body deeper than one full tile (world §9)
	var open_b := 2 - TilePacket.POPCOUNT[pattern & BOTTOM_MASK]
	var open_t := 2 - TilePacket.POPCOUNT[pattern & TOP_MASK]
	@warning_ignore("integer_division")
	var d_b := clampi(liq / maxi(8 * open_b, 8), 0, 8)
	var rem := maxi(liq - 64 * open_b, 0)
	@warning_ignore("integer_division")
	var d_t := clampi(rem / maxi(8 * open_t, 8), 0, 8)
	# the standing body: the open bottom row shares the volume, the remainder rides the top -- unless a special draw owns the tile (its art carries the body, the fill never shows beneath it)
	if acl == CL_DL or acl == CL_DR:
		_draw_wave_d(x, y, px, py, acl == CL_DR, blit, pattern)
		return   # the diagonal wave owns the whole tile on standing water too -- its 3/4 shape plus the pinned cell
	if acl != CL_H:
		_blit_cells(blit, kind, pattern, px, py + 8, d_b, deep and d_t == 0 and d_b > 0 and d_b < 8, crest_v, BOTTOM_MASK)
	_blit_cells(blit, kind, pattern, px, py, d_t, deep and d_t > 0 and d_t < 8, crest_v, TOP_MASK)
	# a standing river rolls: the wave owns the bottom row outright -- overridden, not overlaid (world §9)
	if acl == CL_H:
		_draw_wave_h(x, y, px, py, liq, blit, pattern, true)
	# rain falls through to the waterline: the column above continues down this tile's open cells to the surface fill
	var rain_a := _raining_above(x, y, kind)
	if rain_a > 0 and acl == CL_NONE:
		_rain_through(x, y, blit, kind, pattern, rain_a >= 64, px, py)
	# the banked waterfall read: fill plus rain, held a full cycle after the downflow dies
	if acl == CL_FALL:
		_draw_rain(x, y, px, py, liq, mag, blit, pattern)

## Blit the level tile into each open cell of the subtile row at (dx, dy) -- row_mask pins the call to one half of the tile so a masked cell's column sibling never paints over it; solid cells draw nothing (per-cell compositing, world §9).
func _blit_cells(blit: Callable, kind: String, pattern: int, dx: int, dy: int, lines: int, surface: bool, crest_v: int, row_mask: int) -> void:
	if kind == "" or lines <= 0:
		return
	var role := _level_role(lines, surface, crest_v)
	for c in SUB_QUADS:
		if (c[0] & row_mask) != 0 and (pattern & c[0]) == 0:
			blit.call(kind, role, dx + c[1], dy)

## The level-tile role for a line count: quantized to the four steps; the crest pair rides the surface's 2/4/6 steps -- a full step stays flat (a brim-full surface has no wave).
func _level_role(lines: int, surface: bool, crest_v: int) -> String:
	var q := clampi((lines + 1) >> 1, 1, 4) * 2
	if surface and q != 8:
		return "crest_%d%s" % [q, "a" if crest_v == 0 else "b"]
	return "lev_%d" % q

## The rain field: droplets, not texture -- light rains one droplet descending tl->bl then one tr->br; heavy rains two crossing tl+br -> bl+tr; four x-offsets cycle in order. The clock is per-tile phase-hashed -- every tile runs the same cycle offset by its position (x*7 + y*13), so the field desyncs without state; the animation always completes, ending on the cell floor (world §9).
func _draw_rain(x: int, y: int, px: int, py: int, liq: int, mag: int, blit: Callable, pattern: int) -> void:
	var kind := _kind_maj(stone.idx(x, y))
	if kind == "":
		return
	for d in _droplet_positions(x, y, maxi(liq, mag) >= 64):
		_drop_at(blit, kind, pattern, px + d[0], py + d[1])

## The droplet positions for this tick as tile-local [x, y] pairs: an 8-frame light cycle (4 frames per descent, 4px steps ending at the floor), a 4-frame heavy crossing cycle, the x variant advancing one offset per full descent -- both phase-hashed by tile position so neighbors desync.
func _droplet_positions(x: int, y: int, heavy: bool) -> Array:
	var f := ((water.tick_count >> 1) + x * 7 + y * 13) & 7
	var v := (((water.tick_count >> 4) + x * 3 + y * 5) & 3) * 2
	if heavy:
		var q := f & 3
		return [[v, q * 4], [8 + v, 12 - q * 4]]
	if f < 4:
		return [[v, f * 4]]
	return [[8 + v, (f - 4) * 4]]

## Blit one droplet at map (lx, ly) when its containing subtile cell is open -- rain never draws over solids.
func _drop_at(blit: Callable, kind: String, pattern: int, lx: int, ly: int) -> void:
	var left := lx % 16 < 8
	var top := ly % 16 < 8
	var cell := GridSand.TL if top and left else (GridSand.TR if top else (GridSand.BL if left else GridSand.BR))
	if (pattern & cell) == 0:
		blit.call(kind, "drop", lx, ly)

## The falling column above (x, y) of the same kind: its liquid amount, or 0 when the tile above pours no rain -- rain falls through to the waterline (world §9).
func _raining_above(x: int, y: int, kind: String) -> int:
	if y == 0 or kind == "":
		return 0
	var a := stone.idx(x, y - 1)
	if stone.is_solid(x, y - 1) or KIND[_majority(a)] != kind:
		return 0
	var liq := _liquid_total(a)
	if liq < 16:
		return 0   # a film pours no rain
	if not (stone.drains_v(x, y - 1) and stone.edge_v_open(x, y)):
		return 0   # the column above rests on something -- its rain already landed
	var below_full := not stone.is_solid(x, y) and _liquid_total(a + stone.width) >= 240
	return 0 if below_full else liq

## The kind for a draw: the dry-gap replay override while a banked picture plays out, else the live read.
func _kind_now(i: int, liq: int) -> String:
	if _ctx_kind >= 0:
		return KIND[_ctx_kind]
	return KIND[_band_top(i, liq)]


## The rain draw's kind: override-aware like _kind_now, over the majority read.
func _kind_maj(i: int) -> String:
	if _ctx_kind >= 0:
		return KIND[_ctx_kind]
	return KIND[_majority(i)]


## The special-draw bank (world §9): one byte of view state, never census -- a live special class matching the latch tops the bank to its cycle plus exactly one banked cycle. The latch holds for the bank's whole life: a different class can never preempt it and takes over only after a full quiet cycle drains the bank -- so oscillating conditions (a bursty pour stamping its diagonal only on landing ticks) can never flicker a tile between pictures. Returns the active class: while the bank holds, the latched draw plays out in full -- every special picture survives at least one full animation cycle after its conditions cease. Spending is the tick frontier's job, not this one.
## The special-draw bank (world §9): one byte of view state, never census -- a live special class matching the latch tops the bank to its cycle plus exactly one banked cycle. The latch holds for the bank's whole life: a different class can never preempt it and takes over only after a full quiet cycle drains the bank -- so oscillating conditions (a bursty pour stamping its diagonal only on landing ticks) can never flicker a tile between pictures. Returns the active class: while the bank holds, the latched draw plays out in full -- every special picture survives at least one full animation cycle after its conditions cease. Spending is the tick frontier's job, not this one.
func _bank(i: int, desired: int) -> int:
	var latch := wave_left[i] >> 5
	var ticks := wave_left[i] & 31
	if desired != CL_NONE and (latch == desired or ticks == 0):
		# a matching condition repeats the animation; a quiet bank may latch a new class
		if latch != desired:
			latch = desired
		var cyc := CYCLE_RAIN if desired == CL_RAIN else CYCLE_WAVE
		ticks = mini(ticks + cyc, mini(cyc * 2, 31))
	wave_left[i] = ticks | (latch << 5)
	return latch if ticks > 0 else CL_NONE

## Spend one banked tick from every active bank, once per sim tick however many frames render inside it -- the bank's clock is the CA's own (world §9).
func _spend_all() -> void:
	for i in wave_left.size():
		if (wave_left[i] & 31) > 0:
			wave_left[i] = maxi((wave_left[i] & 31) - 1, 0) | (wave_left[i] & (7 << 5))
			if (wave_left[i] & 31) == 0:
				wave_kind[i] = 255   # the picture is gone -- its context goes too

## The waterfall's fill: the solid column at full level in both open rows -- rain rides over it.
func _falling_fill(x: int, y: int, px: int, py: int, liq: int, blit: Callable, pattern: int) -> void:
	var kind := _kind_now(stone.idx(x, y), liq)
	if kind == "":
		return
	_blit_cells(blit, kind, pattern, px, py + 8, 8, false, 0, BOTTOM_MASK)
	_blit_cells(blit, kind, pattern, px, py, 8, false, 0, TOP_MASK)


## Rain droplets over a standing tile's open cells -- the falling column's continuation down to the surface fill, phase-hashed to the tile like the field above it (world §9).
func _rain_through(x: int, y: int, blit: Callable, kind: String, pattern: int, heavy: bool, px: int, py: int) -> void:
	for d in _droplet_positions(x, y, heavy):
		_drop_at(blit, kind, pattern, px + d[0], py + d[1])

## The rapid class of a flow: "h" lateral at or above RAPID_MIN, "d" down-diagonal, "" otherwise -- sideways-moving liquid gets waves, not droplets (world §9).
func _rapid(dir: int, mag: int) -> String:
	if mag < RAPID_MIN:
		return ""
	match dir:
		GridWater.FlowDir.LEFT, GridWater.FlowDir.RIGHT:
			return "h"
		GridWater.FlowDir.DOWN_LEFT, GridWater.FlowDir.DOWN_RIGHT:
			return "d"
		_:
			return ""

## The wave frame name for this tick -- two frames rolling one bulge per four ticks, phase-hashed by tile position like the rain (world §9).
func _wave_frame(x: int, y: int, base: String) -> String:
	return "%s_%s" % [base, "a" if (((water.tick_count >> 2) + x * 7 + y * 13) & 1) == 0 else "b"]

## The horizontal wave: rides the bottom row alone when the tile holds under half or stands on ground, or the top row with the bottom row pinned full beneath it -- the wave overrides the level draw (its art carries its own body), and the water never vanishes mid-wave (world §9).
func _draw_wave_h(x: int, y: int, px: int, py: int, liq: int, blit: Callable, pattern: int, supported: bool) -> void:
	var kind := _kind_now(stone.idx(x, y), liq)
	if kind == "":
		return
	var frame := _wave_frame(x, y, "wave_h")
	if not supported and liq >= 128:
		_blit_role_row(blit, kind, frame, pattern, px, py, TOP_MASK)
		_blit_cells(blit, kind, pattern, px, py + 8, 8, false, 0, BOTTOM_MASK)
	else:
		_blit_role_row(blit, kind, frame, pattern, px, py + 8, BOTTOM_MASK)

## The diagonal wave: always three quarters of the tile -- down-right rolls on TL+BR, down-left on TR+BL (the diagonal matching the flow's leading edge), the remaining bottom cell pinned full until the cycle finishes (world §9).
func _draw_wave_d(x: int, y: int, px: int, py: int, right: bool, blit: Callable, pattern: int) -> void:
	var kind := _kind_now(stone.idx(x, y), _liquid_total(stone.idx(x, y)))
	if kind == "":
		return
	var frame := _wave_frame(x, y, "wave_d")
	var wave := (GridSand.TL | GridSand.BR) if right else (GridSand.TR | GridSand.BL)
	var pin := GridSand.BL if right else GridSand.BR
	for c in SUB_QUADS:
		if (c[0] & wave) != 0 or c[0] == pin:
			if (pattern & c[0]) == 0:
				blit.call(kind, frame if (c[0] & wave) != 0 else "lev_8", px + c[1], py + c[2])

## Blit one atlas role into each open cell of the subtile row at (dx, dy) -- the wave row draw, masked like every cell blit.
func _blit_role_row(blit: Callable, kind: String, role: String, pattern: int, dx: int, dy: int, row_mask: int) -> void:
	for c in SUB_QUADS:
		if (c[0] & row_mask) != 0 and (pattern & c[0]) == 0:
			blit.call(kind, role, dx + c[1], dy)

## The tile's top-band material: the lightest material holding more than a quarter of the liquid -- mixed tiles read their top subtile as the lighter phase, the bottom as the denser (the per-line stack, coarsened to subtile rows).
func _band_top(i: int, liq: int) -> int:
	for m in range(LIQ_DRAW.size() - 1, -1, -1):
		if pk.get_pool(i, LIQ_DRAW[m]) > (liq >> 2):
			return LIQ_DRAW[m]
	return TilePacket.Mat.WATER

## Liquid units at tile i -- the pool minus the two gases, the renderer's lines read.
func _liquid_total(i: int) -> int:
	return pk.pool_total(i) - pk.get_pool(i, TilePacket.Mat.SMOKE) - pk.get_pool(i, TilePacket.Mat.STEAM)

## Majority liquid at tile i -- the material desire (ties and empties read as water).
func _majority(i: int) -> int:
	var best := TilePacket.Mat.WATER
	var best_v: int = pk.get_pool(i, best)
	for m in range(1, TilePacket.MAT_COUNT):
		var v := pk.get_pool(i, m)
		if v > best_v:
			best = m as TilePacket.Mat
			best_v = v
	return best
