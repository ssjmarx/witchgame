## The liquid picture arc: the wave mode latch, the pin, the banked crest (2026-10-14)

- **The h-wave mode latch**: the two h-wave geometries (TL+TR over a full bottom fill vs BL+BR alone) were chosen live per paint from `supported`/`liq >= 128` -- a class-latched wave teleported rows at tick rate under a wobbling below_full. The mode now rides `wave_kind` bit 4, written only on a fresh latch: a wave keeps the geometry it was born with, class and shape both.
- **Postmortem, red waves**: the fresh-latch gate originally read `wave_left[i]` after `_bank` had already topped it, so `wave_kind` was never written, stayed 255 from init, and the dry-gap replay did `255 & 3 = 3` -- KIND[3] is lava. Water waved red. Lesson: capture the pre-bank byte; `_bank` mutates in place.
- **The pin** (the general column-feed is dead): an animating surface -- a wave, a wave replay, or a bottom-row crest -- pins the single supported wet tile below to full rows in the surface's kind. No chaining, stone absorbs it, falling tiles and dry gaps never receive, bank bytes untouched so the overridden animation resumes when the pin lifts. The first cut was a full column feed ("any body liquid feeds the tile below") -- it flooded open cells inside structures, cutting through stone; the narrowed rule is the one that survived.
- **Crest law**: the crest is the standing surface itself -- any partial surface row rides crest art (the `deep` gate, which read live `below_full >= 240` and flickered under the pour sawtooth, is dead). A brim-full surface (d_b 7-8, remainder hidden by the 8-line quantization) crests on its empty top row, stepped by that remainder -- the water the quantization hid is visible again.
- **CL_CREST, the sixth bank class** (human ruling: "pin the crest's minimum existence time to 4 ticks"): crest *existence* is banked while its *shape* stays live -- step and row follow the waterline every qualifying tick, and when the surface stops qualifying the crestline rolls `CYCLE_CREST` 4+ more ticks over the receding body. The bank's class-switch law is unchanged: the crest latches only into a quiet bank.
- **One body, one crestline**: the brim-crest first qualified every full tile -- a deep pool stacked a crestline per tile down the column. The fix is the `_body` pass flag (information, not a drawing rule): a crest may draw only where the tile above drew no liquid body. Solids and transit (droplets, waterfall fills) end a body; waves, rows, crests and their holdovers continue it.
- **Full water outranks animation**: a pinned tile, or a wave playing with real water above its row, draws a solid column -- crest-over-wave is structurally impossible now.
- **The subtile-aware full read** (human ruling, the rain-chase fix): `supported` and `_raining_above` asked "is the tile below full?" with a flat `_liquid_total >= 240` -- a stone-holding tile mid-descent (64 stone + water under 191) and a misaligned bowl's shelf tile (128 stone + filling water) both read not-full, so settled water above them rained forever. The read is now capacity-aware: `liquid + 64 x POPCOUNT[occlusion_bits] >= 240` (`_below_full`) -- the waterline's full mark rises with every solid subtile, degenerating to the old rule on plain pools. The dead first proposal (waterline-in-top-open-row) would have misread bottom-solid tiles, where any water sits in the top row with real headroom above it.
- **Standing anti-flicker order** (all view-side, fenced world §9): pin > full-water override > wave/diagonal/fall classes > crest grace > plain rows. Two pass-transient column bytes (`_pin`, `_body`) plus the per-tile bank; the CA is untouched, UT2's pin is untouched, and the full regression is green at every step (the pour-sawtooth flicker on staircases is what all of this exists to kill).

## The widened POUR (supersedes the dry-space-only anti-oscillation gate)


- **Ruling** (human-directed, 2026-10-14): POUR is now capacity-driven and two-step -- (1) move all water *that fits* (viscosity-capped) into the down-diagonal target regardless of its existing contents, (2) the remainder falls through to CREEP in the same pass instead of returning. Previously POUR refused any diagonal target at or above LINE (the dry-space gate, the anti-oscillation law) and returned early so creep never saw the remainder -- the "staircase puddles creep the tops" behavior. This resolves that open ruling.
- **The change is three lines in `_cell_pass`** (`grid_water.gd`): the `pool_total < LINE` clause dropped, the `return` replaced by re-reading `w`, so CREEP runs on the remainder.
- **Equilibrium shift, honestly pinned**: UT2's floor split under oil moved from the uneven `[46, 123, 43, 43]` to the near-even `[65, 64, 62, 64]` (sums to the dumped tile's 255) -- the widened pour levels the floor beneath oil. Every other UT2 invariant held unchanged; the full regression passes 10/10.
- **Throughput note**: viscosity caps each move independently, so a pouring tile may now move up to `visc` diagonally *plus* `visc` laterally in one tick -- accepted by the human's spec ("move all water that can fit... move the remainder according to sideways movement").
- **Watch item**: the anti-oscillation protection the old gate provided is gone by design; regression is green and no oscillation surfaced, but sandbox eyeballs on staircases and pours-into-puddles are worth a look.

## The universal special-draw bank (render anti-flicker law)

- **Ruling**: every special liquid picture -- rain, waterfall, waves (h and d) -- plays at least one full animation cycle after its conditions cease; the waterline returns only after a full quiet cycle. Promoted from the wave-only bank after live flicker reports.
- **The byte**: low 5 bits ticks left (capped at two cycles: 16 for waves/waterfall, 31 for rain), high 3 bits the latched class (h / dL / dR / rain / waterfall, direction folded in).
- **Group latching**: waves stay waves, drops stay drops -- a shape only switches through a full quiet cycle, so a flow oscillating lateral↔diagonal every tick renders one constant wave (probe S1: 16/16 stable; pre-fix `h.d.h.d.`).
- **The tick frontier (post-fix)**: the bank originally spent one unit per *paint*, but the live frame loop paints ~6x per sim tick -- holdovers drained 6x too fast, flicker faster than the animations themselves. The bank now spends via a global tick frontier (one spend pass per new tick_count); probe S2 (one paint/tick) and S5 (six paints/tick) drain identically. Lesson: the probe modeled a cadence the live loop does not run.
- **Probe-caught bugs during the build**: the first cap was 31 flat (sustained activity banked ~4 cycles, S2 held 20+ waves -- now exactly one banked cycle, 15 w's then level); a diagonal rapid on *standing* water drew nothing at all (the diagonal wave only existed in the falling branch -- now it owns the standing tile's 3/4 too); an empty tile froze its bank (now cleared with the picture, so no ghost can resurrect).
- **Also this arc**: rapids outrank the waterfall read (a diagonal-dominant tile is a rapid at any weight, never a waterfall -- pillar-split at feed 255 now waves instead of waterfalling); the diagonal-flow probe library (pillar/stairs × low/med/high feed) lives in this session's record, not the tree.
- **Open ruling**: steady-state staircases hold a puddle per step, and POUR's dry-space-only gate (the anti-oscillation law) means no diagonal pours land in full puddles -- the water creeps the tops and falls off the end. POUR widening deferred by the human ("i may come back to adjust POUR afterward").

## Rapids polish: diagonals, override-not-overlay, the bulge, the bank

- **Diagonals corrected**: down-right rolls on TL+BR, down-left on TR+BL -- the first cut had the pair swapped.
- **Waves override, never overlay**: a rolling river's bottom row skips the level fill; the wave art carries its own body water. The first cut blitted the wave over the fill, reading as current marks on blue.
- **The bulge art**: three rows of base water with a five-row rolling crest (heights [4,5,5,5,4,3,3,3], frame b reversed) -- the first cut was a monotone ramp, not a wave.
- **The wave bank** (the ruling): view state, one byte per tile, one cycle deep -- a rapid tops the bank to two cycles (playing plus exactly one banked), a quiet tick spends one; flow must vanish a full 0.8 s cycle before the waterline returns. The stateless alternatives were weighed honestly: cycle-boundary sampling gives most of the anti-flicker but not the guaranteed continuation; hysteresis is memory by definition. Adopted as the renderer's first per-tile state, fenced in §9 as view-only, decaying, never census.
- Probe verified: the wave overrides the bottom row (only the top row's level tile draws beside it) and the timeout -- the wave holds seven quiet paints and the level returns on the eighth, exactly one CYCLE after flow death.

# dev_log.md — the development log

*The evidence of decisions made during development: session rulings, changelogs,
supersessions, and the provenance behind every law in the main docs. The main docs
(`world.md` and the three game deltas) carry current-state and ship-plan only —
everything historical lives here. Newest entries first.*

---

---

## The wetability clause and the droplet rain (2026-10 -- post-2b nits)

- **Rapids shipped**: lateral or diagonal flow at RAPID_MIN 48+ draws waves -- two curve-derived frames (a rolling bulge, crest over body), phase-hashed by tile like the rain. Horizontal: bottom row alone under half capacity, top row with the bottom pinned full over it (no vanishing mid-wave). Diagonal: always 3/4 -- wave on the leading diagonal, the remaining bottom cell pinned full. Standing rivers roll the bottom-row wave. Verified by pixel probe: A [0,0,26,26], B [32,37,64,64], C [0,26,26,64], D rain 10.

- **A lone notch beside water drains through** (the user's 3/4-tile report): a TL+TR+BR tile with BL open held water that crept in from the side, because `drains_v` demanded a full open column. The fix is the **wetability clause**: a blocked tile still drains through an open exit cell when the exterior tile beside it is open at that cell and holds real liquid -- the water can stand there, so it can fall from there. The wet source must hold liquid (gases wet nothing): that keeps OC7's pinched tile sealed (its BL faces a dry open column) and OC2's zigzag holding (its BL faces solid). Direction-aware (`drains_v` falls, new `drains_up` for gas rise and the seek lift -- a top-notch clause mirrors the bottom one); OC14/OC15 pin the report's scene and its tile-boundary control.
- **Rain became droplets**: the two-band dash tiles read as static wallpaper. New art: one 2x3 droplet sprite (`drop` role); light rains one droplet descending tl->bl then one tr->br (8-frame cycle, 4px steps); heavy rains two crossing tl+br -> bl+tr (4 frames); four x-offsets cycle in order. The clock is global and decoupled from the sim -- the animation always completes, ending on the cell floor. Waterfall = fill + the heavy pair; rain-through uses the same positions, masked to open cells.
- **Two operational lessons**: the bake tool only regenerates the gray atlas with `--regen` (a stale gray faithfully re-colored is the invisible-witch class of bug again), and headless runs load Godot's *import cache*, not the changed PNG -- run `Godot --headless --path . --import` after any re-bake before probing.
- **Doc drift caught**: world.md's §3 liquids paragraph still carried the pre-cut air-gate law ("Air is gated, not simulated... escape flood"); rewritten to the sealed-air truth. The lesson: wide deletions need a doc grep for the retired vocabulary, not just the planned paragraph.

---

## The sealed-air cut (2026-10 -- the foundation-shaker)

**The ruling:** dynamic sealed air pockets are dropped. Air is nothing -- never
stored, never gated, never flooded for; liquid fills any void it can flow into,
and water enters underwater caves like anything else. Authored sealed air MAY
return as a puzzle verb at a future date. U-bends stay (open-topped manometers,
oil riding higher in a trap); the run-splitting that keeps them honest stays.

**Why:** the user's own oldest verdict -- the most expensive and inauthentic
calculation in the project. The escape flood ran every tick (the single most
expensive per-tick structure in the water engine) to maintain an answer that
only mattered when geometry was sealed AND liquid was knocking; the player sees
only a refusal either way; no 90s game computed air reachability. The breaking
point was the witch-pump fork: her displacement splashing into sealed pockets
was licensed-by-design (BT10's sealed-pool splash) yet composed with lateral
creep and repetition into an unbounded pump -- no local rule separates them,
so the whole model went.

**What died:** water_analyze.gd entirely (region flood, escape fixpoint, body
flood, contact tables); the air-gate family (grid_water's (a)(c)(d) gate on
POUR/CREEP, seek's _pocket_vented_for rise clause, the bridge's may_displace);
headroom/eject escape clauses in water_pools; is_air_passable / is_air_sealed /
get_region_of; the renderer's pocket tint and CaFx's sealed stencil (with
DEBUG_SEALED/DEBUG_OPEN). OPEN_AIR furniture keeps its gas-eating only.
**Tests:** Ex2 (sealed pocket frozen), Ex3a (sealed cave stays dry), UT3
(sealed chamber refuses), DT4 (inverted cup), OC11-13 (air chambers, air nodes,
the displacement gate) deleted; OC8-10 keep their run-splitting assertions,
lose their body-topology ones. **Measured:** the full regression dropped from
~510-970s to ~264s -- the escape flood was that expensive.

## Three bug reports, three invariant ports (2026-10)

**Fire bits ride fuel cells only** (the orphan-fire report): `_catch_bit` births embers
on breathing cells, which need not hold wood, and engulf likewise -- so fire bits
routinely sat on empty cells, where they never burn (the burn reads wood & fire), never
clear (burnout clears wood & fire), and never die while wood trickled through the tile:
the never-burning flame. Fix, two halves: **engulf lights fuel cells only** (wood fire
spreads within the wood; oil fire, positionless, may ride any cell) and the gutter
**masks fire to the fuel cells each tick** as the invariant's enforcer. The mask alone
was wrong -- it killed fresh embers before engulf could reach fuel and changed engulf's
pick (slowing the boil); the gate caught FT3/FT4 flipping and the probe showed the
fight. Honest retunes: fire on empty cells no longer boils, so FT3's siege now leaves
damp 34 (was 10) and FT4's middle needs damp 32 to catch (was 64). FT12 pins the oracle.

**A non-bridging tile is not an air node** (the 3/4-pocket report): `is_air_passable`
and `_is_air_idx` now read `interior_bridges` -- a 3/4 or pinched tile is matter with
a nook, holding no pocket membership and tinting nothing in the G overlay. Side effect,
correct: an OPEN_AIR fixture on a non-bridging tile stops venting. OC12 pins it.

**The bow wave respects the air-gate** (the witch-fills-pockets report): the bridge's
`_pour_into` accepted on `pool_free` alone -- displacement poured straight into sealed
pockets. GridWater exposes `may_enter` (the sim's own `_gate`), and every bridge pour
(entry, wake, sides, eject climb) routes through it. OC13 pins the gate directly.

**Two follow-ups the gate caught:** a non-bridging tile must never START a body either
(the pinched tub's wall was absorbing its feeding side as the flood's origin -- OC10);
and the first OC13 world walled its own chamber shut (the probe read region -1 and the
gate's ungated path fired -- the example's bug, not the engine's).

---

## The pinched-tile bridge cut (2026-10, the user's air-pocket report follow-up)

Air chambers split by a pinched (TL+BR) wall read as one pocket, and the same hole
let seek runs, bodies, and escape chain through pinched tiles -- the air-side twin of
the corner-reachability fix, which had closed only the pour. The generalized ruling:
**a pinched tile bridges nothing** -- `interior_bridges` (an open row or column,
`drains_v or drains_h`; fixtures and the boundary never bridge) gates four consumers:
run extension in `pass_all`, the body and pocket flood joins, and escape marking (a
pinched tile's air is never vented). OC10 (the tub through a pinched wall: columns
diverge, the pinched tile's water joins no side's body) and OC11 (air chambers:
different regions, both sealed) pin it; the probe also confirmed the S1 split-wall
and partial-ceiling scenes were already correct.

---

## The connectivity port: runs, bodies, pockets split at sealed edges (2026-10, the user's tub report)

Water leveled a tub across a full-height one-subtile wall (TL+BL) and across a
cross-boundary diagonal (TR over BL). The movement rules were already correct -- creep
reads edge + interior, so each side saturates the wall's open face and stops -- but the
CONDUIT abstractions didn't: `pass_all`'s runs joined any contiguous pool_total >= LINE
tiles (so seek teleported volume across the wall once it held water), and
`_flood_body`/`_flood_region` connected bodies and pockets the same way. The user's
ruling, now law: **a body can't be connected across a tile the liquid could not flow
through.** Fix: three edge gates -- run extension reads `edge_h_open`, and both floods'
joins read their directional edge. OC8 (the tub: sides keep their totals, the dam's
water belongs to its feeding body) and OC9 (the cross-boundary wall, same) pin it; the
prior suites are untouched (plain water/air edges are always open).

---

## The tileset lab, stage two: the atlas + matter, gas, fire (2026-10)

The 8×8 tile atlas ships and the renderer's matter, soil, gas, and fire passes blit
from baked PNGs. Liquids and ambiance stay procedural until their own stages.

**Rulings and shape:**

- **One layout, many banks**: `tile_atlas.gd` holds the single `LAYOUT` (40 roles:
  fills, lip/seam strips, dither ramps, embers, licks) shared by the baker
  (placement) and the renderer (blits); the gray atlas (`assets/gray/tiles.png`)
  is painted by slot-index painters and is the hand-editable truth; six bakes color
  it per bank. A slot past a short bank clamps brightward — the shared layout's
  foreign roles, never read by the renderer.
- **The renderer keeps its one-Image composite** — atlas blits replace per-pixel
  fills; scenes and layering unchanged. The seam rule survives verbatim as neighbor
  queries choosing lip/seam/silence strips; the gas pass quantizes to subtile bands
  (smoke-top, steam-below, complementary dither phases mixing at the boundary — no
  alpha blending, the DMG way); soil damp quantizes to full bands plus a
  quarter-step boundary; fire blits hash-keyed ember and lick tiles.
- **Coarsenings accepted**: damp was a per-pixel gradient (now 4 quarter steps); the
  gas band split was row-precise (now subtile); the lick lost its sub-pixel jitter
  (the 3 baked variants carry the variety); wood's plank art went flat (texture
  returns by hand in the gray atlas — the pipeline's point).

**Three incidents, all caught by gates or probes:** a missing-layout-key abort
mid-`_init` hung the first bake run headless (SceneTree never quits on abort —
lesson: `-s` tools fail loudly or hang silently, so guard the lookups); the
2-color banks crashed `color_image` on the 4-slot fire art (fixed by the clamp
ruling); and the **stale-gray fossil** — the first crashed run had left a partial
gray on disk that later runs faithfully re-colored (584 opaque pixels, `full` roles
and licks empty), and **PT6's per-role population check caught it** — the
invisible-witch lesson, now machine-enforced. Regen: 1126 opaque pixels, 40 roles,
eight palette proofs green.

**Proofs:** PT6 (every baked atlas pixel ∈ its bank; every role populated),
PT7 (the gray source holds baseline levels only). Visual parity is the eyeball
gate in the labs.

**Post-script (the user's eyeball gate earned its keep twice):** the gas pass
first blitted one 8×8 dither per band — half of every gas tile stayed empty,
because the pool is tile-granular while the atlas is 8×8; fixed by spanning each
band across both subtile columns (verified headlessly: 128/128 coverage on a full
tile). Matter, soil, and fire were immune — subtile-granular passes.

---

## The tileset lab, stage one: the bake pipeline (2026-10)

The art pipeline ships: colorless baselines, bank-colored bakes, the palette as the
only color source. The witch's sheet is its first customer.

**Rulings:**

- **Godot bakes, not python** — the baker runs headless in-engine (`-s
  res://scripts/tools/bake_witch.gd`) and reads `Palette` constants directly, so the
  palette law holds by construction; a bank change plus a re-bake cannot drift. No
  second toolchain, no new dependency.
- **The pipeline law**: sources are **colorless baselines** — grayscale index levels
  (`Palette.BASELINE_LEVELS`, four evenly spaced levels for the tile banks to come)
  under `assets/gray/`, regenerated only with `--regen` so hand-edits survive; bakes
  under `assets/baked/` color them from banks and are never hand-edited. The witch
  loads `assets/baked/` now.
- **The real sheet quantized cleanly**: exactly three used colors plus transparency —
  `#000000` outline → INK, `#53528c` body → INDIGO, `#fe0000` accents → RED. Zero
  unmapped grays on the color pass.
- **Two bugs the gate caught**: preload'd instance methods need `.new()` (parse
  errors); and a double alpha division in `bake_lib` (`c.a / 255.0` on an
  already-normalized float) made every opaque pixel alpha ≈ 1/255 — the baked witch
  would have been invisible. PT5 caught it; fixed to `b.a = c.a`.
- **The color-budget counter and DMG 4-shade mode are deferred** (user ruling:
  polish out of scope) — banked in current_plan as ideas, not law.

**Proofs:** PT4 (the quantizer maps used colors to slots, preserves alpha, warns past
the bank), PT5 (the colorizer writes bank colors only, counts off-level grays).

**The invisible-witch incident (caught by eyeball, not the gate):** the alpha fix
landed in `bake_lib` but the first (buggy) run had already written the gray baseline
with 1/255 art pixels; the fixed re-run without `--regen` faithfully re-colored the
poisoned baseline — correct RGB, invisible alpha, witch gone in-game. PT4/PT5 never
saw it because they build their own in-memory sources: the math was fixed, the
artifact wasn't. Remediation: `--regen` (alphas verified `{0: 2387, 255: 1709}` on
both files) and a standing guard — the baker now counts opaque pixels and fails
loudly on zero. Lesson banked: **a file-producing tool must gate its own output;
suite proofs of the math do not validate the artifact.**

---

## The occlusion pass (2026-10, roadmap §1 shipped)

Directional solidity on the tile pool — the roadmap's first post-audit lab. Ten suites
green, the prior nine untouched.

**The law, as it settled after two mid-implementation amendments:**

- **Crossings versus presence.** `is_solid` stays (presence: fixtures, the boundary,
  4/4 matter — the surface walks, soak stop, burial, sand gates, bridge support read
  it). New crossing tests on `GridStone`, indexed by the tile's 4-bit solid pattern
  (OR of the three matter nibbles) against one 16-entry table pair (`BLOCKS_V`/
  `BLOCKS_H` beside POPCOUNT).
- **The edge test** (the user's amendment, caught in planning): the shared edge seals
  when the two near sides united span it — the source's bottom row ∪ the target's top
  row for vertical (a stacked BL over TR seals), the joined columns for horizontal.
  The first draft read only the target's whole pattern; that misses every cross-tile
  seal.
- **The interior test** (implied by the amendment): the source's own pattern must
  leave an open path — an open column to exit vertically, an open row horizontally.
  This is what makes diagonal-pair (TL+BR) floors hold: water enters the open top,
  finds no through-column, and stays. Same tables, second read.
- **The corner law for diagonals, corrected live:** the plan's "opposed pair pinches"
  formulation leaked — OC2's zigzag drained through pours that rounded a neighbor's
  solid corner while the opposite cell stood open. The per-cell law the sand pass
  obeys is three SINGLES: the source's own exit corner, the side tile's corner, the
  target's entry corner — any one solid cell seals. (OC5's pinch works under either
  reading; OC2 only under the singles.)
- Consumers: FALL/rise = interior + edge; CREEP/spread = interior + edge; POUR = the
  corner law (also loosened correctly: water now pours under a top-row overhang);
  the seek rise, the escape flood's edges, and the gas exchange gate the same way;
  the hop reads the corner law instead of both-capacity-0.

**The debugging arc:** OC5's "leak" was a world typo (`'r'` where `'s'` was meant —
unfused cells scattered and opened the corner; the probe showed the stone moving,
which no gate can explain). OC4's first failure was an off-by-one glyph (the dam at
x1, the reduction at x2 — reducing air). OC4's top dam tile saturates only to the
seek-equalized level (creep stops at LINE; deep rows fill to 127 via pour) — the
check now asserts deep rows exactly, the top row merely wet. BK9 needed NO change:
the chipped wall admits water through its opened face exactly as it always claimed.

**The pinched-interior amendment** (the user's corner-leak report, same lab): a TL+BR tile's open cells are corner-pinched and never connect, but the pour read the source's exit corner as merely open — water that entered at the open top teleported across the pinch and out the far corner. Fix: `_corner_reachable` — the exit corner must share a fully open row or column with a partner (the interior test's per-corner form). A diagonal pair now pours nothing; funnels, overhang pours, and dam saturation all re-verified by derivation and by OC7 (the report's exact scene: water top and right, the pocket behind the pinch stays dry, the tile saturates to 127 and holds). The gas hop inherits the fix through `blocks_diag`.

**Suite:** `test_occlusion.gd`, tenth registered — OC0 funnel, OC1 top-row hold, OC2
the zigzag, OC3 the stacked diagonal, OC4 the saturating dam, OC5 the pinch, OC6 the
cleared column. No class_name (path-loaded, the structures pattern) — no rescan.

**Docs:** world §3 gains the occlusion ruling; E2 and the suite inventory say ten;
current_plan §1 deleted (tileset → §1, buoyancy → §2); this entry.

---

## The cleanup cut (2026-10, roadmap §1 shipped)

The plausibility audit's first deliverable: TAGS dies, the ladder goes pow2, the census
pads to sixteen. One session, all nine suites green.

**Rulings, in order:**

- **TAGS retired as state** — the `tags` column, `TAG_WET`, `has_tag`/`set_tag`, and the
  entire per-tick tag pass are gone. Wet is a computed read (`is_wet`: damp above half
  capacity) — no staleness, no hysteresis; the 30%-floor band that survived as tag state
  is the accepted flicker. The mortar seam and every test read the helper.
- **The census is sixteen flat bytes** — column order [0]terrain [1-3]matter nibbles
  [4-9]pool [10]damp [11]fire [12]debug [13]struct [14][15]**reserved zero** ("a real
  90s reserve"). Editor slots version 4; version-3 blobs remap (tags dropped, tail
  shifted, reserve appended); pre-retirement blobs flow through `migrate_legacy_cols`,
  which now detects the Stage-2 format by `cols.size() > 15` — not `> COL_COUNT`, which
  the pad broke.
- **One byte-scaled heaviness table** — `SUB_DENSITY` is dead as a concept; `DENSITY`
  is nine entries with the kinds indexing past `K_DENSITY` 6: steam 1 · smoke 2 ·
  wood_s 4 · oil 16 · water 32 · acid 64 · lava 128 · stone_s 128 · soil_s 128. Every
  entry under the top bit. Stone and soil TIE lava — the medium rule's strict `>` makes
  equals sink, so no kind needs to out-rank another. (The audit's first ladder had
  512s in it — magnitude vanity; the tie ruling halved everything into one byte.)
- **Fire constants** — `BURN_RATE` 32 (a 4/4 tile's 256-pool burns in exactly 8 ticks),
  `IGNITE_WOOD` 4 (front at 2.5 tiles/s; smother delay follows at 4 by the symmetry
  law). `PRESSURE_RATE` stays 64: the coupled-retune idea (halve it with the ladder)
  was wrong because the ladder is not a uniform rescale — water went 30→32, so halving
  the cap genuinely halved water's seek pace (UT1/UT4 failed identically at both
  values until the revert).

**Equilibrium shifts, honestly pinned** (the 2:1 water:oil ratio is real physics, not
a restyle): UT1's manometer balance moved (left 128→64, right 128→191); UT2's floor
split under oil is now uneven (46/123/43/43 — exact-pinned); UT4's container holds 249
oil with a ~0.9% crude-sum balance (tolerance 60→192). The checks' hardcoded ×30/×20
head multipliers now read ×32/×16. FT retimes: FT3's siege leaves damp 10 (the faster
burn boils less), FT6 needed a 2-tall wood column (a single W now burns out in 8 ticks
< the 11-tick window), FT8's pace pins are 7/0/63 at t10, FT11's one-tick dump is 128.

**FT7's wall reshape — the one real physics casualty:** the old example's wall was
welded to the shell (x=0, breathing only through itself); at 128 smoke/tick the
ignition accrual never holds 4 consecutive eligible ticks and rows 2-1-0 never catch —
a permanent stall, probed live. A wall with air on both sides ([".W."]×5) climbs and
burns through by ~tick 47. Lesson banked: **vertical fronts breathe through their
shafts; a shell-welded column is a chimney with no draw.** The example now uses the
breathing wall.

**Docs:** world.md §2/§3/§13/E2 synced (sixteen-column census, computed wet, the
ladder, BURN_RATE 32, IGNITE_WOOD 4, SUB_DENSITY folded); current_plan.md §1 deleted
(shipped), remaining sections renumbered; this entry.

---

## The bedrock arc + the plausibility audit (2026-10, post-editor-lab through the nits)

The arc that took the engine from wood-terrain to pure subtile matter, then audited
the whole roadmap against the Game Boy plausibility bar.

**Stage rulings, in order:**

- **Kind two is wood** — `ice_s`/`K_ICE`/`Led.ICE_S` renamed to `wood_s`/`K_WOOD`/`Led.WOOD_S`, census slot three unchanged. The matter arc's ICE cut as a pure rename; freeze/thaw, MELT, and cold are dead.
- **Structures are authored, never sim-created.** The first design (per-tick connected-component labeling with an anchored graph — "connectivity decides") was **rejected mid-implementation**: structures re-forming under sim rules felt wrong. The locked doctrine: the editor fuses, the player's future fuse ability fuses, the sim destroys and never creates. Membership is census state (`struct_s`, one byte, nibble-pairs over the subtile layout), not derived. Cuts partition: orthogonally connected runs of ≥2 survive as separate structures; singletons revert to the loose rules. Diagonals never connect (the tile-is-one-place ruling retired). Authored walls convert pre-fused (the retirement cut's authoring act).
- **The movement doctrine** (design-ahead-of-code, buoyancy lab): unsupported pieces fall as a unit (the compromise rule — C3's aqueduct comes down as beams); slope sliding by contact patch with center-of-mass balance was later **cut by the plausibility audit** as the least Game Boy system planned; pieces in liquid move with the liquid's current; her lasso is universal (enemies, pots, structures — one grasp set, one thing at a time, structures within her weight cap, 90° rotation while carried — tetris-block bridges).
- **The retirement cut** — STONE, WOOD, SOIL terrain exit the enum (terrain is AIR + fixtures); solidity reads `solid_capacity == 0`, so a chipped wall admits water; FUEL and its ledger row retire for the per-tile burn-pool overlay (64 fuel-equivalents per wood_s subtile at flat BURN_RATE, bone-dry ignition, progressive burnout whose clears re-partition through the cut); census migration for legacy saves; condensation reads stone_s faces.
- **The breath model** (a mid-arc redesign after the tile-based air gate broke on partial matter): each fire subtile drinks its own cell + its two corner faces; 4/4 unions to the shipped geometry; oil (pool matter, positionless) drinks tile + all four orthogonals; smothering is the ignition delay inverted (wood 5, oil 1) — a starving fire pauses (no burn, no boil, no catch, no stimulus) and dies when starved that long. Two chicken-and-egg bugs found by probe: the ember must be born on a breathing cell (`_catch_bit`), and contact ignition must gate on fuel *existence* (`_fuel_here`), not the burn pool.
- **Fire pins its fuel** — a burning subtile does not move (an orphan 4/4 ghost fire otherwise grows in mid-air when burning wood walks away from its tile-resident fire bits); a fire with no wood and no oil gutters regardless of pool.
- **The density medium rule** — a solid rests in any pool material denser than itself, falls through the lighter, gas included (wood no longer floats on smoke); sink rate through liquid (SUB_SINK), air rate through gas (FALL). `SUB_DENSITY` joins `DENSITY` on the packet.
- **Renderer fixes**: the rain field draws liquid materials only (a flow stamp with no liquid beneath it is gas in transit — rising or lateral smoke is never rain); the matter face draws by the seam rule (no line between adjacent members, seams against loose or foreign matter); the editor becomes the authoring tool (exact-subtile paint/erase, the struct toggle, blocking overlay menus, inspector retired).
- **A latent GridStructures bug** fixed in passing: its bit↔cell mapping was vertically flipped vs GridSand's layout (internally consistent, so full-tile tests passed; wrong at partial granularity).

**The plausibility audit** (against "a 1994 programmer just barely got this to work"):

- **Cuts accepted:** the melt lab's HEAT×4 + re-melt machinery (replaced by a contact cast: water + lava → steam + stone_s); the groundwater lab's MOIST×4 schema (tile damp stands); the currents lab's solved flow field (**dead — replaced by the obstacle doctrine below**); structure slope-balance/CoM voting; the heavier-arm slide; TAGS (wet computed from damp at read; the census pads to sixteen bytes with two reserved).
- **Pow2 retunes planned:** the density ladder (steam 2 · smoke 4 · wood 8 · oil 32 · water 64 · acid 128 · lava 256 · soil 256 · stone 512); BURN_RATE 32 (exactly 8 ticks per full tile); IGNITE_WOOD 4 or 8.
- **The currents insight:** *flow is an obstacle, not a field.* The witch pulls herself across water on a floating barge with her lasso (build the ship, shape the pool, pull yourself across); flow below a threshold pushes her, above it the tile rejects her (block or redirect to pass) — and the waterfall rendering (rain tiles over filled water) is the telegraph for the impassable threshold. Zero new sim systems: advection reads the existing flow export.
- **Structure falling kept** (the one caveat to the slide cuts): a wooden pillar burning from the bottom falls one tile at a time as it burns — the very Game Boy rendering of "the structure is collapsing." Wacky shapes resting on 45° slopes: acceptable jank.
- **The renderer verdict: 8×8 is the shape.** The GB's native tile; render grid = matter grid = collision grid (partial tiles stop being special anywhere); 2px water steps (four level tiles); crests animate synchronized on one global clock (checkerboard `(x+y)&1` dual-phase if lockstep reads too uniform — per-tile random offsets ruled modern); rain = four flow-level variants; gas = dither→solid with the two-gas density overlay (steam over smoke; miasma was cut long ago); matter+liquid compositing = the hand-listable 16-entry solid/liquid table (the same table as directional occlusion); AmbGen becomes an offline asset compiler — bake stalactites to a tilemap sheet, runtime places tiles, drips are one 3-frame animation at a spike tip.
- **The art pipeline law:** every currently rendered matter state gets baked into sprite sheets; the final sheets are real PNGs, actually loaded by the game — bake today's look, hand-edit in Aseprite, iterate. Extended at the tileset lab: **the witch converts to greyscale PNGs colored by the palette bank — every single visible game asset is a PNG colored by the bank, no exceptions.**

---

## Migrated history

*The blocks below moved verbatim from the main docs at the documentation split. The main docs carry current law; this is the record of how it got there.*

### world.md — where the code stood (final sync, at the documentation split)

**Where the code stands** *(synced at the editor lab, `de6e436`)*. Shipped and therefore authoritative: the packet and its ledger (§2 as shipped — ten booked rows since the retirement cut retired FUEL, plus two unbooked overlays — `actor_s`, the bridge's claim column, cleared at every tick head, and `debug_s`, census column thirteen: the editor lab's debug furniture), the terrain/liquid/solids/reactions quartet — `GridStone`, `GridWater` (an orchestrator over the five cleanup-pass modules: `WaterFlow`, `WaterGas`, `WaterAnalyze`, `WaterPools`, `WaterSeek`), `GridSand` (owning `GridStructures`, the authored-structure pass — §3's bedrock cut: fuse, freeze, cut, burn), `GridReactions` — (§3 all-liquid movement densest-first with viscosity, the density sort pass, pressure-head seek level, displacement, the absent-material pass gates, both flow exports, soil/stone/wood movement, damp and soak; since the fire lab: gas movement and exchange, the fire solver with its contact-ignition delay, condensation, and wood terrain; since the bridge lab: the sealed-chamber density swap; since the bedrock lab's retirement cut: authored walls, capacity solidity, and the per-subtile burn), the room model (`Room`/`RoomState` — §8's first half: one CA domain per room — the sextet: debug furniture and the bridge at the tick head, then solids, liquids, reactions — the per-room PRNG, snapshot/restore at fifteen census columns plus the ignition and burn-pool overlays, unobserved rooms never ticked), the bridge's thermal half (`ActorBridge` + `ThermalBody` — §4.1–§4.2 as shipped: claims and displacement, ABSORB/DRIP/BOIL/CROSS-TALK/DRY, fire/lava contact, the per-tick body shuffle, the family checksum), the actor shell's first cut (`CollisionMirror`, `Witch` — §5 partial: the matter-to-physics contact contract and one heroine's locomotion), the renderer and palette with the ambiance layer (`ElementRenderer`, `CaFx`/`AmbGen`/`AmbCave`, `Palette` — §9 lines marked *shipped*, the palette law included), and the `TestSandbox` harness with the water, packet, soil, oil, fire, bridge, rooms, palette, debug, and structures suites (six water examples, four packet tests, eleven soil examples, eight oil examples, ten gas examples, eleven fire examples, fourteen bridge examples, four room examples, four palette proofs, five debug examples, ten structures examples — 3000 ticks to equilibrium, all through the shared drift-watched runner; the fire lab runs its timing tests short and overrides the conservation policy with the water+steam+damp trio and the 4:1 smoke production rate; the rooms lab restores its worlds instead; the debug suite drives fresh Rooms directly — the furniture pass rides `Room.tick`, which the shared runner never calls). The witch lab (`test_witch.tscn`) and the room editor (`test_editor.tscn`) are manual playgrounds, not example suites — they stay out of `run_all`, which runs the nine registered suites headlessly behind a compile gate (every global class must parse) and a vacuous-suite check (a suite that runs zero examples fails). Not yet code: acid/lava chemistry and freeze/thaw, MELT, smolder (§4.4), the magic orders, the door protocol, pockets, per-actor ledgers beyond the family sum, the lasso and the contact-event modules (§6–§7), the light rig, the effects over-pass (§9), and the level format (§10). Shipped prose names its source; planned prose is design-ahead-of-code and says so.
### world.md — the changelog stack (v1.9 through v1.0)
**Changelog v1.7 — the editor lab (`de6e436`): ambiance, the palette law, debug furniture, the room editor**

- **The ambiance layer is code** (`AmbGen`, `AmbCave`, `CaFx`): the background-module contract — world-blind by construction, layout pure in the seed, animation pure in seed and slot, one map-sized texture served whole on `serve(tick)`; the dark cave is the first module (the void default, lumpy rock masses, stalactite/stalagmite edges — a pure bake of the layout stream, never re-rolled — plus drip eras as the one motion verb: ERA_LEN 32 ticks per era, 1–4 drips, hashed on the slot so replays replay). `CaFx` is the second painter: the under-pass serves the module's background then composes the live sealed stencil (bank-dark checker dither over sealed air — escape stays the one opinion every shade follows); the over-pass is the effects layer (currents, waves, splashes, bubbles, licks), empty and wired so the painter's order never changes again. The FX domain is the room seed XOR a salt — a different stream from the CA by construction, never the sim PRNG (§0 law 9). `ElementRenderer.redraw()` runs under → tiles → over → overlays; four dungeon sets (whisper blue, brick crypt, moss grotto, sandstone catacomb) recolor the same cave today
- **The palette law is code** (`Palette`, `TestPalette` PT0–PT3): master is DB16 canonical, named; guests are additions beyond DB16, documented one # reason each — the lock is procedural, never a ceiling; tile banks hold at most four colors and sprite banks at most three plus transparency, index 0 darkest in both; debug and editor overlay colors are exempt, never shipped art. Law, machine-checked — and the audit grew a second rule: `build_project_map.py` fails on any `Color(...)` literal outside `palette.gd` (testing suites exempt)
- **Debug furniture is code** (`GridDebug`, `TilePacket.DebugTile`, census column fifteen `debug_s`): water sources dose 16 units per tick with refused units un-made (the smoke precedent) and stamp the flow export in the feed's direction; drains take what arrives; steam vents dose upward; open air eats smoke and steam — and counts as the escape for the analyze pass while it breathes (air-passable; a drowned vent stops venting). The furniture pass rides `Room.tick()` at the head, before the bridge; buried furniture is inert (seal a spring and you dam it); furniture never books — overlay state, carried by the census, DT0 the restore proof
- **The room editor is code** (`TestEditor`, `scenes/testing/test_editor.tscn`): four persistent rooms on the F-keys, census bytes saved to `user://editor` slots; menu-driven paint over tiles and furniture; the inspector card (the hovered witch's thermal state, else the tile's census down to furniture and flow); a chorus of witches sharing one input; M cycles the ambience set — the level format's seed, its save bytes a real artifact for `RoomSpec`
- **The flow export reads truer everywhere**: density-sort trades stamp both arrivals (the dense sinker DOWN, the light riser UP — gas climbing through liquid exports UP); sand's displacement arrivals stamp UP; the bridge's entry pours, wakes, and the eject climb stamp via `_dir_between`. And every solid face in the renderer now draws from its `BANK_*` — the old single-color constants are gone

**Changelog v1.9 — the bedrock lab opens: kind two is wood**

- **The matter arc's ICE cut lands as a pure rename** (`TilePacket`): the third subtile kind — census slot three, the buoyant one — renames `ice_s`/`K_ICE`/`Led.ICE_S` to `wood_s`/`K_WOOD`/`Led.WOOD_S`; the column keeps its bytes, the ledger its row, the table values their numbers — `SUB_SINK` −1 now reads "loose wood rests buoyant until the buoyancy lab's weights." Behavior-neutral by design: the editor's ice brush becomes the wood_s brush, and that is the whole visible seam. Stage 1 of the bedrock lab; the structure pass and the STONE/WOOD/SOIL terrain retirement follow

- **The structure doctrine is locked** (design-ahead-of-code, the bedrock lab's target): structures are authored — the editor fuses, the sim destroys, never creates; connectivity is orthogonal subtile adjacency and diagonals never connect; a cut re-partitions (runs of ≥2 stay structures, singletons go loose); members are rigid forever and motion is whole-piece, later-lab — unsupported pieces fall as a unit (the compromise rule), slope sliding by contact patch with center-of-mass balance, advection by the liquid's current field, and pickup: the universal lasso — enemies, pots, and structures are one grasp set, one thing at a time — lifts within her weight cap, rotates 90°, tosses or places back into the CA, tetris-block bridges on the shard-actor pattern. The anchored graph (boundary and terrain anchors, anchor dissolution, tile-is-one-place) is retired before any code shipped

- **The structure pass is code** (`GridStructures`, `TilePacket.struct_s`, census column sixteen): authored membership over stone_s/wood_s cells — the editor's struct brush fuses, the shared erase cuts, the sim destroys and never creates; a member sits out the sand pass until its piece is cut (runs of ≥2 stay structures, singletons revert loose — BK0–BK7), the membership invariant rides `set_sub` so no path can ghost-freeze an empty cell, and the editor's slots migrate (a zero column appends to pre-structure saves). Whole-piece motion stays design-ahead-of-code (the buoyancy, currents, and shard-actor labs own it)

- **The retirement cut is code** (bedrock stage three): STONE, WOOD, and SOIL terrain exit the enum — terrain is AIR plus the fixtures, and solidity reads `solid_capacity == 0`, so a chipped wall admits water into the notch; authored walls convert to **pre-fused 4/4 matter** (the conversion is an authoring act — old census bytes migrate: terrain kinds convert, fixture indices renumber, the fuel column drops, damp clamps); FUEL and its ledger row retire for the burn-pool overlay — 64 fuel-equivalents per wood_s subtile at the flat rate, bone-dry ignition, progressive per-subtile burnout whose clears re-partition through the cut; the carve and the paint verbs author fused matter; condensation reads stone_s faces; the editor's slots version at v3. BK8 pins the mid-fire collapse, BK9 the chipped notch
- **The editor becomes the authoring tool, and the matter face reads structures**: exact-subtile paint and erase (what you point at is what you paint), the struct toggle (with it on, painted solids carry membership and connect cell by cell), blocking overlay menus that pause the sim, the inspector retired; and the matter face draws by the seam rule — no line between adjacent members, seams against loose or foreign matter, so a fused beam renders as one seamless mass. The rain field draws liquid materials only -- a flow stamp with no liquid beneath it is gas in transit, never falling rain (the smoke-rain fix)

**Changelog v1.8 — the liquids overhaul (code) and the matter arc (rulings locked, design-ahead-of-code)**

    The liquid layer is the pose model (Liquids): capture reads the settled CA into per-tile desires (containment binary and claim-aware, level throughput-aware, flow from the export), advance eases the pose on the frame clock, paint draws from the pose alone — the quadratic Bezier surface with containment-weighted neighbor edges, the traveling ripple, current lines, the portioned material stack, the rain field for falling water. No discrete decisions in paint (§9)
    The witch displaces like a body, not a fountain: containment reads the live claim — a tile filled to its claim-reduced budget props the column above it, so the water she holds out renders standing, never rain; and the bridge's pour order is the bow wave first (lateral, roomier side first — state-derived alternation, no PRNG, restore-exact), then the entry tile, then up the column to the first headroom, then the wake as catch-all. BT10 re-sealed (entry and sides block — the surface still breaks), BT15 pins the bow wave
    The matter arc — rulings locked at the planning session, six labs, not yet code: melt (lava as permanent fire, the cast, stone_s heat), bedrock (STONE, WOOD, and SOIL terrain retire into 4/4 matter; structures), acid (priced bites, a half-life), groundwater (per-subtile moisture; the WET tag and the TAGS column retire), buoyancy (the weight system, her swim rewrite), currents (the solved field — wind, grown up). Doctrine lives in §3's design-ahead-of-code sections
    The cuts: ICE and every notion of cold — freeze/thaw, MELT, snow, buoyant ice rest, the turtle's COLD aura (re-theme pending) — plus glaze, the LOOSE flag (superseded by structures), smolder's CA-side plan (§4.4 superseded — it moves actor-side, the beam lab owns the timer), and rain from this arc (C3's weather authors with the shipped furniture)

**Changelog v1.6 — the bridge lab (`864db58`) and the cleanup pass (`a5a9cc2`–`5417eac`): rooms, the customs office, the first actor**

- **The room model is code** (`Room`, `RoomState`): the engine quintet around one packet — the bridge runs at the tick head, then solids, liquids, reactions — with the per-room PRNG (seeded at construction, advanced only inside ticks) and the snapshot/restore machinery: fourteen census columns, the ignition overlay, both sweep-parity counters, copied as values on both sides (the aliasing canary), asserted green outside the tick. Unobserved rooms are never ticked — frozen by absence, not by a flag. The rooms suite (RT1–RT4): byte-exact restore that survives later ticks, fire's forgiveness (spent fuel, fire bits, and ignition progress all return to baseline), the frozen twin, and same-seed determinism — cheap no longer: the PRNG rolls now
- **The bridge is code** (`ActorBridge`, the customs office): bodies register and unregister; the tick head clears and rebuilds every body's claim, then runs each body's passes in a per-tick Fisher–Yates shuffle on the room PRNG; the quanta are expected-value rolls (numerator/denominator, the remainder rolled in-tick) — lumpy by doctrine, integer by law. Shipped exchanges: **ABSORB** (pool → wetness, tiered; a full tile drinks to saturation in one tick), **DRIP** (wetness → pool, ~4 water/s scaled by drip_mul, one PRNG-picked overlapped tile per operation), **BOIL** (heat + pool water → steam in the tile, tiered; min(heat, water) at a full tile — the dunk, budget-neutral by construction), **CROSS-TALK** (heat + own wetness → steam, flat 8/s), **DRY** (heat + damp underfoot → steam at 8/s — the bridge drier is no longer planned), FIRE/LAVA contact (+4/+8 per tick, capped at HEAT_MAX). The family checksum brackets the whole pass — pool + damp + every body's wetness; nothing crosses the customs office without landing (BT1–BT14)
- **The 1:1:1:1 retune is law: water, steam, damp, and wetness are one unit.** The even 2:1 wetness lattice is dead. `ThermalBody` carries heat 0–64 (HEAT_MAX — even maxed, she converts less than she displaces) and wetness 0–64 at 1:1; ABSORB and DRIP trade water and wetness one-for-one; CROSS-TALK and DRY are 1:1:1. Consequence: the carry window halves (~16 s at saturation, DRIP 4/s) — the knobs are DRIP and WETNESS_MAX, never a second lattice. HOT stays 63, SACRED
- **The claim column ships** (`actor_s`): a body's hitbox volume becomes live capacity — standing holds the water out, moving claims new tiles, leaving releases. Claims are overlay: never booked, never audited (`solid_capacity` is the ledger's legality line; `pool_capacity` reads the claim live), cleared at every tick head and on restore. Overflow pours through the entry tile first, then the vacated column (the wake), then up and out (the splash — rule five's walk, bridge-side). Displacement's proofs: entry splashes once and tenancy pumps nothing (BT11), the standing claim holds seek-level out (BT12), the walking wake keeps the basin and the family (BT13), the sealed pool breaks its own surface (BT10), a dry hot body boils before it drinks (BT14). And fire breathes through an actor: the air gate refunds claimed volume (+64 per nibble) — fire is a hazard to actors, never starved by one
- **The actor shell's first cut ships:** `ThermalBody` (heat, wetness, drip_mul, overlapped/support tiles, per-tile volumes, the entry tile and the wake — the owner writes at frame speed, the bridge spends at tick speed), `CollisionMirror` (the matter-to-physics half of the contact contract: the packet's solid map as 8×8 colliders, re-diffed every tick, boundary walls on three sides and open sky above — fire burns the floor out from under her), and **the witch herself** (`Witch`): a `CharacterBody2D` on a body, the 8×24 hitbox (a subtile wide, three tall), the 10px jump in code (SACRED), the capacity-aware wade line (half the tile's free capacity in liquid — a soil-bottomed pool reads true), swim (SWIM_GRAV 120, the stroke gated on sinking, the crouch dive), the outlined sheet driving her anim state. She never writes a tile — everything crosses the bridge. The witch lab (`test_witch.tscn`) is her manual playground: spawn/teleport, paint, ignite, live heat/wetness/family readout
- **The sealed chamber sorts** (`GridSand`): a crossing subtile may swap into a full tile whose terrain holds a pool — the swap replaces budget and escape with a density trade: the destination sheds its liquid into the source (`TilePacket.shift_pool`, booked both sides), and the liquid rises into the space each subtile vacates. Soil tolerates the one-unit clamp gap (its damp drinks the squeeze); stone and ice demand the exact fit. ST6's sealed-column ruling retimed; ST11 seals the proof
- **The whole bank runs at once:** `run_all` registers the rooms suite behind the others (the witch lab stays out — a playground, not an example suite)
- *(Addendum, the cleanup pass — no law changes)* The folders now name the domains — `sim/`, `bridge/`, `render/` — and the liquid engine is an orchestrator over five sibling modules: `WaterFlow` (the flow export), `WaterGas` (the rising rules), `WaterAnalyze` (the label pass), `WaterPools` (the column walks), `WaterSeek` (the pressure trades) — `RefCounted`, DAG-shaped, `tick()` calling them in the identical order. The bridge examples moved to `test_bridge.gd` (the fire scene's K runs GT+FT; total coverage unchanged), the sandbox's paint and verdict verbs are shared single paths, and `run_all` hardened: the compile gate (stale class caches fail loudly) and the vacuous-suite check. Every cut landed with the regression output byte-identical — 850 lines of `GridWater` became 365 plus five focused modules; 1004 lines of `test_fire` became 601 plus the bridge suite

**Changelog v1.5 — the fire lab (`d3946f0`) and the Amazon sibling (`5369ce6`)**

- **FUEL is a booked row; fire is unbooked overlay:** the packet's eleventh ledger row books burnable energy attached to solids (`fuel`, outside the pool), and `fire_s` holds fire bits as overlay state — never packet matter, never booked — with `has_fire()` as the fire solver's absent-pass gate. WOOD joins the terrain (`GridStone.Terrain`, carved at fuel granularity); a wood tile holds damp flat at `WOOD_DAMP_CAP` 64 — half a full soil tile, render-darkening past half
- **The gases join `MOVERS`** (smoke, steam appended — the loop order is still the drain order) and run their own rules: rise first, lateral creep only when pinned, an up-diagonal hop around corners (both flanking corners capacity-0 is the sealed crack), never seek level — a gas column is not a pressure vessel; the sort pass is the only elevator a gas needs through liquid. A horizontal exchange pass trades gas ratios between gas-holding neighbors (half-difference capped by `GAS_SWAP` 16, both givers taken before any add, refused adds refunded) — the equalizer seek level refuses to be (GT0–GT9)
- **The fire solver is code** (`GridReactions`, FT1–FT11): soak precedes fire by ruling — the puddle drinks before the flame boils what is left of it. Burning tiles burn fuel constant at `BURN_RATE` 24 (never ventilation-modulated — bits pace everything but the burn), pool oil at `OIL_PER_FUEL` 4, vent smoke at `SMOKE_PER_UNIT` 4 as a production rate (whatever does not fit is un-made — no debt, no buffer), engulf one bit per tick, boil water and damp up the tiered ladder at distance rings (`BOIL_W` 8/4/2, `BOIL_D` 4/2/1 — standing water at twice the damp rate everywhere; the rings ignore occlusion by ruling: stone-slowed distant boil is the readable distinction), breathe through the all-adjacent air gate (`AIR_MIN` 16 = LINE), starve unfed flame, smother without air. `ignite()` is the god hand; FUEL 0 → out (WOOD → AIR: arson is level editing, FT1)
- **Contact ignition ships — and it is not smolder:** cold fuel in orthogonal contact accrues ticks toward catch (`IGNITE_WOOD` 5 — the front walks 2 tiles/s; `IGNITE_OIL` 1 — oil flashes), the timer is the material's (multiple burning neighbors never stack it), catches land from a pending list after the sweep, damp fuel refuses, oil under a water layer waits (FT3, FT4). §4.4's heat-stimulus smolder — the 4 s warning — remains planned; the two timers are different machines
- **Condensation rains steam back** (`CONDENSE_RATE` 2): steam → water in place, on tiles orthogonally touching cool STONE (wood insulates), suppressed within Chebyshev `FIRE_DIST` 4 of any active fire — the mask rebuilds every tick (GT3, GT5). Water, steam, and damp are one closed trio: boil and condensation trade inside it — and the boil ladder is the **first drier**: fire drains damp to steam (`BOIL_D`)
- **The renderer moves to `scripts/fx/`** and learns the warm bank: wood planks (dusty khaki vs soil's umber, a plank seam for identity); gases drawn top-down — checker dither at eight units per line from the tile's top, solid past 121, rows split by share with the lightest band on top (the liquid stack partition, mirrored) — with every liquid read (`_liquid_total`) excluding the gases; fire bits as a 3-frame cycle (`FIRE_1/2/3`, hash-keyed per tile, never the PRNG) on top of everything the tile holds. `Palette` gains the wood, gas, and fire rows (oil, soil, and the debug colors retuned to hex in passing); acid and lava still alias water
- **The fire scene and suites:** `test_fire.tscn` — the fire lab whole (paint wood, steam, smoke, damp; `I` ignites at hover) — with the gas suite (GT0–GT9: fuel books, rise, ceiling spread, the rain cycle, the lip, the sealed cavity, stratification, the frozen diagonal, the rim export, the backed-up column) and the fire suite (FT1–FT11: burn-through, the self-smothering niche, damp refusal, the two-fire siege, the boil ladder, condensation distance, the climb, front pace, the crack, breath, the jam). `TestSandbox` gains overridable `drift_report`/`run_ticks`/`drift_watch`; the fire lab's conservation policy: the water+steam+damp trio is closed, fuel+oil burn to smoke at 4:1 as a production rate — smoke never shrinks, and never grows faster than four per unit burned
- **The Amazon doc joins the family:** `amazongame.md` v1.0 — a third delta doc, the demanding customer of three planned engine deltas: the **LOOSE flag** (§3 stone subtiles), the **wind system** (§3 gas — the open item's first real customer), and the **shard-actor pattern** (§4 — matter leaving the packet as actor holdings and returning on settle; the pot-interior precedent generalized). The family is three heroines; the crossover law reads across all three (§6). The witch's outlined sprite placeholder (`assets/witch/witch-Sheet-outlined.png`) landed in the same commit

**History — v1.0–v1.4, collapsed** *(every shipped ruling below lives in the sections above or in Appendix A's supersession rows; the hashes are the record)*

- **v1.4 (`17a4fb6`) — the perf pass:** absent-material gates (`has_mat`, `_two_mats_present`), the O(1) volume checksum from the booked ledger, zero per-tick allocation in `GridWater`'s bookkeeping, `is_solid` reading every full-solid terrain — behavior-neutral by design
- **v1.3 (`2582b3b`) — oil ships:** `GridWater` becomes the all-liquid engine (MOVERS densest-first), viscosity as a throughput cap, the density sort pass, seek level on density-weighted pressure integrals (RISE_MIN_DIFF and CELL_UNITS retired), `_eject_lightest_up` factored, the oil suite (OT1–OT4, UT1–UT4)
- **v1.2 (`1bb3c45`) — damp ships:** the reaction engine and soak's percolation skip, wet tags (the body-state system's first brick), moisture-is-mortar, GridSand's own flow export, damp riding crossings — and the ST5 lesson in law form: **a guard evaluates the post-state**. The drift watch and the soil suite (ST1–ST10) land with it
- **v1.1 (`d199585`) — synced to code:** §2 rewritten from `TilePacket` as shipped, the loose-solids field (the LOOSE flag planned), water rules and the rendering split made honest, the constants table cleaned (FLOW_RATE retired as never-shipped)
- **v1.0 — the founding statement:** extracted from `witchgame.md` v2.1; the game docs become deltas. The founding laws live in their sections, retune-annotated where the 1:1 pass touched them: the bridge's heat/wetness contract (§0 law 2, §4), HOT 63 and the vent ladder (§13), DRIP (§0 law 5, §4.2), smolder CA-side (§4.4), actors-cross-doors (§0 law 6, §8), pockets (§8), the contact contract (§0 law 8, §5), flat 10 s stun and 3 lives (§13, §8), one-PRNG-per-room determinism (§0 law 9, §1)



### world.md — retired constants (§13 provenance)
# retired: BURN_DRAIN (wood 8 / vine 12 / coal 1) — superseded by BURN_RATE 24 + OIL_PER_FUEL 4, shipped (v1.5)
# retired: OPEN_AIR_MIN — shipped as AIR_MIN 16, the all-adjacent air gate (v1.5)
# retired: FLOW_RATE = 3 — never shipped; flow speeds are the rule formulas above
# retired: SOIL_SUB 64 / DAMP 2:1 — superseded by DAMP_PER_SUB 32 at 1:1 (v1.2)
# retired: CELL_UNITS 256 / RISE_MIN_DIFF 256 — head math replaced by density-weighted pressure (v1.3)
# retired: FUEL/FIRE as planned fields — shipped at the fire lab: fuel a booked row, fire unbooked overlay (v1.5)
# retired: wetness 0–254 even (2:1) · CROSS_TALK 16 · DRIP 2:1 — superseded by the 1:1:1:1 retune at the
#   bridge lab: water, steam, damp, and wetness one unit; WETNESS_MAX 64, CROSS_TALK 8 (v1.6)
```

### world.md — Appendix A: supersessions
## Appendix A — supersessions (what this doc retires)

| Source | Retired by |
|---|---|
| witch v2.1 §1–§4 | absorbed here; `witchgame` v3.0 is a delta doc |
| witch "damp meter" | actor **wetness** — 0–254 even at the time, 0–64 at 1:1 since the v1.6 retune; tile DAMP unchanged |
| witch DRY_RATE 3/s, drip 1-per-2 | universal DRIP + CROSS-TALK |
| witch SOAK_RATE <tune> | the tier table |
| witch immune to heat | she has heat (fire/lava contact); she generates none |
| beam-specific smolder | CA-side smolder, hysteresis, universal — same 4 s |
| witch wading (BOOTS ad hoc) | half speed at ≥128 liquid, universal |
| MG "inert below HOT" | the bridge is always live; HOT gates smolder and tells |
| MG heat ladder | vent ⌊H/2⌋, keep ⌈H/2⌉ — 255→128→64→32; gains halved |
| MG MELT aura | CA reaction underfoot |
| MG ball LIT ≥ 64 | one threshold: HOT = 63 |
| MG spouts / recycle | pockets are one-way, forever |
| MG stun scaled by speed | flat 10 s |
| MG strip as a domain type | one room; reaches are beat annotations |
| MG star-well | cut (the nap garden replaces the finale) |
| FUEL/FIRE as planned fields | shipped (v1.5): fuel a booked ledger row; fire unbooked overlay bits |
| "gases join at the float lab" | joined at the fire lab — smoke/steam in MOVERS with their own rules (v1.5) |
| BURN_DRAIN / OPEN_AIR_MIN (planned) | superseded by BURN_RATE 24 / OIL_PER_FUEL 4 / AIR_MIN 16, shipped (v1.5) |
| wetness 0–254 even only — the 2:1 lattice (§2, §4.2, §4.6) | the 1:1:1:1 retune: water, steam, damp, and wetness one unit; WETNESS_MAX 64 — shipped at the bridge lab (v1.6) |
| CROSS_TALK 16 wetness/s · DRIP 2 wetness : 1 water · ABSORB 1 : 2 | CROSS_TALK 8 flat, all trades 1:1 — the same retune (v1.6) |
| "the shipped engine is PRNG-free" (§1 determinism) | the per-room PRNG is consumed at the tick head — body shuffle and quanta rolls, RT4 the proof (v1.6) |
| E3/E4 "not started" (§11) | the actor shell's first cut and the bridge's thermal half are code (v1.6) |
| "no tool or verb dries damp yet" (§3 soil, App. B) | DRY underfoot is code — the bridge drier shipped (v1.6) |
| "Palette bank (planned): eight rows × four colors; sprites authored 2-bit grayscale" (§9) | the bank law, shipped (v1.7): DB16 master plus documented guests; tile banks at most four, sprite banks at most three plus transparency — `TestPalette` machine-checks it |
| `FIRE_1/2/3` (§9) | `BANK_FIRE` — the fire cycle is a bank now, renamed by the law (v1.7) |
| "E5 — Light: rig, profiles, palette module — not started" (§11) | the palette module and the ambiance layer are code since the editor lab; the rig and profiles remain design (v1.7) |
| "fourteen census columns" (§2, §8, the v1.6 changelog) | fifteen — `debug_s`, the editor lab's furniture column, rides the census (v1.7) |


### witchgame.md — the changelog stack (v3.4 through v3.0)
**Changelog v3.2 — the editor lab: her dungeons get their dark (world v1.7)**

- **The palette law is code** (world §9): DB16 master plus documented guests, tile banks at most four and sprite banks at most three, index 0 darkest — her placeholder bank (`SPRITE_WITCH`) is in it. The v3.1 "palette bake stays pending" addendum is half-superseded: the *law* shipped; her sheet's re-quantization stays pending
- **Her dungeon sets are code**: four ambience banks — whisper blue, brick crypt, moss grotto, sandstone catacomb — recolor the same cave backdrop; a backdrop's identity is (room seed, set), so every chamber of her map can carry its own dark deterministically
- **The room editor is her map's seed** (`test_editor.tscn`): four persistent rooms, paint over tiles and debug furniture (water sources, drains, steam vents, open air), an inspector card, a witch chorus sharing one input — her seven chambers author into this, and the save bytes are the level format's first real artifact (world §10)

**Changelog v3.4 — the pace retune (code truth banked; no lab)**

- **WALK is 80 px/s (5 t/s)** — witch.gd has said 80 since the bridge lab; the doc's 40 was drift, and the bank follows the code (world §0 law 10). Horizontal jump reach doubles (~2 tiles at the SACRED arc); C0's 16px ledge joke is vertical and survives
- **PANIC_RUN retired: panic steers, never speeds.** The flee runs at WALK — the
  pressure is the clock, the ratchet, and the forced direction. C2's panic-run
  geometry retimes at M4 with both retunes in hand

**Changelog v3.3 — the matter arc rulings (design-ahead-of-code; world v1.8 §3)**

    Her swim becomes buoyancy (world §3): no more infinite stroke-jumping — she floats to the top, rests with her bottom half submerged, and a stroke from the surface buys exactly 10px above the water top (the SACRED jump, kept through water). Walking the bottom wants ballast — the future grab mechanic's job, and the weight-4 turtle is its first customer (ruling pending)
    Cold is cut: no ice, no freeze/thaw, no underfoot melt. The turtle loses its COLD aura — re-theme pending; its landed state (heavy riser, pressure plates) unchanged
    Her dungeon is matter now (the bedrock lab): wood and stone terrain retire into structures — C3's aqueduct burns as a wood_s structure and collapses by the compromise rule (world §3: an unsupported piece falls as a unit), C5's far wall is a wood_s wall that must be bone-dry to catch, and C2's fizzle grind survives as wood_s moisture. A chipped wall admits water: acid digs, water follows
    Structure pickup rides her lasso (world §3's movement doctrine): the lasso is universal — enemies, pots, and structures are one grasp set, one thing at a time — and a structure within her weight cap lassos like anything else, rotates in 90° increments while carried, and is tossed or placed back into the CA. Bridge-building with tetris blocks; the shard-actor pattern's second customer (rotation binding pending). C3's aqueduct, C5's wall, and every fallen beam afterward are hers to re-lay
    Smolder is hers now: the 4 s timer lives actor-side (the beam lab owns it; world §4.4 superseded) — the CA keeps only the steam and the fuel
    C3's rain authors with the shipped furniture (sources and drains) until/unless a rain system returns with world's boundary flux

**Changelog v3.1 — the bridge lab lands her substrate (world v1.6)**

- **She walks.** `Witch` is code: a `CharacterBody2D` on a `ThermalBody`, the 8×24 hitbox (a subtile wide, three tall), the 10px jump SACRED in engine code, the capacity-aware wade line, swim (submerged → buoyancy, world §3's weight system: floats to the top, rests half-submerged, the 10px surface stroke — no water-walking, no infinite stroke-jumping; ballast comes with the grab mechanic), the outlined sheet driving her anim state — and she never writes a tile; everything crosses the bridge. The witch lab (`test_witch.tscn`) is her playground: spawn/teleport (N), paint stone/water/wood/soil/damp, ignite (I), live heat/wetness/family readout
- **The bridge carries her now** (world §4 shipped): ABSORB/DRIP/BOIL/CROSS-TALK/DRY, fire contact +4/t — the mop verb, the steam bomb, and the fire-walk budget are engine law with acceptance proofs (BT1–BT14). Her panic clock, the smolder stimulus, and her verbs (lasso, beam, tags) remain game-side
- **Wetness is 1:1 now — the 1:1:1:1 retune is law** (world v1.6): water, steam, damp, and wetness are one unit; her meter is 0–64 and v3.0's "0–254 even" body is superseded. The carry window halves (~16 s at saturation, DRIP 4/s) — the knob stays the DRIP rate, never a second lattice. C2's mop-and-drip beat gets faster to drain; author accordingly
- Her dungeons have their memory now: the rooms lab (RT1–RT4) shipped snapshot/restore and the frozen unobserved room (world §8's first half), and the collision mirror keeps her floors honest — fire burns them out from under her

**Changelog v3.0**

- Restructured as a delta doc; §1–§4 of v2.1 are absorbed into `world.md`
- **Her damp meter is now universal wetness** (0–254, even lattice). DRY_RATE 3/s is retired — DRIP is ~4 water/s randomized, so the carry window is ~32 s of walking. *Tuning note: if the window is too generous, the knob is the DRIP rate, not a new mechanic*
- **She has heat now.** Sources: FIRE/LAVA contact only (+4/+8 per tick); she generates none — her magic pays zero heat. HOT witch smolders fuel she overlaps, dries damp soil underfoot (landslide), melts ice, trails steam through puddles. Her heat never hurts her; it hurts the room
- **The fire-walk license is the steam budget:** fire pushes her panic clock at ½× while her wetness > 0. The hiss stopping is the warning — fire zones burn off her cargo, now with teeth
- **Panic v2:** when panic ends she enters recovery frames (0.75 s, clock frozen, briefly vulnerable); a hit or fire during recovery resumes panic from the frozen value; calm drains the clock at 1×. KO at 5. CRISP unchanged: panic ending while still in fire
- **Spikes:** top contact only — engine bounce along the trajectory ring, +1 s panic. She has no hearts; she has the clock
- **Tags are fuel (8).** The smolder warning applies to them. A hot witch leaning on her own tag gets four seconds of mercy
- **The beam's burn band is a smolder stimulus** — the CA owns the 4 s timer and hysteresis (world §4.4). The beam-drying grind survives as engine law: four seconds per fizzle, repeated
- **Wisp ignition is HOT-presence smolder** — 4 s of hissing telegraph. C2's bridge beat retimes accordingly
- **Aim anchor unified at sprite center** (stick vector and mouse both; the same anchor steers the light). The mouse threshold's old feet-anchor is retired
- Her breadcrumb trail extends the engine trajectory ring to 5 s
- **Lives: 3, found as world secrets.** Zero lives → the full reset. The entry-door ritual is the voluntary version
- Enemy API compliance is law (world §6): every witch enemy must survive the magical girl's verbs. A witch-caught Drip is a throwable water balloon — its SPLASH is its wetness, dumped
- *(Addendum, `d3946f0`)* The outlined witch sheet placeholder (`assets/witch/witch-Sheet-outlined.png`) is in the repo — placeholder art; the palette bake (world §9) stays pending. The fire lab shipped her world's fuel-and-fire substrate (world v1.5): burnable wood, contact ignition at 5 ticks, and the boil ladder that finally dries damp — her smolder, heat, and panic clock remain bridge-side (E4)

### amazongame.md — the v1.0 changelog and addendum
**Changelog v1.0** — consolidation of brainstorm v0.1–v0.4

*(Addendum, world v1.6 — the bridge lab)* The engine shipped the room model, the bridge's thermal half, and the first heroine shell; the 1:1:1:1 retune (water, steam, damp, wetness one unit) now prices every wetness number in the family. Our declared deltas — the LOOSE flag, the wind system, the shard-actor pattern — remain planned and untouched.

- **Rooms reset on exit. Completely.** The witch's snapshot doors are dead here; the island runs the family default — baseline on every cycle. Lasting change lives in game-side flags, never matter. **The rooms forget; the satchel never does**
- **No levels, no XP, no economy.** Tin is found (damage), laurels are found (health, four leaves per heart; past cap, one life each), jars and gadgets are found. Sustain is renewable (drops, respawning fauna); progress is not. No shop will ever be built
- **The pip economy, third reading.** The girl's impacts *spend* pips; her sword *fills* them (full = panic = rout); bronze carries **grip** pips her strikes *drain* (empty = freed). One damage stat, both directions. The pip is the family's HP: the girl spends them, the Amazon fills them, the witch ignores them, and the lords lose them
- **The flee is a system:** away-vector steering; a door is an exit only if it is *not between* the animal and her; doors close with her body or with matter; fences at one subtile; cower when boxed; panic decays while cowering (pens are renewable)
- **The lasso yanks** — the enemy to one tile away, into sword range. Two yanks and the animal is wary (side-steps casts, this visit). **Bronze is immune: the lasso zips *her* to *it***
- **Five throw arcs** from one formula: class base (heavy 1 / mid 2 / light 3) + effort (stand 0 / run 1 / shot-put 2). The shot-put is a motion input — back-forward-back-forward — because she is the athlete, and hers is the only game with execution
- **Carrying is two-handed** and restricting by class; the sword button becomes drop, the lasso button becomes throw
- **The quiver is one nibble:** fifteen arrows, a 4-bit field. The engine joke canon grows
- **Combo drops** on the rout: arrows (a nibble's worth), hearts, randomized jars
- **The winged sandals: "DOUBLE JUMP."** Jump height 10px → 20px. One jump, doubled; the card does not lie. `SANDAL_JUMP_V = 139` — her doc's one dispensation
- **Wind completes smolder instantly.** Smolder is a placed fuse; the bag of winds is the detonator
- **Her heat byte never moves.** Fire costs her hearts (quarter-rate while wet — the steam-budget nod at quarter scale); flame is cargo in the torch, the arrow, the jar. She is the only heroine who is never hot
- **The grip is the boss health bar** — pips in reverse, fixed pools, so exploration always shortens every future fight
- **Purification, not destruction:** the lords are taken, not evil; the host cannot be hurt; the win state is a friend back
- **Saffron is structure (b):** questgiver from the landing, taken mid-slice at the vault door — the mini-boss is the tutorial for the finale mechanic of the full game
- **Cut:** the spirit-pocket seal (expulsion is CA smoke, gone), snapshots, the rodeo (post-slice), the grapple-any-surface hook (post-slice, the movement capstone), petrify and the thunderbolt (post-slice, endgame)
- **Upstream amendments:** pip dots above enemies are family-wide now (the girl's precedent, our law); the girl's terrain-zip ruling stands from her doc

### magicalgirlgame.md — the changelog stack (v2.1 through v2.0)
**Changelog v2.1 — the bridge lab sync (world v1.6)**

- **The substrate is engine code now:** the bridge's thermal half (`ActorBridge` — the exchanges, claims, displacement, BT1–BT14), the collision mirror, the first heroine shell, and the room model (`Room`/`RoomState`, RT1–RT4). Her thermal numbers below are the shipped ones
- **The 1:1:1:1 retune is law:** water, steam, damp, and wetness one unit — her wetness is 0–64, cross-talk steams at 8/s, and the carry is ~16 s. The retired numbers (cross-talk 16/s, carry ~32 s) are superseded wherever they appear below; retime R3's cistern pacing and the Cinderkit table's splash sizes at her next pass

**Changelog v2.0**

- Restructured as a delta doc; v1.0's §1–§4 and its engine claims are absorbed into `world.md`
- **The heat ladder is fixed:** HOT = 63 (SACRED, shared). The throw vents ⌊H/2⌋ into the ball — **255 → 128 → 64 → 32.** Three throws from blazing, two of them incendiary (balls at 127 and 64 are HOT; the third, at 32, is cool). Gains halved to match: flap +4, dash +8, fire +4/t, lava +8/t
- **The bridge is always live.** "Inert below HOT" is dead law. Below HOT the world steams — puddles shrink, rain wisps, her wetness boils off. At HOT the world catches — smolder warnings bloom where she stands. Steam below, fire at, no gate between
- **Smolder is universal CA law** (world §4.4): a HOT ball smolders fuel on impact — 4 s of telegraph, then fire. The Cinderkit's "ignites on contact" likewise
- **MELT is a CA reaction underfoot** — SR-A's pond melts as she skates; the melt-trail *is* the meter. The aura is cut
- **Pits are pockets:** one-way, any orientation, an evil aura on every one. Matter in = lost (ledgered, fine). Enemies in = captured, scored. She is an actor — falling in is death
- **Spouts and the star-well are cut.** Pockets keep what they take until the room forgives. The finale is the **nap garden:** the capture log napping in R7
- **Aiming: eight directions, snapped, straight line before spin, no preview.** Canonical angles make the outcome space memorizable; the room is the feedback
- **Touches defined** (see §6): any collision after her launch. The direct pot is the zero-touch pot
- Stun flat 10 s (shared). Windup 0.2 s — frame data, M1 verify
- **Lasso core inherited in full, water-cast included** (v1.0 was silent; the refraction cast is core tip behavior, world §7)
- **Lives: 3, earned by the ladder.** Zero → level reset, all states. Death: the strip resets, respawn at the entry door, prizes persist. Dying to farm washes out at best
- She inherits **wetness:** the mop-ferry-drip-boil loop, exercised lightly in R3, crossover-proofed
- **LOOSE_STONE now engine-shipped and exercised here** (R2's pillar, R6's cast-stone) — the witch's demo never calls for it; ours does
- Light posture: **outdoors the level sets the ambient; indoors she radiates** (lantern radius, a full screen). Firelight is a witch ability — her fires burn bright and cast nothing
