# Game Design Document — *Daily Seed* (working title)

**Genre:** Daily-seed survivors-like / score-attack roguelite
**Engine:** Godot 4.7.1, GDScript, GL Compatibility renderer
**Price point:** $1–5
**Run length:** 10 minutes fixed
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
  compare score  ←  run ends (death or 10:00)  ←  level up (pick 1 of 3)
```

Moment-to-moment: the player never presses an attack button. They **position**.
All skill expression is in movement — kiting, funneling enemies into clusters,
deciding when to grab a distant XP gem versus play safe.

Session shape: one run is 10 minutes. A player who wants "one more go" is
committing to a known, bounded chunk of time. That bounded commitment is what
makes a daily leaderboard habit-forming rather than exhausting.

---

## 2. Win / lose

- **Lose:** player HP reaches 0. Run ends immediately, score is kept and
  submitted. Dying is not a failure state that wastes your attempt — you still
  get a leaderboard entry. This matters: a punishing daily would kill retention.
- **Win:** survive to 10:00. Awards a **+2000 clear bonus**, then the run ends.
- There is **exactly one ranked attempt per day.**

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

- Movement: WASD / arrows / left stick. 8-directional, no acceleration ramp —
  crisp and responsive beats realistic.
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

## 5. Enemy (Phase 1: exactly one)

**Drifter** — a neon square that moves straight at the player.

| Stat | Value |
|---|---|
| HP | 20 |
| Move speed | 90 px/s |
| Contact damage | 10 |
| XP dropped | 1 |
| Score value | 10 |

Enemies spawn **off-screen** on a ring around the player and walk inward. They
never spawn on top of the player — that would feel like cheating, and with a
fixed seed everyone would hit the same unfair moment.

*Phase 2 adds 4 more types (fast/weak swarmer, tanky slow, ranged shooter,
splitter). Deliberately out of scope until the one-enemy loop is fun.*

---

## 6. XP and level-up

- Drifters drop **XP gems** worth 1. Gems are collected by walking within the
  pickup radius; they drift toward the player once inside it.
- Gems **persist for the whole run** (no despawn timer). Uncollected XP on the
  field is a deliberate risk/reward decision, not a punishment for looking away.

**XP curve:** level *N* requires `5 + (N-1) * 4` XP.
(L1→2 = 5, L2→3 = 9, L3→4 = 13, …) Roughly 12–16 levels in a full 10-min run.

**On level-up:** the game **pauses**, presents **3 upgrade cards**, player picks
one with mouse or keyboard/controller. No reroll, no skip in v1.

### Upgrade pool (Phase 1: 6 entries, all stackable)

| Upgrade | Effect | Max stacks |
|---|---|---|
| Overclock | +25% fire rate | 5 |
| Hollow Point | +5 damage | 8 |
| Split Shot | +1 projectile per volley | 3 |
| Piercing | +1 pierce | 3 |
| Kinetics | +15% move speed | 4 |
| Magnetism | +40% pickup radius | 4 |

When an upgrade hits max stacks it leaves the pool. If fewer than 3 upgrades
remain available, backfill with a **+10 HP heal** card so there is always a
choice to make.

---

## 7. Difficulty ramp

Spawn pressure scales with elapsed time, not with player level — level-scaling
punishes players for playing well, and breaks seed comparability.

| Time | Spawn interval | Enemies per spawn | Enemy HP mult |
|---|---|---|---|
| 0:00–2:00 | 1.20 s | 1 | 1.0× |
| 2:00–4:00 | 0.90 s | 2 | 1.2× |
| 4:00–6:00 | 0.70 s | 2 | 1.5× |
| 6:00–8:00 | 0.55 s | 3 | 1.9× |
| 8:00–10:00 | 0.40 s | 4 | 2.4× |

Hard cap of **300 live enemies** — a performance guard rail. When the cap is
hit, spawns are skipped (**not queued**; queueing would desync the seed).

---

## 8. Scoring

```
score = (kills          × 10)
      + (survival_secs  ×  5)
      + (xp_collected   ×  2)
      + (2000 if survived to 10:00 else 0)
```

A full clear lands roughly in the 25,000–35,000 range. Comfortably inside
**int32**, which is what Steam leaderboards accept.

Kills dominate, so the leaderboard rewards *aggressive efficient play* rather
than running in circles for 10 minutes. Survival time is weighted low enough
that cowardice doesn't win, but present so a death at 9:30 still beats a death
at 2:00.

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
- **Music:** one 60–90 s CC0 loop.
- **SFX:** retro/sfxr-style — shoot, hit, enemy death, XP pickup, level-up,
  player hurt, run over. 7 sounds total.

Every committed asset gets a `assets/CREDITS.md` entry with source + license.
CC0 or self-generated only.

---

## 12. Scope ledger — what is NOT in v1.0

Recorded so these get re-proposed as *post-launch*, not smuggled into the build:

- Real-time multiplayer of any kind
- Ghosts / replay racing (best v2 candidate)
- Multiple characters or starting loadouts
- Meta-progression / permanent unlocks between runs
- Boss enemies
- Multiple maps or biomes
- Weapon evolutions / combo crafting
- Endless mode past 10:00

---

## 13. Phase plan & definition of done

| Phase | Deliverable | Done when |
|---|---|---|
| 0 | This document | Approved by Nick |
| 1 | Vertical slice | Move, auto-attack, seeded Drifter waves, XP, level-up 3-choice, run ends → score |
| 2 | Content + feel | 5 enemies, 6 upgrades, particles, screen shake, 7 SFX, difficulty ramp |
| 3 | Daily seed + local scores | Determinism test passes; local high-score table; **ranked-attempt bookkeeping** (one per UTC day, persisted, survives a mid-run quit) and **archive practice** on any past date |
| 4 | Steam | GodotSteam 4.20 prebuilt GDExtension; leaderboard submit/fetch + achievements; **runs fine with Steam absent** |
| 5 | Ship prep | Menus, settings, pause, controller, Windows export, release checklist. Includes the **ranked-run confirmation gate** and the archive date-picker UI |

**Phase 1 is the real risk gate.** If the one-enemy one-weapon loop isn't fun to
play for 10 minutes, no amount of Phase 2 content will save it. Evaluate
honestly at that checkpoint before building more on top.
