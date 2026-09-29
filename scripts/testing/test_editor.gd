## The room editor v1 (world.md §8, the level format's seed): four persistent
## rooms on the F-keys, menu-driven paint over tiles and debug furniture, an
## inspector card, and a chorus of witches sharing one input -- a playground.

class_name TestEditor
extends TestSandbox

const SLOT_DIR := "user://editor"
const SLOT_PATH := SLOT_DIR + "/slot_%d.bin"
const EDITOR_SEED_BASE := 11   # rooms 0-3 seed 11-14, clear of every suite's seeds
const DEFAULT_ROOM := 11       # the fresh-slot carve: 11 wide keeps every U-shell write in bounds
const AMBIENCE_NAMES := ["blue", "red", "green", "yellow"]

enum Tool { STONE, WOOD, SOIL, ICE, DAMP, WATER, OIL, ACID, LAVA, STEAM, SMOKE, SRC_WATER, DRAIN, SRC_STEAM, OPEN_AIR }

var rooms: Array[Room] = []
var renderers: Array[ElementRenderer] = []
var sprites: Array[Sprite2D] = []
var mirrors: Array[CollisionMirror] = []
var room_witches: Array = []   # one Array[Witch] per room -- the chorus rosters
var observed := 0
var tool := Tool.WATER

# editor chrome: Controls on a high layer, never pixels in the CA picture
var ui: CanvasLayer
var menu_bar: HBoxContainer
var panels: Array[PanelContainer] = []
var inspector: PanelContainer
var inspect_label: Label

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

## Held strokes need a held button and a mouse clear of the chrome: RMB erases (furniture included), LMB lays the current tool.
func _paint_stroke(t: Vector2i) -> bool:
	if t.x < 0 or _over_ui():
		return false
	if not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		return false
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_erase_tile(t)
		mirrors[observed].sync()
		return true
	return _apply_tool(t)

## The shared erase plus the furniture column: RMB clears everything the editor can author at this tile.
func _erase_tile(t: Vector2i) -> void:
	super._erase_tile(t)
	stone.packet.set_debug(stone.idx(t.x, t.y), TilePacket.DebugTile.NONE)

## Lay one tool at the hover tile: solids and furniture refuse occupied ground, soil and ice lay one guarded subtile, liquids dose 255 through the tool path.
func _apply_tool(t: Vector2i) -> bool:
	var pk := stone.packet
	var i := stone.idx(t.x, t.y)
	match tool:
		Tool.STONE:
			if _lay_solid(t, GridStone.Terrain.STONE):
				mirrors[observed].sync()
				return true
		Tool.WOOD:
			if _lay_solid(t, GridStone.Terrain.WOOD):
				mirrors[observed].sync()
				return true
		Tool.SOIL:
			return _brush_guarded(pk, i, TilePacket.K_SOIL)
		Tool.ICE:
			return _brush_guarded(pk, i, TilePacket.K_ICE)
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

## Furniture goes onto cleared ground only (AIR, empty pool) -- the _lay_solid rule mirrored; it keeps a pool so matter can reach it.
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
			_carve_preset(rooms[k].stone, rooms[k].water, rows)

## Snapshot the observed room into slot k's file as an opaque census blob (the level format keeps its own lab); a crossed save also restores it into room k, live.
func _save_slot(k: int) -> void:
	var s := rooms[observed].snapshot()
	var f := FileAccess.open(SLOT_PATH % k, FileAccess.WRITE)
	if f == null:
		return
	f.store_var({"cols": s.cols, "ign": s.ignition, "wt": s.water_ticks, "st": s.sand_ticks})
	f.close()
	if k != observed:
		rooms[k].restore(s)

## Read slot k's census from disk as a RoomState; null when no file exists and the carve path takes over.
func _read_slot(k: int) -> RoomState:
	var f := FileAccess.open(SLOT_PATH % k, FileAccess.READ)
	if f == null:
		return null
	var d: Dictionary = f.get_var()
	var s := RoomState.new()
	for col in d["cols"]:
		s.cols.append(col)
	s.ignition = d["ign"]
	s.water_ticks = d["wt"]
	s.sand_ticks = d["st"]
	return s

## Build the chrome: three buttons (tiles, furniture, inspector) over their pop-up panels -- editor tooling, so default theme and rough edges are fine.
func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	menu_bar = HBoxContainer.new()
	menu_bar.position = Vector2(2, 2)
	ui.add_child(menu_bar)
	panels = [
		_build_panel(0, [["stone", Tool.STONE], ["wood", Tool.WOOD], ["soil", Tool.SOIL], ["ice", Tool.ICE], ["damp", Tool.DAMP], ["water", Tool.WATER], ["oil", Tool.OIL], ["acid", Tool.ACID], ["lava", Tool.LAVA], ["steam", Tool.STEAM], ["smoke", Tool.SMOKE]]),
		_build_panel(1, [["water source", Tool.SRC_WATER], ["drain", Tool.DRAIN], ["steam vent", Tool.SRC_STEAM], ["open air", Tool.OPEN_AIR]]),
	]
	var tiles := _chrome_button("tiles")
	tiles.pressed.connect(_open_menu.bind(0))
	menu_bar.add_child(tiles)
	var furn := _chrome_button("furn")
	furn.pressed.connect(_open_menu.bind(1))
	menu_bar.add_child(furn)
	var info := _chrome_button("info")
	info.pressed.connect(_toggle_inspector)
	menu_bar.add_child(info)
	inspector = PanelContainer.new()
	inspector.position = Vector2(132, 22)
	inspector.custom_minimum_size = Vector2(104, 0)
	inspector.visible = false
	inspect_label = Label.new()
	inspect_label.add_theme_font_size_override("font_size", 8)
	inspector.add_child(inspect_label)
	ui.add_child(inspector)

## One pop-up panel of tool buttons under the bar; starts hidden.
func _build_panel(k: int, entries: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = Vector2(2 + k * 108, 22)
	panel.visible = false
	var box := VBoxContainer.new()
	panel.add_child(box)
	for e in entries:
		var b := _chrome_button(e[0])
		b.pressed.connect(_pick_tool.bind(e[1]))
		box.add_child(b)
	ui.add_child(panel)
	return panel

## A small chrome button: 8px font, tight minimum.
func _chrome_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 8)
	b.custom_minimum_size = Vector2(48, 18)
	return b

## Toggle one menu: opening hides the other; a second click closes it.
func _open_menu(k: int) -> void:
	for p in panels.size():
		panels[p].visible = (p == k) and not panels[p].visible

## Pick a tool from a menu and close both -- one click selects, the strokes follow.
func _pick_tool(t: int) -> void:
	tool = t as TestEditor.Tool
	for p in panels:
		p.visible = false

## Toggle the inspector card.
func _toggle_inspector() -> void:
	inspector.visible = not inspector.visible

## True when the mouse sits on the chrome -- strokes are ignored there (raw button state reads true even when a Control consumed the click).
func _over_ui() -> bool:
	var p := get_global_mouse_position()
	if menu_bar.get_global_rect().has_point(p):
		return true
	for panel in panels:
		if panel.visible and panel.get_global_rect().has_point(p):
			return true
	return inspector.visible and inspector.get_global_rect().has_point(p)

## The observed room's witch under the mouse, if any -- her 8x24 hitbox, soles-centered.
func _hovered_witch() -> Witch:
	var p := get_global_mouse_position()
	for witch in room_witches[observed]:
		if Rect2(witch.position.x - 4.0, witch.position.y - 24.0, 8.0, 24.0).has_point(p):
			return witch
	return null

## The HUD line plus the inspector card's live text.
func _update_info(t: Vector2i) -> void:
	super._update_info(t)
	_update_inspector(t)

## Refresh the inspector: the hovered witch's thermal state, else the hovered tile's census down to furniture and flow -- the canonical deep readout.
func _update_inspector(t: Vector2i) -> void:
	if not inspector.visible:
		return
	var witch := _hovered_witch()
	if witch != null:
		inspect_label.text = "WITCH  heat %d/64  wet %d/64" % [witch.body.heat, witch.body.wetness]
		return
	if t.x < 0:
		inspect_label.text = ""
		return
	var pk := stone.packet
	var i := stone.idx(t.x, t.y)
	var txt := "TILE %d,%d  %s" % [t.x, t.y, GridStone.Terrain.keys()[pk.get_terrain(i)].to_lower()]
	txt += "\nsub s%d d%d i%d  damp %d/%d  fuel %d  fire %d" % [pk.get_sub(i, TilePacket.K_STONE), pk.get_sub(i, TilePacket.K_SOIL), pk.get_sub(i, TilePacket.K_ICE), pk.get_damp(i), pk.damp_capacity(i), pk.get_fuel(i), pk.get_fire(i)]
	txt += "\npool w%d o%d a%d l%d m%d v%d  free %d" % [pk.get_pool(i, TilePacket.Mat.WATER), pk.get_pool(i, TilePacket.Mat.OIL), pk.get_pool(i, TilePacket.Mat.ACID), pk.get_pool(i, TilePacket.Mat.LAVA), pk.get_pool(i, TilePacket.Mat.SMOKE), pk.get_pool(i, TilePacket.Mat.STEAM), pk.pool_free(i)]
	txt += "\nflow %d %s  %s  furn %s" % [water.get_flow_mag(t.x, t.y), GridWater.FlowDir.keys()[water.get_flow_dir(t.x, t.y)].to_lower(), "sealed" if water.is_air_sealed(t.x, t.y) else "vented", TilePacket.DebugTile.keys()[pk.get_debug(i)].to_lower()]
	inspect_label.text = txt
