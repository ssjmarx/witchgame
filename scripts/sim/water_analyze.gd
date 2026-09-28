## The label pass (world.md §3): connected liquid bodies (one pressure network
## each, mixtures included), air pockets with their body-contact rows, and the
## escape map -- which air reaches open sky. Per-tick opinion, one tick stale.

class_name WaterAnalyze
extends RefCounted

var width: int
var height: int
var stone: GridStone
var pk: TilePacket

var _region_of: PackedInt32Array
var _regions: Array = []       # per pocket: [{ body_top: { body id -> row } }]
var _escape: PackedByteArray   # per cell: the air here can reach open sky
var _body_of: PackedInt32Array # per cell: connected-water body id, -1 = none
var _next_body_id := 0

## Size the label arrays; everything starts unlabelled.
func _init(w: int, h: int, terrain: GridStone) -> void:
	width = w
	height = h
	stone = terrain
	pk = terrain.packet
	_body_of = PackedInt32Array()
	_body_of.resize(w * h)
	_body_of.fill(-1)
	_region_of = PackedInt32Array()
	_region_of.resize(w * h)
	_region_of.fill(-1)
	_escape = PackedByteArray()
	_escape.resize(w * h)

## Clear every label -- the world reset path.
func reset() -> void:
	_body_of.fill(-1)
	_next_body_id = 0
	_region_of.fill(-1)
	_regions.clear()
	_escape.fill(false)

## Rebuild this tick's labels: merged liquid bodies (any material — one pressure network), air pockets, escape flags.
func analyze() -> void:
	_body_of.fill(-1)
	_next_body_id = 0
	_region_of.fill(-1)
	_regions.clear()
	for i in width * height:
		if pk.pool_total(i) >= GridWater.LINE and _body_of[i] == -1:
			_flood_body(i)
	for i in width * height:
		if _is_air_idx(i) and _region_of[i] == -1:
			_flood_region(i)
	_compute_escape()

## True when this cell's air can reach open sky.
func escape_at(i: int) -> bool:
	return _escape[i]

## The connected-liquid-body id at cell i, -1 = none.
func body_at(i: int) -> int:
	return _body_of[i]

## The air-pocket id at cell i, -1 = none.
func region_at(i: int) -> int:
	return _region_of[i]

## The pocket's body-contact table (body id -> highest touching row); the caller owns the region guard.
func body_top(region: int) -> Dictionary:
	return _regions[region].body_top

## Flood-fill one connected liquid body (any material — pressure transmits through mixtures), stamping its id as we go.
func _flood_body(start: int) -> void:
	var id := _next_body_id
	_next_body_id += 1
	var stack := PackedInt32Array()
	stack.push_back(start)
	_body_of[start] = id
	while not stack.is_empty():
		var i: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var x := i % width
		if x > 0 and pk.pool_total(i - 1) >= GridWater.LINE and _body_of[i - 1] == -1:
			_body_of[i - 1] = id
			stack.push_back(i - 1)
		if x < width - 1 and pk.pool_total(i + 1) >= GridWater.LINE and _body_of[i + 1] == -1:
			_body_of[i + 1] = id
			stack.push_back(i + 1)
		if i >= width and pk.pool_total(i - width) >= GridWater.LINE and _body_of[i - width] == -1:
			_body_of[i - width] = id
			stack.push_back(i - width)
		if i + width < width * height and pk.pool_total(i + width) >= GridWater.LINE and _body_of[i + width] == -1:
			_body_of[i + width] = id
			stack.push_back(i + width)

## Label one air pocket; record its highest contact per body (a rotation's upper junction).
func _flood_region(start: int) -> void:
	var id := _regions.size()
	var cells := PackedInt32Array()
	var stack := PackedInt32Array()
	stack.push_back(start)
	_region_of[start] = id
	while not stack.is_empty():
		var i: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		cells.push_back(i)
		var x := i % width
		if x > 0 and _is_air_idx(i - 1) and _region_of[i - 1] == -1:
			_region_of[i - 1] = id
			stack.push_back(i - 1)
		if x < width - 1 and _is_air_idx(i + 1) and _region_of[i + 1] == -1:
			_region_of[i + 1] = id
			stack.push_back(i + 1)
		if i >= width and _is_air_idx(i - width) and _region_of[i - width] == -1:
			_region_of[i - width] = id
			stack.push_back(i - width)
		if i + width < width * height and _is_air_idx(i + width) and _region_of[i + width] == -1:
			_region_of[i + width] = id
			stack.push_back(i + width)
	var body_top := {}   # body id -> row of its highest cell touching us
	for i in cells:
		var x := i % width
		if x > 0:
			_note_contact(i - 1, body_top)
		if x < width - 1:
			_note_contact(i + 1, body_top)
		if i >= width:
			_note_contact(i - width, body_top)
		if i + width < width * height:
			_note_contact(i + width, body_top)
	_regions.append({ "body_top": body_top })

## Record a pocket cell's orthogonal neighbor as a body contact, keeping the highest row per body.
func _note_contact(n: int, body_top: Dictionary) -> void:
	if pk.pool_total(n) < GridWater.LINE:
		return
	var b := _body_of[n]
	if b < 0:
		return
	@warning_ignore("integer_division")
	var row := n / width
	if not body_top.has(b) or row < int(body_top[b]):
		body_top[b] = row

## Mark every cell whose air can reach open sky; a monotone fixpoint, so order never matters.
func _compute_escape() -> void:
	_escape.fill(false)
	var changed := true
	while changed:
		changed = false
		for y in height:
			for x in width:
				var i := pk.idx(x, y)
				if _escape[i] or stone.is_solid(x, y):
					continue
				var ok := y == 0  # open sky above the map
				if not ok and _escape[i - width]:
					ok = true  # rise through air, or bubble up through liquid
				if not ok and y > 0 and stone.is_solid(x, y - 1):
					if (x > 0 and _escape[i - 1]) or (x < width - 1 and _escape[i + 1]):
						ok = true  # pinned under a ceiling: slide sideways
				if not ok and pk.pool_total(i) <= GridWater.AIR_PASSABLE_MAX \
						and ((x > 0 and _escape[i - 1] and pk.pool_total(i - 1) <= GridWater.AIR_PASSABLE_MAX)
						or (x < width - 1 and _escape[i + 1] and pk.pool_total(i + 1) <= GridWater.AIR_PASSABLE_MAX)
						or (y > 0 and _escape[i - width] and pk.pool_total(i - width) <= GridWater.AIR_PASSABLE_MAX)
						or (y < height - 1 and _escape[i + width] and pk.pool_total(i + width) <= GridWater.AIR_PASSABLE_MAX)):
					ok = true  # air flows through air
				if ok:
					_escape[i] = true
					changed = true

## Flat-index form of is_air_passable.
func _is_air_idx(i: int) -> bool:
	var p := pk.xy_of(i)
	return not stone.is_solid(p.x, p.y) and pk.pool_total(i) <= GridWater.AIR_PASSABLE_MAX
