## The bake library (tileset lab): pure image-in/image-out passes shared by the
## bake scripts and the palette suite -- the colorless baseline quantizer and the
## bank colorizer. No paths, no side effects; callers load and save.

extends RefCounted

## Quantize src to the colorless baseline: every used color maps to its nearest bank slot by squared RGB distance, written as that slot's baseline gray level with alpha preserved. Returns [image, report] -- the report names each mapping and warns when distinct used colors exceed the bank.
func baseline_image(src: Image, bank: Array) -> Array:
	var img := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	var slots := {}
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a8 == 0:
				continue   # the new image starts transparent black; nothing to write
			var key := c.to_html(false)
			if not slots.has(key):
				slots[key] = nearest_slot(c, bank)
			var g: Color = Palette.BASELINE_LEVELS[slots[key]]
			g.a = c.a
			img.set_pixel(x, y, g)
	var report := PackedStringArray()
	for key in slots:
		var slot: int = slots[key]
		report.append("%s -> slot %d (%s)" % [key, slot, (bank[slot] as Color).to_html(false)])
	if slots.size() > bank.size():
		report.append("WARN: %d distinct colors against a %d-slot bank -- hand-edit the baseline" % [slots.size(), bank.size()])
	return [img, report]

## Colorize a baseline image with a bank: each pixel's gray level maps back to its slot's bank color, alpha preserved. Returns [image, unmapped] -- unmapped counts pixels whose gray is no baseline level (hand-edits to fix).
func color_image(src: Image, bank: Array) -> Array:
	var img := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	var unmapped := 0
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a8 == 0:
				continue
			var slot := level_slot(c)
			if slot < 0:
				unmapped += 1
				continue
			var b: Color = bank[slot]
			b.a = c.a
			img.set_pixel(x, y, b)
	return [img, unmapped]

## The gray level's slot index, -1 when the pixel is no baseline level; tolerance 8 absorbs hand-edit antialiasing without crossing the 85-wide level spacing.
func level_slot(c: Color) -> int:
	for i in Palette.BASELINE_LEVELS.size():
		var lv: Color = Palette.BASELINE_LEVELS[i]
		if absi(c.r8 - lv.r8) <= 8 and absi(c.g8 - lv.g8) <= 8 and absi(c.b8 - lv.b8) <= 8:
			return i
	return -1

## The bank slot whose color sits nearest c by squared RGB distance; deterministic, first index wins ties.
func nearest_slot(c: Color, bank: Array) -> int:
	var best := 0
	var best_d := 1 << 24
	for i in bank.size():
		var b: Color = bank[i]
		var dr := c.r8 - b.r8
		var dg := c.g8 - b.g8
		var db := c.b8 - b.b8
		var d := dr * dr + dg * dg + db * db
		if d < best_d:
			best = i
			best_d = d
	return best
