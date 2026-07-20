# Game Design Document — *Daily Seed* (working title)

**Version 1.4** — **meta-progression.** Small, converging permanent upgrades
earned from ranked runs, plus records, cosmetics and titles. Planned in sections
20–24; nothing in this version is built yet.

*(v1.3 was **stage progression.** The run is cut into escalating,
boss-gated stages with per-stage clocks, schedules, palettes and rosters.
Planned in sections 16 and 17.)*

*(v1.2 was the content expansion: dash, a weapon roster with seed-limited
slots, evolutions, a combo multiplier, drops, an expanded bestiary with elites,
and multiple telegraphed boss archetypes. Planned in section 14, data shapes in section 15.)*

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
        ┌─────────────── one stage ───────────────┐
Enter → │ fight → level up → BOSS → clear → PORTAL│ → next stage → …
        └─────────────────────────────────────────┘
                              ↓
                     run ends (death only)
```

Every stage is a self-contained escalation: its own clock, spawn schedule, drop
schedule, palette, enemy roster and boss. Kill the boss, walk into the portal it
leaves behind, and the next stage begins harder.

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
- **Ranking is score-at-death**, with **stage reached** stored and shown
  alongside it. Nobody "beats" the game. The board spreads by *how deep you
  got* — and from v1.3 "deep" is a literal, legible number rather than an
  inference from score.
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

Source of truth: `docs/content-roster.md`. Seven base weapons are specified;
**five ship in v1.2** (see section 14 for which two are held back and why).

| Weapon | Behaviour | Role | Upgrade dials | v1.2 |
|---|---|---|---|---|
| **Pulse** *(exists)* | Seeking shot at the nearest enemy | Reliable single-target | fire rate, damage, pierce, +projectile | Yes |
| **Orbit** | Orbs circle the player, damage on contact | Passive defence / crowd | +orbs, radius, spin speed, damage | Yes |
| **Curveball** | Shots arc outward, sweeping an area | Spread / around corners | curve tightness, count, damage | Yes |
| **Boomerang** | Out and back, hits on both legs | Positional skill | range, count, return speed, pierce | Yes |
| **Nova** | Expanding ring from the player, AoE + knockback | Close crowd control | radius, frequency, damage, knockback | Yes |
| **Lance** | Periodic piercing beam along facing | High single-target line | width, damage, duration, tracking | Held |
| **Drone** | Following mini-turret that auto-fires | Sustained extra DPS | +drones, fire rate, follow range | Held |

Passives are **global** — they apply to every held weapon at once. That is what
keeps them meaningful as the roster grows and what makes evolution recipes
legible: a passive is a build direction, not a per-weapon tax.

### Passives

Existing: Overclock (+fire rate), Hollow Point (+damage), Kinetics (+move speed),
Magnetism (+pickup radius, capped), Vitality (+max HP), Split Shot (+projectile),
Piercing (+pierce), Velocity (+projectile speed).

Added in 6b:

| Passive | Effect | Note |
|---|---|---|
| **Cooldown Core** | −weapon cooldown | Must be differentiated from Overclock — see section 14 |
| **Amplifier** | +area / projectile size | New dial; nothing else scales size |
| **Guard** | −dash cooldown, +i-frame duration | Pairs with 6a's dash |
| **Greed** | **+XP gain only** | The roster's "+drop luck" is deliberately dropped — section 14 |

**Velocity Coil** from the roster is the existing **Velocity** passive renamed;
it is not a new entry.

### Weapon slots are set by the daily seed

**Capped at 3.** Five weapons exist and you may hold three, so every run is a
real draft. The count is still drawn from the `daily` stream and still shown on
the menu and the ranked confirmation, but the table currently has one entry.

Once slots are full, cards offer levels for weapons you hold rather than new
ones. Three slots also means evolutions (section 6b) are reachable rather than
theoretical: a wider loadout spreads levels too thin to max anything.

**Consequence to note:** slot count was previously the seed's strongest lever on
how a day plays. With it fixed, the **seed-selected enemy roster** (section 5)
carries that job alone. If days start feeling samey, that is where to look
first — or re-open this table, which is a data change.

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

The roster specifies six new enemies; **four ship in v1.2** (section 14).

| Enemy | Behaviour | Purpose | v1.2 |
|---|---|---|---|
| **Dasher** | Telegraphs, then bursts at the player | Punishes lazy positioning | Yes |
| **Shielded** | Front shield; vulnerable from the side or behind | Forces repositioning | Yes |
| **Bomber** | Rushes and detonates (telegraphed AoE) | Spacing threat | Yes |
| **Weaver** | Erratic sine approach | Accuracy check | Yes |
| **Orbiter** | Circles at range | Anti-lazy-aim | Held |
| **Healer** | Heals nearby enemies | Target prioritisation | Held |

Nine types total in v1.2. **Shielded** is the important one: it is the first
enemy where *where you stand relative to it* is the entire problem, which is the
skill the whole game is built around.

### Today's roster is seed-selected

Drifters and Swarmers are always active. From the remaining seven, the `daily`
stream picks **four** for the day, so 6 of 9 types are live on any given seed. So a given seed might be tanks-and-shielded
(a grind) or dashers-and-weavers (a twitchy sprint), and everyone playing that
day gets the same one.

This is the other half of the answer to "won't every day feel the same" — the
pacing skeleton is fixed, but the roster and the weapon-slot count are not.

### Elites

Any spawn can roll **elite** (~4%, from the spawn block's 4th draw). An elite is
the same type with a modifier applied: bigger, glowing, more HP, more damage,
more score, and a bright outer ring so it reads instantly in a crowd.

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

### v1.2: four archetypes, all telegraphed

The roster specifies six; **four ship in v1.2** (section 14). Which one fills
each 3-minute slot comes from `hash(date,"boss",slot)` — indexed, so slot 3
cannot be shifted by what happened at slot 1.

| Boss | Core pattern | Escalation | v1.2 |
|---|---|---|---|
| **Spinner** | Rotating radial spray | Faster spin, more arms; dash-while-spraying variant | Yes |
| **Aimed Volley** | Telegraphed shotgun bursts at the player | Tighter spread, higher velocity | Yes |
| **Charger** | Dashes across the arena in telegraphed lanes, shedding bullets | More lanes, quicker recovery | Yes |
| **Ring Master** | Expanding rings with gaps to weave | Gaps shrink as the run deepens | Yes |
| **Summoner** | Shielded; spawns minion waves | More adds, shorter shield windows | Held |
| **Turret Fortress** | Dense stationary fire with rotating safe lanes | Lanes narrow and rotate faster | Held |

**Every attack telegraphs.** A windup — charging ring, widening cone, colour
shift — precedes every volley by at least `BOSS_TELEGRAPH_MIN` (0.45 s), and that
floor holds however deep the run goes. Dense patterns are only fair if they are
*readable*; without a tell, a hard pattern and a cheap one feel identical to the
player, and the player is right to be annoyed.

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

Drops exist to **pull the player somewhere they would rather not go**. A bomb
sitting in the middle of a crowd is a decision; a bomb that walks to you is a
reward for nothing.

### Instant pickups

| Pickup | Effect | v1.2 |
|---|---|---|
| **Bomb** | Heavy damage to every enemy within a fixed world radius. Bosses take a capped chunk, never an instakill. | Yes |
| **Magnet** | Sweeps *all* field XP to the player, gems flying in over ~0.8 s | Yes |
| **Health** | Restores a chunk of HP | Yes |
| **Invulnerability** | A few seconds of invulnerability with a clear visual | Yes |
| **Freeze** | Briefly freezes/slows all enemies | Held |

> **Bomb radius is world-space, never the viewport.** "On screen" depends on
> window size, resolution and fullscreen state — so a bomb that hit "everything
> visible" would hit a different set of enemies for a player on a 4K monitor than
> on a laptop, on the same seed. That is a silent fairness break, and it is
> exactly the class of bug the determinism rule exists to catch.

### Temporary weapons (25 s, icon + countdown beside the EXP bar)

**They fire in addition to your loadout, never instead of it.** Replacing your
fire turns a drop into a downgrade as soon as your own weapons outgrow it — a
late-run Shotgun over a maxed evolved build is strictly worse than nothing. A
powerup that becomes a debuff teaches players to avoid pickups, which defeats
the point of placing them somewhere dangerous.

| Drop | Effect | v1.2 |
|---|---|---|
| **Shotgun** | Wide short-range burst | Yes |
| **Machine Gun** | Very high rate, low damage per shot | Yes |
| **Splash Gun** | Killed enemies explode for 50% of max HP to nearby foes (chains) | Yes |
| **Chain Lightning** | Bolt arcs between nearby enemies | Held |
| **Flamethrower** | Short cone with burn damage-over-time | Held |

### Chain effects must be ordered, capped and RNG-free

Splash Gun and Bomber both cascade. Two hard rules:

- **Depth-capped** (3), or one kill can cascade to the whole field and the frame
  budget with it.
- **Deterministically ordered.** Target selection iterates the enemy container in
  **child order — that is, spawn order** — and breaks distance ties by spawn
  ordinal. Never by `instance_id` and never by dictionary iteration order:
  neither is stable across runs, so a chain would branch differently on two
  machines from identical state.

### Where drops come from

Three sources, all determinism-safe:

1. **Scheduled ground drops** — the `drops` stream precomputes the entire run's
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
an evolution card. Taking it replaces the base weapon in place and does not cost
a slot. Four of the roster's seven recipes ship in v1.2 — the other three depend
on weapons held back.

| Base + Passive | Evolves into | Effect | v1.2 |
|---|---|---|---|
| Pulse + Piercing | **Railgun** | Full-screen piercing lance through everything in line | Yes |
| Orbit + Amplifier | **Event Horizon** | Huge orbiting ring that drags enemies inward | Yes |
| Boomerang + Split Shot | **Blade Storm** | A returning fan of blades | Yes |
| Nova + Cooldown Core | **Supernova** | Near-constant expanding shockwaves | Yes |
| Curveball + Hollow Point | **Seekers** | Homing high-damage curved missiles | Held |
| Lance + Velocity Coil | **Prism Sweep** | Rotating beam sweeping the field | Held |
| Drone + Overclock | **Gun Battery** | Several rapid-fire turrets | Held |

The slot count decides whether a day rewards focus or breadth: with three slots
you should reach two evolutions, with five probably none.

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
- **SFX:** 10 retro/sfxr-style sounds — shoot, hit, enemy death, XP pickup,
  level-up, player hurt, run over, boss spawn, boss death, dash. **Generated by `tools/gen_sfx.py`**, our own
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
- **v1.2 content expansion** — planned in section 14: a weapon roster with
  seed-limited slots, weapon evolutions, a combo multiplier, drops and temporary
  weapons, four more enemies plus elites, telegraphed boss archetypes, a dash.
- **v1.4 meta-progression** (sections 20–25): capped, converging permanent
  upgrades from ranked runs, records, cosmetics, titles.
- **v1.3 stage progression** (sections 16–19): boss-gated stages with per-stage
  clocks, schedules, palettes and rosters; portals; boss enrage; stage reached
  tracked alongside score.

**Still OUT** — recorded so these get re-proposed as *post-launch*, not smuggled
into the build:

- Real-time multiplayer of any kind
- Ghosts / replay racing (best v2 candidate)
- Multiple characters or starting loadouts
- Meta-progression / permanent unlocks between runs
- **Per-stage obstacles / terrain** — explicitly deferred to a later sub-phase
  (7e). Collision geometry and the pathing it forces on nine enemy behaviours is
  a system of its own, and stages deliver their escalation through palette,
  roster and multipliers without it.
- **Seasonal meta resets** — considered and declined, section 23. Seasonal
  *leaderboards* remain an option; a meta wipe does not.
- Multiple maps or biomes beyond the per-stage palette cycle
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

Planned against `docs/content-roster.md`. Six sub-phases, each committed, pushed
and determinism-checked on its own.

Ordering is forced by two dependencies: **slots before evolutions** (an evolution
is meaningless without slot pressure to play against), and **drops before elites**
(elites guarantee a drop, so the drop system must already exist).

### Roster item → sub-phase

| Sub-phase | Roster items | New RNG work |
|---|---|---|
| **6a** | **DONE.** Dash (i-frames, tell, cooldown); EXP bar labelled + gem-gold; HEALTH bar labelled + green | None — dash is input, not randomness. Digest gained `dashes`, and the scripted test player now dashes. |
| **6b** | **DONE.** Weapons: Pulse, Orbit, Curveball, Boomerang, Nova · Passives: Cooldown Core, Amplifier, Guard, Greed · slot system · reroll + banish | `daily` stream (slot count); card draws indexed by `(date, level, action)`. Digest gained slots, weapons, passives, banished, rerolls, banishes. |
| **6c** | **DONE.** Evolutions: Railgun, Event Horizon, Blade Storm, Supernova · combo multiplier | None — both deterministic given play. Digest gained `combo`. |
| **6d** | **DONE.** Pickups: Bomb, Magnet, Health, Invulnerability · Temp weapons: Shotgun, Machine Gun, Splash Gun | `drops` stream, schedule precomputed at run start. Digest gained drops taken/spawned and a schedule fingerprint. |
| **6e** | **DONE.** Enemies: Dasher, Shielded, Bomber, Weaver · seed-selected daily roster · elites | Roster from `daily`; spawn block grew 3 draws → 5 (elite + elite-drop). Digest gained roster and elite count. |
| **6f** | **DONE.** Bosses: Spinner, Aimed Volley, Charger, Ring Master · telegraphs · escalation | Indexed `boss` stream per slot (archetype + drop). Digest gained the boss order. |

### Definition of done, per sub-phase

1. `tools/determinism_check.sh` green, **including its negative control**.
2. The digest extended with that phase's new state. Without this the check passes
   while the new system diverges freely — worse than no check, because it reads
   as coverage.
3. All four test suites green.
4. Every new number in `balance.gd`. No literal in gameplay logic.
5. A real run played, not just headless verification.

---

## 14b. What I would cut, and why

You offered a trim line. I land on **exactly your suggested minimum**, and here
is the reasoning per cut — each is held for post-launch, not deleted.

**Weapons — cut Lance and Drone (ship 5 of 7).** Both introduce a *new system*
rather than a new behaviour. Lance is a continuous beam, so it needs a swept-line
damage path that no projectile weapon uses. Drone is an autonomous ally with its
own targeting, movement and firing — effectively a second player — and its
evolution (Gun Battery) multiplies that entity. The other five are all
projectile-or-area variants sharing one pipeline. This cut removes the two
weapons that would each cost more than the remaining five combined.

**Evolutions — 4 of 7.** Seekers, Prism Sweep and Gun Battery all depend on cut
weapons, so this follows automatically.

**Temp weapons — cut Chain Lightning and Flamethrower (ship 3).** Chain Lightning
is a *third* chain system alongside Splash and Bomber, and chains are the highest
determinism risk in the whole roster. Flamethrower needs a damage-over-time
system plus cone collision, neither of which exists. Shotgun, Machine Gun and
Splash cover the "temporarily play differently" fantasy on their own.

**Pickups — cut Freeze (ship 4).** Slowing all enemies is tempting but the
obvious implementation reaches for `Engine.time_scale`, which would corrupt the
fixed-timestep contract the entire daily seed rests on. Doing it correctly means
a per-enemy speed multiplier threaded through every movement path. Worth doing —
not worth doing first.

**Enemies — cut Healer and Orbiter (ship 4 new).** Healer requires enemies to
find and mutate *each other* every frame: at a 300-enemy cap that is an O(n²)
scan and the first thing that will blow the frame budget. Orbiter is
behaviourally close to Shooter, which already holds range — the least new
information per unit of work in the list.

**Bosses — cut Summoner and Turret Fortress (ship 4).** Summoner is the one I
feel strongest about: **a boss that spawns enemies collides with the 300-enemy
cap, and cap pressure is player-dependent.** If a summon is ever suppressed
because a good player left the field crowded, two runs diverge. It is solvable
(reserved cap headroom, positions pre-drawn per `(slot, summon_index)`) but it is
a determinism special case, and special cases are where this class of bug lives.
Turret Fortress overlaps Spinner and Ring Master in what it asks of the player.

**Net v1.2:** 5 weapons · 12 passives · 4 evolutions · 4 pickups · 3 temp weapons
· 9 enemies + elites · 4 bosses. Still roughly triple the current content.

---

## 14c. Determinism risk register

Every roster item that could break the seed, and how it is scheduled.

| # | Risk | Resolution |
|---|---|---|
| 1 | **Greed's "+drop luck"** — a passive altering drop rates makes drops depend on the player's build, but the drop schedule is precomputed at run start | **Greed affects XP only.** Anything else means the schedule cannot be precomputed, which forfeits the strongest guarantee in the design. If drop generosity should vary, it varies *by seed*, not by build. |
| 2 | **Chain targeting** (Splash, Bomber, Chain Lightning) picking "nearest, ties broken somehow" | Iterate the enemy container in **child order (spawn order)**; break ties by spawn ordinal. Never `instance_id`, never dictionary order — neither is stable across runs. Depth-capped at 3. |
| 3 | **Bomb hitting "on-screen" enemies** | Fixed **world-space radius**. Viewport size varies with resolution and fullscreen, so a viewport-based bomb hits different enemies for different players on the same seed. |
| 4 | **Elite roll and elite drop** resolving at death, which is player-timed | Both drawn in the **5-draw spawn block** when the enemy spawns; merely read back on death. |
| 5 | **Boss drops** resolving at death | Drawn when the **slot is assigned**, from `hash(date,"boss",slot)`. |
| 6 | **Summoner adds vs the enemy cap** *(deferred, but recorded)* | If ever built: reserve cap headroom for summons and pre-draw positions per `(slot, summon_index)`. Never let cap pressure suppress a summon. |
| 7 | **Freeze via `Engine.time_scale`** *(deferred)* | Never. Per-enemy speed multiplier threaded through movement, so the physics step is untouched. |
| 8 | **Reroll / banish** | `hash(date, level, action_index)` — indexed per action, so whether, how often and how slowly the player acts shifts nothing. |
| 9 | **Weapon slot count and daily enemy roster** | `daily` stream, drawn **once at run start** before anything else consumes randomness. |
| 10 | **Dasher / Bomber telegraph timing** | Fixed constants and per-enemy timers seeded from spawn ordinal — never a live draw. |
| 11 | **Shielded directional damage** | Pure geometry against the enemy's own facing. No RNG, but it touches every damage source, so every weapon must route through one damage entry point. |

---

## 14d. Things heavier than they look

Not determinism issues — schedule and performance ones.

- **Performance is the real risk.** 5 weapons + evolutions + 9 enemy types + 300
  enemies + drops + boss bullet patterns is a large multiple of what runs today.
  Target: 60 fps at 300 enemies and 200 live projectiles. Projectile pooling is
  likely needed at 6b and near-certain by 6f. If forced to choose, the enemy cap
  drops before the frame budget slips.
- **Shielded changes the damage pipeline.** Directional damage means every source
  — projectile, orbit contact, Nova ring, splash chain, bomb — has to ask the
  same question about hit angle. That is a refactor to a single damage entry
  point, and it is cheaper to do at the start of 6e than to retrofit.
- **Cooldown Core vs Overclock are near-duplicates.** "−cooldown" and "+fire
  rate" are the same number from two directions. Proposal: **Overclock** stays
  per-shot rate, **Cooldown Core** reduces the *between-volley* cooldown that
  Orbit, Nova and Boomerang use — so it is the multi-weapon passive and Overclock
  is the single-target one. Otherwise one of them should be cut.
- **Card-pool legibility.** Weapons, weapon levels, passives and evolutions
  competing for three card slots, at a moment the player is under pressure.
  Needs type colour-coding and an owned/level indicator on every card.
- **Telegraph visibility.** A boss windup competing with fifty enemies and
  particle bursts may simply not be seen. May need a brief desaturation of
  everything else, or drawing the boss above all other entities.
- **Seed meaning changes** across the v1.2 boundary — more streams, more draws
  per spawn. Fine pre-launch, but no comparing scores across it.

---

## 15. Data shapes (v1.2)

All of this lives in `balance.gd`. The point of writing the shapes down is that
**content becomes rows, not branches** — a sixth weapon or a tenth enemy should
not touch gameplay logic.

```gdscript
WEAPONS = {
  "pulse": {
    name, desc,
    behavior: "seek",          # seek | orbit | curve | boomerang | nova
    max_level: 5,
    base:      {damage, cooldown, speed, count, pierce, lifetime, radius, spread},
    per_level: {damage: +4.0, cooldown: x0.90, count: +0},
    evolves_with: "pierce", evolves_to: "railgun",
  },
  "orbit": { behavior: "orbit",
             base: {damage, orbs, radius, spin_speed, tick_cooldown} },
  "nova":  { behavior: "nova",
             base: {damage, radius, frequency, knockback} },
}

PASSIVES = {                    # global; apply to every held weapon
  "overclock":     {stat: "fire_rate",       op: "mul", value: 1.25, max: 5},
  "cooldown_core": {stat: "volley_cooldown", op: "mul", value: 0.90, max: 5},
  "amplifier":     {stat: "area_scale",      op: "mul", value: 1.15, max: 4},
  "guard":         {stat: "dash_cooldown",   op: "mul", value: 0.85, max: 3},
  "greed":         {stat: "xp_gain",         op: "mul", value: 1.15, max: 4},
}

EVOLUTIONS = [                  # weapon at max level + passive at max stacks
  {weapon: "pulse",     passive: "pierce",    result: "railgun"},
  {weapon: "orbit",     passive: "amplifier", result: "event_horizon"},
  {weapon: "boomerang", passive: "split",     result: "blade_storm"},
  {weapon: "nova",      passive: "cooldown_core", result: "supernova"},
]

WEAPON_SLOTS = {weights: [[3, 0.45], [4, 0.35], [5, 0.20]]}   # `daily` stream

DROPS = {
  "bomb":   {kind: "instant", effect: "blast", world_radius: 900.0,
             damage: 9999.0, boss_damage_cap: 0.25, weight: 0.16},
  "magnet": {kind: "instant", effect: "sweep_xp", fly_in: 0.8, weight: 0.20},
  "health": {kind: "instant", effect: "heal", amount: 35.0, weight: 0.24},
  "invuln": {kind: "buff", duration: 6.0, weight: 0.12},
  "shotgun":     {kind: "temp_weapon", duration: 25.0, weight: 0.10},
  "machine_gun": {kind: "temp_weapon", duration: 25.0, weight: 0.10},
  "splash":      {kind: "temp_weapon", duration: 25.0, weight: 0.08,
                  hp_fraction: 0.50, radius: 140.0, chain_depth_max: 3},
}
DROP_SCHEDULE = {first: 45.0, interval: 38.0, jitter: 12.0, placement: "world_ring"}

ENEMY_TYPES = {                 # existing shape, plus:
  "dasher":   {..., telegraph: 0.5, dash_speed: 620.0, dash_cooldown: 3.0},
  "shielded": {..., shield_arc_deg: 140.0, shield_mult: 0.15},
  "bomber":   {..., fuse: 0.7, blast_radius: 120.0, blast_damage: 28.0,
               chain_depth_max: 3},
  "weaver":   {..., wave_amplitude: 90.0, wave_frequency: 1.6},
}
ENEMY_ROSTER = {core: ["drifter", "swarmer"], pick: 4,
                pool: ["tank","shooter","splitter","dasher","shielded","bomber","weaver"]}

ELITE = {chance: 0.04, hp_mult: 6.0, damage_mult: 1.5, score_mult: 5.0,
         scale: 1.4, ring_color, guaranteed_drop: true}

BOSS_ARCHETYPES = {
  "spinner":      {patterns: ["rotating_spray"], speed_mult: 1.00},
  "aimed_volley": {patterns: ["shotgun_burst"],  speed_mult: 1.10},
  "charger":      {patterns: ["lane_dash"],      speed_mult: 1.35},
  "ring_master":  {patterns: ["gapped_ring"],    speed_mult: 0.60},
}
BOSS_PATTERNS = {
  "rotating_spray": {telegraph: 0.60, bullets: 8, spread_deg: 360, speed: 210,
                     cadence: 3.4, per_index: {bullets: +1.5, speed: x1.08}},
  "gapped_ring":    {telegraph: 0.75, bullets: 28, gaps: 3, gap_deg: 34,
                     speed: 170, per_index: {gap_deg: -3.0, speed: x1.06}},
}
BOSS_TELEGRAPH_MIN = 0.45       # escalation never goes below this

COMBO   = {window: 2.5, per_kill: 0.02, max_bonus: 1.5, decay_per_sec: 6.7}
DASH    = {distance: 190.0, duration: 0.16, iframes: 0.32, cooldown: 3.0,
           alpha: 0.45, afterimages: 3}
REROLLS = 3
BANISHES = 2
```

---

## 16. Stage progression (v1.3)

### The problem it fixes

The run currently has no shape. Difficulty rises smoothly, a boss arrives every
three minutes, you kill it, and *nothing changes*. There is no arrival, no
breather, and no legible sense of getting further — only a score that grows.

Stages give the run a spine: **fight → boss → portal → a visibly harder place.**

### The loop

| Phase | What happens |
|---|---|
| **Combat** | Stage clock runs, waves spawn, difficulty ramps *within* the stage |
| **Boss** | At the end of the combat phase the stage boss spawns. **Regular spawns stop entirely.** |
| **Clear** | Boss dies → a shockwave clears remaining regulars → a genuine breather |
| **Report** | "STAGE N COMPLETE" card showing exactly what gets harder next |
| **Portal** | A portal stands where the boss fell; walk in to advance |

### Stages are derived, never authored

Stage *N*'s configuration is a pure function of `(daily_seed, N)`, so the ladder
is endless without a hand-written list:

| Quantity | Rule (applied `N-1` times) |
|---|---|
| Enemy HP | × 1.40 |
| Enemy damage | × 1.20 |
| Spawn interval | × 0.90, floored |
| Enemies per spawn | +1 every 2 stages |
| Score per kill | × 1.20 |
| Combat duration | 150 s, constant for now |
| Palette | cycles through 6, intensity rising with N |
| Enemy roster | `hash(seed,"stage",N,"roster")`, widening with N |
| Boss archetype | `hash(seed,"boss",N)` — the existing indexed stream |

Score scaling matters: **depth has to pay**, or a player optimises by farming a
shallow stage forever.

### The fairness model changes, deliberately

Today every player is on one absolute clock. From v1.3 they are not:

> **Every player gets identical Stage N content. They reach it at their own
> pace.** Skill is depth.

A stage's schedule is seeded from `(daily_seed, stage_index)` and its clock
starts at zero **when the player enters**. Two players who reach Stage 4 twenty
minutes apart fight the same Stage 4.

### Anti-stall: boss enrage

A boss the player cannot kill must not become a camping spot. From
`ENRAGE_DELAY` (40 s) after the boss spawns, every `ENRAGE_STEP` (10 s):

- boss damage × 1.20
- volley cadence × 0.92, floored at `BOSS_CADENCE_MIN`
- bullet speed × 1.08
- the boss visibly reddens, one step at a time

The telegraph floor still holds. Enrage makes stalling lethal without making it
unreadable.

### Presentation

1. **Calm beat** — the boss's death shockwave clears remaining regulars and
   awards **no score**, which both creates a real breather and removes the
   "let trash pile up, then kill the boss" exploit. The run has no breathing
   points at all today; this is the first.
2. **Escalation readout** — the STAGE COMPLETE card states the increase in
   plain numbers: enemy HP +40%, damage +20%, new types entering, next boss.
   Making the difficulty increase *legible* is half the point of the feature.
3. **Portal** at the boss's death position, tinted with the *next* stage's
   accent as a teaser.
4. **New arena** — palette shift carries the visual change, since all art is
   procedural.

### Palette rule

The stage palette recolours the **arena only**: background, grid, walls, portal.
**Enemy colours do not change per stage.** GDD section 11 requires shape to
carry identity, and re-hueing enemies every stage would throw away the
recognition a player has built up — exactly when the screen is getting busier.

---

## 17. Stage determinism (v1.3) ⚠️

The per-stage rework touches the seed contract, so the rules are set out
explicitly.

### Per-stage streams

| Stream | Key |
|---|---|
| stage spawn | `hash(date,"spawn",N)` |
| stage drops | `hash(date,"drops",N)` |
| stage roster | `hash(date,"stage",N,"roster")` |
| boss slot | `hash(date,"boss",N)` |

Every one is keyed by stage index, never a single running stream. **This is what
contains divergence.** How long a player takes to kill the Stage 3 boss is
player-dependent; if a shared stream carried across stages, that duration would
shift Stage 4's content and two players on one seed would stop playing the same
game.

### The portal position must never leak

The portal appears where the boss died, which is player-dependent. So:

- Portal position feeds **nothing**. It is presentation only.
- Stage N+1's streams are keyed on `(date, N+1)` and nothing else.
- The player always enters a new stage at the **arena centre**, a fixed point —
  never at a position derived from where they entered the portal.

If any of those three slipped, one player's boss fight would silently reshape
the next stage for them alone.

### Spawns stop during the boss fight

Proposed rather than assumed, because it has a determinism consequence as well
as a design one. Stopping regular spawns entirely means a stage consumes a
**fixed** number of spawn draws, so the whole stage is identical for everyone.
A trickle would leave the stage's tail dependent on fight length. Divergence
would still be contained by the per-stage keying, but "identical Stage N" is a
stronger and simpler promise to keep.

### Other rules

- The clear shockwave triggers **no** kill handlers: no score, no elite drops,
  no RNG. It is a removal, not a thousand kills.
- Uncollected drops do not survive a stage transition; the arena is replaced.
- Enrage is time-driven and consumes no randomness.
- The digest gains stage index, stage phase, stage clock, and each per-stage
  stream's state.

### The test needs a new lever

The determinism check must cross several stage transitions, and advancing
requires actually killing bosses — which a scripted player with a starting
loadout will not manage against scaling boss HP. A test-only
`--boss-hp-mult=0.02` hook lets the harness traverse stages quickly. It joins
`TEST_HOOK_ARGS`, so as with every other hook a run using it **can never be
ranked**.

---

---

## 18. v1.3 rollout plan

Four sub-phases. Each is committed, pushed and determinism-checked on its own,
and each extends the digest with what it adds.

| Phase | Scope | Determinism work |
|---|---|---|
| **7a** | **DONE.** Stage state machine (Combat → Boss → Clear → Portal), per-stage clocks, per-stage spawn/drop/roster streams, boss at end of combat, spawns stop during boss, stage scaling multipliers | The whole per-stage rekeying. New `--boss-hp-mult` test hook so the check can cross stages. Digest gains stage index, phase, clock, stream states. |
| **7b** | **DONE.** Portal entity, death shockwave, calm beat, stage transition, STAGE COMPLETE card with the escalation readout | Portal position must feed nothing; player re-enters at arena centre. |
| **7c** | **DONE.** Per-stage palettes (arena only) and per-stage enemy rosters | Roster from the stage stream; enemy colours deliberately unchanged. |
| **7d** | **DONE.** Boss enrage, stage-reached tracking in saves / game-over / local table, GDD and scope-ledger updates | Enrage is time-driven, consumes no RNG. |

**Ordering is forced:** 7a establishes the clocks everything else keys off, and
the portal (7b) has nothing to connect until stages exist. Palettes (7c) are
cosmetic and deliberately last-but-one so they cannot mask a logic problem.

### Definition of done, per sub-phase

1. `tools/determinism_check.sh` green **including its negative control**, and
   from 7a onward the run must cross **at least three stage transitions**.
2. Digest extended with that phase's new state.
3. All eleven suites green.
4. Every new number in `balance.gd`.
5. A real run played.

---

## 19. Data shapes (v1.3)

```gdscript
STAGE = {
  combat_duration: 150.0,          # seconds before the boss spawns
  hp_mult: 1.40,                   # all applied (N-1) times
  damage_mult: 1.20,
  interval_mult: 0.90,
  interval_floor: 0.12,
  count_bonus_every: 2,            # +1 enemy per spawn every N stages
  score_mult: 1.20,
  roster_pick_base: 4,             # widens with depth
  roster_pick_every: 3,
}

STAGE_PALETTES = [                 # cycles; index (N-1) % size
  {background, grid, wall, accent},
  ...                              # 6 entries
]

BOSS_ENRAGE = {
  delay: 40.0, step: 10.0,
  damage_mult: 1.20, cadence_mult: 0.92, speed_mult: 1.08,
  tint: Color(1.0, 0.35, 0.35),
}

STAGE_CLEAR = {
  shockwave_delay: 0.35,           # beat before the field clears
  calm_duration: 3.5,              # breather before the card
  awards_score: false,             # closes the pile-up-then-kill exploit
}

PORTAL = {radius: 34.0, spin: 1.4, pull_hint: 60.0}
```

---

## 20. Meta-progression (v1.4)

### The honest framing

Any permanent power on a ranked board is an asymmetry: a day-1 player and a
day-30 player are not competing on equal terms. The design cannot remove that,
only make it **small, converging and visible**. Everything below follows from
that, and the transparency rule (showing a player's meta tier next to their
entry) is part of the design rather than a nicety.

The counter-argument worth stating: **cosmetics-only meta has zero fairness
cost.** If the leaderboard ever matters more than the progression, that is the
fallback.

### The shape

- Points are earned from **ranked runs only**. Practice and archive earn nothing.
- Points buy **purchases** in seven player-side stats.
- Each purchase is **+0.25%** in that stat.
- **Per-stat cap: 12 purchases (+3%).**
- **Aggregate cap: +10%, hard.** Never more, whatever is spent.
- **Respec is free**, so allocation is a decision rather than a commitment.

Because per-stat cost escalates, spreading is cheaper than concentrating. Early
players spread thin; only a well-stocked player can push two or three stats to
their cap. That is the intended shape: the cap binds before mastery does.

### The stats

Weighted toward **utility**, because damage and HP compound with in-run upgrades
and inflate deep-stage scores — the exact place an unfair edge would show.

| Stat | Effect at cap | Why it is safe |
|---|---|---|
| Starting HP | +3% | Flat, does not compound |
| Move speed | +3% | Utility; helps positioning, not damage |
| Pickup radius | +3% | **Still bounded by the existing hard cap** |
| Dash cooldown | −3% | Utility |
| Starting XP | +3% toward level 2 | Front-loads one card, does not scale |
| Rerolls | +1 at cap | Discrete, changes choice not power |
| Damage | +3% | **Deliberately the weakest option** |

### Cost and convergence

Purchase *k* in a stat costs `12 × 1.19^(k−1)` points.

| Power | Purchases | Points | New player | Strong player |
|---|---|---|---|---|
| 35% of cap | 14 | 184 | 7 days | 4 days |
| 70% of cap | 28 | 444 | 16 days | 9 days |
| 100% of cap | 42 | 813 | 30 days | 17 days |

**Power finishes in about three weeks and then stops.** The infinite sink is
cosmetic, not statistical — see section 22. That is a deliberate departure from
"the last stretch takes months": with one ranked run per day, a months-long
*power* tail and a hard +10% ceiling cannot both hold. Putting the long tail in
cosmetics keeps the sink open forever without ever widening the gap.

### Earning, and a trap in it

```
points = 24 + 3 × min(stage_reached, 8)      # ranked runs only
```

Scaling points by stage reached means **better players earn meta faster**, which
works against convergence. Left uncapped (`8 + 6 × stage`) a strong player earns
**2.8×** a newcomer's rate and pulls away. The flattened curve above holds it to
**1.6×**, and the large flat base means a struggling player still converges.

### Transparency

The player's tier and total bonus appear on the main menu and the run-end
screen, and beside leaderboard entries when Phase 4 lands. Hiding a known
asymmetry would be worse than the asymmetry.

---

## 21. Meta determinism (v1.4) ⚠️

### Player-side only. No exceptions.

Meta upgrades may touch **only** the player's own stats. They may never
influence drop rates, drop schedules, spawn counts, enemy rosters, boss
assignment, or anything else feeding a precomputed seeded schedule.

**There is no luck stat, and there will not be one.** This is the same trap that
removed Greed's "+drop luck": the drop schedule is precomputed at stage entry, so
anything that changed drop odds would make drops depend on the player's profile
and forfeit the strongest guarantee in the design.

The seven stats above are safe by construction — every one is a number the
player carries, not a number the world is built from.

### The save-file hazard

Meta state lives in the player's save. A determinism run that read it would
depend on **the tester's local profile**, so the same seed would verify
differently on two machines — the exact failure the check exists to catch.

So: a `--meta-profile=none|max` test hook overrides the save entirely, and the
check runs **twice — once at zero, once at max** — asserting each is internally
identical. It joins `TEST_HOOK_ARGS`, so a run using it can never be ranked.

Note that zero and max legitimately produce *different* digests from each other:
a stronger player kills more. What must hold is that each configuration is
reproducible.

---

## 22. Records, cosmetics and titles (v1.4)

**Personal bests** — best stage, best score, lifetime kills/runs/bosses, and a
"NEW PERSONAL BEST" moment on the run-end screen. Free retention, zero fairness
cost.

**Cosmetics**, bought with the same points: arena palettes, player shapes,
projectile trails. **Zero gameplay effect, enforced by keeping them out of the
stat path entirely** — a cosmetic is a colour or a shape, never a number. This
is where the long tail lives, and it can be endless precisely because it cannot
tilt a board.

Player shape is the one to watch: section 11 makes shape carry identity, so
cosmetic shapes must stay visually distinct from every enemy silhouette.

**Titles** for milestones ("Reached Stage 10", "30-Day Streak"), shown on the
profile and beside leaderboard entries.

---

## 23. On seasonal resets — recommendation: **no**

Not for this game, and specifically:

- **The daily seed already is the reset.** Every day is a fresh, equal start.
  Seasons solve staleness that a daily format has largely solved already.
- **Accumulation is already capped** at +10% and converges in ~3 weeks. A wipe
  would cap something that is bounded by construction.
- **It punishes exactly the players who engaged most**, and buys back very
  little fairness, because the asymmetry being reset is small by design.
- **Operationally expensive** for a solo $1–5 title: season boundaries, archived
  boards, one Steam leaderboard per season, and the comms around all of it.

**If seasonal structure is wanted, run seasonal *leaderboards* and let meta
persist.** Monthly boards give lapsed players the re-entry point without taking
anything away, and they map cleanly onto per-month Steam leaderboards.

---

## 24. v1.4 rollout plan

| Phase | Scope | Determinism work |
|---|---|---|
| **8a** | **DONE.** Meta profile persistence, point awards from ranked runs, seven stats, cost curve, caps, free respec, applied to the player at run start | `--meta-profile` hook; the check runs at zero **and** at max |
| **8b** | Upgrade screen from the main menu: costs, caps, tier readout, respec, transparency | None |
| **8c** | Records, lifetime stats, NEW PERSONAL BEST moment | None |
| **8d** | Cosmetics and titles | Cosmetics must not reach the stat path |

**Ordering:** 8a establishes what the rest displays. 8d is last because it is the
only part with no gameplay effect, so it cannot mask a balance problem.

### Definition of done, per sub-phase

1. Determinism green at **both** meta extremes, including the negative control
   and the ≥3-stage requirement.
2. Twelve suites green.
3. Every number in `balance.gd`.
4. A real run played.

---

## 25. Data shapes (v1.4)

```gdscript
META_STATS = {
  "hp":        {name: "Vitality",   stat: "meta_hp_mult",       per_buy: 0.0025, max_buys: 12},
  "speed":     {name: "Fleetfoot",  stat: "meta_speed_mult",    per_buy: 0.0025, max_buys: 12},
  "pickup":    {name: "Lodestone",  stat: "meta_pickup_mult",   per_buy: 0.0025, max_buys: 12},
  "dash":      {name: "Reflex",     stat: "meta_dash_mult",     per_buy: -0.0025, max_buys: 12},
  "xp":        {name: "Headstart",  stat: "meta_start_xp",      per_buy: 0.0025, max_buys: 12},
  "reroll":    {name: "Foresight",  stat: "meta_rerolls",       per_buy: 0.0025, max_buys: 12},
  "damage":    {name: "Edge",       stat: "meta_damage_mult",   per_buy: 0.0025, max_buys: 12},
}
META_COST_BASE = 12.0
META_COST_GROWTH = 1.19
META_AGGREGATE_CAP = 0.10        # hard ceiling on the sum of all bonuses
META_POINTS_BASE = 24
META_POINTS_PER_STAGE = 3
META_POINTS_STAGE_CAP = 8        # flattens the veteran earning advantage

COSMETICS = {
  "palette_ember": {kind: "palette", cost: 400, ...},
  "shape_delta":   {kind: "player_shape", cost: 600, ...},
  "trail_spark":   {kind: "trail", cost: 250, ...},
}
TITLES = [
  {id: "stage_10", name: "Deep Diver", condition: "best_stage >= 10"},
  {id: "streak_30", name: "Devoted",   condition: "daily_streak >= 30"},
]
```
