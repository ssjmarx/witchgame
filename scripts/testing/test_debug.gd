## The debug-furniture acceptance suite (world.md §3): fresh Rooms driven
## directly (the RT pattern -- the furniture pass rides Room.tick, which the
## shared runner never calls). Sources dose, drains take, open air breathes.

class_name TestDebug
extends TestSandbox

## The lab's example set: the furniture proofs, in order.
func run_tests() -> void:
	print("== debug self-tests ==")
	_example("DT0  furniture rides the census round trip", _dt0_roundtrip)
	_example("DT1  the source fills its shaft, then the dose is un-made", _dt1_source)
	_example("DT2  the drain empties the bowl to its films", _dt2_drain)
	_example("DT3  open air eats the gases", _dt3_open_air)
	_example("DT4  the inverted cup: sealed holds its breath, vented drinks, then drowns its breather", _dt4_cup)
	print("== done ==")

## DT0: painted furniture, fifty ticks, restore -- the DEBUG_S column returns byte-exact with the census (RT1's proof, furniture edition).
func _dt0_roundtrip() -> String:
	var r := Room.new(GRID_W, GRID_H, 21)
	var o := _carve_preset(r.stone, r.water, ["....", "...."])
	var pk := r.stone.packet
	pk.set_debug(pk.idx(o.x + 1, o.y), TilePacket.DebugTile.WATER_SOURCE)
	pk.set_debug(pk.idx(o.x + 2, o.y + 1), TilePacket.DebugTile.DRAIN)
	var base := r.snapshot()
	for _t in 50:
		r.tick()
	if r.water.total() <= 0:
		return "the source never dosed -- vacuous"
	r.restore(base)
	if not r.snapshot().same_bytes(base):
		return "restore not byte-exact with furniture in the census"
	if pk.get_debug(pk.idx(o.x + 1, o.y)) != TilePacket.DebugTile.WATER_SOURCE:
		return "the furniture column did not return"
	if not pk.assert_all():
		return "ledger red after restore"
	return ""

## DT1: a one-wide shaft under the source: fall fills it brim-full ungated (pour and creep find only walls, a one-tile run has no pair to trade), the source tile tops off at exactly 255, and from then on every dose is refused -- totals pin at 510, no debt, no overflow.
func _dt1_source() -> String:
	var r := Room.new(GRID_W, GRID_H, 22)
	var o := _carve_preset(r.stone, r.water, ["s", ".", "."])
	var pk := r.stone.packet
	pk.set_debug(pk.idx(o.x, o.y + 1), TilePacket.DebugTile.WATER_SOURCE)
	for _t in 1000:
		r.tick()
	var src_i := pk.idx(o.x, o.y + 1)
	if pk.get_pool(src_i, TilePacket.Mat.WATER) != 255:
		return "the source tile holds %d/255 -- never brimmed" % pk.get_pool(src_i, TilePacket.Mat.WATER)
	if pk.mat_total(TilePacket.Mat.WATER) != 510:
		return "the shaft holds %d of 510" % pk.mat_total(TilePacket.Mat.WATER)
	var a := pk.mat_total(TilePacket.Mat.WATER)
	r.tick()
	if pk.mat_total(TilePacket.Mat.WATER) != a:
		return "steady state breached -- the dose is not being refused"
	if not pk.assert_all():
		return "ledger red"
	return ""

## DT2: a bowl with a drain in its floor: everything the flow rules can move walks into the drain and is taken; sub-visible films may cling to the floor tiles (one line is the tolerance).
func _dt2_drain() -> String:
	var r := Room.new(GRID_W, GRID_H, 23)
	var o := _carve_preset(r.stone, r.water, ["....", "wwww", "wwww"])
	var pk := r.stone.packet
	if pk.mat_total(TilePacket.Mat.WATER) <= 0:
		return "carve laid no water -- vacuous"
	pk.set_debug(pk.idx(o.x + 1, o.y + 2), TilePacket.DebugTile.DRAIN)
	for _t in 2000:
		r.tick()
	var left := pk.mat_total(TilePacket.Mat.WATER)
	if left >= GridWater.LINE:
		return "the bowl holds %d units after the drain" % left
	if not pk.assert_all():
		return "ledger red"
	return ""

## DT3: a sealed pocket of smoke and steam with an open-air tile in the cavity: the gases walk into it and are taken (steam may rain onto the stone first -- condensation is another sanctioned exit); sub-visible films excepted.
func _dt3_open_air() -> String:
	var r := Room.new(GRID_W, GRID_H, 24)
	var o := _carve_preset(r.stone, r.water, ["sssss", "vmm..", "sssss"])
	var pk := r.stone.packet
	if pk.mat_total(TilePacket.Mat.SMOKE) + pk.mat_total(TilePacket.Mat.STEAM) <= 0:
		return "carve laid no gas -- vacuous"
	pk.set_debug(pk.idx(o.x + 3, o.y + 1), TilePacket.DebugTile.OPEN_AIR)
	for _t in 600:
		r.tick()
	var gas := pk.mat_total(TilePacket.Mat.SMOKE) + pk.mat_total(TilePacket.Mat.STEAM)
	if gas >= 8:
		return "open air left %d gas units standing" % gas
	if not pk.assert_all():
		return "ledger red"
	return ""

## DT4: the inverted cup, mouth down in the pool -- the control holds its breath (interior bone dry, Ex3a's law); the vented cup drinks: its bottom tile fills to 255, the water then tops 15 in the breather tile itself, the seed drowns, and the fill freezes steady -- the drowned-vent gate made visible in one example.
func _dt4_cup() -> String:
	var rows: Array = ["wsssww", "ws.sww", "ws.sww", "wwwwww", "wwwwww"]
	var control := Room.new(GRID_W, GRID_H, 25)
	var vented := Room.new(GRID_W, GRID_H, 26)
	var oc := _carve_preset(control.stone, control.water, rows)
	var ov := _carve_preset(vented.stone, vented.water, rows)
	vented.stone.packet.set_debug(vented.stone.idx(ov.x + 2, ov.y + 1), TilePacket.DebugTile.OPEN_AIR)
	for _t in 800:
		control.tick()
		vented.tick()
	var pk_c := control.stone.packet
	var pk_v := vented.stone.packet
	var dry := pk_c.get_pool(pk_c.idx(oc.x + 2, oc.y + 1), TilePacket.Mat.WATER) \
			+ pk_c.get_pool(pk_c.idx(oc.x + 2, oc.y + 2), TilePacket.Mat.WATER)
	if dry != 0:
		return "the sealed cup drank %d units -- the pocket gate leaked" % dry
	var drunk := pk_v.get_pool(pk_v.idx(ov.x + 2, ov.y + 1), TilePacket.Mat.WATER) \
			+ pk_v.get_pool(pk_v.idx(ov.x + 2, ov.y + 2), TilePacket.Mat.WATER)
	if drunk < 271:
		return "the vented cup drank only %d units -- the seed never vented" % drunk
	var a := pk_v.mat_total(TilePacket.Mat.WATER)
	for _t in 100:
		vented.tick()
	if pk_v.mat_total(TilePacket.Mat.WATER) != a:
		return "the vented room never settled"
	if not pk_c.assert_all() or not pk_v.assert_all():
		return "a ledger went red"
	return ""
