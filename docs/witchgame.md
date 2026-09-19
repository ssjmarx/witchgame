# WITCH DEMO — Vertical Slice GDD v3.0

*Delta doc on `world.md` v1.1. The engine — room model, CA, bridge, actor shell, contact contract, lasso core, doors, pockets, death and lives machinery, rendering, light rig, level format — is inherited from there. This doc owns her verbs, her rooms, her policy, and her roster. Where this doc and `world.md` disagree about engine behavior, `world.md` wins.*

**Goal:** one contiguous dungeon of seven chambers where every verb, element, container, and enemy behavior is operational with placeholder art. If this slice is fun with gray boxes, the game exists.

**Pitch:** a Game Boy Color–styled puzzle platformer. (Internal touchstones live outside the pitch.)

**Inheritance map:** §1 tech (world §1) · §2 data (world §2) · §3 sim (world §3) · §4 rendering (world §9) · lasso core (world §7) · enemy frame (world §6) · doors/death/lives (world §8) · smolder (world §4.4) · thermal exchanges (world §4.2).

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

## 0. Design doctrine

The laws this document has accumulated. When in doubt, these decide. Engine doctrine (picture-is-the-state, integer quanta, density single-owner, actors-cross-doors) is inherited — world §0.

1. **Magic is the only fidelity break, and the witch declares her exemptions:** the lantern's light, the beam, the lasso's render, the plumb bob's lean. The *consequences* of magic — steam, scorch, LIT, smolder — are physical and stay in GBC bounds.
2. **Effects are region-scale.** Previews show regions (bodies, runs), not pixels.
3. **Capture, not crafting.** Pot contents are witnessed world state, never recipes.
4. **She is the dungeon's courier.** Atoms never cross doors; actors do (world law) — and in her dungeons, the actors are her, her pots, and whatever she holds. Every reagent that moves between sealed rooms moves in her hands.
5. **Two reset layers.** The room forgives on death and door-cycles; the dungeon forgives at the entry door.
6. **Fire is pressure, not health.** Danger that makes her flee — the clock, not a tick-down. (The magical girl eats fire for power; that inversion is hers, not ours.)
7. **Some mechanics are occult:** discoverable, never taught, no chalk. The plumb bob leans; that's all. Dry soil smothers fire; nobody says so. She can mop a puddle into herself and drip it elsewhere — or boil it off in a roar of steam.
8. **Her heat is not her danger; it's the room's.** She is the accidental arsonist.

## 1. Tech setup

Inherited from world §1 in full: Godot 4.5, 240×240 / 720×720, integer scaling, 16×16 tiles with 8×8 subtiles, 15×15 visible, 10 Hz integer deterministic tick. Per-room PRNG and the modern conveniences ride the actor shell — planned, not yet code (world v1.1 sync).

**Map:** one `LevelSpec`, 112×15, seven `RoomSpec`s separated by door walls. Every door is player-facing — a boundary by engine law. Camera clamps to the active room's rect. Unobserved chambers freeze (inherited).

| Verb | Pad | KBM | Notes |
|---|---|---|---|
| Move | L-stick | A/D | waddle 40 px/s (2.5 t/s) |
| Aim | R-stick: vector off **sprite center**, direction + length = deflection | mouse position (anchor: sprite center) | one input steers aim AND beam, both schemes |
| Beam | stick deflection past threshold | mouse past distance threshold from **sprite center** | transition anim: lantern dims, beam blooms; live on the last frame. Pad: fixed speed; mouse: tracks distance |
| Lasso / throw / drop | X | LMB | no windup — her cast is instant. Near-feet aim = gentle drop |
| Jump | A | Space | fixed 10px, no variable height |
| Place staff | B | E | toggle near planted staff to re-grab |
| Ignite | Y | RMB | short range, infinite |

**Aiming is continuous, angle by angle, with a dotted preview** — hers. (The magical girl throws in eight directions with no preview; the aiming *lives on the actors*, world §7.) The same sprite-center anchor steers the lantern's light.

## 2. Data model

Inherited from world §2 in full — packet, content pool, room records, ledger. **No game-side extensions to the packet.** Her content leans on: DAMP (her ignite fizzle, the wick), FUEL (everything she burns, tags included), COLD (the turtle), SURFACE (growth, glaze), FLOW (diffusers), and the smolder overlay (world §4.4). Tags are spawned fuel decals, not terrain — a tagged wall tile carries FUEL 8 in a marker.

## 3. Element simulation

Inherited from world §3 in full. `element_tick()` unchanged; GridWater authoritative.

**Exercised this slice: the whole catalogue.** Water, oil, acid, lava, ice, glaze, growth, soil, stone, gas, rain, electricity, botanicals, pots, smolder — the witch is the engine's full-catalogue customer. Unlit: LOOSE_STONE (ships; the demo never calls for it). Gated: the wind system (breeze ships authored or stubbed — world's open item; the exit checklist holds breeze's feet to the fire).

## 4. Rendering

Inherited from world §9: the room-sized Image at 10 Hz, the 8×4 bank, 2-bit grayscale baked through the Palette module, rows-are-conditions, Bayer dither, derived animation, twinkling dotted previews.

Her loads on the shared bank:

- **P0 witch** — eyes: two 1×2 red pixels, exempt row, canvas layer above the CanvasModulate. Cartoon law
- **P1 warm** — fire, embers, the lantern's tint. Her hit-flash swaps to this row — the shared panic/fire clock made visible
- **P6 stationery** — chalk arrows, paper tags; her handwriting, one row
- **P7 accent** — secrets, plumb target, throw previews

Her state reads, no meters anywhere:

- **Wetness:** the hem — a dither band whose depth reads her wetness; SATURATED is a soaked hemline, and walking leaves P2 droplets (hashed phases)
- **Heat has no dedicated tell. The room tells on her:** smolder warnings bloom at her feet, steam pours off in puddles. A hot witch is visible from her consequences — doctrine, not laziness
- **Smolder renders from the CA overlay** — one 4 s animation, many causes (her beam, a hot enemy, her own body)

## 5. The Witch

16×32. Waddle 40 px/s. Panic run 70 px/s (4.4 t/s — the number that was always true; v2.1's C5 misuse of it is corrected below).

```
GRAVITY = 480                     # inherited
JUMP_V  = 98                      # 10px exactly — SACRED, shared legs
SWIM_GRAV = 120                   # inherited
PANIC_MAX = 5.0                   # accrued panic → KO
HIT_PANIC = 1.0                   # forced panic per hit
PANIC_RUN = 70 px/s
RECOVERY = 0.75 s                 # <tune> — the vulnerable calm
PANIC_DRAIN = 1×                  # calm erases panic 1:1
FIRE_PANIC = 1× dry · ½× while wetness > 0
TRAIL = 5 s                       # her breadcrumb extension of the engine ring
```

**The jump.** JUMP_HEIGHT = 10, SACRED — margin over the 8px subtile step. The 16px ledge in C0 remains unjumpable; the joke survives. Coyote time, jump buffering, ledge tolerance: in.

**Locomotion through liquids (inherited):** ≥128 liquid in her feet tile → half speed; submerged → swim (stroke = jump, 10px surface hop, no air meter — air is gated, not simulated). Oil is swimmable and grants no wetness. FLOW and wind push her, capped vs. walk speed.

**The panic system (v2).** One clock, two feeders, one vulnerable calm:

- **Hits** — enemy contact, spike tops, eel shock — knock her back, flash her hot (P1 row), and force panic: 1 s per hit, breadcrumbs reversed, away from what hit her. Panic accrues the clock 1:1 while she's in it
- **Fire contact** pushes the clock at **1× dry, ½× while her wetness > 0** — the steam budget. A saturated witch has ~10 s of fire in her; a dry one has 5. When the hiss stops, the clock doubles
- **Panic behaviors:** release capture, drop carried pots, flee the breadcrumb trail at 70 px/s
- **Panic ends:** still touching fire → **CRISP** (fire death, same presentation family as KO). Otherwise → **recovery frames**: 0.75 s, a brief getting-herself-together animation, clock frozen. A hit or fire during recovery resumes panic *from the frozen value* — the ratchet. Chained pressure is how she dies, never a single mistake
- **After recovery**, the clock drains at 1×. The dungeon wants her calm
- **KO at 5:** slump, blinky eyes, 1.5 s — a non-event, same family as CRISP. Room to baseline, respawn at the door she entered from, one life spent, placed tag burned

**Her thermal profile.** Heat is a byte she almost never fills (world §4). Sources: FIRE +4/t, LAVA +8/t on contact. Her verbs generate none — magic pays zero heat, through customs like everything else. But when she is hot — and a fire-fleeing witch almost always is (63 heat is under two seconds of flame) — the engine stops caring whose game this is:

- At **HOT (63)** she smolders any fuel she overlaps: the 4 s warnings bloom at her feet as she runs. Her wake half-smolders and decays behind her (0.5 s hold, 2× decay); cornered in vines, it catches. Fleeing through her own escape route is the emergent drama — the room reset forgives
- She **dries damp soil underfoot** (8 damp/s) — a hot witch crossing a wet slope triggers the landslide herself
- She **melts ice underfoot** (16 water-eq/s) and **boils puddles** by the tier table
- She sheds heat only as steam: cross-talk off her own wetness, pool water, rain, or a held wet enemy leaking into her tile. The puddle beyond the flames is the heat dump — that is the fire-walk license, reframed and kept

**Her wetness (the mop-and-drip verb, universalized).** ABSORB by tier — she can mop a puddle dry (a full tile instantly; a film takes patience, and the tiers are honest about which). SATURATED (254) carries ~32 s of drip — she chooses where it lands by standing there, and the randomized drip is lumpy by design. Standing in rain soaks her. She is a timed water carrier, still; the meter is the drip, still; fire zones burn off her cargo, now at half-rate panic as payment.

**Conductivity:** wet is a wire (world §3). The same puddle that is fire-walk license is electrocution risk — the eel's shock is a hit.

**The lantern is a physics pendulum on the staff tip.** Staff: 5-cell walk cycle, anchor position authored per cell — she walks with it, the tip swings, the lantern swings on the tip. Verlet point + distance constraint + gravity + drag + cone clamp (±~70°, a projection, not a special case). The light follows the bob: gait swings it, panic whips it, stillness settles it. The plumb bob is the same body — a small persistent attraction toward secret markers (and toward lives, now: the secrets the plumb leans at are worth one each) tilts its hang; divination as physics. The lantern rides the lasso tip during a throw — you throw the light; on return it snaps back with its momentum, still swinging. Planted staff: the lantern hangs from the planted tip (the turret light). Underwater, the constraints come off: the bob is a free body — buoyant, drifting, trailing her motion, still lit — and re-clamps when she surfaces. Magic, smoke-occluded only.

**Chalk hints:** chalk arrow decals, in-fiction. C0 has three. Nothing else explains anything. Occult mechanics get no chalk, ever.

## 6. Lasso + enemies

The core is identical for both girls (world §7): IDLE → FIRE_TIP (straight, 7 tiles, loose rope render) → SNATCH (0.15 s, auto-reel) → CARRIED, one at a time, water-cast included — the tip refracts and slows, the preview bends at the surface line, depth reads on sight, underwater enemies are fishable. Gentle drop ≤1.5 tiles: placed docile, exactly where put.

**Her deltas are modules and frame data:** no windup (her cast is instant — the magical girl's 0.2 s windup is hers, not shared), and the tip is a tool beyond catching — **levers** flip from range, **pots** yank to hands, **swing rings** catch the tip and pendulum (release = tangential launch — feels like a bad idea; correct). Her thrown enemies run the gravity-arc module plus their per-enemy landed power.

**CAPTURED:** preview always visible; aim far → THROW (enemy runs its projectile profile); aim near → DROP (placed STUNNED, flat 10 s, recapturable).

| Enemy | Wt | Thermal | Alive | As projectile | Landed state |
|---|---|---|---|---|---|
| Slime | 1 | drip_mul 0 — goo, not water | slow hop patrol | fat lob arc | SPLAT: 8px riser, fire blanket, covers spikes; lasso re-gathers |
| Woodpecker | 1 | neutral | hover sine, dives | straight, never arcs | PERCH: sticks in wall, walkable top, angry wiggle |
| Wisp | 1 | **HOT actor, self-sustaining** | drifts at you | straight, slow | STICK: flame + light 20 s; water douses it dead (its heat dumps in one cloud) |
| Turtle | 4 | COLD radiator (3×3 tile flag) | plays dead until 2-tile proximity | heavy short arc | SITS: heavy riser; 3×3 COLD aura; pressure plates |
| Breeze | 1 | neutral | drifts horizontally | sticks where thrown | BLOWS: wind stamp, 4 tiles cardinal; ventilation + ember-leaps (wind system: authored or stubbed) |
| Eel | 1 | wet always — the conductive body | patrols its water | straight, slow | ZAP: discharges through its wet body, 20 s; recapturable. Wet actors in the body take a hit |

**The wisp's ignition is smolder now:** its HOT presence builds the 4 s warning on any fuel it drifts over — hiss, smoke, then fire. The telegraph is the fairness; the panic is still the panic.

**Respawn rule:** held or captured enemies are marked out of the room baseline — nothing duplicates across a door. Load-bearing for the C6 turtle smuggle.

**API compliance (world law):** every enemy must interface with the magical girl's verbs — bands, pips, spin, pockets. And hers flow back: a Drip in the witch's lasso is a water balloon whose SPLASH is its wetness, dumped on impact. No enemy may assume its native girl.

**Shape grammar:** hostile reads angular; stunned/projectile reads round; size = weight. Circle/square placeholders are the degenerate form.

Post-slice: moth (the tag-eater, §9), grub (thrown terrain-eater; drills her-width tunnels; stops at doors — even the worm respects the boundary), mold (growth antagonist), ink-squid (smoke weapon vs. the beam; breeze counters).

## 7. Pots

The pot interior is engine (world §6): a 255-unit content pool plus 4-bit enemy occupancy, up to four enemies, each nibble costing 64 capacity. States compose — one fish and 191 units of water. Reactions run inside; that is what a condensing steam bottle is. Contents are holdings: ledger-visible, door-portable — the pot is an actor, and atoms cross doors only inside actors.

**The fill verb.** A thrown empty pot scoops whatever it passes through mid-air — rain, waterfall, steam, smoke — filling in flight. A filled pot shatters on contact and releases its contents where it breaks (scoop-delivery by arc: throw the empty pot through the waterfall, the water lands where it shatters). **The monster exception:** a thrown pot with enemy room that hits a monster captures it into the next empty slot instead of shattering — an empty pot thrown at a slime comes back a slime pot. Gentle drop puts any pot down unbroken. An empty pot that lands without scooping shatters harmlessly — the pot is spent; fixtures are finite.

**The wick rule:** a resting pot shares with its tile, both directions, 64/tick, ledgered — it fills from a pool, and it dampens the fuel it leans against. C5's water pot between plant and wall is this rule wearing a puzzle hat.

**The fire pot** shows a convenience puff while carried (not sim fire). On break, the tile where it broke receives its fuel and lit state. Loose fuel obeys buoyancy; flames need open air — a fire pot broken into water is a dud: one beat of burn, a steam puff, sinking coals. Land it on dry stone.

**Fill at rest:** resting in water ≥50% tile fills 64/tick; soil mound → DIRT; burning brazier → FIRE. Gentle drop = carrying (safe 8px riser). Weights: empty 1, water 3, enemy = enemy's weight + 1. Loadout readable across the room: hat = enemy, arms = pot.

**No crafting — explicit.** Cauldrons, brewing, material dumping: cut. Contents are captured, never assembled. Every pot state is witnessed world state.

## 8. Ignite, beam, light

**Ignite (the verb):** tile under aim within 1.5 tiles, else faced tile. Fuel > 0, water 0, DAMP < 60 → **IGNITE** order — direct to FIRE, bypassing smolder; magic pays no heat but goes through customs (world §4.3). DAMP ≥ 60 → **FIZZLE**: hiss, steam, DAMP −8 — you can stubbornly click a wall dry, eight per click. No fuel → tiny spark.

**The beam is binary.** It exists or it doesn't; direction is the aim — the stick vector or the mouse, one input, both verbs at once. Activation: deflection / distance past threshold from **sprite center**. Transition: lantern dims, beam blooms, live on the last frame; pad fixed speed, mouse tracks distance.

**Focus bands (SACRED):**

| Band | Range | Effect |
|---|---|---|
| — | 0–2 | nothing (omni territory) |
| GROWTH | 2–10 | steerable growth |
| BURNING | 10–22 | focus ±6, centered on 16 |
| GROWTH | 22–30 | the big-room inversion — past the waist the cone diverges and gentles |
| — | 30+ | nothing |

The focal point renders at exactly 16 tiles — the player sees the lens converge. Ten tiles out-ranges the seven-tile lasso; the lens and the lasso have different identities.

**Terrain is the beam's only terminator.** It overruns its aim and dies on the first opaque thing. Occluders follow subtile shapes (a soil berm honestly shades the beam); glaze is opaque. Standing water doesn't affect it; **a lot of water moving does** — any tile above DIFFUSER_FLOW is a wall of light (the waterfall in C6 is a level-design noun).

**Smolder is CA-side (world §4.4).** The beam's burn band sets the stimulus; the CA builds the 4 s timer, holds 0.5 s, decays at 2×, and completes into ignition — or into the fizzle on damp fuel: hiss, steam, DAMP −8, reset. Beam-drying a wall means four seconds per fizzle, repeated — the deliberately annoying grind, now engine law rather than beam special-case. Wetting or burying resets instantly. No heat field anywhere, ever.

**LIT semantics:** binary for growth steering. Firelight never steers growth. Ranked light is reserved for wild growth, a post-slice enemy.

**Growth:** 4 s per tile, four blips telegraphing, blip one shows roots toward the currently chosen target — steerable mid-charge. Beam-growable triggers where you need them (the botanical sensor family, world §3).

**Light rig assignments (rig inherited, world §9):** CanvasModulate near-black blue; omni on the lantern bob; focus cone with occluder polylines regenerated on tile and subtile changes; smoke attenuation; LIT mask by visibility-checked fan; fire light pool of 6 — arson is illumination, and firelight is *ours* (the magical girl doesn't get it); plumb lean; dithered gradient textures. Firelight stays in witch dungeons: profile flag, engine machinery.

**Exemptions, restated:** lantern light, the beam, the lasso's render, the plumb lean — magic, out of GBC bounds. Everything they cause — steam, scorch, LIT, smolder warnings — physical, in bounds.

## 9. Tags, death, lives, and the two reset layers

**The paper tag.** A written slip (P6, her handwriting, same row as the chalk), slapped on the wall. It snapshots the room at the stamp: leave and return, and the room reverts to exactly that moment. Order of operations is the grammar: stamp before the risky verb and it's an undo (burn the bridge, leave, return — the bridge is back); stamp after and it's a contract (the hole in the wall is now dungeon history). **The tag is fuel (8):** removal by ignite — deliberate — by spreading fire reaching that wall — accidental, unwarned — or by smolder, **with** the 4 s warning: a hot player leaning on their own tag gets four seconds of mercy. Placement is a skill; a wooden wall is papering your fuse. Water: soggy but functional.

**Death.** The room restores baseline; she respawns at the door she entered from; one life spent; a placed tag is destroyed, unplaced tags are safe. Placing a tag is putting your stake on the poker table. Baseline restore forgives everything: pocketed enemies return, spent fuel returns, the smolder overlay clears.

**Lives: 3, found as secrets.** The witch earns nothing; she *finds* — the plumb bob leans at them (the C6 alcove is the authored one). **Zero lives → the full reset:** every chamber to baseline, tags erased, inventories emptied, back to the entry door.

**The two reset layers.**

- **Room layer:** door-cycles (untagged → baseline; tagged → snapshot) and death (baseline, stake burned)
- **Dungeon layer:** the entry-door ritual. Walk out and come back in — every chamber to baseline, the tag allotment restored, lives restored, the candle relit. The voluntary full reset; its price is the walk. Zero lives is the involuntary version

**Tag economy:** fixed allotment per level — three for the early levels, five for the longer ones. The demo carries one.

**Meta structure (full game, for context):** ~8 levels, each a semi-open dungeon. Walk in the door; the dungeon doesn't necessarily make physical sense; relight — or swap in — the candle, and the dungeon lights itself. Cutscenes between levels; a different cutscene when loading an in-progress game. Details deferred.

**The moth (post-slice):** the tag-eater. It lives in the doorways — the sacrosanct boundary is its habitat — and eats paper. Mechanically the janitor: destroying a lock reverts the room, so the harshest narrative beat in the game is also its safest actor. Playtests must keep this true.

## 10. The map: seven chambers, 112×15

One `LevelSpec`, seven `RoomSpec`s. No pockets authored in the demo — bottomless capture is engine capability held in reserve; her dungeons use them rarely, and a lost enemy is a tragedy the room reset forgives.

**C0 — "THRESHOLD" (x 0–11).** Black room, the door, the grind, the slam, the beat, the lantern click. A 16px ledge she cannot jump — still, at 10px — the joke taught in silence. A slime in a spike pit (top contact bounces her, the clock ticks — the pit teaches both) and a chalk arrow: lasso, aim, splat, walk across. A second arrow teaches drop-vs-throw.

**C1 — "THE STRAP" (x 12–27).** The lasso lab. 3-tile wall, woodpecker perch staircase, lever + closed gate from range, the swing ring with its deliberate jank and the safer route below.

**C2 — "KINDLING" (x 28–45).** The fire lab. Vine curtain (the ignite verb), the wisp and the bridge that will catch — now with 4 s of hissing telegraph, still catching — the panic-run geometry with the puddle, the damp wall and the fizzle, the slime blanket. New and discoverable, no chalk: dry soil smothers fire. She can mop the puddle into herself and drip it elsewhere — nobody will tell her that's possible. And the emergent the engine wrote for free: flee the fire, hit the puddle, and her heat dumps in one roar of steam — the safety, discoverable. A cornered, hot, wet witch is a steam bomb; the C2 geometry corners her on purpose.

**C3 — "THE DROWN" (x 46–61) — the water signature moment.** Semi-exterior: the upper reaches open to sky, rain falls past the walkway (the weather tease — plants in pots drinking), and collects off-map into a wooden aqueduct spanning above the chamber. Below: the 6-deep pool, the turtle on the floor (cold aura demos naturally), the pot pedestal on the near shore, the gate lever on the far shore, underwater. The exit ledge sits 3 tiles above the surface — no surface hop reaches it. The solve: ignite the aqueduct's wooden support. The reservoir drains, the pool rises, and she swims up to the exit as the room floods around her — dynamic moment, show-off, and swimming tutorial in one beat. Alternates: pedestal pot as a stair, a slime lily pad. The door-cycle restores the aqueduct.

**C4 — "GARDEN CORE" (x 62–79).** The chain, drizzle edition: ignite the brazier by the puddle → steam rises and spreads along the cold ceiling → condenses as slow drizzle → the incline funnels it to the soil patch → the damp front creeps down, visibly → plant the staff, aim the beam up the wall → steerable moss trellis, one tile per four seconds, blips telegraphing the target → climb her garden. The turtle as a mobile condenser plate remains the alternate solve.

**C5 — "THE LENS" (x 80–95) — the garden's dark twin.** A long room, open-framed on the beam axis (the stone-frame signal: this room continues). A growth anchor mid-room, in the growth band from the naive stance. The far wall is wood, floor to ceiling — and the beam doesn't stop at what you're pointing at. The player gardens; the beam overruns; the smolder starts on the far wall; the surprise lands mid-growth. Four solves, all authored in: **angle** — a stone beam dump catches the overrun (new level vocabulary); **damp** — the wick rule, a water pot between plant and wall, doubling as the mid-failure rescue (fire ~1 tile/s against her calm 2.5 t/s waddle — she outwalks it); **berm** — pile soil to shade the line; **stance** — sub-10 is safe: walk toward the danger; a spike moat justifies the distance. Fuse (4 s smolder) < grow time (4 s per tile): the first attempt fails by surprise, the retry fails by timer, only a solution completes. A fuel path runs from wall to growth site. Telegraphs: the smolder animation and sound, plus authored scorch on the far wall in the baseline — this wall has burned before. No tag lesson here; papering the far wall is the trap, not the teach — though now the smolder warning fires on the tag too, and the trap at least *hisses*.

**C6 — "THE HOOK" (x 96–111).** The finale, plus the countermeasure: a waterfall spawns above the room and drains below it — never accumulating, never flooding — across the sightline to the burnable wooden door. A wall of moving water the lens cannot pass; the firebomb remains the solve. The pot survives the flight (not sim fire until it breaks) but must land on dry stone — an empty pot thrown through the waterfall arrives full and breaks wet where it lands, which is its own lesson. Behind the door: the vine curtain (burn it or slime-smother the wisp), the secret alcove the plumb bob has leaned toward since the entrance — **an extra life lives in it** — the pressure plate (weight 2 — two slimes, or the turtle smuggled from C3), and the tag: burn the door, tag the room, and walk out through a hole you made and notarized. Final frame: a big sealed door, unmistakably the shape of C0's entrance. Fade. Demo over.

## 11. Placeholder art & audio

- Palette discipline from day one: the 8×4 bank, not arbitrary 16-color sets
- Witch: 16×32 dark silhouette — triangle hat, robe wedge, two red eye pixels; she is 90% shape
- Enemies: colored blobs with distinct silhouettes; circle/square placeholders encode mode; pots are simple cylinders, contents visible as a fill band
- SFX: jsfxr for everything — whip, snatch pitch-drop, crackle, hiss, the smolder's sound, the pot's shatter
- Music: one looping CC0 drone, filtered low

## 12. Build order

Engine stages E0–E5 are world.md's; E5 ships in two cuts — ambient+omni early for M0, cones/LIT/fans at M3.

- **M0 — Room + witch** *(needs E0, E5-cut-1)*: tilemap, camera clamp, 10px jump, darkness + omni + the pendulum lantern. *Is it already atmospheric? The pendulum is the question — if not, stop and fix here*
- **M1 — Lasso loop** *(needs E3)*: tip, snatch, capture, twinkling previews, throw/drop, slime + woodpecker, stun/recover, lantern rides the tip, pots as actors (yank to hands), levers, swing ring. C0–C1 playable
- **M2 — Water** *(needs E1)*: GridWater integration + flow export + the wick rule + drizzle condensation + chamber restore. C3's pool and the aqueduct beat
- **M2.5 — Materials** *(needs E2)*: soil subtiles (nibble CA, damp front, mortar), stone subtiles, oil, acid + decay, glaze, lava, ice. Reaction matrix + the ledger
- **M3 — Light deep-dive** *(needs E5-cut-2)*: binary beam + transition, focus bands, LIT mask, smolder integration (stimulus flag → CA timer → fizzle grind), steerable growth. C5 testable in isolation
- **M4 — Witch thermal + panic** *(needs E4)*: swim, wade, ABSORB/DRIP on her, panic v2 (recovery frames, resume-from-value, steam budget), KO, CRISP, spike bounce, heat-from-fire and its consequences. C3 playable end-to-end
- **M5 — Pots + remaining enemies** *(needs E3/E4)*: pot interior, the fill verb, capture rules, break/buoyancy, wisp (smolder-based), turtle, breeze (wind authored or stubbed), eel + conductivity, botanical triggers. C3–C5 real
- **M6 — Meta** *(needs E4)*: pressure plate, paper tags (fuel objects, smolderable, stake-on-death), plumb bob, lives-as-secrets, global reset / the ritual, C6 + the waterfall, the opening cinematic. Slice complete

**Explicit cuts (do not build):** crafting of any kind; hand lantern; lasso-shears; cracked-floor turtle smash; crooked geometry; hearts of any kind — she has the clock. Deferred/optional: staff tips, rain lightning, snow, wild growth, grub/mold/ink-squid. The mirror moth is re-authorized post-slice as the tag-eater.

## 13. Tuning constants (game-side; engine constants live in world §13)

```
WALK = 40 px/s (2.5 t/s) · PANIC_RUN = 70 px/s (4.4 t/s)
JUMP_HEIGHT = 10 (SACRED, shared) · RISER = 8 (SACRED)
PANIC_MAX = 5.0 · HIT_PANIC = 1.0 · RECOVERY = 0.75 s <tune>
PANIC_DRAIN = 1× · FIRE_PANIC = 1× dry · ½× while wetness > 0
TRAIL = 5 s                        # breadcrumb extension of the engine ring
FOCUS_POINT = 16 tiles (SACRED, rendered)
GROW_BANDS = 2–10, 22–30 (SACRED) · BURN_BAND = 10–22 (SACRED)
GROWTH = 4 s per tile · SMOLDER = 4 s (engine) — the mirror pair
DAMP_IGNITE_THRESH = 60 · FIZZLE = DAMP −8 (verb and smolder completion alike)
TAG_FUEL = 8 · TAGS: demo 1; full game 3–5 per level
LIVES = 3 · zero → full reset · the ritual restores them
PLATE_WEIGHT = 2 · FIRE_LIGHT_POOL = 6
LANTERN_BUOY = <tune> · WISP_STICK = 20 s · EEL_ZAP = 20 s
```

## 14. Slice exit checklist

- Can a player lose access to a solution? (resets forgive; tags persist what should)
- Does every chamber teach exactly one thing, with zero text?
- Two ways to solve C3, C4, and C5?
- Does the reservoir flood land as the water signature moment?
- Does fire read as alive at 1 tile/s, and can she outwalk it at her calm waddle?
- Do enemy hits read as pressure that makes her flee, not punishment that ticks?
- Does the panic recovery window read as vulnerability, not invincibility? Does the ratchet kill only under chained pressure?
- Is the steam budget legible — does the hiss stopping register as the warning it is?
- Does the hot-fleeing witch smoldering her own escape route land as drama, not betrayal?
- Is the lens surprise fair in hindsight — was the landing spot always the brightest thing in the room?
- Does every chamber pass the lens audit? (wood at distance is a switch)
- Can a tagged state softlock — and does death forgive it, stake included?
- Do held enemies cross doors without duplicating?
- Does breeze earn its slot (or does it get cut)?
- Is the 10px jump charming by C0's ledge, not frustrating?
- Do the lives-as-secrets stay optional — beatable at three, richer at five?
- Did you smile when the plumb bob leaned?

## Appendix A — level format: game checkers

`LevelSpec`/`RoomSpec` are world §10. The witch's checker family (the design invariants as code):

- **The lens audit:** every burnable with a sightline longer than 10 tiles from any reachable stance is either intended (a switch) or protected (damp, distance, diffuser, dump)
- **Beam-dump existence:** every required-burnable has at least one authored stone dump on some sightline
- **Riser solvability:** every exit reachable by 8px risers and 10px jumps given the baseline terrain (the engine checker; the witch is its demanding customer)
- **Resource asymmetry:** the fuel, water, and soil budgets per chamber match the intended solve count
- **Smolder fairness:** any fuel whose loss strands a solve has damp, a diffuser, distance, or a reset path — and the 4 s warning is never the only mercy
- Test 8×8 vignettes, not chambers. Keep the seed, not the room. Contact sheets for curation. The loop — generated rooms inspiring hand-authored ones — is the product.

## Appendix B — risk register (game-side; engine risks live in world App. B)

- **The always-hot fleeing witch:** under two seconds of flame fills her to HOT; everything she passes smolders behind her. Intended — but playtest the wake. If cornered-in-vines ignitions feel like betrayal rather than drama, the knob is smolder decay rate, not her heat gains
- **Panic state machine:** recovery frames, resume-from-frozen-value, drain-after-recovery — three interacting timers on one clock. Test the chains deliberately: hit → recover → hit → recover → fire, and assert the KO lands only at five accrued
- **Breadcrumbs vs. the ring:** the engine trajectory ring is 1 s (spike bounce); her trail is 5 s. Same logger, per-heroine length — don't let the spike bounce read a 5 s trail and yeet her into last decade
- **Beam stimulus export:** the burn band must present a tile mask to the CA every tick, cheap — a per-tick `PackedByteArray`, not per-frame queries
- **Tag × smolder × snapshot:** smolder completing on a tag must destroy the tag and revert the room to baseline at the next door-cycle — the interaction of the overlay, the fuel decal, and the room record is the most stateful corner of the meta layer. Test it with fire, with the beam, and with a hot witch leaning
- **Wisp retiming:** the 4 s telegraph changes C2's bridge beat from instant to warned. Retime the panic-run geometry so the lesson (bridges catch) survives the fairness
- **The eel's shock:** spec'd as a hit (knockback + 1 s panic) through the wet body. Verify a wet witch holding the eel doesn't shock *herself* by her own wetness — the discharge should travel the pool's body graph, and her wetness makes her a node, not a source
- **C2 puddle authoring:** mop-and-drip must read. Author the puddle ≥128 water (the fast tier) — a film mops at 4/s and the verb dies of boredom
