# current_plan.md — the working roadmap

*The plan of record: what is being built next and the rulings each item carries.
The only doc allowed to describe future work in detail. Items are deleted from
here as they ship (their rulings land in the main docs; the session record lands
in `dev_log.md`). The main docs carry current law; `dev_log.md` carries evidence.*

*Standing audit bar for everything below: **Game Boy plausible** — one 10 Hz integer
world that looks like a 1994 programmer just barely got it to work. Powers of two
wherever a number is chosen. The tile grid is privileged (THE gameboy-authentic
shape). Structures and buoyancy are big gameplay-positives and stay.*

## 1. The tileset lab

**Goal: every single visible game asset is a PNG colored by the palette bank — no
exceptions.** The renderer moves to an 8×8 tile atlas; all currently rendered matter
state is baked into sprite sheets that become real PNGs actually loaded by the game
(bake today's look, hand-edit in Aseprite, iterate — the perfect art pipeline).
**The witch converts to greyscale** and starts authoring her colors from the palette
bank in this lab too.

**Stage 2 shipped — the atlas foundation + matter, gas, and fire** (`tile_atlas.gd` +
`bake_tiles.gd`, PT6/PT7): the 8×8 tile atlas bakes from slot-index painters through
the same gray→bank pipeline (one shared `LAYOUT`, one bake per bank under
`assets/baked/`); `ElementRenderer` blits matter (fill + lip/seam strips, the seam
rule unchanged), soil (damp quantized to subtile bands with a quarter-step boundary),
gas (subtile bands, smoke-top/steam-below, complementary dither phases mixing at the
boundary — no blending), and fire (hash-keyed ember + lick tiles). The per-pixel
paths for those passes are deleted; **liquids and ambiance stay procedural until
their own stages** (2b liquids: level/crest/rain tiles, the waterline lift, the
matter+liquid compositing table; 2c ambience: the AmbGen offline bake and the drip
animation). Wood's plank art went flat at 8×8 — texture returns by hand in the gray
atlas.

- **8×8 is the shape** — the DMG's native tile; render grid = matter grid =
  collision grid, so partial-filled tiles stop being a special case anywhere.
- **Water:** four level tiles (2/4/6/8 px lines); the water line draws the bottom
  subtile full, the top subtile at level — the top two level tiles double as
  **crest tiles** with two–three wave variants animating ping-pong. **Synchronized
  on one global clock** (period-authentic); the checkerboard `(x+y)&1` dual-phase
  trick stands in if lockstep reads too uniform. Per-tile random offsets are modern
  — rejected.
- **Rain:** four flow-level variants, drawn TL→BL then TR→BR with a random offset —
  instant gameboy rain. The **waterfall read** at high flow = rain tiles drawn over
  filled water — and that image is the telegraph for FLOW_BLOCK (§2): when the
  player sees it, they know the flow is above the you-cannot-move-through limit.
- **Gas:** keep the dithering → solid progression past 50% capacity; overlay the two
  most present gases in density order (steam over smoke — the only pair; miasma was
  cut long ago).
- **Matter + liquid compositing:** the hand-listable 16-entry solid/liquid
  combination table — e.g. solids in BL+TR: water from the left or top fills TL
  (blocked from flowing right/down); from the right or bottom it fills BR. The same
  tables as the shipped occlusion (world §3).
- **AmbGen becomes an offline asset compiler:** the generator bakes
  stalactites/stalagmites of assorted sizes onto a tilemap sheet; the runtime places
  tiles from the sheet instead of generating caves bespoke. Drips become **one**
  3-frame animation placed at the tip of a random spike or two.
- **The seam rule is an autotiler:** the matter-face edge logic maps directly onto
  16-bit edge-mask tiling (the era's blob/edge-mask trick); bank-tinted tile lookups
  replace per-pixel edge draws.

## 2. The sealed-air aftermath (shipped 2026-10 -- the cut landed same-day)

Air is nothing; liquid fills any void it can flow into; sealing is a future
authored verb (a marker tile, when a puzzle wants it). The occlusion law,
run-splitting, and the U-bend/oil-trap correctness are untouched and still law.

## 3. The buoyancy lab

- **Structure falling ships** — the compromise rule: an unsupported piece falls as a
  unit, **one tile at a time** (a stone object on a wooden pillar: burn the pillar
  and the object falls; a pillar burning from the bottom sinks one tile per burn
  step — the VERY gameboy rendering of "the structure is collapsing"). Wacky
  structure shapes resting on slopes: acceptable jank.
- **Float/sink by the density chart** (already shipped — `SUB_DENSITY` vs `DENSITY`).
- **Flow is an obstacle, not a field.** Advection reads the existing flow export
  (direction + strength stamped by every liquid rule) — no solver, ever.
  - `FLOW_PUSH`: heavy water dumping on her feet pushes her a bit for game feel —
    a nudge below the threshold, never fully blocking.
  - `FLOW_BLOCK`: at the waterfall threshold the tile **rejects** her — she must
    block or redirect the flow to pass. The waterfall render (§1) is its telegraph.
  - **The lasso-barge:** the witch pulls herself through water on a floating barge
    with her lasso. She builds the ship (structures + density float), shapes the
    pool and surroundings (dams, drains, the CA itself), stands on it, and pulls
    herself across. The traversal puzzle is the level.
- **Her swim rewrite** rides the same buoyancy: she floats to the top, rests with
  her bottom half submerged, a stroke from the surface buys the 10px SACRED jump
  through water.
