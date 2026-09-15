# WITCH DEMO — Vertical Slice GDD v2.1

**Goal:** one contiguous dungeon of seven chambers where every verb, element, container, and enemy behavior is operational with placeholder art. If this slice is fun with gray boxes, the game exists.

**Pitch:** a Game Boy Color–styled puzzle platformer. (Internal touchstones live outside the pitch.)

## Changelog v2.1

- Fidelity doctrine corrected: **magic is the only fidelity break** — all matter, physics, and generated effects stay in GBC bounds
- Aim model corrected: **no virtual cursor** — a stick vector off her sprite center (length = deflection) / the mouse position; aim and beam share one input by design
- **The content pool:** gas is 0–255 with smoke and steam tracked separately; every fluid/gas field shares one 255-unit capacity per tile; damp, fuel, and fire sit outside it
- **Pot capacity + the fill verb:** the pot interior is a tile (255 pool + four enemy nibbles); thrown empty pots scoop mid-air; monster-capture exception; pots are actors
- **Witch damp interfaces with the CA:** absorbs 1 water per 2 damp, drips it back as she dries — she is a timed water carrier
- Lantern underwater: free-floating, buoyant, trails her motion
- **Enemy hits:** knockback, flash, forced panic; shared panic clock; 5s → KO
- The beam obeys the ignite fizzle rule on damp walls — beam-drying is deliberate friction

## 0. Design doctrine

The laws this document has accumulated. When in doubt, these decide.

1. **The picture is the state.** The sim renders itself; nothing draws what isn't true, and nothing true goes undrawn.
2. **Magic is the only fidelity break.** Matter and physical phenomena — the simulation, the rendering, the palettes, and every generated effect (waterfalls, spray, waves) — live inside the Game Boy Color aesthetic, low-fi by intent so nothing sits out of place beside GBC sprites. Magic — the lantern's light, the lasso, the beam, whatever else is supernatural — is exempt from the bounds.
3. **Solids get subtiles; fluids and gases get bytes — one shared pool.** The subtile (8×8, the literal GB hardware tile) is the collision, opacity, and terrain-editing quantum. All 0–255 content shares one capacity per tile; what a solid *holds* (damp, fuel) lives outside the pool.
4. **Every exchange is an integer quantum.** No partial conversions, no rounding loss: 1 water ⇄ 2 damp only when both full units exist; remainders stay put. Generalize to every reaction, the witch included.
5. **Effects are region-scale.** Previews show regions (bodies, runs), not pixels.
6. **Capture, not crafting.** Pot contents are witnessed world state, never recipes.
7. **Fields don't cross doors; inventory does.** She is the only reagent carrier between sealed rooms. DOOR is always solid to CA flow, open or closed.
8. **Two reset layers.** The room forgives on death and door-cycles; the dungeon forgives at the entry door.
9. **Density rules have exactly one owner** — the lighter material checks; the heavier never does. No double swaps.
10. **Some mechanics are occult:** discoverable, never taught, no chalk. The plumb bob leans; that's all.

## 1. Tech setup

- **Godot 4.x**, GDScript
- **Viewport 240×240**, window 960×960, stretch `viewport`, integer scaling, nearest filtering
- **Tiles:** 16×16, each four 8×8 subtiles. Visible area 15×15. **Map: 112×15** — one scene, seven chambers separated by door walls
- **Element tick:** fixed 10 Hz, integer only, deterministic. Render 60fps; simulation never does
- **Chambers freeze when unobserved.** Only the current chamber simulates (on-theme and cheap)
- Modern conveniences in: coyote time, jump buffering, ledge tolerance. Not a twitch platformer; the edge cases will be appreciated

| Verb | Pad | KBM | Notes |
|---|---|---|---|
| Move | L-stick | A/D | waddle |
| Aim | R-stick: a vector off the center of her sprite, in the stick direction, **length = deflection** | mouse position | one input steers aim AND beam — both verbs at once, by design, on both schemes |
| Beam | stick deflection past threshold | mouse past a distance threshold from the center of her feet | transition anim: lantern dims, beam blooms; **beam live on the last frame**. Pad: fixed transition speed; mouse: transition tracks distance |
| Lasso / throw / drop | X | LMB | near-feet aim = gentle drop |
| Jump | A | Space | fixed 10px, no variable height |
| Place staff | B | E | toggle near planted staff to re-grab |
| Ignite | Y | RMB | short range, infinite |

## 2. Data model

Per-tile packet (~14 bytes/tile, ~3.5KB/chamber):

```
TERRAIN : AIR, STONE, WOOD, SOIL, BRAZIER, SPIKE, DOOR, DOOR_CLOSED
STONE_S : 4-bit occupancy — carve/cast granularity (DOOR/BRAZIER/SPIKE never subtiled)
SOIL_S  : 4-bit occupancy — the nibble IS the matter (popcount = mass)
ICE_S   : 4-bit occupancy — 32 water ⇄ 1 subtile, displaces 64
FUEL    : 0–255, attached to solids (vine 60, wood 255, coal 255)     — outside the pool
FIRE    : 0–255, burning state (requires open air)                    — outside the pool
WATER, OIL, ACID, LAVA, SMOKE, STEAM : each 0–255 — the content pool
DAMP    : 0–255, held by solids (64 capacity per soil subtile)        — outside the pool
SURFACE : NONE, MOSS, VINE, COAL, SLIME, GLAZE
FLAGS   : COLD, LIT, SCORCHED, structural
FLOW    : exported per tile per tick (direction + strength) — derived, not matter
```

**The content pool.** Water, oil, acid, lava, smoke, and steam are separate 0–255 fields sharing one budget: their total in a tile can never exceed 255, reduced 64 per solid subtile. Mixtures are allowed and render layered by density — heaviest at the bottom, gas on top (oil rides water within a tile; smoke rides everything). Reactant pairs sharing a tile resolve immediately per the reaction matrix — they never stably coexist; non-reactants layer and stay. **Damp is the stated exception:** it describes what the solid is *holding*, not what is *present*, so it lives outside the pool — and so do fuel and fire, which belong to solids. Overflow is ejected through the displacement rule, never destroyed. Gas thresholds (dissipation, wind displacement, beam attenuation) rescale to the new 0–255 density.

Pot model: **the pot interior is a tile** — a 255-unit content pool plus a 4-bit enemy occupancy, up to four enemies; each enemy nibble reduces the pot's fluid/gas capacity by 64. States compose: one fish and 191 units of water. Reactions run inside the pot — that is what a condensing steam bottle is.

Chamber record: baseline / saved bytes / saved enemies / tagged / enemy_baseline, plus **held-enemy exclusion marks** — captured enemies are out of the baseline; nothing duplicates across a door.

**Conservation ledger:** one row per material (WATER; DAMP at 2:1; SOIL subtile; STONE subtile; OIL; ACID; LAVA at 64:1; ICE subtile at 32:1; SMOKE; STEAM), reactions as balanced integer transfers, plus a **boundary-flux row** (exterior rooms, waterfalls). Asserted every tick alongside the pool constraint (Σ content ≤ capacity). A drift is a bug, not a rounding error.

## 3. Element simulation

```
func element_tick(ch):
	var order = ch.permutation              # fixed, seeded by chamber id
	for idx in order: _liquid_pass(idx)     # water (GridWater), oil, acid, lava, subtile solids
	_seek_level(); _export_flow()
	for idx in order: _fire_pass(idx)
	for idx in order: _gas_pass(idx)
	for idx in order: _growth_pass(idx)
	for idx in order: _phase_pass(idx)      # freeze, thaw, cast, glaze
	ledger.assert_all()
```

**Water — GridWater is authoritative.** Built and tested; where this document and the code diverge, the code wins. Rules as shipped: **FALL** (exclusive, instant; water/air swaps are how bubbles rise — one cell per tick, columns fall coherently), **POUR** (over lips into dry space only, corner-safe, air-gated), **CREEP** (half-difference into dry space, gated), **SEEK LEVEL** (each horizontal run is one incompressible conduit; columns trade volume surface-to-surface until heads match, at PRESSURE_RATE per run-row; a full capped column between them is a rigid pipe). **Invariant:** every move downhill-or-level; Σ(water × height) never increases — oscillation and uphill creep impossible by construction. **Air is gated, not simulated:** a pocket takes water only if its air escapes by sky, bubbling, donor-headspace, or high-junction rotation. **Determinism:** alternating sweep per tick; the escape flood is an order-independent monotone fixpoint. **Scan-order guarantee:** each cell's pass runs once per tick, and vertical moves only deposit into already-scanned rows — no double-moves; lateral CREEP cascades are convergent and intended. **Pool-aware capacity:** arriving water competes with resident oil and gas for the tile's budget; overflow displaces per the rule below.

Known approximations (accepted): region labels one tick stale; donor headspace treated as freely expandable; divided vessels can rest one line off level. Planned GridWater patch: allow small-diff rises into headroom escaped-to-sky (the invariant permits diff ≥ water[above] + 2; keep the strict gate for pocketed headroom).

**Displacement:** a solid subtile reduces the tile's pool capacity by 64; four subtiles is fully solid, identical to v1 STONE. When capacity drops below current content — placement, casting, freezing — the excess is ejected through normal flow rules. Matter is displaced, never destroyed.

**Flow export:** per tile per tick, direction + strength, from instrumented moves. Gameplay: pushes the witch, enemies, loose objects (capped vs. walk speed). Rendering: deltas drive waterfalls and splash. A tile with water-in-transit above `DIFFUSER_FLOW` becomes a **diffuser** — the beam cannot pass (§8).

**Soil (subtiles).** 4-bit occupancy; popcount is matter, Σ popcount asserted. **All sixteen shapes are representable** — transient shapes during falls and slides are the *animation*: soil visibly tumbles through unstable forms toward stable ones. Stability is what the rules produce, not a stored constraint. Moves: fall if below empty; slide diagonally if the diagonal-below is empty and the side is clear (corner rule); repose emerges — settled neighbors differ by ≤ ~1 subtile; piles are 8px staircases. 8px is a hop, never an auto-step. **Moisture is mortar:** saturated subtiles don't slide; fire drying a wet slope triggers a landslide (buries fire, spikes, enemies). **Damp accounting:** capacity 64 per soil subtile (one subtile 0–63, two 0–127, four 0–255); arriving water splits half-flows / half-absorbs (integer halves; remainders flow); exchange **2 damp per 1 water, integer-only** — convert one water unit only when two free damp units exist; damp percolates downward through saturated soil, so deep piles keep drinking. A full water tile over full soil soaks to ~127 water with the soil saturated. Render: darken the top ⌈damp/64⌉ subtiles — the creeping front; water films above the soil's low surface, the high quad pierces.

**Stone subtiles.** Static occupancy. Carved by acid (64 acid destroys one subtile), cast by lava (64 lava + water → one subtile + steam). Wood is carved at fuel granularity (acid drains fuel; fuel 0 → AIR). Doors never carve. Glaze is immune.

**Oil.** Pool liquid, fuel 255. Density rule owned by the oil — oil with water above swaps down; water never checks oil; within a tile they layer (water below, oil above). Burning oil travels the float layer and self-limits as it consumes. The one sanctioned fire that swims.

**Acid.** Pool liquid. 64 acid dissolves one subtile of stone or soil (or 64 fuel of wood), consuming itself. **Acid decays and is purged below 64** — dissolved into imperceptibility. Deliberately unlike water, which is conserved forever.

**Ice.** Subtile solid. 32 water freeze into one subtile; one subtile displaces 64 pool capacity — **freezing expands**. The freeze check requires the displaced material somewhere to go (air-gate family). Ice floats: submerged ice migrates up a subtile per tick (density rule owned by ice); water above ice swaps down; ice freezing under existing ice pushes it up. Thaw returns 32 water per subtile. Implementation difficulties: Appendix B.

**Lava.** Stone that forgot it's solid. Pool liquid, slow; ignites fuel on contact; water contact casts one stone subtile per 64 lava and makes steam. Fire as masonry — redirect lava through a water channel to build lips, steps, half-walls.

**Glaze.** Sustained fire on a soil surface vitrifies it (SURFACE: GLAZE). Opaque, acid-proof. The counter-material: acid digs, glaze routes.

**Fire.** A burning tile requires **open air** — pool capacity minus water and solid subtiles ≥ 16. Less smothers (steam wisp if water). This is the universal snuff: drown it or bury it — pour soil on flames. Loose fuel (from broken pots) obeys buoyancy: heavies sink after a beat afloat; burning fuel on water burns one beat, boils a little water, sinks, snuffs. Spread: orthogonal, free; wind ember-leaps one gap downwind. Damp siege as v1 (drain 4/tick, steam). Fuel 0 → out (WOOD → AIR: arson is level editing; else SCORCHED). **Lens ignition is not a heat field:** sustained burn-band exposure plays a 4-second smolder animation — the mirror of the growth blips, smoke and sound — and ignites on completion. Beam leaving, wetting, or burying resets it.

**Gas.** Smoke and steam, each 0–255 in the pool. Smoke rises and pools under ceilings, advects downwind (draft fields are authored wind — **wind system TBD**). Steam rises, spreads along the ceiling, and condenses off cool stone as **slow drizzle** — the enclosed water cycle; the room's rate reads as the garden's metronome. (The v1 single-drip clock is retired.)

**Rain.** Exterior chambers expose open-sky columns; exposed tiles gain water per tick; wind slants it; water leaving the map is boundary flux. Rain feeds reservoirs and aqueducts (wood) off-map. Optional post-slice: seeded lightning (conducts through the rising body); snow in cold chambers.

**Electricity exists only as the eel.** A spark is a flood through a connected wet body — the sim's own body graph. The eel thrown into water discharges through the body; the preview highlights the affected region. She is conductive when damp: the same puddle that is fire-walk license is electrocution risk. Wet paths are wires — soak a line, drop the eel, trigger the far botanical.

**Botanical triggers** (the sensor family — no tech in this world, forest spirits only): gate-fungus (wet contact), pitcher plant (level switch), snap-grass (flow switch), scorch-bloom (fire contact). Beam-growable: the lens can grow a trigger where you need one. Field state, queryable by level logic.

**Body-state subsystem.** Per-body quality flags for connected like-material bodies — water: poisoned, tainted, holy; soil: fertile or not. Quality, **not phase**: water, steam, and ice are three distinct elements with phase-change rules, never tags on one body. Potential system; the demo candidate is the poison-and-boil-purify loop.

**Reaction matrix** (every cell is a puzzle verb):

| | |
|---|---|
| water + cold → ice (32 ⇄ 1 subtile) | ice + heat → water |
| lava + water → stone subtile + steam | acid + stone/soil → AIR (−64 acid) |
| oil + fire → surface burn | acid + water → poison body |
| soil + water → damp (2:1, integer) | soil + sustained fire → glaze |
| fire without open air → out | damp + fire → steam siege |

## 4. Rendering

One `Image` the size of the map, 10 Hz, `ImageTexture`, under actors. The sim state is the picture; debugging is looking at the room. All of this is physical state — it stays in GBC bounds.

**Palette bank** (replaces the DB16 plan): eight rows × four colors for the whole screen —

```
P0 witch              (eyes: exempt row, own layer)
P1 warm  — fire, embers, lantern tint
P2 cool  — water, steam-shadow, cold
P3 enemy hostile
P4 enemy docile (captured / stunned)
P5 gas    — smoke / steam densities
P6 witch stationery — chalk arrows, paper tags
P7 accent — secrets, plumb target, throw previews
```

Sprites authored as 2-bit grayscale, baked at boot through the Palette module — one table is the single source of truth; field and sprite colors can never drift. **Rows are conditions, sprites are modes:** a row per state (hostile / docile / stunned / burning / damp) — five silhouettes × N rows instead of thirty sprites; a state machine readable across the room. Per-chamber remaps ("palette as place") tint the bank; **semantic slots never remap** — fire stays warm, water stays readable, her eyes stay red. Eyes: two 1×2 unshaded pixels on a canvas layer above the CanvasModulate. Cartoon law.

- Water: fill fraction, dithered below 64; films above soil's low surface; 60fps shimmer over 10Hz steps (the period-authentic split)
- Mixtures render layered by density within a tile — water under oil under gas; the pool's arrangement is visible at a glance
- Subtile solids: 8×8 quads — terrain editing at literal hardware-tile resolution
- Damp front: the top ⌈damp/64⌉ subtiles darken; percolation is visible
- Gas: Bayer dither by density (0–255). Fire: 3-frame palette cycle. Scorch: permanent dark flag
- Derived animation — all of it low-fi, palette-and-dither language, never out of place beside GBC sprites: splash disturbance decays per tick (a restored room comes back calm — the dungeon forgets the splash); waterfalls are streaks on high downward flow — the renderer reads the flow field, no semantic labels; spray and waves keyed on (tile hash, tick count), never wall-clock
- Growth: four blips over four seconds; blip one shows roots toward the currently chosen target — **growth is steerable mid-charge**
- Smolder: the four-second mirror animation
- **Dotted previews:** dotted line = intent, everywhere — throw arcs, drops, growth targets, the eel's affected body. Dots twinkle (random phase per dot, star-like); **line color is stateful** — throw arc P7, damp effect water colors, cold effect cool colors, burn warm

## 5. The Witch

16×32. Waddle 40 px/s, ~2.5 tiles/s.

```
const GRAVITY = 480
const JUMP_V  = 98        # solves to exactly 10px
const SWIM_GRAV = 120
const PANIC_MAX = 5.0
const HIT_PANIC = 1.0     # forced panic per enemy hit
```

- **JUMP_HEIGHT = 10 (SACRED — was 9).** Margin over the 8px subtile step. The 16px ledge in C0 remains unjumpable — the joke survives.
- Coyote time, jump buffering, ledge tolerance: in.
- Swim (BRIM): gravity 120, vy clamp, infinite jump = swimming. BOOTS: shallow slow. surface_hop: identical 10px, no bonus; ledges >10px need a riser. Sacred number.
- **Enemy contact.** A hit knocks her back, flashes her like damage, and forces panic — **one second per hit** — running her breadcrumbs in reverse, away from what hit her. The panic clock is shared with fire: hits and fire contact both push it. If she panics for five full seconds (**PANIC_MAX**), the run ends in a **KO** — she slumps, blinky eyes, 1.5s, chamber reset. A non-event, same family as CRISP. Enemies are danger the way fire is danger: pressure that makes her flee, not health that ticks down.
- Panic from fire (v1): release capture, drop carried pots, reverse breadcrumbs at 70 px/s; at trail end she recovers unless still touching fire → CRISP. Either flavor of death resets the chamber and burns a placed tag.
- **Damp, and the CA.** Water contact soaks her at the integer exchange: **one unit of water per two units of damp** — submersion saturates quickly (SOAK_RATE, tuning), and a shallow puddle drains visibly into her. She can mop a puddle dry and carry it. Drying drains 3/s; every two damp held drips **one water into her current tile** — near fire it evaporates on the spot (steam). She is a timed water carrier: soak here, sweat there, the meter is the drip, and fire zones burn off her cargo. Fire-walk license unchanged.
- **The lantern is a physics pendulum** on the staff tip. Staff: 5-cell walk cycle, anchor position authored per cell — she walks with it, the tip swings, the lantern swings on the tip. Verlet point + distance constraint + gravity + drag + cone clamp (±~70°, a projection, not a special case). The light follows the bob: gait swings it, panic whips it, stillness settles it. **The plumb bob is the same body** — a small persistent attraction toward secret markers tilts its hang; divination as physics. The lantern **rides the lasso tip** during a throw — you throw the light; on return it snaps back with its momentum, still swinging. Planted staff: the lantern hangs from the planted tip (the turret light). **Underwater, the constraints come off:** the bob becomes a free body — buoyant, drifting in any direction, floating up and trailing behind her motion, still lit. The pendulum re-clamps when she surfaces. The lantern is **magic, not flame** — exempt from the fidelity bounds; only smoke occludes it.
- Chalk hints: chalk arrow decals, in-fiction. C0 has three. Nothing else explains anything. Occult mechanics get no chalk, ever.

## 6. Lasso + enemy system

Staff/lasso FSM (v1): IDLE → FIRE_TIP (tip travels straight, max 7 tiles, loose rope render) → SNATCH (0.15s) → CAPTURED; swing rings (pendulum, release = tangential launch — feels like a bad idea; correct); levers; pots yanked to hands. CAPTURED: preview always visible; aim far → THROW (enemy runs its projectile behavior); aim ≤1.5 tiles from feet → DROP (placed STUNNED). Thrown → STUNNED (10s, recapturable) → recovers.

**Through water:** the tip travels, refracts, slows — a fishing-line cast. The preview bends identically; the kink is the surface line, so depth reads on sight. Hit = auto-reel; no manual reeling. Range is measured in tiles — water costs time, not cover. Underwater enemies are fishable.

| Enemy | Wt | Alive | As projectile | Landed state |
|---|---|---|---|---|
| Slime | 1 | slow hop patrol | fat lob arc | **SPLAT**: 8px riser, fire blanket, covers spikes; lasso re-gathers |
| Woodpecker | 1 | hover sine, dives | straight, never arcs | **PERCH**: sticks in wall, walkable top, angry wiggle |
| Wisp | 1 | drifts at you, ignites fuel on contact | straight, slow | **STICK**: flame + light 20s; water douses it dead |
| Turtle | 4 | plays dead until 2-tile proximity | heavy short arc | **SITS**: heavy riser; 3×3 COLD aura; pressure plates |
| Breeze | 1 | drifts horizontally | sticks where thrown | **BLOWS**: wind stamp, 4 tiles cardinal; ventilation + ember-leaps |
| **Eel** | 1 | patrols its water | straight, slow | **ZAP**: discharges through its wet body, 20s; recapturable |

**Respawn rule:** held or captured enemies are marked out of the chamber baseline — nothing duplicates across a door. Load-bearing for the C6 turtle smuggle.

Shape grammar (placeholder and final): hostile reads angular; stunned/projectile reads round; size = weight. The circle/square test sprites are the degenerate form.

Post-slice candidates: moth (the tag-eater, §9), grub (thrown terrain-eater; drills her-width tunnels; stops at doors — even the worm respects the boundary), mold (growth antagonist: spreads on damp without LIT; fire is the lawnmower), ink-squid (smoke weapon vs. the beam; breeze counters).

## 7. Pots

One pot. **The pot becomes what you submerge it in** — and now, what you throw it through.

**Capacity: the pot interior is a tile.** A 255-unit content pool plus a 4-bit enemy occupancy — **up to four enemies** — each enemy nibble reducing the pot's fluid/gas capacity by 64. A pot with one fish holds 191 units of water; a pot of four slimes holds nothing else. Any composition a real tile can hold, up to one tile's worth; reactions run inside (the condensing steam bottle is a pot-internal phase change).

**Pots are actors.** Picked up with the lasso verb exactly like catching a monster; they live in the same actor space as enemies, and their behavior is to sit still and contain things.

**The fill verb.** A thrown **empty** pot scoops whatever it passes through while in the air — rain, waterfall, steam, smoke — filling in flight. A **filled** pot shatters on contact with anything and releases its contents (scoop-delivery by arc: throw the empty pot through the waterfall, and the water lands where it breaks). **The monster exception:** a thrown pot with enemy room that hits a monster captures it into the next empty slot instead of shattering — an empty pot thrown at a slime comes back a slime pot. A gentle drop at her feet puts any pot down unbroken. An empty pot that lands without scooping shatters harmlessly — the pot is spent; fixtures are finite.

**No crafting — explicit.** Cauldrons, brewing, material dumping: cut. Contents are **captured, never assembled**: hold the pot in a brazier flame → FIRE pot; hold it in steam → a steam bottle, which slowly condenses inside — a sweating, delayed water source. Every pot state is witnessed world state.

**The fire pot is not simulation fire** — it shows a convenience puff while carried. On break, the tile where it broke receives its contents: the fuel amount and lit state (over water, the tile above the surface). Loose fuel obeys buoyancy; flames need open air — so a fire pot broken *into* water is a dud: one beat of burn, a steam puff, sinking coals. Land it on dry stone.

Fill at rest (v1): resting in water ≥50% tile fills 64/tick; soil mound → DIRT; burning brazier → FIRE. Gentle drop = carrying (safe 8px riser). Weights: empty 1, water 3, enemy = enemy's weight + 1. Loadout readable across the room: hat = enemy, arms = pot.

## 8. Ignite, beam, light

**Ignite (v1):** tile under aim within 1.5 tiles, else faced tile. Fuel > 0 and water 0 → ignite. Damp > 0 → fizzle (hiss, steam, damp −8; you can stubbornly click a wall dry). No fuel → tiny spark.

**The beam is binary.** It exists or it doesn't; direction is the aim — the stick vector, or the mouse. Activation: stick deflection past threshold, or the mouse past a distance threshold from the center of her feet. A visual transition plays — lantern dims, beam blooms — and the beam goes live **on the last frame of the transition**. Pad: fixed transition speed. Mouse: the transition tracks distance. Aim and beam are one input on both schemes — the two verbs happen simultaneously without interference, by design.

**Focus bands (SACRED).** The focal point renders at exactly **16 tiles** — the player can see the lens converge. Bands measured from the beam's origin (her hand, or the planted staff):

```
0 – 2    : nothing (omni territory)
2 – 10   : GROWTH
10 – 22  : BURNING (focus ± 6, centered on 16)
22 – 30  : GROWTH (the big-room inversion — past the waist the cone diverges and gentles)
30 +     : nothing
```

Growth bands are equal, eight wide, on either side; burn is twelve, centered on the focus. Ten tiles out-ranges the seven-tile lasso — the lens and the lasso have different identities.

**Terrain is the beam's only terminator.** The cursor never ends it — the beam overruns its aim and dies on the first opaque thing. Occluders follow subtile shapes (a soil berm honestly shades the beam); glaze is opaque.

**Water and the beam:** standing water does not affect it; a spray does not either. **A lot of water moving does:** any tile with water-in-transit above `DIFFUSER_FLOW` is a diffuser — the beam cannot pass. A waterfall is a wall of light (also a level-design noun — see C6).

**LIT semantics:** binary for growth steering — the `most_lit` ranking is retired (ranked light makes vines seek the focal waist). Firelight never steers growth. Ranked light is reserved for wild growth, a post-slice enemy.

**Smolder → ignite:** burn-band exposure on a fuel tile plays the 4-second smolder (smoke, sound); completion ignites. Beam leaving, wetting, or burying resets it. No heat field anywhere. **On a damp tile, the beam obeys the ignite verb exactly:** a full four-second hold ends in the fizzle — hiss, steam, damp −8 — and the smolder resets. Beam-drying a wall means four seconds per fizzle, repeated: a deliberately annoying grind, priced to push players toward better ideas without foreclosing the stubborn one.

Light rig: CanvasModulate near-black blue; omni on the lantern; focus cone with shadows from occluder polylines regenerated on tile *and subtile* changes; beam smoke attenuation (retuned to 0–255 densities); LIT mask by 5-ray visibility-checked fan; fire light pool of 6 — arson is illumination; plumb bob lean; dithered gradient textures. **The light rig is magic — exempt from the fidelity bounds.** The beam's *effects* (smolder, scorch, LIT) are physical and stay in bounds. Lantern: rides the tip, magic, smoke-occluded only, free-floating underwater.

## 9. Tags, death, and the two reset layers

**The paper tag.** A written slip (P6 — her handwriting, same row as the chalk), slapped on the wall. It snapshots the room at the stamp: leave and return, and the room reverts to exactly that moment. **Order of operations is the grammar:** stamp *before* the risky verb and it's an undo (burn the bridge, leave, return — the bridge is back); stamp *after* and it's a contract (the hole in the wall is now dungeon history). Removal: **ignite** — deliberate — or spreading fire reaching that wall, accidental. Placement is a skill; a wooden wall is papering your fuse. Water: soggy but functional.

**Death.** The room restores baseline. **A placed tag is destroyed; unplaced tags are safe.** Placing a tag is putting your stake on the poker table. Future design pass: other global resources that feed the death loop and can be staked by use in the world — noted as an extension of the global layer.

**Two reset layers.**
1. **Room layer:** door-cycles (untagged → baseline; tagged → snapshot) and death (baseline, stake burned).
2. **Global layer:** the dungeon. Tags are global objects that modify room-layer behavior. **Global reset:** walk out the entry door and come back in — every chamber to baseline, the tag allotment restored, placed tags erased. The candle ritual replays.

**Tag economy:** a fixed allotment per level — three for the early levels, five for the longer ones. The demo carries **one**.

**Meta structure (full game, for context):** ~8 levels, each a semi-open dungeon you're dropped into. Walk in the door; the dungeon doesn't necessarily make physical sense; relight — or swap in — the candle, and the dungeon lights itself. Exit through fixed corridors with an accommodating variance of monsters. Cutscenes between levels; a different cutscene when loading an in-progress game. Details deferred.

**The moth (post-slice):** the tag-eater. It lives in the doorways — the sacrosanct boundary is its habitat — and eats paper. Mechanically the janitor: destroying a lock reverts the room, so the harshest narrative beat in the game is also its safest actor. Playtests must keep this true.

## 10. The map: seven chambers, 112×15

**C0 — "THRESHOLD" (x 0–11).** v1: black room, the door, the grind, the slam, the beat, the lantern click. A 16px ledge she cannot jump — still, at 10px — the joke taught in silence. A slime in a spike pit and a chalk arrow: lasso, aim, splat, walk across. A second arrow teaches drop-vs-throw.

**C1 — "THE STRAP" (x 12–27).** v1: the lasso lab. 3-tile wall, woodpecker perch staircase, lever + closed gate from range, the swing ring with its deliberate jank and the safer route below.

**C2 — "KINDLING" (x 28–45).** v1: the fire lab. Vine curtain (the ignite verb), the wisp and the bridge that will catch, the panic-run geometry with the puddle, the damp wall and the fizzle, the slime blanket. New and discoverable, no chalk: dry soil smothers fire. And she can mop the puddle into herself and drip it elsewhere — nobody will tell her that's possible.

**C3 — "THE DROWN" (x 46–61) — the water signature moment.** Semi-exterior: the upper reaches open to sky, rain falls past the walkway (the weather tease — a purely visual treat, plants in pots drinking), and collects off-map into a **wooden aqueduct** spanning above the chamber. Below: the 6-deep pool, the turtle on the floor (cold aura demos naturally), the pot pedestal on the near shore, the gate lever on the far shore, underwater. The exit ledge sits 3 tiles above the surface — no surface hop reaches it. **The solve: ignite the aqueduct's wooden support.** The reservoir drains, the pool rises, and she swims up to the exit as the room floods around her — dynamic moment, show-off, and swimming tutorial in one beat. Alternates: pedestal pot as a stair, a slime lily pad. The door-cycle restores the aqueduct.

**C4 — "GARDEN CORE" (x 62–79).** v1's chain, drizzle edition: ignite the brazier by the puddle → steam rises and spreads along the cold ceiling → condenses as slow drizzle → the incline funnels it to the soil patch → the damp front creeps down, visibly → plant the staff, aim the beam up the wall → steerable moss trellis, one tile per four seconds, blips telegraphing the target → climb her garden. The turtle as a mobile condenser plate remains the alternate solve.

**C5 — "THE LENS" (x 80–95) — the garden's dark twin.** A long room, open-framed on the beam axis (the stone-frame signal: this room continues). A growth anchor mid-room, in the growth band from the naive stance. The far wall is **wood, floor to ceiling** — and the beam doesn't stop at what you're pointing at. The player gardens; the beam overruns; the smolder starts on the far wall; the surprise lands mid-growth. Four solves, all authored in: **angle** — a stone beam dump catches the overrun (new level vocabulary); **damp** — the wick rule, with a water pot placed *between* plant and wall, doubling as the mid-failure rescue (fire ~1 tile/s, her 4.4 calm); **berm** — pile soil to shade the line; **stance** — sub-10 is safe: walk *toward* the danger; a spike moat justifies the distance. Fuse (4s smolder) < grow time (4s per tile): the first attempt fails by surprise, the retry fails by timer, only a solution completes. A fuel path runs from wall to growth site. Telegraphs: the smolder animation and sound, plus authored scorch on the far wall in the baseline — *this wall has burned before*. No tag lesson here; papering the far wall is the trap, not the teach.

**C6 — "THE HOOK" (x 96–111).** v1's finale, plus the countermeasure: a **waterfall** spawns above the room and drains below it — never accumulating, never flooding — across the sightline to the burnable wooden door. A wall of moving water the lens cannot pass; the firebomb remains the solve. The pot survives the flight (not sim fire until it breaks) but must land on dry stone — an empty pot thrown *through* the waterfall arrives full and breaks wet where it lands, which is its own lesson. Behind the door: the vine curtain (burn it or slime-smother the wisp), the secret alcove the plumb bob has leaned toward since the entrance, the pressure plate (weight 2 — two slimes, or the turtle smuggled from C3), and the tag: **burn the door, tag the room, and walk out through a hole you made and notarized.** Final frame: a big sealed door, unmistakably the shape of C0's entrance. Fade. Demo over.

## 11. Placeholder art & audio

- Palette discipline from day one: the 8×4 bank (§4), not arbitrary 16-color sets
- Witch: 16×32 dark silhouette — triangle hat, robe wedge, two red eye pixels; she is 90% shape
- Enemies: colored blobs with distinct silhouettes; circle/square placeholders encode mode; pots are simple cylinders, contents visible as a fill band
- SFX: jsfxr for everything — whip, snatch pitch-drop, crackle, hiss, the smolder's sound, the pot's shatter
- Music: one looping CC0 drone, filtered low

## 12. Build order

- **M0 — Room + witch:** tilemap, camera clamp, 10px jump, darkness + omni + the pendulum lantern. *Is it already atmospheric? The pendulum is the question — if not, stop and fix here*
- **M1 — Lasso loop:** tip, snatch, capture, twinkling previews, throw/drop, slime + woodpecker, stun/recover, lantern rides the tip, pots as actors (yank to hands). C0–C1 playable
- **M2 — Water:** GridWater integration (authoritative, pool-aware) + flow export + wick rule + drizzle condensation + chamber restore. C3's pool and the aqueduct beat
- **M2.5 — Materials:** soil subtiles (nibble CA, damp front, mortar), stone subtiles, oil, acid + decay, glaze, lava, ice. Reaction matrix + the ledger
- **M3 — Light deep-dive:** binary beam + transition, focus bands, LIT mask, smolder + the damp-fizzle grind, steerable growth. C5 testable in isolation
- **M4 — Witch wet state:** swim, damp absorption + drip, panic (fire + enemy hits, KO), crisp death. C3 playable end-to-end
- **M5 — Pots + remaining enemies:** pot-as-tile interior, the fill verb, capture rules, break/buoyancy, wisp, turtle, breeze (wind system authored or stubbed), eel + electricity, botanical triggers. C3–C5 real
- **M6 — Meta:** pressure plate, paper tags (stake-on-death, global reset), plumb bob, swing ring, C6 + the waterfall, the opening cinematic. Slice complete

**Explicit cuts (do not build):** crafting of any kind (cauldrons, brewing, material dumping); hand lantern; lasso-shears; cracked-floor turtle smash; crooked geometry. Deferred/optional: staff tips, rain lightning, snow, wild growth, grub/mold/ink-squid. The mirror moth is re-authorized post-slice as the tag-eater.

## 13. Tuning constants

```
TILE = 16, SUBTILE = 8             # SACRED — the subtile is the hardware tile
JUMP_HEIGHT = 10                   # SACRED (was 9 — margin over the subtile step)
RISER = 8                          # SACRED
WALK = 40 px/s, TICK = 10 Hz
GRAVITY = 480, JUMP_V = 98         # sqrt(2·g·h), h = 10
FOCUS_POINT = 16 tiles             # SACRED — rendered, the visible waist
GROW_BANDS = 2–10, 22–30           # SACRED
BURN_BAND = 10–22                  # SACRED (focus ± 6)
SMOLDER = 4 s                      # mirrors GROWTH = 4 s per tile
POOL = 255 per tile, −64 per solid subtile (enemies included, in pots)
SOIL_SUB = 64 units, DAMP 2:1      # integer quanta only
ACID_SUB = 64, purge below 64      # acid is not conserved; water is
LAVA_SUB = 64, ICE_SUB = 32 water (displaces 64)
GAS = 0–255 per type; thresholds retuned to the new scale
FLOW_RATE = 3, PRESSURE_RATE = 64  # cell rules / seek-level per run-row
BURN_DRAIN: wood 8, vine 12, coal 1
DAMP_IGNITE_THRESH = 60; FIZZLE = damp −8 (ignite and beam alike)
OPEN_AIR_MIN = 16                  # fire needs one line of air; less smothers
DIFFUSER_FLOW = <tune>             # water-in-transit that blocks the beam
SOAK_RATE = <tune>                 # her absorption; DRY_RATE = 3/s; drip 1 water per 2 damp
HIT_PANIC = 1 s per hit; PANIC_MAX = 5 s → KO
LANTERN_BUOY = <tune>              # underwater free-body drift
LASSO_RANGE = 7 tiles, STUN = 10 s
PLATE_WEIGHT = 2, FIRE_LIGHT_POOL = 6
TAGS: demo 1; full game 3–5 per level
```

## 14. Slice exit checklist

- [ ] Can a player lose access to a solution? (resets forgive; tags persist what should)
- [ ] Does every chamber teach exactly one thing, with zero text?
- [ ] Two ways to solve C3, C4, and C5?
- [ ] Does the reservoir flood land as the water signature moment?
- [ ] Does fire read as alive at 1 tile/s, and can she outwalk it at her slowest carry?
- [ ] Do enemy hits read as pressure that makes her flee, not punishment that ticks?
- [ ] Is the lens surprise fair in hindsight — was the landing spot always the brightest thing in the room?
- [ ] Does every chamber pass the lens audit? (wood at distance is a switch)
- [ ] Can a tagged state softlock — and does death forgive it, stake included?
- [ ] Do held enemies cross doors without duplicating?
- [ ] Does breeze earn its slot (or does it get cut)?
- [ ] Is the 10px jump charming by C0's ledge, not frustrating?
- [ ] Did you smile when the plumb bob leaned?

## Appendix A — the level format (generator target)

One serializable spec per level — one or more chambers. Every generator emits it; the game reads it; generated baselines hand-edit in Godot's tilemap for quick tweaks.

```
LevelSpec {
	meta:     { seed, name, tile_w, tile_h, palette: 8×[4], music }
	chambers: [ ChamberSpec ]
}
ChamberSpec {
	rect: Rect2i                        # tiles within the level
	terrain: 2D [TERRAIN]
	stone_sub, soil_sub: 2D nibble maps
	pool (sparse index → per-type values): water, oil, acid, lava, smoke, steam
	solids-held: fuel, damp
	surfaces: moss, vine, coal, slime, glaze
	flags: cold_tiles, scorch, secrets
	wind: draft field (authored vectors — system TBD)
	rain: open-sky column list
	fixtures: brazier, spike, plate, lever, hook, pedestal,
			   swing_ring, door { to, locked }, beam_dump
	spawns: [ { enemy | pot, x, y, patrol?, contents? } ]
	markers: chalk arrows, plumb targets
}
```

Generator notes: run several that disagree — maze output as topology for large chambers; a terrain generator that runs the *sim itself* (pour water, let it settle, place exit, fuel, and soil relative to where the pools sit); an LLM writing structured specs that a deterministic compiler builds. Checkers are the real artifact — the design invariants as code: riser solvability, beam-dump existence, the lens audit, resource asymmetry, pool legality. Test 8×8 vignettes, not chambers. Keep the seed, not the room. Contact sheets for human curation. The loop — generated rooms inspiring hand-authored ones — is the product.

## Appendix B — implementation risk register

- **The content pool:** GridWater's capacity checks become pool-aware — arriving water competes with resident oil and gas; within-tile density layering is render-only, between-tile moves are the density rules. Overflow must eject through flow rules without losing volume; the ledger and the pool assertion will catch it if it doesn't.
- **Ice buoyancy:** submerged ice migrating up while water swaps down crosses the subtile/byte boundary — the hardest piece of the matter engine. The freeze escape check reuses the air-gate family; expansion (32 water → 64 displacement) must displace, never destroy.
- **Subtile dynamics:** all sixteen shapes representable (transients are the animation); correctness rests on the move rules plus the Σ popcount assertion; her footing is the standard two-point ground check.
- **Witch-as-sponge:** her absorption and drip must route through the tile pool like any other exchange — integer quanta, ledgered.
- **Divided-vessel stall (GridWater):** documented; the vented-rise relaxation is the planned patch.
- **Seek-level × subtile capacity:** soil piles change per-tile pool capacity; runs and heads must respect it.
- **Wind system:** not yet authored; draft fields are authored data waiting for it. Gas advection and breeze stamps both block on it.
