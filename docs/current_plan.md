# current_plan.md — the working roadmap

*The plan of record: what is being built next and the rulings each item carries.
The only doc allowed to describe future work in detail. Items are deleted from
here as they ship (their rulings land in the main docs; the session record lands
in `dev_log.md`). The main docs carry current law; `dev_log.md` carries evidence.*

*Standing audit bar for everything below: **Game Boy plausible** — one 10 Hz integer
world that looks like a 1994 programmer just barely got it to work. Powers of two
wherever a number is chosen. The tile grid is privileged (THE gameboy-authentic
shape). Structures and buoyancy are big gameplay-positives and stay.*

## 1. The cleanup cut

- **TAGS dies** — the wet tag becomes a computed rule (wet means damp above half
  capacity, checked where it's read); the census drops to fourteen used columns and
  **pads to sixteen flat bytes with two reserved** (a real 90s reserve).
- **The density ladder retunes to powers of two** (order-preserving, constants-only):
  steam 2 · smoke 4 · wood 8 · oil 32 · water 64 · acid 128 · lava 256 · soil 256 ·
  stone 512. Soil equal to lava sinks through it.
- **Fire constants go pow2:** BURN_RATE 32 (256-pool at 32/tick = exactly 8 ticks per
  full wood tile); IGNITE_WOOD 4 or 8 (tuning call: front at 2.5 or 1.25 tiles/s).
- **Struck from the arc:** the melt lab's HEAT×4 per-subtile heat + re-melt timers
  (replaced by a **contact cast** folded into the acid lab: water + lava → steam +
  stone_s, one quantum per tile per tick, no new columns); the groundwater lab's
  MOIST×4 schema (tile damp stands; the lab shrinks to wood damp capacity + soak
  tuning); structure slope-balance / center-of-mass voting (unit fall, density
  float/sink, and lasso pickup cover the fantasy); the heavier-arm slide; the
  currents field solver (**flow is an obstacle, not a field** — §4 below).

## 2. The occlusion pass

- **Directional bitmask blocking on the tile pool** — the tile grid stays privileged;
  solids thinner than a tile still hold liquid. One shared ruling:
  - blocks **vertical** flow iff the tile's solid pattern has ≥1 left subtile AND ≥1
    right subtile (BL|TL and BR|TR);
  - blocks **horizontal** iff ≥1 top AND ≥1 bottom;
  - blocks **diagonal** iff the opposed diagonal pair on the crossing corner is
    filled (TL+BR or BL+TR — the same corner law the sand pass obeys).
- The 16-entry solid-pattern table is written **once** and shared by sim (the
  occlusion check at every `is_solid` call site: water FALL/POUR/CREEP/SEEK, gas
  rise/spread, the escape walk, sand entry gates, the bridge pours) and render
  (§3's compositing table).
- A one-subtile-thick floor is a funnel through its open half; a two-subtile or
  zigzag floor holds — the diagonal rule makes the zigzag work.

## 3. The tileset lab

**Goal: every single visible game asset is a PNG colored by the palette bank — no
exceptions.** The renderer moves to an 8×8 tile atlas; all currently rendered matter
state is baked into sprite sheets that become real PNGs actually loaded by the game
(bake today's look, hand-edit in Aseprite, iterate — the perfect art pipeline).
**The witch converts to greyscale** and starts authoring her colors from the palette
bank in this lab too.

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
  filled water — and that image is the telegraph for FLOW_BLOCK (§4): when the
  player sees it, they know the flow is above the you-cannot-move-through limit.
- **Gas:** keep the dithering → solid progression past 50% capacity; overlay the two
  most present gases in density order (steam over smoke — the only pair; miasma was
  cut long ago).
- **Matter + liquid compositing:** the hand-listable 16-entry solid/liquid
  combination table — e.g. solids in BL+TR: water from the left or top fills TL
  (blocked from flowing right/down); from the right or bottom it fills BR. The same
  table as §2's occlusion.
- **AmbGen becomes an offline asset compiler:** the generator bakes
  stalactites/stalagmites of assorted sizes onto a tilemap sheet; the runtime places
  tiles from the sheet instead of generating caves bespoke. Drips become **one**
  3-frame animation placed at the tip of a random spike or two.
- **The seam rule is an autotiler:** the matter-face edge logic maps directly onto
  16-bit edge-mask tiling (the era's blob/edge-mask trick); bank-tinted tile lookups
  replace per-pixel edge draws.

## 4. The buoyancy lab

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
    block or redirect the flow to pass. The waterfall render (§3) is its telegraph.
  - **The lasso-barge:** the witch pulls herself through water on a floating barge
    with her lasso. She builds the ship (structures + density float), shapes the
    pool and surroundings (dams, drains, the CA itself), stands on it, and pulls
    herself across. The traversal puzzle is the level.
- **Her swim rewrite** rides the same buoyancy: she floats to the top, rests with
  her bottom half submerged, a stroke from the surface buys the 10px SACRED jump
  through water.
