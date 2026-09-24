# MAGICAL GIRL DEMO — Vertical Slice GDD v2.0

*Delta doc on `world.md` v1.5 — shared engine, shared enemy IP, different verbs. Sibling of `witchgame.md` v3.0 and `amazongame.md` v1.0. Engine deltas: **none.** The strip, the bridge, LOOSE_STONE, the pockets — all engine now. This doc owns verbs, aiming, roster, rooms, and prizes.*

**Goal:** one continuous-scroll strip of seven reaches plus three single-screen shrines where every verb — grab, throw, swoosh, band, pip, pocket, vent, boil — is operational with placeholder art. If this slice is fun with gray boxes, the game exists.

**Pitch:** a Game Boy Color–styled action platformer where the enemies are the ammo, the level is the billiard table, and a deterministic cellular automata keeps honest score of everything she breaks. Non-lethal: nobody dies, everybody naps.

**Inheritance map:** tech (world §1) · data model (world §2) · element sim (world §3) · the bridge, heat and wetness, smolder (world §4) · rendering and light (world §9) · actor API and weight (world §6) · lasso core (world §7) · rooms, doors, death, lives, pockets (world §8) · level format (world §10).

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

## 0. Design doctrine

1. **The picture is the state.** (inherited) The sim renders itself; nothing draws what isn't true.
2. **Magic is the only fidelity break, localized.** Her halo, the pocket auras, her indoor glow, the lasso's render — exempt from GBC bounds. Everything her heat does is physical and stays in bounds: the halo is magic, the steam it makes is sim.
3. **Two layers, one customs office.** (inherited, world law) Actors at 60 fps carry heat and wetness; matter at 10 Hz carries neither; the bridge is the whole interface.
4. **Every collision separates at right angles.** Three bands choose where the right angle sits. SACRED.
5. **Geometry decides; stats decorate.** Collisions are equal-mass forever. Weight edits terrain, reel-in, and reel speed — never the bands.
6. **Three pips, always visible.** Chains relay through fresh pips. The room's population is the limiter, not the physics.
7. **Stun is the use verb.** Nothing dies. The stunned floor is next shot's rack — and the gentle drop builds tables on purpose.
8. **Fire is a meter problem; spikes are a heart problem; pockets are a respect problem.** Three pressures, three dials, never confused. The aura is the promise.
9. **The critical path never waits.** Water placement is pacing, not permission. Shrines are garnish: optional, instant-retry, content-light.
10. **Aim is one input; english is one gesture — and no preview.** Point, swoosh, lock. Eight directions and canonical angles make the outcome space small enough to hold in the head; the room is the feedback.
11. **Steam below HOT; fire at HOT; no inert.** The bridge is always live — she is never nothing to the world.
12. **Some mechanics are occult.** The Cometling gets no chalk, ever.

## 1. Tech setup

Inherited from world §1 in full: Godot 4.5, 240×240 / 720×720, integer scaling, 16×16 tiles with 8×8 subtiles, 15×15 visible, 10 Hz integer deterministic tick. Per-room PRNG and the modern conveniences ride the actor shell — planned, not yet code (world v1.1 sync).

**Map:** one `LevelSpec` — the strip, **one RoomSpec, 112×15**, continuous scroll (camera free, clamped to strip bounds). No boundaries on the critical path; reaches are beat annotations, not walls. Three single-screen shrine RoomSpecs (15×15) attach via doors off-path; unobserved rooms freeze (inherited). The strip is always live — it's one room, and that's cheap.

| Verb | Pad | KBM | Notes |
|---|---|---|---|
| Move | L-stick | A/D | run 56 px/s (3.5 t/s) |
| Jump / flap | A | Space | flap in air: fixed rise, +4 heat |
| Dash | B | Shift | burst 0.15 s @ 150 px/s, +8 heat |
| Aim | R-stick — snaps to 8 | mouse — snaps to 8 | one input: throw direction AND tug retarget |
| Lasso / throw / drop | X | LMB | windup 0.2 s, locks at the final frame; ≤1.5 tiles from feet = gentle drop |
| Tug | X again while ball in flight | LMB again | once per throw; + ball's remaining heat |

**Aiming is eight directions, a straight line before spin, no dotted preview.** Hers is the memorizable outcome space: canonical angles, snapped tiers, honest physics. (The witch aims continuously with a twinkling preview — aiming lives on the actors, world §7. Same engine, opposite skill expression.)

## 2. Data model

Inherited from world §2 in full — packet, content pool, room records, ledger. **No game-side packet extensions; the engine packet is complete for us.**

- **Fixtures:** pockets `{ orientation: floor | wall | ceiling }` — floor ones are authored as "pits," wall and ceiling as "wells"; same fixture, same aura, same one-way law. Stream gates `{ enemy, quota, period_s }`. Racks: finite authored spawn groups, flagged no-stream
- **Game-side state, never CA state:** the prize inventory (hearts, lives, tissues, blossoms) and the **capture log** — one line per catch. The ledger's fauna-flux row sees the enemies; the pocket-loss row sees the matter; nothing in the CA ever sees a prize
- The strip's fauna economy: racks are finite, streams are the tap, pockets are the drain

## 3. Element simulation

Inherited from world §3 in full; `element_tick()` unchanged; GridWater authoritative.

**Exercised this slice:** water, steam, smoke, soil, stone **+ LOOSE_STONE** (R2's pillar, R6's cast-stone), oil, ice — authored *and melting* (SR-A, via the bridge), fuel, fire, damp (her DRY underfoot), rain (R3). **Dark:** acid, lava, glaze, growth and the botanicals, the pot interior, electricity. The witch is the full-catalogue customer; we are the kinetic one — and the crossover content inherits everything we leave dark.

## 4. Rendering

Inherited from world §9: the room-sized Image at 10 Hz, the 8×4 bank, 2-bit grayscale baked through the Palette module, rows-are-conditions, Bayer dither, derived animation.

Same bank, this game's semantic loads:

- **P0** her — long-hair wedge, dress, galaxy-skirt triangle; two 1×2 violet eye pixels, exempt row, canvas layer above the CanvasModulate. Cartoon law
- **P1** warm — the lit-ball ember trails, her HOT halo, Cinderkit, the Wickmoths
- **P4** docile — carried, stunned, sleeping racks, the nap garden
- **P6** stationery — chalk arrows and the named-shot feed. Billiards is played with chalk
- **P7** accent — pocket auras, pips, the spin swirl at lock

Her reads, no meters anywhere:

- **Pips:** three dots over every live enemy; the last blinks; pip loss ticks down in pitch. Always visible — law 6
- **The trail is the cargo manifest:** a thrown ball renders a trail whose density reads its heat — steam wisps when cool-ish, ember streak at HOT. The trail plus the halo plus the moths is the thermometer set
- **Her halo:** at HOT, a steam-halo around her — rain flash-vaporizing, puddle skin boiling, the world reacting. Diegetic heat, three ways, zero HUD
- **Wickmoth count** reads her heat past HOT — one at 64, more as she climbs. The moths are the other thermometer
- **Spin:** 4-frame rotation cycle on thrown balls; heading quantized to 16 steps; swirl icon at lock shows the tier
- **Stun:** P4 row swap + orbiting stars shedding as the flat 10 s runs; wake-up hop on recover
- **The evil aura** on every pocket: magic-class light leaking from the hole — the warning is the promise

**Light posture.** Her levels are outdoors: the level profile sets an open ambient — day, readable, no rig games. **Indoors (the shrines), she radiates** — the same radius as the witch's lantern, a full screen, magic-exempt. Firelight is a witch ability: her fires render bright in P1 and cast no rig light at all. The spectacle is palette, not rig — which is exactly why it stays in GBC bounds.

## 5. The Magical Girl

16×32. Run 56 px/s.

```
GRAVITY = 480
JUMP_V  = 98        # 10px — SACRED, shared legs with the witch
FLAP_V  = <tune>    # fixed rise, no variable height
DASH    = 0.15s @ 150 px/s
HEARTS  = 3 (cap 5), 1s i-frames per hit
```

**Locomotion (inherited laws):** ≥128 liquid in her feet tile → half speed; submerged → swim, witch rules — stroke = jump, 10px surface hop, no air meter. Oil is swimmable exactly like water **except it grants no wetness** — and it is fuel. Wind and FLOW push her, capped vs. walk speed.

**Hearts — the contact rules, by law 8:**

- Hostile enemy touch: 1 heart. Spike top: 1 heart and the engine's trajectory bounce
- **Fire and lava: heat, never hearts** (+4 / +8 per tick, the bridge). Flame is a resource she can stand in — the inversion is the fantasy, and R5 prices it
- **Pockets: death.** The aura warned her; she is an actor, and actors fall in
- 0 hearts: slump, blinky eyes, 1.5 s — a non-event, the shared family

**The heat meter.** One byte, inherited (world §4.2). No decay, no bands, no tantrum, no cold state — **one threshold, HOT = 63.** The schedule:

| Verb | Heat |
|---|---|
| Walk, jump, grab, drop, gentle drop | 0 |
| Flap | +4 |
| Dash | +8 |
| Throw | **vents ⌊H/2⌋ into the ball** |
| Tug | + the ball's remaining heat |
| FIRE / LAVA contact | +4 / +8 per tick |
| Cinderkit touch | +8 (module — archetype contact, not bridge) |

**The ladder: 255 → 128 → 64 → 32.** Three throws from blazing to neutral; the first two balls HOT (127, 64 — smolder on impact, 4 s, then fire), the third cool (32 — a safe shot). Combat is thermal regulation, the regulation is fun, and it doesn't need managing. Gains are movement and contact — the wave's choreography writes the schedule; the streams feed her ammunition, and each catch-and-throw is a half-vent. Three of them is the level's ending.

**Cooling is not authored — it is the bridge.** Film 4/s, deep 16/s, a full tile instant (`min(heat, water)`), rain boiling as it lands in her tile, wetness steaming off at 16/s. All her cooling is water contact, and **the dunk is a steam bomb** — self-capped by the pool budget: one tile of steam, never a flood. Cistern ceilings are tall for a reason.

**Her wetness — the inherited verb, worn lightly.** She mops at the pool (by tier), carries ~32 s of drip, and drips where she stands; heat boils it off as steam where she wants steam. Nobody asks her to use it in the slice — R3 lets her discover she can — and it crossover-proofs her: the same loop the witch uses to water gardens, ours uses to leave a line of droplets across a cistern floor, like ruled paper.

**Death and lives.** Hearts to zero, or a pocket: **death.** The strip resets to baseline; she respawns at the entry door — the level's start; one life spent; a non-event. **Prizes persist** (they're hers), and the pocketed come home with the baseline — which means dying to farm is a wash at best: a death costs a life, the best chain pays one or two, and the ledger of lives closes at zero. **Shrine deaths are cheap:** the shrine resets, she's back at its door in the strip, one life spent, nothing else lost. **Zero lives → the level reset:** every room to baseline, prizes and tissues forfeit, hearts and lives restored, back to the very beginning. (If death proves too harsh in playtest, checkpoints are the standing reconciler — authored doorframes at reach seams. Not built this slice.)

## 6. Lasso + billiards

The core is identical for both girls (world §7): IDLE → FIRE_TIP (straight, 7 tiles, loose rope render) → SNATCH (0.15 s, auto-reel) → CARRIED (orbits her, P4 row), one at a time, **water-cast inherited** — the tip refracts, the kink reads depth, underwater enemies are fishable. Gentle drop ≤1.5 tiles: placed docile, exactly where put. **The drop builds the table; the throw spends it.**

**The throw.** Press: windup anim, 0.2 s. Lock at the final frame — direction = the snapped 8-way aim; sweep during the windup = spin. At lock: a swirl icon shows the tier. No dotted preview — the outcome space is in your head, the room is the feedback. Ball: `RigidBody2D` with her modules attached — **bands** (collision response), **pips** (impact budget), **spin** (trajectory edit), **bank** (wall policy). Speed = weight base + ½ her velocity (`<tune>`). Heat = the vented half. Her own throws never hurt her; the tug's heat return is the price of recall.

**The bands** (offset = perpendicular distance between centers ÷ combined half-widths; deflection measured off the throw line):

| Band | Offset | Struck ball | Thrown ball | Name |
|---|---|---|---|---|
| Center | < ¼ | straight ahead, 100% | stops, stuns | **PASS** |
| Body | ¼–¾ | ±45°, 75% | ∓45°, 75% | **FORK** |
| Rim | > ¾ | ±75°, 25% | ∓15°, 100% | **FLICK** |

**SACRED: struck angle + thrower angle = 90°, every collision.** The band chooses where the right angle sits; outgoing directions snap to the canonical angles. Players aim in one reference frame.

**Pips.** Three per enemy (SACRED). Every impact — enemy or wall — spends one. The fourth impact: stop + stun (flat 10 s, recapturable). Struck enemies go live with **fresh pips**: chains relay, and a throw can touch every enemy in the room. The Pass thrower stops and stuns too — every shot seeds the floor with stunned, recapturable, perfectly billiard-shaped bodies. Last shot's wreckage is next shot's rack.

**Spin** never touches the bands. Two snapped tiers, free: LIGHT = drift 1 tile per 4 traveled (sweep ≥45°), HARD = 1 per 2 (sweep ≥90°); sign from the vertical direction of the sweep. Inherited through every bounce; FORK children inherit mirrored (the split blooms into two curls); PASS and FLICK children fly true.

**Weight** — collision math is equal-mass, always (law 5). Weight is three classes that edit terrain:

| Class | vs stone | vs wood | vs soil |
|---|---|---|---|
| Heavy (Shellback) | plows: shatters, keeps ¾, no pip | plows | plows |
| Medium (most) | shatters & stops, −1 pip | shatters & stops, −1 pip | knocks 1 subtile loose, stops |
| Light (Whisk) | bounces off, −1 pip | bounces off, −1 pip | knocks 1 subtile loose, stops |

Reel-in: heavies slow, lights instant. Feel, not math. Stone shatters into four LOOSE_STONE subtiles that pile by the soil rules — the debris visibly slows into world-time on impact.

**The tug.** X while your ball is in flight, once per throw: reel-back, retarget, + its remaining heat. Re-aims; refunds nothing.

**Touches, defined.** A touch is any collision *after her launch* — relay strikes, wall banks, floor skips — every impact along the path that delivers the body to the pocket. Her launch is not a collision: the direct pot, thrown clean into the pocket, is the zero-touch pot. R1 is the assert case: strike D1 (1), D1 strikes D2 (2), D2 strikes D3 (3), D3 strikes D4 (4), D4 sails in — the far one pops the pocket on four touches. Pips bound each body's own flight (three, then it sits); the chain bounds nothing but geometry.

## 7. Pockets, prizes, the feed

**Pockets** are fixtures, any orientation — floor, wall, ceiling. **One-way, forever: nothing flies out. There is no spout.** Every pocket renders its evil aura — magic-class light leaking from the hole — and the aura is honest about all three of its meanings: matter that falls in is **gone** (booked as pocket-loss; the ledger calls it fine); an enemy that falls in is **captured** — scored, fed, logged; a heroine who falls in is **dead**. The warning is the promise. In her levels they are common and they are the table; in the witch's dungeons they are rare (her doc's affair — for her, losing an enemy to one is a tragedy the room reset forgives).

**Capture** fires the event with the ball's manifest — enemy, weight, touches — and the ladder pays. The **capture log** is run-level game state: one line per catch. It is what R7's finale reads, and death does not un-catch — the room's enemies come home with the baseline; the log keeps what she did to them.

**The prize ladder** — each potted enemy scores its own chain:

| Touches | Prize |
|---|---|
| 0 (direct pot) | tissue pack |
| 1 | heart |
| 2 | big heart |
| 3 | teardrop — invulnerability, 5 s of sparkle |
| 4 | 1-Up |
| 5+ | +1 life each |

Multi-pot: each extra pot in the same play upgrades every prize one tier. Shellback pots one tier richer — the heavy haul bonus. The only farmable shot is the direct pot, and it pays tissues: **the consolation prize is the anti-farming design.** (Tissues are a collection stat; post-slice, a tissue wrings out into 64 water.)

**The feed:** named shots chalk onto the screen in P6 — PASS, FORK, FLICK, BANK, CAROM, BREAK (a rack), DOMINO (a pocket fed by the sim itself — the flood carried the rack in; rare, loud), POT. Billiards is played with chalk.

## 8. Enemies

Silhouette IP is shared with the sibling — same creatures, per-game verbs, and **the API is law (world §6): every enemy must survive both heroines.** A witch-caught Drip is a throwable water balloon whose SPLASH is its wetness; our Shellback is her turtle under our verbs — hers sits on plates and radiates cold, ours plows. Shape grammar inherited: hostile reads angular; stunned/projectile reads round; size = weight.

| Enemy | Wt | Thermal | Alive | As projectile | Landed state |
|---|---|---|---|---|---|
| **Drip** | 1 | saturated; slow seep (drip_mul ¼) | marches in chains — a faint wet dotted line behind them | straight; SPLASH is its remaining wetness, 2:1 | a puddle sized by what it carried — or a scalded husk if it cooked in flight |
| **Puffseed** | 1 | dry | bobs in floaty clumps | floaty arc, extra hang | POP: a smoke puff that covers a spike for a beat |
| **Snapcricket** | 1 | dry | sprints through crowds, agitating | fast, flat | CHIRP: wakes sleepers on a timer — the anti-stall |
| **Willow Whisk** | 0 | dry | erratic hover | doubled spin curvature | WILT: settles light as a leaf |
| **Shellback** | 4 | dry | slow patrol | heavy short arc; plows terrain | SITS: heavy riser, walkable — the witch's turtle, our verbs |
| **Cobble** | 3 | dry | waddles | short lob | SHATTER: four LOOSE_STONE subtiles pile where it lands |
| **Cinderkit** | 1 | lit = HOT actor | chases while lit; touch = +8 heat, never hearts | fireball: smolders fuel on impact while HOT, 4 s | PILOT: doused ember, recapturable |
| **Smolderwisp** | — | the steam body | drifts; the lasso passes through | n/a | water contact condenses it into a free Drip — the splash becomes its wetness, booked as fauna flux |
| **Wickmoth** | — | ambient | orbits her halo at HOT; the thermometer — count reads heat | n/a | ambient; cousin of the witch's tag-eater (post-slice), different animal |
| **Cometling** | 1 | ignites at its 3rd pip | streaks the sky lane every ~40 s | straight, fast | a comet until something cools it. Pot it first — **it pays tissues.** The tell is worth more than the pay. No chalk |

Notes: dousing a lit Cinderkit is billiards as fire suppression — a Drip's impact splash does it. Smolderwisp is the anti-billiard enemy until splashed. Every enemy is a ball first; the table is per-enemy behavior, the bands are forever. The universal thermal rule runs underneath all of them: a hot enemy boils the puddle it stands in, smolders the fuel it crosses, and steams off its own wetness — there is no special case anywhere, and a hot girl is just the biggest battery on the field. (The witch is a battery that never charges itself; ours charges on purpose.)

## 9. The map: one strip, seven reaches, three shrines

The strip: one RoomSpec, 112×15, continuous scroll. Rhythm per reach — arrival, crowd, bank, water, wave, travel, vista — shuffled.

| Reach | x | Beat | Teaches |
|---|---|---|---|
| **R0 THE LAWN** | 0–11 | One Drip, one floor pocket, its aura obvious. Direct pot → tissue pack. Chalk: grab, throw, drop-vs-throw | the economy, via the gag |
| **R1 THE LINE** | 12–25 | Four Drips march in a chain — the seep-line behind them is the room's own ruled paper — wall pocket at the end, a Snapcricket pacing. Pass down the line; the far one pops the pocket: 4 touches, a 1-Up. The pacing Snapcricket is the authored fifth link: +1 life | the cradle — and the count |
| **R2 THE BANK** | 26–39 | Puffseed clusters, ceiling pocket, a stone pillar. HARD spin around it; the pillar shatters and piles into LOOSE_STONE steps. Willow Whisk debut | fork, swoosh, spin |
| **R3 THE CISTERN** | 40–49 | Rain column, pool, tall ceiling. The dunk — and its steam bomb. Racks sleep in alcoves. She can mop at the pool and ferry a drip-line across if she likes; nobody asks. Leaving: flapping through the rain scrubs her heat — the rain is the coolant and the curtain | water = pacing, not permission |
| **R4 THE PARADE** | 50–65 | The wave: two stream-gates emit for 30 s, feeding her ammunition. You're *meant* to go hot — mid-combo your throws turn incendiary, the room fogs and glows, and the vent schedule lands you neutral at the end. Three catch-and-throws is the schedule | the power spike, scheduled by the level |
| **R5 THE OILS** | 66–81 | Oil terraces. Heat is on tap — the films themselves charge her (fire is heat, never hearts; touching flame is legal, and it's the trap's other half). Hot, the films burn behind her — spectacle as platforming hazard, every catch telegraphed by the 4 s smolder. Cinderkit chases; douse it, throw your own fireball — into what, is the trap. Bank shots over oil into wall pockets. Splash the Smolderwisp for a free Drip | fire discipline |
| **R6 THE STAIR** | 82–95 | Vertical climb. Shellback plows cracked cast-stone ledges the medium can't; Cobble lobs build steps; Flick shots around pillars into side pockets. The flap tax bites here — the climb is priced in heat, and there is no water on the wall | weight classes, the sky lane's cost |
| **R7 THE GREEN** | 96–111 | Arrival garden, one final mini-arena — then the **nap garden**: every enemy she pocketed, napping in a row, one silhouette per catch, the capture log made flesh; prize tallies as garden statuary. A Cometling streaks the sky lane. The final door is shaped unmistakably like a pocket — **and conspicuously has no aura**: the girl who has learned to read auras reads this one as safe. She waves; they shake off, and bow. Fade | the occult |

**The shrines** — single-screen, door-attached, instant retry, restore on exit. Every room heats her; the discipline is the challenge. Rewards are garden rewards: blossoms, hearts, a shortcut.

- **SR-A SKATING POND** (off R2; waterfall door — a hot body boils the curtain open, and the cistern is next door). Ice floor that melts underfoot as she skates: **the melt-trail is the meter** — every step spends heat, the pond is the budget. Bank the sleeping Puffseed rack into the side pocket before the floor under it goes. Blossom + big heart
- **SR-B THE SILENT BREAK** (off R4). Six sleeping Drips, one patrolling Snapcricket, three pockets, one relay. Nothing wakes early — nothing can wake at all; the pockets keep. The mastery room: multi-pot or the long count. Blossom + shortcut door to R6
- **SR-C THE KILN** (off R6; steam-curtain door that parts only for a hot body). A flooded antechamber: one tile of water, 255 units, over the chest. Arrive maxed, boil exactly one tile dry, land at zero. The bridge's assert-case as a room — integer elegance, self-capping by construction. Teardrop + blossom

## 10. Placeholder art & audio

- Palette discipline from day one: the 8×4 bank, not arbitrary sets
- Her: 16×32 silhouette — hair wedge, dress, skirt triangle, two violet eye pixels; 90% shape. The halo, the auras, and her indoor glow are the only magic renders
- Enemies: circle/square placeholders encode mode; pips are three dots; the trail is the cargo manifest
- SFX: jsfxr — whip crack, snatch pitch-drop, impact thuds (Pass = deep), pip tick descending, stun stars, pocket chime, prize pop, steam hiss, the bow's three sleepy notes
- Music: one looping CC0 tune. The percussion breathes with the sim tick — boiling rooms get busier; the metronome is literal

## 11. Build order

Engine stages E0–E5 are `world.md`'s.

1. **M0 — Strip + her** *(needs E0)*: tilemap, scroll camera clamped to the strip, 10px jump, flap, dash, conveniences, the outdoor ambient profile. *Is breezy already?* If not, stop and fix here
2. **M1 — Lasso + billiards** *(needs E3)*: tip, snatch, carry, windup + swirl, bands, pips, spin modules, stun, Drip + Puffseed + Snapcricket, the water-cast inheritance test. *Does a Pass feel like a Newton's cradle — and does the throw read with no dotted line?* **The three numbers: FORK's 75%, the windup's 0.2 s, the touch-count rule.** Everything else in this doc is built to survive those three moving
3. **M2 — Heat + bridge** *(needs E4)*: meter, vent, the tier table, smolder, halo, Wickmoth, Cinderkit, R4's wave + streams. *Does the wave land you neutral?*
4. **M2.5 — Fixtures**: pockets (aura, one-way, capture events), racks, fauna flux, LOOSE_STONE authored (R2's pillar). *(needs E3/E4)*
5. **M3 — Wave two**: Willow Whisk, Shellback, Cobble, Smolderwisp; prize ladder + multi-pot + the chalk feed
6. **M4 — Shrines**: three rooms, restore-on-exit, the waterfall and steam doors, SR-A's melt-trail
7. **M5 — Occult + finale**: the Cometling, the nap garden, the aura-less pocket door, SFX pass, music. Slice complete

**Explicit cuts (do not build):** numeric scores; bosses in the slice; tug refunds; pot systems and crafting of any kind; Potling, Springsnout, Vitrail, Burrdove, Chilblain, the Eel (post-slice — Chilblain returns with the mirrored FREEZE order as the bridge's stress test); lighting acid/lava/glaze/growth; the crossover; spouts; the star-well; dotted previews; checkpoints (the standing reconciler if death proves too harsh — not built unless playtests demand it).

## 12. Tuning constants (game-side; engine constants live in world §13)

```
TILE = 16, SUBTILE = 8              # SACRED — shared
JUMP_HEIGHT = 10                    # SACRED — shared
RUN = 56, GRAVITY = 480, JUMP_V = 98
FLAP_V, DASH_SPEED = <tune>        # dash 0.15 s @ 150 px/s
HOT = 63                            # SACRED — shared, the only threshold
PIPS = 3                            # SACRED
BANDS: ¼ / ¾                        # SACRED
FORK 45°, FLICK 75/15               # SACRED
SEPARATION = 90°                    # SACRED — the law the fantasy is built on
HEAT: flap +4 · dash +8 · fire +4/t · lava +8/t (contact)
THROW vents ⌊H/2⌋: 255 → 128 → 64 → 32   # three throws, two incendiary
TUG: + ball's remaining heat
COOLING: bridge tiers — film 4/s · deep 16/s · full tile instant (min(heat, water))
WETNESS: cross-talk 16/s · drip 4/s · carry ≈ 32 s
SPIN: LIGHT 1:4 (sweep ≥45°) · HARD 1:2 (sweep ≥90°)
LASSO_RANGE = 7 (shared) · SNATCH = 0.15 s · WINDUP = 0.2 s · STUN = 10 s flat
GENTLE_DROP ≤ 1.5 tiles (shared)
HEARTS = 3 (cap 5) · i-frames 1 s · TEARDROP = 5 s
LIVES = 3 (shared) · zero → level reset
STREAM: quota / period <tune> · POCKET: one-way, no recycle
CINDERKIT touch +8 <tune>
```

## 13. Slice exit checklist

- Does a Pass read as a Newton's cradle in one viewing — no HUD, no labels?
- Can a player recite the three bands after ten minutes, unprompted?
- Does the throw read with no dotted line — eight directions, canonical angles, the room as feedback?
- Is the tissue gag landing? (If the consolation prize isn't funny, the economy isn't legible)
- Can you read her heat across the room — halo, moths, trail — with no meter on screen?
- Does the wave start hot and end neutral without the player ever opening a menu?
- Does the strip never ask her to wait — zero gates, zero forced cooling, zero escort?
- Do the shrines feel like a different game mode, not a chore with a door?
- Do walls, floors, and ceilings all get potted during a normal playthrough?
- Does the evil aura read *before* the first pocket death — is the warning honest about all three of its meanings?
- Is a stunned floor visibly more interesting than a clean one — does wreckage invite the next shot?
- Does touching fire to charge read as empowerment, not bug?
- Does the melt-trail land in SR-A — skating as spending, the pond as the meter?
- Does death-at-R6 feel like an arcade beat, not a chore? (checkpoint watch)
- Does every reach teach exactly one thing, with zero text?
- Did the Cometling stay secret — and did whoever found it tell someone else, knowing it pays tissues?
- Does the nap garden bow land? (One silhouette per catch — does the player recognize anyone?)

## Appendix A — level format: game checkers

`LevelSpec`/`RoomSpec` are world §10; the strip is one RoomSpec with beats, the shrines three more behind doors. The game's checker family (the design invariants as code):

- **Band solvability:** every pocket reachable by some band + spin from some reachable stance
- **Touch-count reachability:** every prize tier has authored geometry — R1 is the 4, SR-B is the 5+
- **Stream economy:** quota vs. capture drain — the room neither empties mid-wave nor floods; the R4→R5 seam is the assert case
- **Flap-tax audit:** every climb is possible without crossing HOT — or the crossing is the lesson
- **LOOSE-steps:** the post-shatter pile passes riser solvability (8px steps vs the 10px jump)
- **Pit-aura coverage:** the engine checker (no unwarned capture); ours is its demanding customer — every pocket visible from every approach that can fall into it

Test 8×8 vignettes, not rooms. Keep the seed, not the room. Contact sheets for curation. The loop — generated rooms inspiring hand-authored ones — is the product.

## Appendix B — risk register (game-side; engine risks live in world App. B)

- **The vent schedule:** if wave tuning is wrong, players end the fight still HOT and R5 punishes them for the wave's design, not theirs. The stream quota is the knob; test the R4→R5 seam specifically — with the halved gains and the three-throw ladder, the schedule is *tighter* than v1.0 assumed
- **The touch-count rule:** R1 is the assert case. If playtesters can't count their own touches, the ladder is noise — the fix is geometry (louder feed callouts), not a HUD
- **No-preview aiming:** if direction reads blurry, the fix is a single 8-way tick on the windup — not a dotted line. The whole doctrine is that canonical angles close the loop in the head
- **Always-live below HOT:** she steams at any heat — wisps off every puddle she crosses. If it reads as noise, the knob is the tier floor (world §4.2), never a gate
- **Pit-death harshness:** accepted arcade ruling; the watch is R6+. Checkpoints are the reconciler, not the default
- **Farm-washout:** death −1 life vs. best chain +2 — assert the ladder can't net-positive through dying, and that tissues stay the only farmable prize
- **The melt-trail (SR-A):** melt is underfoot-only — she melts where she stands, so skating *is* spending. Verify the bank completes before the floor's gone, and that restore-on-exit refills the pond with no stranded chest
- **LOOSE pile geometry:** R2's shatter must pile into steps, not walls — the riser checker runs on the post-shatter state
- **Streams × capture:** population only drains between waves; if a room empties mid-wave the quota is low, if it floods it's high. Fauna flux asserts the books either way
- **The capture log vs. the room:** the log is game-side, the population is CA-side. Death must not un-catch, and the nap garden must read the log — keep the two ledgers separate in code, or R7 will nap the wrong enemies
- **The Cinderkit charge loop:** charging on flame is legal by law 8 — verify it doesn't trivialize R5. The films are simultaneously her charger and her hazard; the smolder telegraph is what keeps the trap honest
- **Multi-tile tier picks (engine, inherited):** her two-tile span across a depth boundary resolves by PRNG pick — verify the dunk reads instant at depth and film at the surface, and that SR-C's one-tile boil still lands exactly at zero
