## Pinch-leak probe #3 (temporary): loads the human's saved census (slot_0) -- the real
## leaking scene -- and ticks it, logging every change with the flow stamps that wrote it.

extends SceneTree

const SLOT := "/home/ssjmarx/.var/app/io.github.MakovWait.Godots/data/godot/app_userdata/witchgame/editor/slot_0.bin"
const DIRS: Array[String] = ["NONE", "UP", "UP_R", "RIGHT", "DOWN_R", "DOWN", "DOWN_L", "LEFT", "UP_L"]
const SPLIT_TILES: Array[Vector2i] = [Vector2i(4, 5), Vector2i(6, 6), Vector2i(8, 7)]
const LEAK_SUBS: Array[Vector2i] = [Vector2i(8, 11), Vector2i(12, 13), Vector2i(16, 15)]   # the human's reported leak subtiles

## Load the saved census, tick it, then render the split tiles and audit the leak subtiles' blits.
func _init() -> void:
	var f := FileAccess.open(SLOT, FileAccess.READ)
	if f == null:
		print("no slot file at ", SLOT)
		quit()
		return
	var d: Dictionary = f.get_var()
	f.close()
	var w: int = d["w"] if d.has("w") else 15
	var h: int = d["h"] if d.has("h") else 15
	print("blob v=", d.get("v", 0), " cols=", d["cols"].size(), " room=", w, "x", h)
	var room := Room.new(w, h, 4242)
	var s := RoomState.new()
	for col in d["cols"]:
		s.cols.append(col)
	room.restore(s)
	var rd := ElementRenderer.new(room.stone, room.water, 4242)
	var fails := 0
	for t in 121:
		room.sand.tick()
		room.water.tick()
		if t % 10 == 0:
			# sample the render every ten ticks -- a flash shows up as a leak blit at any sampled tick
			for t2 in SPLIT_TILES:
				var blits: Array[Vector2i] = []
				var rec := func(kind: String, role: String, bx: int, by: int) -> void:
					if role.begins_with("lev") or role.begins_with("crest") or role.begins_with("wave"):
						blits.append(Vector2i(bx, by))
				rd.liquids.paint(t2.x, t2.y, t2.x * 16, t2.y * 16, rec)
				var counts := {}
				for b in blits:
					var sub := Vector2i((b.x - t2.x * 16) >> 3, (b.y - t2.y * 16) >> 3)
					counts[sub] = int(counts.get(sub, 0)) + 1
				print("t%d tile %s: %s" % [t, t2, counts])
				for ls in LEAK_SUBS:
					if (ls.x >> 1) == t2.x and (ls.y >> 1) == t2.y:
						var sub_local := Vector2i(ls.x & 1, ls.y & 1)
						if counts.has(sub_local):
							print("t%d LEAK: subtile %s drew %d liquid blits" % [t, ls, counts[sub_local]])
							fails += 1
	if fails == 0:
		print("PASS: no leak subtile drew liquid at any sampled tick")
	else:
		print("FAIL: %d leak blits across samples" % fails)
	quit()

## One line per tile: occlusion pattern, so the pinch's tile alignment is readable.
func _print_stone(room: Room) -> void:
	var pk := room.stone.packet
	for y in room.height:
		var parts: Array[String] = []
		for x in room.width:
			parts.append("%d,%d=%d" % [x, y, pk.occlusion_bits(pk.idx(x, y))])
		print("stone row %d: %s" % [y, " ".join(parts)])

## Water per tile, compact.
func _snapshot(room: Room) -> String:
	var parts: Array[String] = []
	for y in room.height:
		for x in room.width:
			var v := room.water.get_water(x, y)
			if v > 0:
				parts.append("%d,%d=%d" % [x, y, v])
	return " ".join(parts) if parts.size() > 0 else "(dry)"

## The flow stamps that wrote this tick -- the move rules sign their work.
func _flow(water: GridWater) -> String:
	var parts: Array[String] = []
	for y in water.height:
		for x in water.width:
			var m := water.get_flow_mag(x, y)
			if m > 0:
				parts.append("%d,%d=%d/%s" % [x, y, m, DIRS[water.get_flow_dir(x, y)]])
	return " ".join(parts) if parts.size() > 0 else "-"