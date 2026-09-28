## The bridge acceptance suite (world.md §4): the thermal exchanges between
## bodies and the CA, the claim and displacement machinery, and the
## PRNG-consumer determinism proofs -- fresh Rooms, driven directly (BT1-BT14).

extends TestSandbox

## The lab's example set: the bridge examples in order.
func run_tests() -> void:
	run_bridge_tests()

## Bridge acceptance examples: fresh Rooms with registered bodies, driven directly -- the exchanges, the dunk, and the first PRNG-consuming determinism proof.
func run_bridge_tests() -> void:
	print("== bridge self-tests ==")
	_example("BT1  a full tile drinks to saturation", _bt_soak)
	_example("BT2  the saturated body drips dry", _bt_drip)
	_example("BT3  cross-talk steams the wet body", _bt_cross_talk)
	_example("BT4  the dunk: one tile of steam, budget-neutral", _bt_dunk)
	_example("BT5  fire dries her out", _bt_fire_loop)
	_example("BT6  DRY drinks the damp underfoot", _bt_dry)
	_example("BT7  same seed, same body, same stream", _bt_seed)
	_example("BT8  the bow wave pushes back through her entry", _bt_bow_wave)
	_example("BT9  the dunk under volume is partial", _bt_partial_dunk)
	_example("BT10 the sealed pool splashes over its surface", _bt_splash)
	_example("BT11 standing in the pool does not pump it over the walls", _bt_no_drain)
	_example("BT12 the standing claim holds the water out", _bt_standing_claim)
	_example("BT13 the walking wake keeps the basin and the family", _bt_walk)
	_example("BT14 the dunk leaves a drink -- boil, then absorb, one tick", _bt_dunk_drink)
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
