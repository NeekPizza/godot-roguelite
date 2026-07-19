# Testing

## Running the game

```bash
godot                 # windowed, normal 10-minute run
godot --headless      # no window; useful for error checking in CI
```

## Test hooks

Arguments after a bare `--` are read by `scripts/run.gd`. They exist so a run
can be exercised unattended — a normal run needs a human to move and to pick
upgrade cards, which makes automated checks impossible otherwise.

| Flag | Effect |
|---|---|
| `--time-scale=X` | Multiplies elapsed time, compressing the difficulty ramp so late-game content and later bosses are reachable unattended. Enemy *movement* stays real-time, so this distorts feel — use it to exercise spawn/boss logic, not to judge balance. |
| `--max-seconds=N` | Ends the run at N elapsed seconds. Purely a harness lever: the game itself is endless and has no time limit. |
| `--auto-pick` | Auto-selects card 0 at every level-up. Without it, a headless run pauses forever at the first level-up waiting for input that will never arrive. |
| `--open=confirm\|archive\|settings` | Menu only: jump straight to an overlay. UI states are otherwise reachable only by clicking, which makes them impossible to screenshot or smoke-test unattended. |
| `--godmode` | Player takes no damage. The only way to exercise the late-tier enemy types unattended — an idle run dies in tier 1-2 and never sees Tanks, Shooters or Splitters spawn. |
| `--quit-on-end` | Releases audio then calls `get_tree().quit()` when the run finishes. Prefer this over `--quit-after` in CI — it exits on a run boundary rather than mid-frame. |
| `--date=YYYY-MM-DD` | Play a past seed as unranked **archive practice**. Never consumes a ranked attempt. |
| `--ranked` | Explicitly start today's **ranked** run, consuming the day's attempt. This is the CLI form of the menu's confirmation prompt — nothing else can burn the attempt. |
| `--practice` | Today's seed, unranked. |
| `--scripted-input=SEED` | Drives the player with a reproducible synthetic input pattern instead of the keyboard. Required for a meaningful determinism test. |
| `--save-file=NAME` | Use `user://NAME` instead of `save.json`. **Always pass this in tests** so a run cannot clobber a real player's ranked ledger. |
| `--screenshot=PATH@N` | Saves a PNG of the framebuffer N seconds in. Requires a window (not `--headless`, which has no renderer). |

Examples:

```bash
# Short unattended smoke run
godot --headless -- --max-seconds=90 --auto-pick --quit-on-end

# Walk deep into the endless ramp, all five enemy types plus several bosses
godot --headless -- --time-scale=10 --max-seconds=900 --auto-pick --godmode --quit-on-end

# Capture the level-up screen 20s in
godot --quit-after 8000 -- --time-scale=6 --screenshot=/tmp/shot.png@20
```

### Gotcha: `--quit-after` counts rendered frames, not seconds

A windowed run is uncapped and can exceed 200 fps, so `--quit-after 600` may
end the process in ~3 seconds of wall time, not 10. Budget generously when
timing a screenshot, or the process exits before the capture fires.

## Determinism check

Two runs of the same seed with identical inputs must produce identical output:

```bash
godot --headless -- --time-scale=10 --max-seconds=900 --auto-pick --godmode --quit-on-end 2>&1 | grep '^\[run\]' > /tmp/d1.log
godot --headless -- --time-scale=10 --max-seconds=900 --auto-pick --godmode --quit-on-end 2>&1 | grep '^\[run\]' > /tmp/d2.log
diff /tmp/d1.log /tmp/d2.log && echo DETERMINISTIC
```

**This is a weak check today** and is knowingly incomplete: with no input, both
runs follow the same code path, so it proves the RNG streams are seeded and
consumed consistently but *not* that player behaviour can't desync them. Phase 3
replaces it with a real test that replays a recorded input sequence and compares
full end state. Do not treat the current check as proof of determinism.

## Gotcha: new assets need two import passes

A script that `preload()`s a freshly added asset fails on the first
`godot --headless --import`: the importer has not produced the `.import`
metadata yet, so the preload cannot resolve and the script fails to compile.
Run `--import` a second time and it resolves. If an autoload fails to compile
this way, the game still boots but that autoload is silently missing.

## Known non-issue: "resources still in use at exit"

A run that has loaded audio prints, at shutdown:

```
WARNING: N ObjectDB instances were leaked at exit
ERROR: N resources still in use at exit
```

This is a **shutdown-order artifact, not a runtime leak.** The named resources
are the `AudioStreamWAV`s held by `sfx.gd`'s const preloads and the music
`AudioStreamOggVorbis`, which the engine's resource cache still references when
it runs its exit check — autoload teardown happens afterwards. The count scales
with how many audio resources are loaded, and is unchanged whether or not
playback is stopped first (verified). Nothing accumulates while the game runs.

Do not "fix" this by removing the preloads; it costs runtime performance to
solve a message that appears only as the process exits.

## Data-integrity test

```bash
godot --headless tests/balance_test.tscn
```

Checks that every declared upgrade actually moves its stat, the pickup ceiling
holds, every enemy in `TYPE_SCHEDULE` exists and is well-formed, every sound the
code plays has a mix level, the ramp stays monotonic and unbounded, and scoring
stays inside int32. Exits non-zero on failure, so it is CI-ready.

**It runs as a scene, not via `--script`.** `godot --headless --script` does not
load autoloads, so any script referencing `Sfx`/`Music` fails to compile and
every player property reads back `null` — the test appears to fail when the game
is fine. Boot a scene instead.

## Test suite

```bash
godot --headless tests/balance_test.tscn                              # data integrity
godot --headless tests/steering_test.tscn                            # input/steering logic
godot --headless tests/input_test.tscn                               # controller bindings
godot --headless tests/dash_test.tscn                                # dash i-frames, cooldown, tell
godot --headless tests/save_test.tscn -- --save-file=test_save.json   # ranked ledger + table
./tools/determinism_check.sh                                          # daily-seed determinism
```

All three exit non-zero on failure, so they are CI-ready.

### The determinism check

`tools/determinism_check.sh` runs one seed twice with a **scripted player** and
asserts the end state matches, including `spawn_rng`'s internal state — which
encodes exactly how many draws the wave scheduler made over the whole run. Two
runs could agree on score while having consumed the stream differently; they
cannot agree on RNG state.

Three things make it meaningful where the old check was not:

1. **The player moves.** With no input, both runs follow an identical code path
   and the test proves almost nothing. Movement changes kills, pickups and
   level-up timing — where a desync would actually surface.
2. **`--godmode`**, so the run reaches bosses and late enemy types instead of
   dying two minutes in.
3. **A negative control.** A *different* scripted player must produce a
   *different* digest. A determinism test that cannot fail is worthless, so the
   script fails if the control does not diverge.

It uses a fixed date rather than today's, so it does not silently change meaning
tomorrow.

## Test hooks cannot produce a ranked score

`--godmode`, `--auto-pick`, `--time-scale`, `--max-seconds` and
`--scripted-input` all ship in the release binary — Godot passes user args to
any build, and stripping them is not practical. So instead, `RunConfig` refuses
to run **ranked** when any of them is present: the run is forced to practice and
the day's ranked attempt is left untouched.

```bash
godot -- --ranked --godmode --max-seconds=5 --auto-pick --quit-on-end
# -> "test hooks active -> forced to practice", ranked ledger stays empty
```

The anti-cheat posture is deliberately minimal (GDD section 10), but letting
`--godmode --ranked` submit a score was a step too far to leave in for free.
