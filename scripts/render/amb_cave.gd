## The dark cave's background module (world.md §9, the ambiance contract):
## a baked texture (the void default, lumpy rock masses, thick spikes) served
## whole, plus drip eras as the one motion verb. World-blind by contract.

class_name AmbCave
extends AmbGen

const TILE := 16   # pixels per tile, the renderer's constant mirrored
const SALT := 0xCA7E         # the cave's layout salt: domain seed XOR this -- its own stream
const ERA_SALT := 0xD21F     # the cave's era salt, mixed with the slot -- drips replay exactly
const GOLDEN := 2654435761   # Knuth's mixer, the era pattern's constant

# -- Cave tuning ------
const ROCK_MIN := 0        # <tune> — large rock masses on the void
const ROCK_MAX := 1
const BUMP_R_MIN := 8      # <tune> — each mass is 2-4 overlapping bumps, this radius range
const BUMP_R_MAX := 64
const TITE_GAP_STEP := 16   # <tune> — the spike walks: chance points per tile since the last (smaller = rarer)
const TITE_W_MIN := 8      # <tune> — stalactite base width range, pixels
const TITE_W_MAX := 16
const MITE_W_MIN := 16     # <tune> — stalagmites run wider
const MITE_W_MAX := 32
const MITE_MAX := 128       # <tune> — the stalagmite length cap: cones truncate into stubs
const SPIKE_TIP_W := 1     # <tune> — the width a spike tapers to
const SPIKE_TIP_RUN := 4   # <tune> — rows past full taper before the spike ends
const DRIPS_MIN := 1       # <tune> — drips born per era
const DRIPS_MAX := 4
const DRIP_FALL_MAX := 16  # <tune> — pixels a drip falls before the dark takes it
const ERA_LEN := 32        # <tune> — ticks per era: the drip re-roll cadence

var width: int
var height: int
var bank: Array[Color]
var _seed := 0                           # the domain seed, kept for the era derivation
var rng := RandomNumberGenerator.new()   # the layout stream: consumed only at bake
var era := RandomNumberGenerator.new()   # the drip era stream: re-seeded per slot
var _base: Image                         # the permanent bake -- every serve copies it fresh (the copy is the erase)
var _tip := PackedInt32Array()           # baked stalactite tips, packed x | y << 8 -- the drip sources
var _slot := -1                          # the era the drip table was baked for
var _drip := PackedInt32Array()          # this era's drips: tip | birth << 6 | fall << 11 | speed bit

## Bind geometry, the bank, and the domain seed; derive the layout stream, bake the permanent base, and serve the first copy.
func _init(p_width: int, p_height: int, p_bank: Array[Color], p_seed: int) -> void:
	width = p_width
	height = p_height
	bank = p_bank
	_seed = p_seed
	rng.seed = p_seed ^ SALT
	texture = Image.create(width * TILE, height * TILE, false, Image.FORMAT_RGBA8)
	_base = Image.create(width * TILE, height * TILE, false, Image.FORMAT_RGBA8)
	_bake()
	texture.blit_rect(_base, Rect2i(0, 0, width * TILE, height * TILE), Vector2i.ZERO)

## Serve the background: re-roll eras on the cave's cadence, copy the base whole (dumb and bulletproof -- it is the erase), then stamp the living drips.
func serve(tick: int) -> void:
	@warning_ignore("integer_division")
	var slot := tick / ERA_LEN
	if slot != _slot:
		_slot = slot
		_bake_era(slot)
	texture.blit_rect(_base, Rect2i(0, 0, width * TILE, height * TILE), Vector2i.ZERO)
	_draw_drips(tick)

## The bake, one fixed-order pass over the layout stream: the void field, the rock masses, then both spike edges -- a pure function of the seed, never re-rolled.
func _bake() -> void:
	_base.fill(bank[0])
	_bake_rocks()
	_bake_spikes(true)
	_bake_spikes(false)

## The near layer: large lumpy masses on the void -- each a cluster of overlapping bumps placed by count, sparse by tuning.
func _bake_rocks() -> void:
	var wpx := width * TILE
	var hpx := height * TILE
	for _r in rng.randi_range(ROCK_MIN, ROCK_MAX):
		var cx := rng.randi_range(12, wpx - 13)
		var cy := rng.randi_range(12, hpx - 13)
		for _b in rng.randi_range(2, 4):
			var r := rng.randi_range(BUMP_R_MIN, BUMP_R_MAX)
			_bake_bump(cx + rng.randi_range(-r, r), cy + rng.randi_range(-r, r), r)

## One bump: an ellipse span per row -- a lit rim on top, a shaded underside, the structure body between; crisp clamped spans, it is the near layer.
func _bake_bump(cx: int, cy: int, r: int) -> void:
	var wpx := width * TILE
	var hpx := height * TILE
	for dy in range(-r, r + 1):
		var span := int(sqrt(float(r * r - dy * dy)))
		if span <= 0:
			continue
		var y := cy + dy
		if y < 0 or y >= hpx:
			continue
		var col := bank[3] if dy == -r else (bank[1] if dy >= r - 2 else bank[2])
		var x0 := maxi(0, cx - span)
		var x1 := mini(wpx - 1, cx + span)
		if x1 >= x0:
			_base.fill_rect(Rect2i(x0, y, x1 - x0 + 1, 1), col)

## One spike edge: the spacing walk (chance rising per tile, reset on spawn) -- slow steps make the spikes rare.
func _bake_spikes(down: bool) -> void:
	var streak := 0
	for x in width:
		if rng.randi_range(0, 99) < streak * TITE_GAP_STEP:
			streak = 0
			_bake_spike(x, down)
		else:
			streak += 1

## One spike at column x: a rolled girth and taper, its length emergent -- the cone runs until the tip width plus a short run; stalactites hang and bank their tips as drip sources, stalagmites rise capped and stubby.
func _bake_spike(x: int, down: bool) -> void:
	var wpx := width * TILE
	var hpx := height * TILE
	var w := rng.randi_range(TITE_W_MIN, TITE_W_MAX) if down else rng.randi_range(MITE_W_MIN, MITE_W_MAX)
	var half := (w + 1) >> 1
	var sx := clampi(x * TILE + rng.randi_range(4, 12), half, wpx - half)
	var taper := rng.randi_range(1, 2) if down else rng.randi_range(2, 3)
	@warning_ignore("shadowed_global_identifier")
	var len := (w - SPIKE_TIP_W) * taper + SPIKE_TIP_RUN
	if not down:
		len = mini(len, MITE_MAX)
	for d in len:
		if d > 0 and d % taper == 0 and w > SPIKE_TIP_W:
			w -= 1
		var px := sx - (w >> 1)
		var y := d if down else hpx - 1 - d
		_base.fill_rect(Rect2i(px, y, w, 1), bank[2])
		if d < (len >> 1):
			_base.set_pixel(px, y, bank[3])   # wet gleam down the left face, the lit half
		if down and d == len - 1:
			_tip.append(sx | (y << 8))

## Bake one era of drips: the era stream re-seeded (cave era salt XOR the golden-mixed slot), the count rolled, each drip's tip, birth, fall, and speed packed into one int.
func _bake_era(slot: int) -> void:
	era.seed = _seed ^ ERA_SALT ^ (slot * GOLDEN)
	_drip.clear()
	if _tip.is_empty():
		return
	for _d in era.randi_range(DRIPS_MIN, DRIPS_MAX):
		var tip := era.randi_range(0, _tip.size() - 1)
		var birth := era.randi_range(0, ERA_LEN - 1)
		var fall := era.randi_range(4, DRIP_FALL_MAX)
		var speed := 1 + era.randi_range(0, 1)
		_drip.append(tip | (birth << 6) | (fall << 11) | ((speed - 1) << 15))

## Stamp the living drips: a 1x2 bead of accent falling from its tip -- existence from the era bake, position arithmetic, the base copy behind it the erase.
func _draw_drips(tick: int) -> void:
	var local := tick % ERA_LEN
	for packed in _drip:
		var birth := (packed >> 6) & 31
		if local < birth:
			continue
		var fall := (packed >> 11) & 15
		var speed := 1 + ((packed >> 15) & 1)
		var d := local - birth
		if d * speed >= fall:
			continue   # the dark took it
		var tip := _tip[packed & 63]
		var y := ((tip >> 8) & 255) + 1 + d * speed
		if y >= height * TILE - 1:
			continue
		texture.set_pixel(tip & 255, y, bank[3])
		texture.set_pixel(tip & 255, y + 1, bank[3])
