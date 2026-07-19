# Game Design Document — *Daily Seed* (working title)

**Version 1.2** — content expansion: dash, a weapon roster with seed-limited
slots, evolutions, a combo multiplier, drops, an expanded bestiary with elites,
and multiple telegraphed boss archetypes. Planned in section 14, data shapes in
section 15. Nothing in this version is built yet.

*(v1.1 made the run endless and removed the win state. v1.0 was a fixed
10-minute run.)*

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
### Dash (v1.2)

A short burst with **invulnerability frames**, on a cooldown. The one active
verb in a game otherwise about positioning, and the answer to being cornered.

| Property | Starting value |
|---|---|
| Distance | 190 px over 0.16 s |
| Invulnerability | 0.32 s (slightly outlasts the movement, so it covers the landing) |
| Cooldown | 3.0 s |
| Tell | Player drops to 45% opacity and leaves three fading afterimages |

The tell is not decoration. Invulnerability the player cannot see is
indistinguishable from luck, and a dodge that reads as luck teaches nothing. The
cooldown is shown as a ring under the player.

Bound to Space, right mouse button, and the pad's right shoulder.

---

## 4. Weapons and slots

### The roster (v1.2 — six base weapons)

Each is a distinct *behaviour*, not a stat variant, and each levels independently
through the card pool.

| Weapon | Behaviour | Why it plays differently |
|---|---|---|
| **Pulse** | Straight shot at the nearest enemy | The baseline. Rewards facing the crowd. |
| **Halo** | Blades orbiting the player | Zero aim, pure positioning — you *drive* the damage. |
| **Arc** | Shot that curves toward its target | Punishes fleeing enemies the Pulse would miss. |
| **Return** | Boomerang, out and back | Two damage windows per throw; rewards standing in the lane. |
| **Nova** | Radial burst centred on the player | Crowd-clearing under pressure, useless at range. |
| **Mines** | Proximity charges dropped behind you | Turns retreating into an attack. |

Every weapon has: base stats, a per-level delta table, a max level, and an
evolution recipe. All of it is data (section 15) — a seventh weapon should be a
new row, not new branches.

### Passives are global

The eight passives (fire rate, damage, projectile count, pierce, move speed,
pickup radius, max HP, projectile speed) apply to **every** weapon at once. That
keeps them meaningful as the roster grows, and it is what makes evolution
recipes legible: a passive is a build direction, not a per-weapon tax.

### Weapon slots are set by the daily seed

**Today's run allows 3, 4 or 5 weapons.** The number is drawn from the `daily`
stream and is the same for every player on that seed.

| Slots | Weight | Feel |
|---|---|---|
| 3 | 0.45 | Forced specialisation; evolutions come early |
| 4 | 0.35 | The middle |
| 5 | 0.20 | Sprawling, generalist builds |

Once slots are full the card pool stops offering new weapons and offers levels
for the ones you hold. The count is shown **on the ranked confirmation screen**,
before the attempt is spent — it changes how you draft, so hiding it would be
hiding a rule.

Slot count is the strongest lever the seed has on how a day actually *plays*,
which is the answer to every day otherwise sharing one skeleton.

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

### v1.2 additions

| Type | Shape | Behaviour |
|---|---|---|
| **Dasher** | chevron | Creeps, telegraphs, then lunges. Punishes standing still. |
| **Shielded** | half-ring square | Blocks damage from the front; must be flanked or out-waited. |
| **Bomber** | round with a fuse ring | Detonates on death, damaging the player *and* nearby enemies. |
| **Weaver** | ribbon | Approaches on a sine path, so leading it wrong misses entirely. |

Nine types total. The Shielded one is the important addition: it is the first
enemy that makes *where you stand relative to it* the whole problem, which is
the skill the game is otherwise built around.

### Today's roster is seed-selected

Drifters and Swarmers are always active. From the remaining seven, the `daily`
stream picks **four** for the day. So a given seed might be tanks-and-shielded
(a grind) or dashers-and-weavers (a twitchy sprint), and everyone playing that
day gets the same one.

This is the other half of the answer to "won't every day feel the same" — the
pacing skeleton is fixed, but the roster and the weapon-slot count are not.

### Elites

Any spawn can roll **elite** (~4%, from the spawn block's 4th draw). An elite is
the same type with a modifier applied: more HP, more damage, more score, and a
bright outer ring so it reads instantly in a crowd.

**Elites always drop something.** The drop is chosen by the 5th draw of that
enemy's spawn block, so it is fixed the moment the elite appears and merely read
back when it dies — never rolled at death, which is player-timed.

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

### v1.2: three archetypes, all telegraphed

Which archetype fills each 3-minute slot is drawn from `hash(date,"boss",slot)`
— indexed, so slot 3 cannot be shifted by what happened at slot 1. Every player
on the seed meets the same bosses in the same order.

| Archetype | Shape | Signature |
|---|---|---|
| **Warden** | octagon | Slow chase, expanding radial bursts. The current boss. |
| **Lancer** | arrowhead | Dashes across the arena *while firing*, so the safe lane keeps moving. |
| **Spiral** | rotating star | Stationary; sweeps rotating streams that force constant circling. |

**Every attack telegraphs.** A windup animation — a charging ring, a widening
cone, a colour shift — precedes every volley by at least
`BOSS_TELEGRAPH_MIN` (0.45 s), and that floor holds no matter how far the run
escalates. Dense bullet patterns are only fair if they are *readable*; without a
tell, a hard pattern and a cheap one feel identical to the player, and the
player is right to be annoyed.

### Escalation

Patterns intensify with the boss index rather than being swapped for different
ones:

| Parameter | Scaling |
|---|---|
| Bullets per volley | `base + floor(index × 1.5)` |
| Spread | widens toward full coverage |
| Bullet speed | `× 1.08` per index |
| Volley cadence | shortens, floored |
| Telegraph | shortens **only to `BOSS_TELEGRAPH_MIN`**, never past it |

### Determinism rules

- **Boss timing is a fixed function of elapsed time**, never player-driven.
- **Which archetype and which drop** come from the indexed `boss` stream at slot
  assignment — not at spawn, and certainly not at death.
- **Boss position is drawn from `spawn_rng`** at that fixed moment, exactly like
  any other spawn, so it consumes the stream predictably.
- **The burst pattern rotates by a constant per burst**, not by an RNG draw.
  The boss fires on player-dependent timing, so any draw there would desync the
  shared stream (the same rule as Splitter children, section 5).

---

## 5c. Drops and pickups (v1.2)

Ground drops exist to **pull the player somewhere they would rather not go**.
A bomb sitting in the middle of a crowd is a decision; a bomb that walks to you
is a reward for nothing.

### Instant

| Drop | Effect |
|---|---|
| **Bomb** | Kills every enemy on screen. Scores normally, so it is worth saving for density. |
| **Health** | Restores 35 HP. |
| **Magnet** | Sweeps *all* field XP to the player, gems flying in over ~0.8 s. |

### Timed buffs (25 s, shown as an icon with a countdown beside the EXP bar)

| Drop | Effect |
|---|---|
| **Invulnerable** | No damage taken. |
| **Shotgun** | Replaces weapon fire with a wide, short-range cone. |
| **Machine gun** | Very high rate, low damage per shot. |
| **Splash gun** | Killed enemies explode for **50% of their max HP** to nearby enemies. |

Splash is the one with teeth: chained detonations are **depth-capped** and
entirely RNG-free, or one kill could cascade differently between two machines
and break the seed.

### Where drops come from

Three sources, all determinism-safe:

1. **Scheduled ground drops** — the `drops` stream precomputes the whole run's
   schedule at start: what, at what absolute time, at what absolute world
   position. Never rolled during play, never placed relative to the player.
2. **Boss drops** — decided when the boss slot is assigned, read back on death.
3. **Elite drops** — decided when the elite spawns, read back on death.

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

**On level-up:** the game **pauses** and presents **3 cards**, drawn from a
single pool of new weapons (if a slot is free), weapon levels, passive levels,
and any unlocked evolutions.

### Reroll and banish (v1.2)

- **Reroll** (3 per run) redraws all three cards.
- **Banish** (2 per run) removes one card from the pool for the rest of the run.

Both are drawn from `hash(date, level, action_index)` — indexed per action, not
from a running stream. That is the whole trick: whether the player rerolls, how
many times, and how long they think about it cannot shift any other stream. Two
players who reroll differently still face identical waves.

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

## 6b. Evolutions and the combo multiplier (v1.2)

### Evolution

A **base weapon at max level** plus a **specific passive at max stacks** unlocks
an evolution card. Taking it replaces the base weapon in place — it does not
cost a slot.

| Weapon | + Passive | → Evolution |
|---|---|---|
| Pulse | Overclock | **Lance** — piercing beam that punches through a line |
| Halo | Kinetics | **Aegis** | 
| Arc | Velocity | **Tempest** |
| Return | Piercing | **Cyclone** |
| Nova | Hollow Point | **Collapse** |
| Mines | Magnetism | **Cluster** |

Recipes are data (section 15). The design intent is that evolutions make the
**slot limit** interesting: with three slots you will reach two evolutions, with
five you will probably reach none, so the daily slot count decides whether the
day rewards focus or breadth.

### Combo multiplier

Kills within `COMBO_WINDOW` (2.5 s) of each other build a chain. The chain
decays if you stop killing.

```
multiplier = 1 + min(COMBO_MAX_BONUS, chain × COMBO_PER_KILL)
```

Starting values: `COMBO_PER_KILL` 0.02, `COMBO_MAX_BONUS` 1.5 (so ×2.5 at cap),
decay 1 chain per 0.15 s once the window lapses.

**It multiplies kill score only** — not survival time, not XP. Multiplying
survival would reward turtling with a full bar, which is precisely the play the
scoring is built to discourage. Shown on the HUD as a number that visibly decays,
because a multiplier the player cannot watch drain is a multiplier they will not
play around.

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

### Seven RNG streams — do not merge them

The most important architectural rule in the codebase. Determinism breaks
silently and is miserable to debug after the fact, so randomness is partitioned
by *concern*, and every gameplay stream is derived from the date.

| Stream | Derivation | Drives | Draw discipline |
|---|---|---|---|
| `spawn` | `hash(date,"spawn")` | wave scheduling | Running stream. **Exactly 5 draws per spawn** — edge, along, type, elite, elite-drop — regardless of outcome. |
| `daily` | `hash(date,"daily")` | weapon-slot count, today's active enemy roster | Drawn **once at run start**, before anything else. |
| `boss` | `hash(date,"boss",slot)` | archetype, pattern variant and drop for boss slot *N* | **Indexed, not running.** Slot 3 cannot be shifted by what happened at slot 1. |
| `drops` | `hash(date,"drops")` | the entire drop schedule: what, when, where | Precomputed into a list **at run start**. Nothing is rolled during play. |
| `upgrade` | `hash(date,level)` | the three level-up cards | Indexed per level. |
| `reroll` | `hash(date,level,action)` | reroll and banish results | Indexed per action, so acting or not acting cannot shift anything else. |
| `fx` | unseeded | particles, shake, sound variation | **Cosmetic only.** May never write gameplay state. |

### The rule that makes all of this work

> **Anything that resolves on player-dependent timing must consume ZERO random
> numbers at that moment. Its randomness is pre-drawn and indexed.**

Enemies die when the player kills them. Bosses fall when the player is strong
enough. Level-ups land whenever XP happens to cross the line. If any of those
moments *drew* from a stream, two players on the same seed would consume it at
different points and their runs would silently diverge.

So instead:

- An elite's drop is decided **when it spawns** (part of the 5-draw spawn block),
  and merely *read back* when it dies.
- A boss's drop is decided **when its slot is assigned**, not when it dies.
- Ground drops are **placed by the precomputed schedule** at absolute times and
  absolute world positions, independent of where the player is.
- Splitter children, boss burst rotation and shooter cadence stay on fixed
  offsets and constants — the original form of this same rule.

The corollary is that the cap check must not skip draws: when the 300-enemy cap
blocks a spawn, its 5 draws still happen. How many enemies are alive depends on
how well the player is fighting, so skipping the draws would desync a strong
player from a struggling one.

### Consequences to respect

- Physics must be fixed-timestep. No gameplay logic in `_process` — gameplay
  goes in `_physics_process`.
- No gameplay decision may read wall-clock time, frame rate, or FPS-dependent
  values.
- Enemy spawn *positions* come from `spawn`, never from the player's current
  position.
- Chain effects (splash damage detonating another enemy) must be **depth-capped**
  and RNG-free, or one kill can cascade differently between machines.

### Verification

`tools/determinism_check.sh` runs one seed twice with a scripted player and
compares an end-state digest that includes `spawn` stream state — which encodes
exactly how many draws were made. It also runs a negative control: a *different*
scripted player must diverge, because a test that cannot fail is worthless.

**Every v1.2 sub-phase extends the digest** with whatever it adds — the daily
selections, the boss assignment list, a hash of the drop schedule — and the
check must stay green before that sub-phase is called done.

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

- **Endless play.** The fixed 10-minute run and its win state are *removed*, not
  deferred: there is no clear condition to come back to.
- **v1.2 content expansion** — moved in from the list below, planned in
  section 14: a six-weapon roster with seed-limited slots, weapon evolutions, a
  combo multiplier, drops and temporary weapons, four more enemies plus elites,
  and three telegraphed boss archetypes. Plus a dash.

**Still OUT** — recorded so these get re-proposed as *post-launch*, not smuggled
into the build:

- Real-time multiplayer of any kind
- Ghosts / replay racing (best v2 candidate)
- Multiple characters or starting loadouts
- Meta-progression / permanent unlocks between runs
- Multiple maps or biomes
- Player characters with different starting kits
- Per-weapon passive trees (passives stay global — see section 4)

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

---

## 14. v1.2 rollout plan

Six sub-phases, each committed, pushed, and determinism-checked on its own. The
ordering is deliberate: **the slot system lands before evolutions** (evolutions
are meaningless without a slot pressure to play against), and **drops land before
elites** (elites guarantee a drop, so the drop system has to exist first).

| Phase | Scope | Determinism work | New digest fields |
|---|---|---|---|
| **6a** | EXP/HEALTH bar labels and colours; dash with i-frames, tell and cooldown | None — dash is input, not randomness | dash cooldown state |
| **6b** | Six base weapons, slot system, reroll/banish | New `daily` stream (slot count); new `reroll` stream indexed by action | slot count, owned weapons |
| **6c** | Evolution recipes, combo multiplier | None new — both are deterministic given play | combo chain, evolutions held |
| **6d** | Drops, buffs, temp weapons | New `drops` stream; schedule **precomputed at run start** | drop-schedule hash, drops taken |
| **6e** | Four new enemies, daily roster selection, elites | Roster from `daily`; spawn block grows 3 draws → **5** (adds elite + elite-drop) | active roster, elite count |
| **6f** | Three boss archetypes, telegraphed escalating patterns | Indexed `boss` stream per slot | boss assignment list |

### Definition of done, per sub-phase

1. `tools/determinism_check.sh` green, **including its negative control**.
2. The digest extended with that phase's new state — otherwise the check would
   pass while the new system diverges freely, which is worse than no check.
3. All four test suites green.
4. Every new number lives in `balance.gd`. No literal in gameplay logic.
5. A real run played, not just headless verification.

### Risks I want on the record

- **Performance is the real one.** Six weapons plus evolutions plus 300 enemies
  plus drops plus boss bullet patterns is a large multiple of what currently
  runs. Target: 60 fps at 300 enemies and 200 live projectiles. Projectile
  pooling is likely needed at 6b and near-certain by 6f. If it comes to a
  choice, the enemy cap gets lowered before the frame budget slips.
- **Card-pool legibility.** Weapons, levels, passives and evolutions in three
  slots is a lot of information at a moment when the player is under pressure.
  Cards will need type colour-coding and an owned/level indicator.
- **Telegraph readability in a crowded screen.** A boss windup competing with
  fifty enemies and particle bursts may simply not be visible. May need the
  screen to desaturate briefly, or the boss to be drawn above everything.
- **Chain reactions.** Splash gun and Bomber both cascade. Depth caps are
  mandatory, and they are a determinism requirement, not a performance nicety.
- **Seed meaning changes.** Adding streams and draws changes what every past date
  produces. Fine pre-launch, and the archive is regenerated from the date
  anyway, but it means no comparing scores across the v1.2 boundary.

---

## 15. Data shapes (v1.2)

Everything below lives in `balance.gd`. The point of writing the shapes down is
that **content becomes rows, not branches**: a seventh weapon or a tenth enemy
should not touch gameplay logic at all.

```gdscript
WEAPONS = {
  "pulse": {
    name, desc,
    behavior: "straight",      # straight | orbit | curve | boomerang | nova | mine
    max_level: 5,
    base:      {damage, cooldown, speed, count, pierce, lifetime, radius, spread},
    per_level: {damage: +4.0, cooldown: x0.9, count: +0},   # applied per level
    evolves_with: "overclock", evolves_to: "lance",
  },
}

PASSIVES = {                    # global multipliers, apply to every weapon
  "overclock": {name, desc, stat: "fire_rate", op: "mul", value: 1.25, max: 5},
}

EVOLUTIONS = [                  # weapon at max level + passive at max stacks
  {weapon: "pulse", passive: "overclock", result: "lance"},
]

WEAPON_SLOTS = {                # drawn once from the `daily` stream
  weights: [[3, 0.45], [4, 0.35], [5, 0.20]],
}

DROPS = {
  "bomb":     {kind: "instant", effect: "clear_screen", color, shape, weight: 0.18},
  "splash":   {kind: "temp_weapon", duration: 25.0, hp_fraction: 0.50,
               chain_depth_max: 3, radius: 140.0, weight: 0.10},
}
DROP_SCHEDULE = {first: 45.0, interval: 38.0, jitter: 12.0, placement: "world_ring"}

ENEMY_TYPES = {                 # existing shape, plus:
  "shielded": {..., shield_arc_deg: 140.0, shield_mult: 0.15},
  "dasher":   {..., dash_telegraph: 0.5, dash_speed: 620.0, dash_cooldown: 3.0},
}
ENEMY_ROSTER = {core: ["drifter","swarmer"], pick: 4, pool: [...]}

ELITE = {chance: 0.04, hp_mult: 6.0, damage_mult: 1.5, score_mult: 5.0,
         ring_color, guaranteed_drop: true}

BOSS_ARCHETYPES = {
  "warden": {shape: "octagon", patterns: ["radial_burst"], speed_mult: 1.0},
  "lancer": {shape: "arrowhead", patterns: ["dash_strafe"], speed_mult: 1.35},
  "spiral": {shape: "star", patterns: ["rotating_stream"], speed_mult: 0.0},
}
BOSS_PATTERNS = {
  "radial_burst": {telegraph: 0.6, bullets: 8, spread_deg: 360, speed: 210,
                   cadence: 3.4, per_index: {bullets: +1.5, speed: x1.08}},
}
BOSS_TELEGRAPH_MIN = 0.45       # floor; escalation never goes below this

COMBO = {window: 2.5, per_kill: 0.02, max_bonus: 1.5, decay_per_sec: 6.7}
DASH  = {distance: 190.0, duration: 0.16, iframes: 0.32, cooldown: 3.0,
         alpha: 0.45, afterimages: 3}
REROLLS = 3
BANISHES = 2
```

---
