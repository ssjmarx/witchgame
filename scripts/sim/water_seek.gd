## The seek-level machinery (world.md §3, rule four): pressure-head
## equalization across horizontal runs -- density-weighted column heads,
## donor/receiver trades, and the sealed-chamber rulings. Liquids only.

class_name WaterSeek
extends RefCounted

const PRESSURE_RATE := 64     # units/tick per square of opening
const PRESSURE_MIN_DIFF := 2  # top-up hysteresis, in donor-material quanta -- the actionable floor is this × density[m]

var width: int
var height: int
var stone: GridStone
var pk: TilePacket
var labels: WaterAnalyze
var pools: WaterPools
var flow: WaterFlow

## Bind the geometry, the packet, the label pass, the pool helpers, and the flow field the deposits stamp.
func _init(w: int, h: int, terrain: GridStone, p_labels: WaterAnalyze, p_pools: WaterPools, p_flow: WaterFlow) -> void:
	width = w
	height = h
	stone = terrain
	pk = terrain.packet
	labels = p_labels
	pools = p_pools
	flow = p_flow

## Rule four: try to equalize pressure across each run of liquid tiles (any material — mixtures are one conduit) for material m.
func pass_all(m: int) -> void:
	for y in range(height - 1, -1, -1):
		var x := 0
		while x < width:
			if pk.pool_total(pk.idx(x, y)) >= GridWater.LINE:
				var x1 := x
				while x1 + 1 < width and pk.pool_total(pk.idx(x1 + 1, y)) >= GridWater.LINE:
					x1 += 1
				run(x, x1, y, m)
				x = x1 + 1
			else:
				x += 1

## Level one horizontal run of material m by pressure: heads are density-weighted column integrals from each surface to the run row -- true hydrostatic pressure at the choke. Donors must carry m at the conduit row; every column of the run may receive.
func run(x0: int, x1: int, y: int, m: int) -> void:
	var rho := TilePacket.DENSITY[m]
	var ptops := PackedInt32Array()
	ptops.resize(width)
	ptops.fill(-1)
	var heads := PackedInt32Array()
	heads.resize(width)
	var cols: Array = []
	for x in range(x0, x1 + 1):
		ptops[x] = pools.pool_top(x, y)
		var h := 0
		for yy in range(ptops[x], y + 1):
			for m2 in TilePacket.MAT_COUNT:
				var v := pk.get_pool(pk.idx(x, yy), m2)
				if v > 0:
					h += v * TilePacket.DENSITY[m2]
		heads[x] = h
		cols.append(x)
	if cols.size() < 2:
		return   # a single-column conduit has no pair to trade
	cols.sort_custom(func(a, b): return heads[a] < heads[b])
	# receivers lowest-pressure first, donors highest first; a failed transfer falls through to the next pair
	for ti in cols.size():
		var t: int = cols[ti]
		for si in range(cols.size() - 1, ti, -1):
			var s: int = cols[si]
			if pk.get_pool(pk.idx(s, y), m) < GridWater.LINE:
				continue   # donors must carry m at the conduit row
			var diff := heads[s] - heads[t]
			if diff < PRESSURE_MIN_DIFF * rho:
				break   # donors only get shorter from here
			if transfer_level(s, t, y, diff, ptops, m) > 0:
				return

## Move volume of material m from column s to receiver t so their pressures converge; returns units moved. Capped by half the pressure difference (no overshoot) and viscosity; the deposit lands at m's surface, the pool floor when m sinks, or the pool surface when m floats -- a full entry makes room by displacement: lighter residents yield in place, a pure-m entry thickens at the interface above, and air above an m-surface is the threshold-gated rise.
@warning_ignore("integer_division")
func transfer_level(s: int, t: int, y: int, diff: int, ptops: PackedInt32Array, m: int) -> int:
	var rho := TilePacket.DENSITY[m]
	var s_top := pools.segment_top(s, y, m)
	# giving side: the column must be able to recede (air replaces the liquid)
	if s_top > 0 and stone.is_solid(s, s_top - 1):
		# capped by stone, but it may still recede if a side pocket expands into the vacated cells
		var surf := pk.idx(s, s_top)
		var side_air := (s > 0 and not stone.is_solid(s - 1, s_top) and pk.pool_total(surf - 1) <= GridWater.AIR_PASSABLE_MAX) \
				or (s < width - 1 and not stone.is_solid(s + 1, s_top) and pk.pool_total(surf + 1) <= GridWater.AIR_PASSABLE_MAX)
		if not side_air:
			return 0
	var avail := 0
	for yy in range(s_top, y + 1):
		avail += pk.get_pool(pk.idx(s, yy), m)
	if avail <= 0:
		return 0
	# the receiver's entry: m's own surface when the column carries m; else the pool floor (m sinks) or the pool surface (m floats)
	var pt: int = ptops[t]
	var pb := pools.pool_bottom(t, y)
	var entry := pk.idx(t, pt)
	var same_mat := false
	for yy in range(pt, pb + 1):
		if pk.get_pool(pk.idx(t, yy), m) >= GridWater.LINE:
			entry = pk.idx(t, pools.segment_top(t, yy, m))
			same_mat = true
			break
	if not same_mat:
		var surf_light := pk.lightest_mat(pk.idx(t, pt))
		if TilePacket.DENSITY[m] > TilePacket.DENSITY[surf_light]:
			entry = pk.idx(t, pb)
		else:
			entry = pk.idx(t, pt)
	# receiving capacity: room at the entry, the gated rise above an m-surface, or displacement
	var target := entry
	var room := pk.pool_free(entry)
	if room <= 0 and same_mat and diff >= TilePacket.POOL_MAX * rho:
		var e_p := pk.xy_of(entry)
		if e_p.y > 0:
			var above := pk.idx(t, e_p.y - 1)
			if not stone.is_solid(t, e_p.y - 1) and pk.pool_total(above) <= GridWater.AIR_PASSABLE_MAX \
					and _pocket_vented_for(above, s, s_top):
				var r2 := pk.pool_free(above)
				if r2 > 0:
					target = above
					room = r2
	@warning_ignore("integer_division")
	var want := mini(mini(mini(PRESSURE_RATE, diff / (2 * rho)), avail), TilePacket.VISCOSITY[m])
	if want <= 0:
		return 0
	if target == entry and room <= 0:
		var lm := pk.lightest_mat(entry)
		if lm >= 0 and TilePacket.DENSITY[lm] < rho:
			room += pools.eject_lightest_up(entry, want - room)
		else:
			var e_y := pk.xy_of(entry)
			if e_y.y == 0:
				return 0   # no column above to yield
			var iface := entry - width
			if pk.pool_total(iface) < GridWater.LINE:
				return 0
			var if_room := pk.pool_free(iface)
			room = if_room + pools.eject_lightest_up(iface, want - if_room)
			target = iface
	var move := mini(want, room)
	if move <= 0:
		return 0
	# remove from the donor's surface, walking down toward the junction; take_pool reports what it got, so the walk cannot over-draw
	var remaining := move
	var yy2 := s_top
	while remaining > 0:
		remaining -= pk.take_pool(pk.idx(s, yy2), m, remaining)
		yy2 += 1
	# deposit at the target (the entry, the interface above it, or one above when the rise fired)
	pk.add_pool(target, m, move)
	if target != entry:
		flow.stamp(target, GridWater.FlowDir.UP, move)
	else:
		flow.stamp(target, GridWater.FlowDir.RIGHT if s < t else GridWater.FlowDir.LEFT, move)
	return move

## Can the air above the receiver's surface give way to this transfer? s and s_top name the donor's own receding headspace.
func _pocket_vented_for(cell: int, s: int, s_top: int) -> bool:
	if labels.escape_at(cell):
		return true
	if s_top > 0:
		var s_above := pk.idx(s, s_top - 1)
		if not stone.is_solid(s, s_top - 1) and pk.pool_total(s_above) <= GridWater.AIR_PASSABLE_MAX \
				and labels.region_at(s_above) == labels.region_at(cell):
			return true  # the donor's own receding headspace
	return false