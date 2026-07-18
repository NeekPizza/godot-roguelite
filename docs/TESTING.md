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
| `--run-seconds=N` | Shortens the run to N seconds. The difficulty ramp is **scaled**, not truncated, so a short run still walks the whole curve from tier 1 to tier 5. |
| `--auto-pick` | Auto-selects card 0 at every level-up. Without it, a headless run pauses forever at the first level-up waiting for input that will never arrive. |
| `--screenshot=PATH@N` | Saves a PNG of the framebuffer N seconds in. Requires a window (not `--headless`, which has no renderer). |

Examples:

```bash
# 30-second unattended smoke run
godot --headless --quit-after 3600 -- --run-seconds=30 --auto-pick

# Capture the level-up screen 20s in
godot --quit-after 8000 -- --run-seconds=30 --screenshot=/tmp/shot.png@20
```

### Gotcha: `--quit-after` counts rendered frames, not seconds

A windowed run is uncapped and can exceed 200 fps, so `--quit-after 600` may
end the process in ~3 seconds of wall time, not 10. Budget generously when
timing a screenshot, or the process exits before the capture fires.

## Determinism check

Two runs of the same seed with identical inputs must produce identical output:

```bash
godot --headless --quit-after 3600 -- --run-seconds=30 --auto-pick 2>&1 | grep '^\[run\]' > /tmp/d1.log
godot --headless --quit-after 3600 -- --run-seconds=30 --auto-pick 2>&1 | grep '^\[run\]' > /tmp/d2.log
diff /tmp/d1.log /tmp/d2.log && echo DETERMINISTIC
```

**This is a weak check today** and is knowingly incomplete: with no input, both
runs follow the same code path, so it proves the RNG streams are seeded and
consumed consistently but *not* that player behaviour can't desync them. Phase 3
replaces it with a real test that replays a recorded input sequence and compares
full end state. Do not treat the current check as proof of determinism.
