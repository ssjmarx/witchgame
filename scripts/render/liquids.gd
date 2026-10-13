## The liquid layer (world.md §9, the desire model): capture reads the settled
## CA into per-tile desires, advance eases the pose toward them on the frame
## clock, paint draws from the pose alone -- no discrete decisions in paint.

class_name Liquids
extends RefCounted

const TILE := 16   # pixels per tile, the renderer's constant mirrored
const EASE_MS := 150   # <tune> — the pose's time constant: ~halving per tick, slow enough that a 0-then-40 pour pulse bobs and never dries
const FP := 16     # the pose's fixed point: without it, integer truncation stalls the last few units and drained films never fade
const BOTTOM_MASK := GridSand.BL | GridSand.BR   # the lift's reads, mirrored from the old renderer
const TOP_MASK := GridSand.TL | GridSand.TR
const LIQ_DRAW: Array[int] = [TilePacket.Mat.LAVA, TilePacket.Mat.ACID, TilePacket.Mat.WATER, TilePacket.Mat.OIL]   # density order: the stack walks densest first
const PRESENCE_FLOOR := 8   # <tune> — half a line of pose: below it a tile holds no picture-worthy water (the ghost's last stand)
const WAVE_P := 24      # <tune> — the ripple's pattern period, projection units (~px along the travel axis)
const WAVE_MAX := 24    # <tune> — full-intensity ripple amplitude, units (1.5 lines): the crest bobs, the level stays true
const FLOW_MIN := 20    # <tune> — pose flow intensity before waves and lines draw (the still-water floor)
const ENTER_MIN := 64   # <tune> — down-arrivals that mark a tile as entering the pool below rather than resting on it: gentle pours merge, heavy falls churn
const TICK_MS := 100  # the CA's window (world §1): a drop crosses its tile per window -- the CA's own fall rate
const DROP_LEN := 2   # <tune> — the droplet dash's height, fixed by ruling: the waterfall scale-up is purely count
const BODY_FLIP := 224   # <tune> — the mode bar: resting must be near-certain (a pose this high means ~2-3 saturated ticks), so the slosh's mid-band duty reads rain and the flip lands once, at genuine top-out

var stone: GridStone
var water: GridWater
var pk: TilePacket

# the pose (fixed point) and the desire (plain) -- the material snaps, never lerps
var _level := PackedInt32Array()
var _vx := PackedInt32Array()
var _vy := PackedInt32Array()
var _cont := PackedInt32Array()
var _mat := PackedByteArray()
var _level_d := PackedInt32Array()
var _vx_d := PackedInt32Array()
var _vy_d := PackedInt32Array()
var _cont_d := PackedInt32Array()
var _mat_d := PackedByteArray()
var _captured := false
var _phase := 0   # the animation clock: waves and dashes key on it, never the sim
var _tick_ms := 0     # the tick window's origin, stamped when the tick count advances -- the drop clock, immune to stroke-recaptures
var _last_tick := -1  # the tick count last seen at capture

## Bind the sim pair the renderer binds; the layer reads state, it never writes it.
func _init(terrain: GridStone, field: GridWater) -> void:
	stone = terrain
	water = field
	pk = terrain.packet
	var n := stone.width * stone.height
	_level.resize(n)
	_vx.resize(n)
	_vy.resize(n)
	_cont.resize(n)
	_mat.resize(n)
	_level_d.resize(n)
	_vx_d.resize(n)
	_vy_d.resize(n)
	_cont_d.resize(n)
	_mat_d.resize(n)

## Capture the desires from settled state, on every redraw (tick, stroke, restore): containment binary -- a tile rests only on stone or FULL liquid (partial liquid is a surface water falls through, never a floor; resting is earned by saturation), everything else falls; covered desires standing water above (a falling stream is not a roof); level is throughput-aware -- the greater of lifted content and this tick's arrivals, so a conveying tile holds little but carries plenty, and the rain never dies mid-column; flow desires follow the export for wet and dry alike -- but a flow stamp with no liquid beneath it feeds no level desire, and the rain field draws liquid materials only: rain is never made of gas (world §9); material the majority, held while dry. The tick window stamps only when the tick count advances: strokes never disturb the drop clock.
func capture() -> void:
	if water.tick_count != _last_tick:
		_last_tick = water.tick_count
		_tick_ms = Time.get_ticks_msec()
	_captured = true
	var w := stone.width
	var prev_sup := PackedByteArray()   # the row above's rest flags: covered reads standing water above
	var row_sup := PackedByteArray()
	prev_sup.resize(w)
	row_sup.resize(w)
	for y in stone.height:
		for x in w:
			var i := stone.idx(x, y)
			var liq := _liquid_total(i)
			var d := water.get_flow_dir(x, y)
			var mag := water.get_flow_mag(x, y)
			var below_solid := stone.is_solid(x, y + 1)
			var below_full := y < stone.height - 1 and _liquid_total(i + w) >= pk.pool_capacity(i + w)
			var supported := below_solid or below_full
			row_sup[x] = 1 if supported else 0
			_cont_d[i] = 255 if supported else 0   # binary: a tile is a body or it falls -- resting is earned by saturation
			if liq >= GridWater.LINE:
				var n := pk.get_sub(i, TilePacket.K_SOIL)
				var covered := supported and prev_sup[x] != 0 and _liquid_total(i - w) >= GridWater.LINE
				var lift := _lifted_lines(liq >> 4, n) << 4
				_level_d[i] = 255 if covered else maxi(lift, mag)
				_mat_d[i] = _majority(i)
			else:
				# liquid's picture only: a flow stamp with no liquid beneath it is gas in transit -- rain is never made of gas (world §9)
				_level_d[i] = maxi(liq, mag) if liq > 0 else 0
			if d == GridWater.FlowDir.NONE:
				_vx_d[i] = 0
				_vy_d[i] = 0
			else:
				var k := mini(mag, 127)
				_vx_d[i] = GridWater.FLOW_DX[d] * k
				_vy_d[i] = GridWater.FLOW_DY[d] * k
		var swap := prev_sup
		prev_sup = row_sup
		row_sup = swap

## Advance the pose toward the desires by the frame's elapsed time -- the exponential ease: steady changes converge within a few windows, pulsing desires hold their midline. The material snaps; the fixed point keeps the last units moving, and the stall snap zeroes the parked residue so drains finish.
@warning_ignore("integer_division")
func advance(delta_ms: int) -> void:
	if not _captured or delta_ms <= 0:
		return
	for i in _level.size():
		if _level_d[i] == 0 and _level[i] > 0 and _level[i] < PRESENCE_FLOOR * FP:
			_level[i] = 0   # the stall snap: truncation parks the last half-unit forever -- drains finish
		@warning_ignore("integer_division")
		_level[i] += (_level_d[i] * FP - _level[i]) * delta_ms / EASE_MS
		@warning_ignore("integer_division")
		_vx[i] += (_vx_d[i] * FP - _vx[i]) * delta_ms / EASE_MS
		@warning_ignore("integer_division")
		_vy[i] += (_vy_d[i] * FP - _vy[i]) * delta_ms / EASE_MS
		@warning_ignore("integer_division")
		_cont[i] += (_cont_d[i] * FP - _cont[i]) * delta_ms / EASE_MS
		_mat[i] = _mat_d[i]
	_phase = (_phase + delta_ms) & 0x7FFFFFF   # the clock turns with the frame; a paused room freezes it

## Paint one tile's liquid from the pose, binary: below the body flip the rain field is the whole picture (liquid materials only -- a gas-majority tile never rains); at or above it the standing-water system -- a quadratic Bezier surface with containment-weighted neighbor edges, a traveling ripple when the flow stirs, current lines through the body, the material stack portioned beneath, the crest dissolving at interior. Geometry reads the pose; mixture reads the pool.
@warning_ignore("integer_division")
func paint(image: Image, x: int, y: int, px: int, py: int) -> void:
	var i := stone.idx(x, y)
	var h_mid := _level[i] >> 4
	if stone.is_solid(x, y) or h_mid < PRESENCE_FLOOR:
		return   # law 1: never water in stone, and no surface to bend where there is no water
	var cont := _cont[i] >> 4
	if cont < BODY_FLIP:
		if LIQ_DRAW.has(_mat[i]):
			_draw_drops(image, x, y, px, py, h_mid, _vx[i] >> 4, _vy[i] >> 4, Palette.MAT_CREST[_mat[i]])
		return   # falling: the rain field (liquid materials only -- a gas-majority tile never rains), no film, no lines, no middle band
	var vxu := _vx[i] >> 4
	var vyu := _vy[i] >> 4
	var mag := clampi(maxi(absi(vxu), absi(vyu)) + (mini(absi(vxu), absi(vyu)) >> 1), 0, 127)
	var lines_total := clampi((h_mid + 15) >> 4, 1, TILE)
	var edge_l := (h_mid + _surface_level(x - 1, y, h_mid)) >> 1
	var edge_r := (h_mid + _surface_level(x + 1, y, h_mid)) >> 1
	var bands: Array[Color] = []
	var top_m := _mat[i]
	var liq := _liquid_total(i)
	if liq >= GridWater.LINE:
		top_m = _portion_bands(i, liq, lines_total, bands)
	else:
		for _b in lines_total:
			bands.append(Palette.MAT_FILL[top_m])   # the ghost: the departing material's film
	var crest_col := Palette.MAT_CREST[top_m]
	var ext_col := Palette.MAT_FILL[top_m]
	var crest_i := clampi((255 - h_mid) * 16, 0, 255)
	var amp := 0
	var proj := 0
	var dproj := 0
	var travel := 0
	if mag >= FLOW_MIN:
		amp = (mag * cont * WAVE_MAX) >> 15
		@warning_ignore("integer_division")
		proj = ((x * TILE) * vxu + (y * TILE) * vyu) / maxi(mag, 1)
		@warning_ignore("integer_division")
		dproj = (vxu << 8) / maxi(mag, 1)
		travel = (_phase * mag) >> 12
	var min_hpx := TILE
	for u in TILE:
		var v := TILE - u
		var h := (v * v * edge_l + 2 * u * v * h_mid + u * u * edge_r) >> 8
		if amp > 0:
			h += _ripple(proj + ((u * dproj) >> 8) + travel, amp)
		var hpx := clampi((h + 15) >> 4, 0, TILE)
		if hpx < min_hpx:
			min_hpx = hpx
		if hpx <= 0:
			continue
		var top_body := ext_col if hpx > lines_total else bands[hpx - 1]
		if ((u * 37 + x * 101 + y * 57) & 255) < crest_i:
			image.set_pixel(px + u, py + TILE - hpx, crest_col)
		else:
			image.set_pixel(px + u, py + TILE - hpx, top_body)
		var r := 0
		while r < hpx - 1:
			var col := ext_col if r >= lines_total else bands[r]
			var r2 := r + 1
			while r2 < hpx - 1 and (ext_col if r2 >= lines_total else bands[r2]) == col:
				r2 += 1
			image.fill_rect(Rect2i(px + u, py + TILE - r2, 1, r2 - r), col)
			r = r2
	_draw_lines(image, x, y, px, py, vxu, vyu, mag, min_hpx, Palette.MAT_FLOW[top_m])

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

## Waterline lift over the tile's own soil subtiles: a squeezed pool reads higher on the fill. v = raw lines, n = soil nibble; returns the drawn line count, clamped to 15.
func _lifted_lines(v: int, n: int) -> int:
	var bottom := TilePacket.POPCOUNT[n & BOTTOM_MASK]
	var top := TilePacket.POPCOUNT[n & TOP_MASK]
	var shown := v
	if bottom == 2:
		if top == 0:
			shown = v + 4
		else:
			shown = mini(2 * v + 4, v + 6)
	elif bottom == 1:
		var cap := 2
		if top > 0:
			cap = 4
		shown = mini(2 * v, v + cap)
	return mini(shown, 15)

## A lateral neighbor's contribution to this tile's crest curve: its pose level weighted by its pose containment -- contained water bends the surface toward its level, falling columns and dry air flatten it as their weight eases to nothing. Solid walls and the map's edge are flat by definition.
@warning_ignore("integer_division")
func _surface_level(x: int, y: int, flat: int) -> int:
	if x < 0 or x >= stone.width or stone.is_solid(x, y):
		return flat
	var j := stone.idx(x, y)
	var w := clampi(_cont[j] >> 4, 0, 255)
	if w <= 0:
		return flat
	@warning_ignore("integer_division")
	return (flat * (255 - w) + (_level[j] >> 4) * w) / 255

## Portion the material stack into per-line bands, densest from the bottom, the densest present absorbing the partition remainder -- the old crested stack, ported beneath the new curve. Returns the topmost material.
@warning_ignore("integer_division")
func _portion_bands(i: int, liq: int, lines_total: int, bands: Array[Color]) -> int:
	var deficit := lines_total
	for m in LIQ_DRAW:
		@warning_ignore("integer_division")
		deficit -= lines_total * pk.get_pool(i, m) / liq
	var acc := 0
	var top_m := TilePacket.Mat.WATER
	for k in LIQ_DRAW.size():
		var m: int = LIQ_DRAW[k]
		var units := pk.get_pool(i, m)
		if units == 0:
			continue
		@warning_ignore("integer_division")
		var lm := lines_total * units / liq
		if acc == 0:
			lm += deficit   # the densest material present absorbs the partition remainder
		for _b in lm:
			bands.append(Palette.MAT_FILL[m])
		acc += lm
		top_m = m as TilePacket.Mat
	while bands.size() < lines_total:
		bands.append(Palette.MAT_FILL[top_m])   # rounding insurance: the walk must never read past
	return top_m

## One ripple sample: a triangle wave over the projection's pattern position, centered to swing plus and minus the amplitude -- the crest bobs as the pattern travels with the flow.
@warning_ignore("integer_division")
func _ripple(proj: int, amp: int) -> int:
	var t := posmod(proj, WAVE_P)
	var tri := t if t < (WAVE_P >> 1) else WAVE_P - t
	@warning_ignore("integer_division")
	return (tri * amp) / (WAVE_P >> 2) - amp

## Current lines through the body: dashes aligned to the flow's dominant axis and drifting along the full vector on the phase clock -- shape follows an axis, motion follows the vector, so no staircase diagonals; count and speed scale with intensity, and a dither dissolves the reorientation whenever the vector rotates through diagonal.
func _draw_lines(image: Image, x: int, y: int, px: int, py: int, vxu: int, vyu: int, mag: int, min_hpx: int, col: Color) -> void:
	if mag < FLOW_MIN or min_hpx < 3:
		return
	var ax := absi(vxu)
	var ay := absi(vyu)
	var sx := signi(vxu) if ax >= ay else 0
	var sy := 0 if ax >= ay else signi(vyu)
	var dens := clampi(absi(ax - ay) * 10 + 55, 55, 255)   # near-diagonal vectors dither: the axis handoff dissolves instead of snapping
	var scroll := (_phase * mag) >> 11
	var dxp := (vxu * scroll) >> 7
	var dyp := (vyu * scroll) >> 7
	var floor_row := TILE - min_hpx + 1   # strictly below this tile's shallowest crest
	for k in clampi(1 + (mag >> 5), 1, 3):
		var cx := (x * 13 + k * 5 + y * 7 + dxp) & 15
		var cy := (y * 11 + k * 9 + x * 3 + dyp) & 15
		for s in 3:
			var lx := (cx + s * sx) & 15
			var ly := (cy + s * sy) & 15
			if ly < floor_row:
				continue   # above the shallowest liquid: undrawn
			if dens < 255 and ((lx * 37 + ly * 101 + x * 57) & 255) >= dens:
				continue   # the dissolve dither
			image.set_pixel(px + lx, py + ly, col)

## Droplets: the rain field -- a per-column-strip texture hashed on world rows, scrolling at the CA's own fall rate (one tile per tick window); each tile samples the sixteen rows passing through it, one dash candidate per row at a hashed column, lit by a density gate keyed on the tile's amount (lumpy by design, rain gaps and all). World-anchored sampling makes the fall seam-continuous; count scales with amount, the waterfall scale-up purely count; diagonals drift by their x/y ratio.
@warning_ignore("integer_division")
func _draw_drops(image: Image, x: int, y: int, px: int, py: int, h_mid: int, vxu: int, vyu: int, col: Color) -> void:
	var thr := (2 + (h_mid >> 4)) << 4   # the per-row gate: sixteen hash bytes at thr/256 each, expectation the tile's amount in drops
	var t := clampi(Time.get_ticks_msec() - _tick_ms, 0, TICK_MS)
	@warning_ignore("integer_division")
	var fall := (t * TILE) / TICK_MS   # 0..16 px: one tile per window, the CA's own fall rate
	var drift := 0
	if vyu != 0:
		@warning_ignore("integer_division")
		drift = clampi((vxu * fall) / maxi(absi(vyu), 1), -TILE, TILE)
	var r0 := (y * TILE - water.tick_count * TILE - fall) & 255   # the strip's texture row entering this tile's top: world-anchored, seam-continuous by construction
	var hpx := image.get_height()
	for r in TILE:
		var hsh := ((r0 + r) * 92837111 + x * 689287499) & 0x7FFFFFFF
		if (hsh & 255) >= thr:
			continue
		var cx := (((hsh >> 8) & 15) + drift) & 15
		for s in DROP_LEN:
			if py + r + s >= hpx:
				break   # the map's floor eats the tail: the drop leaves the world
			image.set_pixel(px + cx, py + r + s, col)
