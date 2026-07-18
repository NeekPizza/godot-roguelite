# Vibe-Coded Steam Game — Build Plan

A decision brief + Claude Code kickoff prompt for a low-budget, AI-driven Steam game priced $1–5, targeting a few thousand sales.

---

## 1. The core decision: skip real-time multiplayer

Your instinct (competition + leaderboards) is right. Your proposed mechanism (real-time online, low latency) is the trap.

**Why not synchronous online multiplayer:**
- Netcode (lag compensation, desync, rollback, cheat prevention) is the hardest thing to build in games and the least reliable thing to vibe-code.
- Indie multiplayer is all-or-nothing: hit critical mass or the servers sit empty and the game dies in months.
- You pay for relay/dedicated servers **forever** on a $1–5 game. Bad unit economics.

**What to build instead — asynchronous competition:**
- **Daily seed:** every player worldwide gets the same procedurally-generated run each day.
- **Global leaderboards:** compare scores/times. Powered by **Steamworks Leaderboards** — free, no servers you run.
- **Ghosts / replays (optional v2):** race a top player's recorded run. Feels multiplayer, is just data.

This delivers competition, "other people are here," and daily retention with **zero netcode and zero server cost.**

> If you later insist on live multiplayer, the ONLY vibe-codeable path is small lobbies (2–8 players) over **Steam's P2P relay networking** (free NAT punch-through + relay, no server bills). Treat it as a post-launch experiment, not the launch bet.

---

## 2. Genre: Daily-seed survivors-like / score-attack roguelite

**The pitch:** A fast, run-based arcade roguelite. Auto-attacking survival or twin-stick score-attack. Each run is 5–15 minutes. Global daily-seed leaderboard is the hook.

**Why it fits every constraint you gave:**

| Constraint | Why this genre wins |
|---|---|
| Vibe-codeable | Simple, well-documented mechanics. Tons of tutorials in the training data. |
| Low-effort art | Genre-defining hits (e.g. Vampire Survivors) are famously ugly. Neon/geometric/pixel all acceptable. |
| Low-effort music | One good AI-generated loop carries a whole run. |
| Sells thousands at $1–5 | Proven price/impulse-buy category. |
| Competitive + leaderboard | Daily seed + Steam leaderboard is native to the genre. |
| "Multiplayer feel" | Async ghosts/leaderboards, no netcode. |

**Runner-up genres** (same async-leaderboard model, pick if the above bores you):
- Minimalist endless twin-stick / bullet-hell score-attack.
- Physics-based time-trial (one-button, "getting over it" energy).
- Daily-puzzle roguelike (Balatro-lite deckbuilder — more design work, less action).

**Avoid:** multiplayer shooters (indie-scale can't compete), anything 3D-asset-heavy, anything needing lots of hand-authored content.

---

## 3. Tech stack

- **Engine:** Godot 4 (GDScript). Text-based scenes = AI can read/edit the whole project. Free, no royalties.
- **Leaderboards + achievements:** Steamworks, via the **GodotSteam** addon.
- **Art:** AI-generated sprites; keep a single cohesive palette (neon-on-dark hides inconsistency). Simple particle effects do heavy lifting.
- **Music/SFX:** One AI-generated loop + a small SFX pack. Free tools: sfxr/jsfxr for retro SFX.
- **Version control:** Git from day one so Claude Code changes are reviewable/revertible.
- **Cost to ship:** Steam Direct fee is $100 (recoupable). Everything else ~free.

**On BMAD:** it's a legitimate agentic planning method, but heavier than a solo project needs. Use the lightweight spec-driven loop in Section 5 instead. If you love structure, run BMAD only for the initial design doc, then drop to the simple loop for building.

---

## 4. Reality check on the business

- Median self-published Steam game earns ~$3–4k; the top 10% take ~84% of all revenue. It's skewed.
- "A few thousand copies" at $1–5 = ~$2k–$10k gross, **minus** Steam's 30% and taxes.
- The daily-leaderboard hook is your best cheap lever for retention + word-of-mouth (people share scores).
- Marketing matters as much as the build: a Steam page up early, a short GIF-friendly loop, and a demo. Budget real time for this — it's the actual bottleneck, not code.

---

## 5. Claude Code kickoff prompt

> Paste the block below into Claude Code in an empty folder. It sets up a spec-driven loop: design doc first, then vertical slice, then iterate.

```
We are building a 2D arcade roguelite for Steam in Godot 4 (GDScript). 
Genre: daily-seed survivors-like / score-attack. Runs last 5–15 min. The 
hook is a global daily-seed leaderboard (async competition, NO real-time 
multiplayer). Art is minimal neon/geometric, music is a single loop. 
Target price $1–5.

Work in this order and STOP for my review after each phase:

PHASE 0 — Design doc
- Create /docs/GDD.md: core loop, win/lose, one enemy type, one weapon, 
  XP/level-up with 3 upgrade choices, run timer, scoring formula, and how 
  the daily seed drives spawns. Keep scope tiny and shippable.

PHASE 1 — Playable vertical slice (no Steam yet)
- Player that auto-attacks, moves with WASD/stick.
- One enemy that spawns in waves from a seeded RNG.
- XP pickups, level-up screen with 3 random upgrades.
- Run ends on death or timer; show a score.
- Keep everything in text scenes; commit to git after each working feature.

PHASE 2 — Content + game feel
- 4–5 enemy types, 5–6 weapons/upgrades, screen shake, hit particles, 
  simple SFX hooks. Difficulty ramps over the run.

PHASE 3 — Daily seed + local leaderboard
- Deterministic daily seed from the date so every run of the day is identical.
- Local high-score table first (proves the loop before Steam).

PHASE 4 — Steam integration
- Add the GodotSteam addon. Wire Steamworks Leaderboards (submit + fetch 
  daily scores) and a few achievements. Guard all Steam calls so the game 
  still runs without Steam for local testing.

PHASE 5 — Ship prep
- Main menu, settings, pause, controller support, export presets for 
  Windows (and Linux/Mac if easy). Write a build/release checklist.

Rules: prefer the simplest thing that works; keep the codebase small and 
readable; explain any tradeoff before adding a dependency; after each phase 
give me a 3-line summary and how to test it.
```

---

## 6. First moves for you (this week)

1. Install Godot 4 and set up a Git repo.
2. Run Phase 0 above; read the GDD and cut anything that smells like scope creep.
3. Reserve your Steam Direct app / put up a coming-soon page early (marketing head start).
4. Generate one music loop + a starter palette so the game has an identity from the first build.
