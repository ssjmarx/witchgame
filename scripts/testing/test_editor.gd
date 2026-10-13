## The room editor v1 (world.md §8, the level format's seed): four persistent
## rooms on the F-keys, blocking overlay menus, the struct toggle and exact
## subtile painting, and a chorus of witches sharing one input -- a playground.

class_name TestEditor
extends TestSandbox

const SLOT_DIR := "user://editor"
const SLOT_PATH := SLOT_DIR + "/slot_%d.bin"
const EDITOR_SEED_BASE := 11   # rooms 0-3 seed 11-14, clear of every suite's seeds
const DEFAULT_ROOM := 11       # the fresh-slot carve: 11 wide keeps every U-shell write in bounds
const AMBIENCE_NAMES := ["blue", "red", "green", "yellow"]
const TOOL_PAGES: Array = [
	[["stone_s", Tool.STONE_S], ["wood_s", Tool.WOOD_S], ["soil", Tool.SOIL], ["damp", Tool.DAMP], ["water", Tool.WATER], ["oil", Tool.OIL], ["acid", Tool.ACID], ["lava", Tool.LAVA], ["steam", Tool.STEAM], ["smoke", Tool.SMOKE]],
	[["water source", Tool.SRC_WATER], ["drain", Tool.DRAIN], ["steam vent", Tool.SRC_STEAM], ["open air", Tool.OPEN_AIR]],
]

enum Tool { STONE_S, WOOD_S, SOIL, DAMP, WATER, OIL, ACID, LAVA, STEAM, SMOKE, SRC_WATER, DRAIN, SRC_STEAM, OPEN_AIR }

var rooms: Array[Room] = []
var renderers: Array[ElementRenderer] = []
var sprites: Array[Sprite2D] = []
var mirrors: Array[CollisionMirror] = []
var room_witches: Array = []   # one Array[Witch] per room -- the chorus rosters
var observed := 0
var tool := Tool.WATER
var struct_on := false         # the struct toggle: with it on, the solid brushes author structure membership cell by cell (world §3)
var struct_button: Button
var overlay: PanelContainer
var overlay_pause_saved := false

# editor chrome: Controls on a high layer, never pixels in the CA picture
var ui: CanvasLayer
var menu_bar: HBoxContainer

## Build the sibling rooms, renderers, sprites, and mirrors; load every slot from disk or carve the default bowl; build the chrome; observe slot 0.
func _setup() -> void:
	rooms = [room]
	renderers = [renderer]
	sprites = [sprite]
	room_witches = [[]]
	for k in range(1, 4):
		var r := Room.new(GRID_W, GRID_H, EDITOR_SEED_BASE + k)
		rooms.append(r)
		var rd := ElementRenderer.new(r.stone, r.water, EDITOR_SEED_BASE + k)
		renderers.append(rd)
		var sp := Sprite2D.new()
		sp.centered = false
		sp.texture = rd.texture
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sp)
		sprites.append(sp)
		room_witches.append([])
	for k in 4:
		mirrors.append(CollisionMirror.new(rooms[k].stone))
		add_child(mirrors[k])
	for rd in renderers:
		rd.furniture = true
	_load_slots()
	_build_ui()
	_observe(0)

## Repoint the aliases at room k: hide the other pictures, park their mirrors out of the tree and their witches -- frozen by absence, colliders included (an out-of-tree body does not exist to physics).
func _observe(k: int) -> void:
	observed = k
	stone = rooms[k].stone
	water = rooms[k].water
	renderer = renderers[k]
	for s in sprites.size():
		sprites[s].visible = s == k
	for m in mirrors.size():
		if m == k and mirrors[m].get_parent() == null:
			add_child(mirrors[m])
		elif m != k and mirrors[m].get_parent() != null:
			remove_child(mirrors[m])
	for w in room_witches.size():
		for witch in room_witches[w]:
			witch.visible = w == k
			witch.process_mode = Node.PROCESS_MODE_INHERIT if w == k else Node.PROCESS_MODE_DISABLED
	mirrors[k].sync()
	renderer.redraw()

## One tick: the observed room rules, its mirror follows, its witches sample their reads from the settled state.
func _tick_world() -> void:
	rooms[observed].tick()
	mirrors[observed].sync()
	for witch in room_witches[observed]:
		witch.sample_liquid()

## Clear the observed room only -- slots keep their saved bytes until crossed again; witches are actors and survive (world.md §8: actors never ride the census).
func _clear_world() -> void:
	rooms[observed].reset()
	mirrors[observed].sync()

## Scene keys: F1-F4 observe a room, Ctrl+F1-F4 snapshot into that slot (a crossed save copies live), N spawns a witch at hover, BACKSPACE despawns the oldest, I ignites at hover, P pauses (Space is the witches').
func _handle_key(k: int) -> bool:
	match k:
		KEY_F1, KEY_F2, KEY_F3, KEY_F4:
			var slot := k - KEY_F1
			if Input.is_key_pressed(KEY_CTRL):
				_save_slot(slot)
			else:
				_observe(slot)
			return true
		KEY_N:
			var t := _hover_tile()
			if t.x >= 0:
				_spawn_witch(t)
			return true
		KEY_BACKSPACE:
			_despawn_oldest()
			return true
		KEY_I:
			var t := _hover_tile()
			if t.x >= 0:
				rooms[observed].react.ignite(t.x, t.y)
			return true
		KEY_P:
			paused = not paused
			return true
		KEY_M:
			renderer.fx.set_ambience(renderer.fx.set_index + 1)
			return true
	return false

## Space is the witches' jump -- swallow it before the harness reads pause; pause lives on P.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_SPACE:
		return
	super._unhandled_key_input(event)

## Held strokes need a held button and a mouse clear of the chrome: RMB erases the exact subtile (a cut), LMB lays the current tool -- solid brushes paint the exact subtile cell, liquids and furniture dose the tile. Strokes are ignored while the overlay menu is open.
func _paint_stroke(t: Vector2i) -> bool:
	if t.x < 0 or _over_ui() or overlay.visible:
		return false
	if not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		return false
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_erase_sub(_hover_sub())
		mirrors[observed].sync()
		renderer.redraw()
		return true
	return _apply_tool(t)

## Erase one exact subtile cell: its matter bit (any kind) through the cut path -- the cut re-partitions; a cell without solid matter falls back to the tile-level wipe (liquids, fire, furniture).
func _erase_sub(sub: Vector2i) -> void:
	if sub.x < 0 or sub.y < 0:
		return
	var pk := stone.packet
	var i := stone.idx(sub.x >> 1, sub.y >> 1)
	var bit := (1 if (sub.y & 1) == 1 else 4) << (sub.x & 1)
	var matter: int = pk.get_sub(i, TilePacket.K_STONE) | pk.get_sub(i, TilePacket.K_WOOD) | pk.get_sub(i, TilePacket.K_SOIL)
	if (matter & bit) == 0:
		for m in TilePacket.MAT_COUNT:
			pk.set_pool(i, m, 0)
		pk.set_fire(i, 0)
		pk.set_debug(i, TilePacket.DebugTile.NONE)
		return
	if (pk.get_sub(i, TilePacket.K_STONE) & bit) != 0:
		pk.set_sub(i, TilePacket.K_STONE, pk.get_sub(i, TilePacket.K_STONE) & ~bit)
	if (pk.get_sub(i, TilePacket.K_WOOD) & bit) != 0:
		pk.set_sub(i, TilePacket.K_WOOD, pk.get_sub(i, TilePacket.K_WOOD) & ~bit)
	if (pk.get_sub(i, TilePacket.K_SOIL) & bit) != 0:
		pk.set_sub(i, TilePacket.K_SOIL, pk.get_sub(i, TilePacket.K_SOIL) & ~bit)
	rooms[observed].sand.structures.repartition_around(sub.x >> 1, sub.y >> 1)

## The hover in expanded-grid subtile coords -- the exact 8x8 cell under the mouse.
func _hover_sub() -> Vector2i:
	var p := get_global_mouse_position()
	var s := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
	if s.x < 0 or s.y < 0 or s.x >= GRID_W * 2 or s.y >= GRID_H * 2:
		return Vector2i(-1, -1)
	return s

## Paint one exact subtile cell: the pointed-at cell only, empty across every kind; with the struct toggle on, stone and wood carry membership (authored structures grow cell by cell, world §3).
func _paint_cell(sub: Vector2i, kind: int) -> bool:
	if sub.x < 0 or sub.y < 0:
		return false
	var pk := stone.packet
	var i := stone.idx(sub.x >> 1, sub.y >> 1)
	var bit := (1 if (sub.y & 1) == 1 else 4) << (sub.x & 1)
	var occupied: int = pk.get_sub(i, TilePacket.K_STONE) | pk.get_sub(i, TilePacket.K_WOOD) | pk.get_sub(i, TilePacket.K_SOIL)
	if (occupied & bit) != 0:
		if struct_on and kind != TilePacket.K_SOIL:
			rooms[observed].sand.structures.stamp(sub.x >> 1, sub.y >> 1, bit)
			return true
		return false   # the exact cell holds matter: precise editing refuses
	pk.set_sub(i, kind, pk.get_sub(i, kind) | bit)
	if struct_on and kind != TilePacket.K_SOIL:
		rooms[observed].sand.structures.stamp(sub.x >> 1, sub.y >> 1, bit)
	return true

## Lay one tool at the hover: liquids dose 255 through the tool path, damp and furniture are tile-level; the solid brushes paint the exact subtile cell under the mouse (world §3 authoring).
func _apply_tool(t: Vector2i) -> bool:
	var pk := stone.packet
	var i := stone.idx(t.x, t.y)
	match tool:
		Tool.STONE_S:
			return _paint_cell(_hover_sub(), TilePacket.K_STONE)
		Tool.WOOD_S:
			return _paint_cell(_hover_sub(), TilePacket.K_WOOD)
		Tool.SOIL:
			return _paint_cell(_hover_sub(), TilePacket.K_SOIL)
		Tool.DAMP:
			return pk.add_damp(i, 64) > 0
		Tool.WATER:
			water.set_water(t.x, t.y, 255)
			return true
		Tool.OIL:
			pk.set_pool(i, TilePacket.Mat.OIL, 255)
			return true
		Tool.ACID:
			pk.set_pool(i, TilePacket.Mat.ACID, 255)
			return true
		Tool.LAVA:
			pk.set_pool(i, TilePacket.Mat.LAVA, 255)
			return true
		Tool.STEAM:
			pk.set_pool(i, TilePacket.Mat.STEAM, 255)
			return true
		Tool.SMOKE:
			pk.set_pool(i, TilePacket.Mat.SMOKE, 255)
			return true
		Tool.SRC_WATER:
			return _lay_furniture(pk, i, TilePacket.DebugTile.WATER_SOURCE)
		Tool.DRAIN:
			return _lay_furniture(pk, i, TilePacket.DebugTile.DRAIN)
		Tool.SRC_STEAM:
			return _lay_furniture(pk, i, TilePacket.DebugTile.STEAM_VENT)
		Tool.OPEN_AIR:
			return _lay_furniture(pk, i, TilePacket.DebugTile.OPEN_AIR)
	return false

## The guarded subtile brush (the witch lab's soil verb, generalized): one subtile into the lowest empty slot when the budget takes it.
func _brush_guarded(pk: TilePacket, i: int, kind: int) -> bool:
	var n := pk.get_sub(i, kind)
	if n >= 15 or pk.pool_total(i) > maxi(0, pk.pool_capacity(i) - 64):
		return false
	pk.set_sub(i, kind, n | (n + 1))
	mirrors[observed].sync()
	return true

## Furniture goes onto cleared ground only (no matter, empty pool) -- the _lay_matter rule mirrored; it keeps a pool so matter can reach it.
func _lay_furniture(pk: TilePacket, i: int, d: int) -> bool:
	if pk.get_terrain(i) != TilePacket.T.AIR or pk.pool_total(i) > 0:
		return false
	pk.set_debug(i, d)
	return true

## Spawn a new witch at tile t (feet at the tile's floor edge) -- every spawn is a fresh body; they all read the same keys and move as a chorus.
func _spawn_witch(t: Vector2i) -> void:
	var witch := Witch.new(rooms[observed])
	add_child(witch)
	witch.position = Vector2(t.x * 16.0 + 8.0, t.y * 16.0 + 16.0)
	room_witches[observed].append(witch)

## Despawn the oldest witch in the observed room, FIFO -- her _exit_tree leaves the bridge registry on its own.
func _despawn_oldest() -> void:
	if room_witches[observed].is_empty():
		return
	var witch: Witch = room_witches[observed][0]
	room_witches[observed].pop_front()
	witch.queue_free()

## Every slot at setup: a file on disk restores its census byte-exact, an empty slot carves the default bowl.
func _load_slots() -> void:
	DirAccess.make_dir_recursive_absolute(SLOT_DIR)
	var rows: Array = []
	for _y in DEFAULT_ROOM:
		rows.append(".".repeat(DEFAULT_ROOM))
	for k in rooms.size():
		var s := _read_slot(k)
		if s != null:
			rooms[k].restore(s)
		else:
			_carve_preset(rooms[k].stone, rooms[k].water, rows, rooms[k].sand.structures)

## Snapshot the observed room into slot k's file as an opaque census blob (the level format keeps its own lab); a crossed save also restores it into room k, live. Version 4: the cleanup cut's sixteen columns.
func _save_slot(k: int) -> void:
	var s := rooms[observed].snapshot()
	var f := FileAccess.open(SLOT_PATH % k, FileAccess.WRITE)
	if f == null:
		return
	f.store_var({"v": 4, "cols": s.cols, "ign": s.ignition, "wb": s.woodburn, "wt": s.water_ticks, "st": s.sand_ticks})
	f.close()
	if k != observed:
		rooms[k].restore(s)

## Read slot k's census from disk as a RoomState; null when no file exists and the carve path takes over. Pre-version blobs migrate: authored terrain converts to pre-fused matter and the fuel column drops (world §3); version 3's fifteen columns drop the tags column and gain the reserved pair.
func _read_slot(k: int) -> RoomState:
	var f := FileAccess.open(SLOT_PATH % k, FileAccess.READ)
	if f == null:
		return null
	var d: Dictionary = f.get_var()
	var s := RoomState.new()
	for col in d["cols"]:
		s.cols.append(col)
	if int(d.get("v", 0)) < 3:
		var migrated: Array = rooms[k].stone.packet.migrate_legacy_cols(s.cols, rooms[k].width, rooms[k].height)
		s.cols.clear()
		for col in migrated:
			s.cols.append(col)
	elif int(d.get("v", 0)) == 3:
		# version 3's fifteen: tags at eleven dies -- shift fire, debug, struct down one, append the zeroed reserve
		var n := s.cols[0].size()
		var remapped: Array = [s.cols[0], s.cols[1], s.cols[2], s.cols[3], s.cols[4], s.cols[5], s.cols[6], s.cols[7], s.cols[8], s.cols[9], s.cols[10], s.cols[12], s.cols[13], s.cols[14]]
		var zero := PackedByteArray()
		zero.resize(n)
		remapped.append(zero)
		remapped.append(zero.duplicate())
		s.cols = remapped
	s.ignition = d["ign"]
	if d.has("wb"):
		s.woodburn = d["wb"]
	s.water_ticks = d["wt"]
	s.sand_ticks = d["st"]
	return s

## Build the chrome: two category buttons and the struct toggle over one blocking overlay menu -- editor tooling, so default theme and rough edges are fine.
func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	menu_bar = HBoxContainer.new()
	menu_bar.position = Vector2(2, 2)
	ui.add_child(menu_bar)
	for k in TOOL_PAGES.size():
		var cat := _chrome_button("matter" if k == 0 else "furn")
		cat.pressed.connect(_open_menu.bind(TOOL_PAGES[k]))
		menu_bar.add_child(cat)
	struct_button = _chrome_button("struct: off")
	struct_button.pressed.connect(_toggle_struct)
	menu_bar.add_child(struct_button)
	overlay = PanelContainer.new()
	overlay.visible = false
	ui.add_child(overlay)

## Open the blocking overlay menu for one page: the sim pauses until a brush is picked (or the menu is dismissed), and the grid auto-fits roughly square.
func _open_menu(page: Array) -> void:
	overlay_pause_saved = paused
	paused = true
	for child in overlay.get_children():
		child.queue_free()
	var grid := GridContainer.new()
	grid.columns = ceili(sqrt(page.size() + 1))
	for e in page:
		var b := _chrome_button(e[0])
		b.custom_minimum_size = Vector2(72, 28)
		b.pressed.connect(_pick_tool.bind(e[1]))
		grid.add_child(b)
	var cancel := _chrome_button("cancel")
	cancel.pressed.connect(_close_menu)
	grid.add_child(cancel)
	overlay.add_child(grid)
	overlay.visible = true

## Close the overlay menu and restore the pause state.
func _close_menu() -> void:
	overlay.visible = false
	paused = overlay_pause_saved

## Pick a tool from the overlay and close it -- one click selects, the strokes follow.
func _pick_tool(t: int) -> void:
	tool = t as TestEditor.Tool
	_close_menu()

## Flip the struct toggle: with it on, the solid brushes author structure membership cell by cell (world §3).
func _toggle_struct() -> void:
	struct_on = not struct_on
	struct_button.text = "struct: on" if struct_on else "struct: off"

## A small chrome button: 8px font, tight minimum.
func _chrome_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 8)
	b.custom_minimum_size = Vector2(48, 18)
	return b

## True when the mouse sits on the chrome -- strokes are ignored there (raw button state reads true even when a Control consumed the click).
func _over_ui() -> bool:
	var p := get_global_mouse_position()
	if menu_bar.get_global_rect().has_point(p):
		return true
	return overlay.visible and overlay.get_global_rect().has_point(p)

## The HUD line, plus the subtile hover -- the exact cell the cursor and the brushes read.
func _update_info(t: Vector2i) -> void:
	super._update_info(t)
	renderer.hover_sub = _hover_sub()
