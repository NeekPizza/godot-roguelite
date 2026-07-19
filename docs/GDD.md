# Game Design Document — *Daily Seed* (working title)

**Version 1.1** — endless model. (v1.0 was a fixed 10-minute run with a win
state; that is removed, see sections 2, 7, 8 and 12.)

**Genre:** Daily-seed survivors-like / score-attack roguelite
**Engine:** Godot 4.7.1, GDScript, GL Compatibility renderer
**Price point:** $1–5
**Run length:** Endless. A run ends only on death; a strong player should top
out around 10–20 minutes.
**The hook:** Every player in the world gets the *same run* each day. Compete on
a global Steam leaderboard. No netcode, no servers.

> **Scope rule for this document:** if a feature is not written here, it is not
> in v1.0. Additions require cutting something else. The single biggest risk to
> this project is scope creep, not technical difficulty.

---

## 1. Core loop

```
Enter daily run  →  move + auto-attack  →  kill enemies  →  collect XP
      ↑                                                        ↓
  compare score  ←     run ends (death)      ←  level up (pick 1 of 3)
```

Moment-to-moment: the player never presses an attack button. They **position**.
All skill expression is in movement — kiting, funneling enemies into clusters,
deciding when to grab a distant XP gem versus play safe.

Session shape: runs are open-ended but self-limiting — the difficulty ramp is
unbounded, so every run ends, and most will land in the 5–20 minute band. The
"one more go" impulse is served by the run being *short because you died*,
not by a clock running out.

---

## 2. Run end and ranking

**There is no win state.** A run ends only when the player dies, and the
difficulty ramp climbs without bound (section 7), so every run ends eventually.

- **Death** ends the run immediately; the score stands and is submitted. Dying
  is not a failure that wastes your attempt — it is simply how runs finish.
- **Ranking is score-at-death.** Nobody "beats" the game. The leaderboard
  spreads by *how deep you got*, which is what keeps a daily seed interesting
  past the first week: there is always a deeper run.
- There is **exactly one ranked attempt per day.**

Removing the win state is what makes the leaderboard the point. With a fixed
10:00 clear, every competent player converged on the same "cleared" result and
the board degenerated into a tiebreak on kill efficiency. Endless means the
score *is* the achievement.

### Ranked vs. practice

Ranked attempts are **never consumed by accident.** Starting today's ranked run
requires an explicit confirmation — *"Start today's ranked run? You get one per
day."* Launching the game, poking around a menu, or misclicking can never burn
it. Nothing auto-counts.

Practice is unlimited and always available:

| Mode | Seed | Ranked? | Availability |
|---|---|---|---|
| **Today — Ranked** | today (UTC) | Yes, submits to leaderboard | Once per day, behind explicit confirmation |
| **Today — Practice** | today (UTC) | No | Only *after* the ranked attempt is used or forfeited |
| **Archive** | any past day | No | Unlimited, any previous date |

**Archive practice** lets a brand-new player learn the game on yesterday's seed
— or any past seed — without ever touching today's ranked attempt. Past seeds
are reproducible for free: the seed is a pure function of the date string, so
the archive costs no storage and no server.

Today's seed is *not* offered as practice before the ranked attempt is spent.
Otherwise a player could rehearse the exact ranked run, which defeats the
premise as thoroughly as unlimited retries would.

**Why one ranked attempt:** it's the whole competitive premise. If you can retry
50 times, the leaderboard measures free time, not skill. This is the single most
important fairness rule in the game. The confirmation gate and the archive exist
so that rule costs new players nothing — they protect the premise *and* the
newcomer, rather than trading one against the other.

---

## 3. Player

| Stat | Value |
|---|---|
| Max HP | 100 |
| Move speed | 220 px/s |
| Pickup radius | 60 px |
| Contact i-frames | 0.5 s after taking damage |

### The world

A **finite 3200×1800 world with hard walls** — about 2.5× the 1280×720 screen on
each axis — viewed through a camera that smoothly follows the player. Roomy
enough to run and kite, never unbounded.

Finite is a deliberate constraint, not a shortcut: it lets enemy spawn points be
**absolute world coordinates** instead of a ring around the player, so everyone
on a seed gets byte-identical spawn *positions*, not just identical spawn
*timings*. See section 9.

- Movement: **WASD / arrows / left stick, or hold left mouse and steer toward
  the cursor.** All three are equivalent; keyboard takes priority while both are
  active so the two never fight. No acceleration ramp — crisp beats realistic.
- The player is a **neon triangle** that points in the movement direction.
- No dash in v1. (Candidate first cut if the game feels too easy.)

---

## 4. Weapon (Phase 1: exactly one)

**Pulse** — fires the nearest-enemy-seeking projectile automatically.

| Stat | Base value |
|---|---|
| Damage | 10 |
| Fire rate | 2.0 / s |
| Projectile speed | 400 px/s |
| Pierce | 0 (dies on first hit) |
| Range | 500 px (despawns beyond) |

Targeting: nearest enemy within range at the moment of firing. If no enemy is
in range, **do not fire** (don't waste the rhythm, and it reads as intentional).

---

## 5. Enemies

Five types, phased in by run time. Each has a **distinct silhouette**, not just
a distinct colour — the game must stay readable for colourblind players and in
a screen crowded with fifty entities.

| Type | Shape | HP | Speed | Contact dmg | XP | Score | Behaviour |
|---|---|---|---|---|---|---|---|
| **Drifter** | square | 20 | 90 | 10 | 1 | 10 | Walks straight at you |
| **Swarmer** | small triangle | 8 | 175 | 6 | 1 | 6 | Fast and fragile; arrives in packs |
| **Tank** | hexagon | 90 | 45 | 20 | 3 | 30 | Slow, brutal on contact |
| **Shooter** | diamond | 25 | 70 | 8 | 2 | 20 | Holds ~340 px and fires every 3.2 s |
| **Splitter** | nested square | 40 | 70 | 12 | 2 | 20 | Bursts into 2 Swarmers on death |

Enemies spawn **off-screen at the world edges** and walk inward. They never
spawn on top of the player — with a fixed seed that would hand everyone the
same unfair moment.

Two rules that exist for determinism, not for feel:

- **Splitter children spawn at fixed offsets**, never random ones. Splitters die
  on player-dependent timing, so drawing from `spawn_rng` there would let a
  skilled player desync the shared wave stream.
- **Shooter cadence is fixed**, staggered from the type's own interval rather
  than randomised, for the same reason.

---

## 5b. Bosses

**One archetype in v1.0, deliberately.** It scales rather than multiplying into
a bestiary — more boss types is the single easiest place for this project to
bleed scope, and a scaling boss delivers the same pacing benefit for a fraction
of the work.

- **Appears at 3:00, then every 3 minutes**, forever.
- **Does NOT end the run when killed.** It is a pace break and a depth marker,
  not a win condition.
- Worth a **large score chunk** (600 × appearance number) and a **guaranteed XP
  payout** of 12 gems worth 3 each.
- A slow, heavy octagon that walks at the player and fires an 8-shot radial
  burst every 3.4 s.

| Appearance | Time | HP | Contact dmg | Score |
|---|---|---|---|---|
| 1 | 3:00 | 700 | 25 | 600 |
| 2 | 6:00 | 1,330 | 30 | 1,200 |
| 3 | 9:00 | 2,527 | 37 | 1,800 |
| 4 | 12:00 | 4,801 | 45 | 2,400 |
| 5 | 15:00 | 9,122 | 55 | 3,000 |
| 6 | 18:00 | 17,333 | 68 | 3,600 |

HP scales ×1.9 per appearance, which looks aggressive until you account for how
hard player DPS compounds through the upgrade pool — fire rate, damage,
projectile count and pierce all multiply together. A gentler curve makes the
boss trivial by its third appearance.

### Determinism rules

- **Boss timing is a fixed function of elapsed time**, never player-driven.
- **Boss position is drawn from `spawn_rng`** at that fixed moment, exactly like
  any other spawn, so it consumes the stream predictably.
- **The burst pattern rotates by a constant per burst**, not by an RNG draw.
  The boss fires on player-dependent timing, so any draw there would desync the
  shared stream (the same rule as Splitter children, section 5).

---

## 6. XP and level-up

- Enemies drop **XP gems** worth 1–3 depending on type (see section 5). Gems are
  collected by walking within the pickup radius; they drift toward the player
  once inside it.
- Gems **persist for the whole run** (no despawn timer). Uncollected XP on the
  field is a deliberate risk/reward decision, not a punishment for looking away.

**XP curve:** level *N* requires `6 + (N-1) * 5` XP.
(L1→2 = 6, L2→3 = 11, L3→4 = 16, …) Roughly 12–15 levels in a full 10-min run.
Steeper than the Phase 1 curve, which handed out levels faster than the upgrades
stayed meaningful once wave density went up.

**On level-up:** the game **pauses**, presents **3 upgrade cards**, player picks
one with mouse or keyboard/controller. No reroll, no skip in v1.

### Upgrade pool (8 entries, all stackable)

| Upgrade | Effect | Max stacks |
|---|---|---|
| Overclock | +25% fire rate | 5 |
| Hollow Point | +5 damage | 8 |
| Split Shot | +1 projectile per volley | 3 |
| Piercing | +1 pierce | 3 |
| Kinetics | +15% move speed | 4 |
| Magnetism | +30 px pickup radius | 4 |
| Vitality | +20 max HP (healed immediately) | 4 |
| Velocity | +20% projectile speed | 3 |

**Pickup radius is hard-capped at 200 px**, enforced in the player's stat setter
rather than in the upgrade that happens to raise it. Magnetism is additive
(+30 px flat, 4 stacks → 180 px) precisely so the design maximum sits *under*
the ceiling by construction. A percentage bonus compounds — 60 × 1.4⁴ = 230 px,
and worse with any future source — which would eventually blanket the world and
turn XP collection from a movement decision into an automatic sweep. The whole
risk/reward of leaving gems on the field depends on that not happening.

When an upgrade hits max stacks it leaves the pool. If fewer than 3 upgrades
remain available, backfill with a **+10 HP heal** card so there is always a
choice to make.

---

## 7. Difficulty ramp

Spawn pressure is a **continuous, unbounded function of elapsed time** — not a
tier table, and never a function of player level. Level-scaling would punish
players for playing well and would break seed comparability.

All three curves are defined in `scripts/difficulty.gd`:

| Quantity | Formula | Behaviour |
|---|---|---|
| Spawn interval | `0.16 + 0.84·e^(−t/300)` | Decays toward a 0.16 s floor |
| Enemies per spawn | `1 + ⌊t/110⌋` | Linear, unbounded |
| Enemy HP multiplier | `1 + 0.115·(t/60)^1.3` | Superlinear, unbounded |

Sampled:

| Time | Spawn interval | Per spawn | HP mult |
|---|---|---|---|
| 0:00 | 1.000 s | 1 | 1.00× |
| 5:00 | 0.469 s | 3 | 1.93× |
| 10:00 | 0.274 s | 6 | 3.29× |
| 15:00 | 0.202 s | 9 | 4.89× |
| 20:00 | 0.175 s | 11 | 6.65× |
| 30:00 | 0.162 s | 17 | 10.57× |

The interval floor exists so the spawn loop cannot be driven toward zero and eat
the frame budget; past ~20 minutes growth comes from wave *size* and HP instead.
At 20 minutes that is roughly 63 enemies per second arriving, against a live cap
of **300** — which is where even a strong build should drown.

Enemy **composition** also ramps continuously. Each type phases in over a window
(Swarmers from 2:00, Shooters from 4:00, Tanks from 6:00, Splitters from 8:00)
while the Drifter share decays from 100% toward ~15%. Shooters are held to ~10%
of spawns: at higher weights the late game reads as a wall of incoming fire
rather than a crowd to out-manoeuvre.

Every spawn consumes exactly **three** `spawn_rng` draws (edge, position, type)
regardless of elapsed time — the weight table always returns all five types in a
fixed order, including zero-weight ones, so the stream stays predictable.

Hard cap of **300 live enemies** — a performance guard rail. When the cap is
hit, spawns are skipped (**not queued**; queueing would desync the seed), but
their RNG draws still happen.

---

## 8. Scoring

```
score = per-type kill values          (Drifter 10 … Tank 30, boss 600 × N)
      + (survival_seconds  ×  5)
      + (xp_collected      ×  2)
```

**No clear bonus** — there is no clear. Kills dominate, so the board rewards
aggressive efficient play rather than running in circles; survival time is
weighted low enough that cowardice does not win, but present so that dying deep
beats dying early.

### Range and the int32 bound

Steam leaderboards take **int32** (max 2,147,483,647), so an endless mode needs
a headroom argument rather than an assumption:

- The ramp bottoms out at a 0.16 s spawn interval against a 300-enemy live cap.
- Assume an absurd sustained 60 kills/s at the richest per-type value (30) for a
  **full hour**: that is ~6.5M from kills.
- Survival adds 5/s (18k/hour) and XP 2 each — both trivial beside that.

A deliberately absurd one-hour run therefore totals ~6.9M, about **0.3% of
int32**. Real runs land in the low hundreds of thousands. Overflow is not a
credible risk.

Submitted scores are bounded against a **ceiling of 50,000,000** — far above any
legitimate run, while still rejecting the obviously fabricated. This is a
plausibility bound, not proof; the anti-cheat posture in section 10 is unchanged
and deliberately minimal.

---

## 9. The daily seed  ⚠️ core technical contract

```
seed = fnv1a_hash("YYYY-MM-DD" in UTC)
```

UTC, not local time — otherwise the "daily" rolls over at different moments per
player and the leaderboard compares different runs. The date string is taken
from `Time.get_datetime_dict_from_system(true)`.

### Three separate RNG streams — do not merge them

This is the most important architectural rule in the codebase. Determinism
breaks silently and is miserable to debug after the fact.

| Stream | Seeded from | Consumed by | Rule |
|---|---|---|---|
| `spawn_rng` | daily seed | wave scheduler only | Consumed in a **fixed order at fixed times**. Never touched by anything player-dependent. |
| `upgrade_rng` | `hash(daily_seed, level_index)` | level-up card draw | Re-derived per level, so *when* you level up cannot shift the sequence. |
| `fx_rng` | unseeded / time | particles, screen shake, sound variation | **Never** allowed to influence gameplay state. |

Why `upgrade_rng` is re-derived per level rather than being one continuous
stream: two players who reach level 7 at different times must still be offered
the same three cards. A continuous stream would give identical *sequences* but
that's already satisfied — the real hazard is a shared stream, where a
player-timed draw would shift the spawn sequence. Keeping them separate makes
the failure impossible rather than merely unlikely.

**Consequences to respect:**
- Physics must be fixed-timestep. No gameplay logic in `_process` — gameplay
  goes in `_physics_process`.
- No gameplay decision may read wall-clock time, frame rate, or FPS-dependent
  values.
- Enemy spawn *positions* come from `spawn_rng`, not from the player's current
  position, or the sequence diverges the instant two players move differently.

### Verification
A headless test runs the same seed twice with a scripted input sequence and
asserts identical end state. This must pass before Phase 3 is called done.

---

## 10. Anti-cheat posture (deliberately minimal)

Local scores are a plain file and are trivially editable. Steam leaderboards are
client-submitted and therefore inherently spoofable. We are **not** building
server-side validation — it is not economically justified on a $1–5 game.

Mitigation is limited to: sanity-bounding submitted scores against the
theoretical maximum, and accepting that the top of the board may contain
cheaters. This is normal for the genre. Do not spend engineering time here.

---

## 11. Art & audio direction

- **Palette:** neon on near-black (`#0B0C14` background). Cyan player, magenta
  enemies, yellow XP, white projectiles. High contrast, colorblind-safe by
  relying on *shape* to distinguish entities, never color alone.
- **All shapes drawn procedurally in-engine** — zero licensing exposure, and it
  means no art pipeline to maintain. Glow is faked with additive sprites
  (GL Compatibility constraint — see `assets/CREDITS.md`).
- **Music:** one 85.7 s synthwave loop, **generated by `tools/gen_music.py`** —
  original work, not a CC0 download, so there is no third-party licence claim to
  trust on a commercial release. 112 BPM, A minor, i–VI–III–VII, with a
  trap-leaning low end: a sustained sine sub through most of the track, and in
  the heavier sections a syncopated 808 bass with pitch glides plus 16th-note
  hats with 32nd-note rolls. Plays at −17 dB so it sits under the SFX.
- **SFX:** 9 retro/sfxr-style sounds — shoot, hit, enemy death, XP pickup,
  level-up, player hurt, run over, boss spawn, boss death. **Generated by `tools/gen_sfx.py`**, our own
  work: no attribution obligation and no third-party licence to verify. The
  generator is fixed-seeded, so re-running reproduces identical files.
- **Particles and screen shake** draw exclusively from `fx_rng`, the unseeded
  stream, and never write gameplay state (GDD section 9).

Every committed asset gets a `assets/CREDITS.md` entry with source + license.
CC0 or self-generated only.

---

## 12. Scope ledger

**Now IN scope:**

- **One scaling boss archetype** (section 5b) — moved in as part of v1.1.
- **Endless play.** The fixed 10-minute run and its win state are *removed*, not
  deferred: there is no clear condition to come back to.

**Still OUT** — recorded so these get re-proposed as *post-launch*, not smuggled
into the build:

- Real-time multiplayer of any kind
- Ghosts / replay racing (best v2 candidate)
- Multiple characters or starting loadouts
- Meta-progression / permanent unlocks between runs
- **Additional boss archetypes** (v1.0 ships exactly one, which scales)
- Multiple maps or biomes
- Weapon evolutions / combo crafting
- New weapons beyond Pulse

---

## 13. Phase plan & definition of done

| Phase | Deliverable | Done when |
|---|---|---|
| 0 | This document | Approved by Nick |
| 1 | Vertical slice | Move, auto-attack, seeded Drifter waves, XP, level-up 3-choice, run ends → score |
| 2 | Content + feel | 5 enemies, 6 upgrades, particles, screen shake, 7 SFX, difficulty ramp |
| 3 | Daily seed + local scores | **DONE.** Determinism test passes (scripted player + RNG-state digest + negative control); local high-score table; ranked-attempt bookkeeping (one per UTC day, persisted, burned at run start so a mid-run quit grants no retry); archive practice on any past date |
| 4 | Steam | GodotSteam 4.20 prebuilt GDExtension; leaderboard submit/fetch + achievements; **runs fine with Steam absent** |
| 5 | Ship prep | **DONE (except a verified Windows binary).** Main menu with the ranked confirmation gate, archive date picker, settings (audio + screen-shake accessibility + fullscreen), pause, controller bindings verified by test, Windows/macOS export presets, `docs/RELEASE.md`. An actual Windows export needs ~1 GB of export templates and a Windows machine to test on |

**Phase 1 is the real risk gate.** If the one-enemy one-weapon loop isn't fun to
play for several minutes, no amount of Phase 2 content will save it. Evaluate
honestly at that checkpoint before building more on top.
