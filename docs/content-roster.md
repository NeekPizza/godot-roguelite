# daily-swarm — Starter Content Roster (v0.1 menu to react to)

A concrete menu of weapons, passives, evolutions, drops, enemies, and bosses to
review Claude Code's plan against. **All numbers are starting points** — they live
in `balance.gd` and get tuned later. Nothing here is final; cut or add freely.

> Determinism reminder: every "seed-selected" item below must come from a
> dedicated date-seeded stream at absolute times/positions, identical for all
> players on the day. Cosmetic-only randomness (muzzle flash, debris) stays on `fx_rng`.

---

## 1. Base weapons (permanent, chosen & upgraded in-run)

Aim for ~7 so a 3–5 slot day still forces real choices. Each covers a different
role (single-target / orbit-defense / AoE / crowd / positional).

| Weapon | Behavior | Role | Upgrade dials |
|---|---|---|---|
| **Pulse** *(exists)* | Auto-fires a seeking shot at nearest enemy | Reliable single-target | fire rate, damage, pierce, +projectile |
| **Orbit** | Orbs/blades circle the player, damage on contact | Passive defense / crowd | +orbs, radius, spin speed, damage |
| **Curveball** | Shots arc/curve outward, sweeping an area | Spread / around-corners | curve tightness, count, damage |
| **Boomerang** | Flies out and returns, hits on both legs (pierces) | Positional skill | range, count, return speed, pierce |
| **Nova** | Periodic expanding ring from the player, AoE + knockback | Close crowd control | radius, frequency, damage, knockback |
| **Lance** | Periodic piercing beam in aim/facing direction | High single-target line | width, damage, duration, tracking |
| **Drone** | Deploys a following mini-turret that auto-fires | Extra sustained DPS | +drones, fire rate, follow range |

Weapon-slot count is **seed-determined (min 3, up to ~5)** and shown on the ranked
confirmation screen — a low-slot day is its own kind of challenge.

---

## 2. Passives (build pieces + evolution triggers)

Existing: Overclock (+fire rate), Hollow Point (+damage), Kinetics (+move speed),
Magnetism (+pickup radius, capped), Vitality (+max HP), Split Shot (+projectile),
Piercing (+pierce).

Add for depth:

| Passive | Effect |
|---|---|
| **Cooldown Core** | −weapon cooldowns / global attack speed |
| **Amplifier** | +area / projectile size |
| **Velocity Coil** | +projectile speed |
| **Greed** | +XP gain and slightly better drop luck |
| **Guard** | −dash cooldown / +i-frame duration |

---

## 3. Evolutions (weapon maxed + paired passive maxed → evolved weapon)

The signature hook. Data-driven recipes so you can retune pairings.

| Base + Passive | Evolves into | Evolved effect |
|---|---|---|
| Pulse + Piercing | **Railgun** | Full-screen piercing lance through everything in line |
| Orbit + Amplifier | **Event Horizon** | Huge orbiting ring that also drags enemies inward |
| Boomerang + Split Shot | **Blade Storm** | A returning fan of blades |
| Nova + Cooldown Core | **Supernova** | Near-constant expanding shockwaves |
| Lance + Velocity Coil | **Prism Sweep** | Rotating beam that sweeps the field |
| Curveball + Hollow Point | **Seekers** | Homing high-damage curved missiles |
| Drone + Overclock | **Gun Battery** | Several rapid-fire turrets |

---

## 4. Temporary weapon drops (25s buffs — boss-dropped or map-placed)

Shown as an icon + countdown next to the EXP bar. Placed to pull players toward risk.

| Drop | Effect |
|---|---|
| **Shotgun** | Wide short-range burst; big up-close clear |
| **Machine Gun** | Very high fire rate straight stream; shreds |
| **Splash Gun** | Killed enemies explode for 50% of their max HP to nearby foes (chains) |
| **Chain Lightning** | Bolt arcs between nearby enemies |
| **Flamethrower** | Short cone with a burn damage-over-time |

---

## 5. Instant pickups (deterministic spawn schedule)

| Pickup | Effect |
|---|---|
| **Bomb** | Screen-clear: heavy damage to all on-screen enemies (bosses take a capped chunk, not instakill) |
| **Magnet** | Sweeps ALL field XP to the player with a fly-in animation |
| **Health** | Restores a chunk of HP |
| **Invulnerability** | A few seconds of invuln with a clear visual |
| **Freeze** *(optional)* | Briefly freezes/slows all enemies |

---

## 6. Enemies

Existing: **Drifter** (straight), **Swarmer** (fast/weak), **Tank** (slow/tanky),
**Shooter** (ranged), **Splitter** (splits on death).

New pool — the day's **active roster is seed-selected** (e.g. 5–7 types active today):

| Enemy | Behavior | Purpose |
|---|---|---|
| **Dasher** | Telegraphs, then bursts toward the player | Punishes lazy positioning |
| **Shielded** | Front shield; only vulnerable from side/behind or after shield break | Forces repositioning |
| **Orbiter** | Circles at range, hard to pin | Anti-lazy-aim |
| **Bomber** | Rushes and explodes (telegraphed AoE) on contact/death | Spacing threat |
| **Healer** | Heals nearby enemies; priority kill | Target prioritization |
| **Weaver** | Erratic sine movement, dodges shots | Accuracy check |

**Elites:** any base enemy can occasionally spawn as an elite (bigger, glowing,
more HP/damage) and **guarantees a drop** on death. Deterministic schedule.

---

## 7. Bosses (seed picks which archetype per 3-min slot; patterns escalate)

All patterns **telegraphed** so density reads as fair, not cheap. As the run gets
deeper: bullet count, spread angle, projectile velocity, and fire rate all rise.

| Boss | Core pattern | Escalation / variant |
|---|---|---|
| **Spinner** | Rotating radial bullet spray | Faster spin, more arms; dash-while-spraying variant |
| **Aimed Volley** | Telegraphed shotgun-spread bursts at the player | Tighter spread, higher velocity |
| **Charger** | Dashes across the arena in telegraphed lanes, shedding bullets | More lanes, quicker recovery |
| **Ring Master** | Expanding rings with gaps to weave through | Gaps shrink as the run deepens |
| **Summoner** | Shielded; spawns minion waves | More adds, shorter shield windows |
| **Turret Fortress** | Stationary dense multi-directional fire with rotating safe lanes | Lanes narrow and rotate faster |

Which boss appears each slot is drawn from a dedicated boss stream, so every player
on the seed fights the same bosses in the same order.

---

## Suggested minimum for a strong v1 (if you want to trim scope)

Weapons 5 of 7 · Passives all · Evolutions 4 · Temp weapons 3 (shotgun / MG /
splash) · Pickups 4 (bomb / magnet / health / invuln) · Enemies 4 new (dasher /
shielded / bomber / weaver) + elites · Bosses 4 archetypes. Everything else layers
in post-launch.
