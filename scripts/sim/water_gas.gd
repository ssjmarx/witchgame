## The gas rules (world.md §3, MOVERS' rising half): gases rise first, spread
## laterally when pinned, hop up-diagonal only around corners, then trade their
## ratios across horizontal faces -- never seeking level. One module, one packet.

class_name WaterGas
extends RefCounted

const SWAP := 16   # <tune> — exchange cap per pair per gas, units per tick
const GASES: Array[int] = [TilePacket.Mat.SMOKE, TilePacket.Mat.STEAM]   # the rising pair; fixed order keeps the refund path deterministic

var width: int
var height: int
var stone: GridStone
var pk: TilePacket
var flow: WaterFlow

## Bind the geometry, the packet via the stone facade, and the shared flow field the stamps land in.
func _init(w: int, h: int, terrain: GridStone, p_flow: WaterFlow) -> void:
	width = w
	height = h
	stone = terrain
	pk = terrain.packet
	flow = p_flow

## True for the rising materials: smoke and steam ride MOVERS but run their own rules — rise first, creep only when pinned, exchange ratios horizontally, never seek level (a gas column is not a pressure vessel; the sort pass is the only elevator a gas needs through liquid).
func is_gas(m: int) -> bool:
	return GASES.has(m)

## Run cell_pass over every cell top-down, sweep alternating per tick: rise mirrors fall's bottom-up — scanning against the motion, so arrived gas is never reprocessed and a bubble climbs one tile per tick.
func cell_pass_all(m: int, tick: int) -> void:
	var ltr := (tick % 2 == 0)
	for y in height:
		if ltr:
			for x in width:
				cell_pass(pk.idx(x, y), m, tick)
		else:
			for x in range(width - 1, -1, -1):
				cell_pass(pk.idx(x, y), m, tick)

## Rise and spread for one gas cell — the three-step stack: what fits goes up (a transit column pistons whole and returns — the chimney ruling); the blocked remainder spreads LATERALLY at its own level, half-difference into lower-gas neighbors both sides; only a cell blocked above AND beside hops up-diagonal — corner rounding, never the primary dispersal, because order IS policy: hop-first grows a backed-up pile into a 45-degree cone, lateral-first flattens it into a mushroom. Rise and the hop are volume-neutral swaps with the air they enter (no air-gate); the hop is corner-gated so gas never leaks through a pinched diagonal.
func cell_pass(i: int, m: int, tick: int) -> void:
	var g := pk.get_pool(i, m)
	if g == 0:
		return
	var p := pk.xy_of(i)
	var visc := TilePacket.VISCOSITY[m]
	var flip := -1 if (tick % 2 == 0) else 1
	# 1) RISE — as much as the headroom above takes; the remainder is step two's business
	if p.y > 0 and not stone.is_solid(p.x, p.y - 1):
		var a := i - width
		var free := pk.pool_free(a)
		if free > 0:
			var move := mini(mini(g, free), visc)
			var taken := pk.take_pool(i, m, move)
			pk.add_pool(a, m, taken)
			flow.stamp(a, GridWater.FlowDir.UP, taken)
			g -= taken
			if g == 0:
				return
	# 2) LATERAL SPREAD — the blocked remainder levels out at its own height, half-difference into lower-gas neighbors, both sides, cascading convergently down the row; one move kind per cell per tick, so a cell that spread does not also hop
	var crept := 0
	if g > 0:
		for k in 2:
			var dx := flip if k == 0 else -flip
			var nx := p.x + dx
			if nx < 0 or nx >= width:
				continue
			if stone.is_solid(nx, p.y):
				continue
			var n := pk.idx(nx, p.y)
			var ng := pk.get_pool(n, m)
			var free := pk.pool_free(n)
			if ng < g - 1 and free > 0:
				var move := mini(mini((g - ng) >> 1, free), visc)
				var taken := pk.take_pool(i, m, move)
				pk.add_pool(n, m, taken)
				flow.stamp(n, GridWater.FlowDir.RIGHT if dx > 0 else GridWater.FlowDir.LEFT, taken)
				g = pk.get_pool(i, m)
				crept += taken
		if crept > 0:
			return
	# 3) UP-DIAGONAL HOP — blocked above and blocked beside: the remainder hops corner-ward; the flip shoulder takes half (odd unit included), the other the rest, so a lone shoulder drains all; the diagonal is sealed only when BOTH flanking corners hold no capacity — the tile above and the tile beside, terrain-solid or four subtiles — one solid corner is a corner to round
	if p.y > 0 and g > 0:
		var capped_above := pk.pool_capacity(i - width) == 0
		for k in 2:
			if g <= 0:
				break
			var dx := flip if k == 0 else -flip
			var nx := p.x + dx
			if nx < 0 or nx >= width:
				continue
			if capped_above and pk.pool_capacity(pk.idx(nx, p.y)) == 0:
				continue   # pinched between two capacity-0 tiles: the sealed crack
			var t := pk.idx(nx, p.y - 1)
			var free := pk.pool_free(t)
			if free <= 0:
				continue
			var want := ((g + 1) >> 1) if k == 0 else g
			var give := mini(mini(want, free), visc)
			var taken := pk.take_pool(i, m, give)
			pk.add_pool(t, m, taken)
			flow.stamp(t, GridWater.FlowDir.UP_RIGHT if dx > 0 else GridWater.FlowDir.UP_LEFT, taken)
			g -= taken

## Horizontal gas exchange (rule six, diffusion-shaped): each gas trades half its difference between adjacent gas-holding tiles, capped by SWAP — the equalizer seek level refuses to be; runs after the movers and before the sort, so the tick ends stratified. Ratios can differ only where both gases exist, so the gate is the pair.
func exchange_pass(tick: int) -> void:
	if not (pk.has_mat(GASES[0]) and pk.has_mat(GASES[1])):
		return
	var ltr := (tick % 2 == 0)
	for y in height:
		if ltr:
			for x in range(width - 1):
				_exchange_pair(pk.idx(x, y), pk.idx(x + 1, y))
		else:
			for x in range(width - 2, -1, -1):
				_exchange_pair(pk.idx(x, y), pk.idx(x + 1, y))

## Trade both gases between horizontal neighbors a and b: per gas half the difference (capped by SWAP), taking from both givers BEFORE any add — a full tile's inflow is covered by its own simultaneous outflow — and refused adds refund the giver, so scarce capacity pinches but never destroys.
func _exchange_pair(a: int, b: int) -> void:
	var hold_a := pk.get_pool(a, GASES[0]) + pk.get_pool(a, GASES[1])
	var hold_b := pk.get_pool(b, GASES[0]) + pk.get_pool(b, GASES[1])
	if hold_a == 0 or hold_b == 0:
		return   # a gas-empty neighbor is creep's business; a gas|liquid face has no ratios to trade
	var amt := [0, 0]
	var to_b := [false, false]
	for k in GASES.size():
		var m: int = GASES[k]
		var d := pk.get_pool(a, m) - pk.get_pool(b, m)
		if absi(d) < 2:
			continue   # terminal granularity: neighbors may rest one unit apart (creep's convention)
		amt[k] = mini(absi(d) >> 1, SWAP)
		to_b[k] = d > 0
	for k in GASES.size():
		if amt[k] > 0:
			pk.take_pool(a if to_b[k] else b, GASES[k], amt[k])
	for k in GASES.size():
		if amt[k] == 0:
			continue
		var m: int = GASES[k]
		var giver := a if to_b[k] else b
		var taker := b if to_b[k] else a
		var accepted := pk.add_pool(taker, m, amt[k])
		if accepted < amt[k]:
			pk.add_pool(giver, m, amt[k] - accepted)   # refused units return to the giver — the refund always fits, it just freed that much room
		flow.stamp(taker, GridWater.FlowDir.RIGHT if to_b[k] else GridWater.FlowDir.LEFT, accepted)
