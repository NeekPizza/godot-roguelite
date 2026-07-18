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
| `--godmode` | Player takes no damage. The only way to exercise the late-tier enemy types unattended — an idle run dies in tier 1-2 and never sees Tanks, Shooters or Splitters spawn. |
| `--quit-on-end` | Releases audio then calls `get_tree().quit()` when the run finishes. Prefer this over `--quit-after` in CI — it exits on a run boundary rather than mid-frame. |
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
