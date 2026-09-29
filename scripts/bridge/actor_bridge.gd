## The customs office (world.md §4): thermal bodies trade heat and wetness
## with the CA at the tick head, PRNG-shuffled body order, integer quanta
## only. The bridge holds no matter and no census -- bodies are scene-owned.

class_name ActorBridge
extends RefCounted

const W: int = TilePacket.Mat.WATER
const STEAM: int = TilePacket.Mat.STEAM
const LAVA: int = TilePacket.Mat.LAVA

const TIER_SLOW := 4              # water/s below 128 units (the film tier)
const TIER_FAST := 16             # water/s at 128+ (the deep tier)
const CROSS_TALK := 8             # wetness/s -- 8 steam/s, -8 heat/s (the water-equivalent rate, preserved through the 1:1 retune)
const DRIP_RATE := 4              # water/s randomized, drip_mul scaled
const DRY_RATE := 8               # damp/s underfoot, 1:1:1 with heat and steam
const CONTACT_FIRE := 4           # heat per tick on fire-bit overlap
const CONTACT_LAVA := 8           # heat per tick on pool-lava overlap

var stone: GridStone
var pk: TilePacket
var width: int
var height: int
var rng: RandomNumberGenerator
var bodies: Array[ThermalBody] = []
var flow: WaterFlow

## Bind the packet via the stone facade and the room PRNG every roll happens inside the tick, never on the frame
func _init(w: int, h: int, terrain: GridStone, p_rng: RandomNumberGenerator, p_flow: WaterFlow) -> void:
	width = w
	height = h
	stone = terrain
	pk = terrain.packet
	rng = p_rng
	flow = p_flow

## Add a body to the registry; the scene owns it and the room census never carries it.
func register(body: ThermalBody) -> void:
	if not bodies.has(body):
		bodies.append(body)

## Remove a body -- captured, dead, or carried through a door; the holder's business.
func unregister(body: ThermalBody) -> void:
	bodies.erase(body)

## The tick head: rebuild the claims, run every body's passes, bracketed by the family checksum -- nothing crosses the customs office without landing.
func tick() -> void:
	pk.clear_actor_claims()
	if bodies.is_empty():
		return
	var fam0 := pk.pool_damp_total()
	for b in bodies:
		fam0 += b.wetness
	var order: Array[ThermalBody] = []
	order.append_array(bodies)
	# Fisher-Yates on the room PRNG: actor order is a per-tick shuffle (world.md §4.1)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: ThermalBody = order[i]
		order[i] = order[j]
		order[j] = tmp
	for b in order:
		_claim(b)
	for b in order:
		if b.tiles.is_empty():
			continue
		_displace(b)
		_contact(b)
		_boil(b)
		_cross_talk(b)
		_dry(b)
		_absorb(b)
		_drip(b)
	var fam1 := pk.pool_damp_total()
	for b in bodies:
		fam1 += b.wetness
	if fam1 != fam0:
		push_error("ActorBridge: family leaked %d" % (fam0 - fam1))

## The claim pass: each body's hitbox volume becomes live capacity -- standing holds the water out, moving claims new tiles, leaving releases.
func _claim(b: ThermalBody) -> void:
	for k in b.tiles.size():
		var vol := b.volume_at(k)
		if vol <= 0:
			continue
		var t := b.tiles[k]
		if not stone.in_bounds(t.x, t.y):
			continue
		pk.add_actor_claim(stone.idx(t.x, t.y), vol)

## Displacement: content above the claim is overflow -- poured through the entry tile first, then the vacated column (the wake), then up and out (the splash).
func _displace(b: ThermalBody) -> void:
	if b.volume_nibbles <= 0 and b.tile_volumes.is_empty():
		return
	for k in b.tiles.size():
		if b.volume_at(k) <= 0:
			continue
		var t := b.tiles[k]
		if not stone.in_bounds(t.x, t.y):
			continue
		var src := stone.idx(t.x, t.y)
		var excess := pk.pool_total(src) - pk.pool_capacity(src)
		if excess <= 0:
			continue
		var left := excess
		var back := b.entered_from
		if back != t and stone.in_bounds(back.x, back.y):
			left = _pour_into(src, stone.idx(back.x, back.y), left)
		for lt in b.last_tiles:
			if left <= 0:
				break
			if lt == t or b.tiles.has(lt) or not stone.in_bounds(lt.x, lt.y):
				continue
			left = _pour_into(src, stone.idx(lt.x, lt.y), left)
		if left > 0:
			_eject_up(src, t.x, t.y, left)

## Contact gains, deterministic: fire bits or pool lava on any overlapped tile heat the body, capped.
func _contact(b: ThermalBody) -> void:
	var hot := false
	var molten := false
	for t in b.tiles:
		if not stone.in_bounds(t.x, t.y):
			continue
		var i := stone.idx(t.x, t.y)
		if pk.get_fire(i) != 0:
			hot = true
		if pk.get_pool(i, LAVA) > 0:
			molten = true
	if hot:
		b.heat = mini(ThermalBody.HEAT_MAX, b.heat + CONTACT_FIRE)
	if molten:
		b.heat = mini(ThermalBody.HEAT_MAX, b.heat + CONTACT_LAVA)

## BOIL: heat + pool water -> steam in the tile, tiered; a full tile converts min(heat, water) in one tick -- the dunk.
func _boil(b: ThermalBody) -> void:
	if b.heat <= 0:
		return
	var k := _pick_index(b)
	var t := b.tiles[k]
	var i := stone.idx(t.x, t.y)
	var water := pk.get_pool(i, W)
	# the glass model: her volume raises the level (content + 64 per nibble); the conversion still caps at actual content
	var depth := water + 64 * b.volume_at(k)
	if water <= 0:
		return
	if depth >= 255:
		var x := mini(b.heat, water)
		x = pk.take_pool(i, W, x)
		pk.add_pool(i, STEAM, x)
		b.heat -= x
		return
	var quanta := _quanta(_tier(water))
	for _q in quanta:
		if b.heat <= 0 or pk.get_pool(i, W) <= 0:
			return
		var x := pk.take_pool(i, W, 1)
		pk.add_pool(i, STEAM, x)
		b.heat -= x

## DRY: heat + damp at the support tile -> steam at the body's picked tile; needs pool room or the quantum holds.
func _dry(b: ThermalBody) -> void:
	if b.heat <= 0:
		return
	var s := b.support
	if not stone.in_bounds(s.x, s.y):
		return
	var src := stone.idx(s.x, s.y)
	if pk.get_damp(src) <= 0:
		return
	var k := _pick_index(b)
	var t := b.tiles[k]
	var i := stone.idx(t.x, t.y)
	var quanta := _quanta(DRY_RATE)
	for _q in quanta:
		if b.heat <= 0 or pk.get_damp(src) <= 0 or pk.pool_free(i) < 1:
			return
		pk.take_damp(src, 1)
		pk.add_pool(i, STEAM, 1)
		b.heat -= 1

## ABSORB: pool water -> wetness at 1:1, tiered; a full tile drinks to saturation in one tick.
func _absorb(b: ThermalBody) -> void:
	if b.wetness >= ThermalBody.WETNESS_MAX:
		return
	var k := _pick_index(b)
	var t := b.tiles[k]
	var i := stone.idx(t.x, t.y)
	var water := pk.get_pool(i, W)
	if water <= 0:
		return
	# the glass model: her volume raises the level; the conversion still caps at actual content
	var depth := water + 64 * b.volume_at(k)
	if depth >= 255:
		var x := mini(water, ThermalBody.WETNESS_MAX - b.wetness)
		x = pk.take_pool(i, W, x)
		b.wetness += x
		return
	var quanta := _quanta(_tier(depth))
	for _q in quanta:
		if b.wetness >= ThermalBody.WETNESS_MAX or pk.get_pool(i, W) <= 0:
			return
		if pk.take_pool(i, W, 1) == 1:
			b.wetness += 1

## CROSS-TALK: heat + own wetness -> steam at the picked tile, flat 8/s since the retune; a full tile makes the quantum hold.
func _cross_talk(b: ThermalBody) -> void:
	if b.heat <= 0 or b.wetness <= 0:
		return
	var k := _pick_index(b)
	var t := b.tiles[k]
	var i := stone.idx(t.x, t.y)
	var quanta := _quanta(CROSS_TALK)
	for _q in quanta:
		if b.heat <= 0 or b.wetness <= 0:
			return
		if pk.pool_free(i) < 1:
			return
		pk.add_pool(i, STEAM, 1)
		b.wetness -= 1
		b.heat -= 1

## DRIP: wetness -> pool water at 1:1, ~4 water/s scaled by drip_mul, at one picked tile; a full tile makes the drip hold.
func _drip(b: ThermalBody) -> void:
	if b.wetness <= 0 or b.drip_mul <= 0:
		return
	var k := _pick_index(b)
	var t := b.tiles[k]
	var i := stone.idx(t.x, t.y)
	var quanta := _quanta(DRIP_RATE * b.drip_mul, ThermalBody.DRIP_SCALE * 10)
	for _q in quanta:
		if b.wetness <= 0:
			return
		if pk.add_pool(i, W, 1) == 1:
			b.wetness -= 1

## The tier rate by the tile's water: deep pools drink and boil four times a film (world.md §4.2).
func _tier(water: int) -> int:
	return TIER_FAST if water >= 128 else TIER_SLOW

## Expected-value quanta roll: numerator/denominator quanta this tick, the remainder rolled on the room PRNG -- lumpy by doctrine, integer by law.
@warning_ignore("integer_division")
func _quanta(num: int, den: int = 10) -> int:
	@warning_ignore("integer_division")
	var base := num / den
	var rem := num % den
	if rem > 0 and rng.randi_range(0, den - 1) < rem:
		base += 1
	return base

## Pour left units of the source's lightest matter into dst, never taking more than dst accepts; returns what remains. The refund guard should be unreachable now -- an over-capacity source frees excess, not room, and the old refund promise died with the claim.
func _pour_into(src: int, dst: int, left: int) -> int:
	while left > 0:
		var m := pk.lightest_mat(src)
		if m < 0:
			return left
		var room := maxi(0, pk.pool_free(dst))
		if room <= 0:
			return left
		var want := mini(mini(left, pk.get_pool(src, m)), room)
		var taken := pk.take_pool(src, m, want)
		var got := pk.add_pool(dst, m, taken)
		left -= got
		if got > 0:
			flow.stamp(dst, _dir_between(src, dst), got)   # the pour is the event: every landing stamps the export -- the splash's arrival record
		if got < taken:
			pk.add_pool(src, m, taken - got)   # guard: the take never exceeds the destination's room
			return left
	return left

## The overflow's fallback: climb the source column and pour into the first headroom (rule five's walk, bridge-side) -- the splash above the surface.
func _eject_up(src: int, x: int, y: int, left: int) -> int:
	while left > 0 and y > 0:
		y -= 1
		var h := stone.idx(x, y)
		if TilePacket.FULL_SOLID[pk.get_terrain(h)]:
			break
		if pk.pool_free(h) > 0:
			left = _pour_into(src, h, left)
	return left

## One overlapped tile index, PRNG-picked -- the two-tile heroine law (world.md §2): the single draw site every thermal operation shares, one sample per tick.
func _pick_index(b: ThermalBody) -> int:
	return rng.randi_range(0, b.tiles.size() - 1)

## The FlowDir code for a step from src to dst (adjacent or diagonal, clamped): entry pours, wakes, and the eject climb all land here; NONE for anything the enum cannot name.
@warning_ignore("integer_division")
func _dir_between(src: int, dst: int) -> int:
	var dx := clampi((dst % width) - (src % width), -1, 1)
	@warning_ignore("integer_division")
	var dy := clampi((dst / width) - (src / width), -1, 1)
	for k in range(1, GridWater.FLOW_DX.size()):
		if GridWater.FLOW_DX[k] == dx and GridWater.FLOW_DY[k] == dy:
			return k
	return GridWater.FlowDir.NONE
