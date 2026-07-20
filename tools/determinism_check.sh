#!/usr/bin/env bash
# Determinism check for the daily seed (GDD section 9).
#
# Runs the SAME seed twice with a scripted player and asserts the end state is
# identical, including spawn_rng's internal state — which encodes exactly how
# many draws the wave scheduler made across the whole run.
#
# Two things make this meaningfully stronger than the old check:
#   1. A MOVING player. With no input both runs follow the same code path and
#      the test proves almost nothing; movement changes kills, pickups and
#      level-up timing, which is where a desync would actually surface.
#   2. --godmode, so the run reaches bosses and the late enemy types instead of
#      dying two minutes in.
#
# It also runs a NEGATIVE CONTROL: a different scripted player must produce a
# different digest. A determinism test that cannot fail is worthless.
#
# A FIXED date is used, not today's, so the test does not change meaning
# tomorrow.
set -euo pipefail

DATE="${1:-2026-01-01}"
SECONDS_LIMIT="${2:-2400}"
SCALE="${3:-14}"
# Advancing a stage means killing its boss, which a scripted player cannot do
# against scaling boss HP. This test-only hook lets the run cross several
# stages; it is in TEST_HOOK_ARGS, so a run using it can never be ranked.
BOSS_HP_MULT="${4:-0.01}"

run() {  # $1 = scripted input seed, $2 = meta profile
  # --meta-profile overrides the tester's saved profile. Without it the check
  # would read local progression and the same seed would verify differently on
  # two machines — the very failure this exists to catch.
  godot --headless -- --save-file=determinism_check.json \
    --date="$DATE" --scripted-input="$1" --boss-hp-mult="$BOSS_HP_MULT" \
    --meta-profile="${2:-none}" \
    --time-scale="$SCALE" --max-seconds="$SECONDS_LIMIT" \
    --auto-pick --godmode --quit-on-end 2>&1 \
    | grep -E '^\[digest\]|^\[run\] over|^\[run\] === STAGE'
}

echo "seed date : $DATE"
echo "sim       : ${SECONDS_LIMIT}s at ${SCALE}x, scripted player, godmode"
echo "stages    : boss HP x${BOSS_HP_MULT} so the run crosses several"
echo

run replay-a none > /tmp/det_a.txt
run replay-a none > /tmp/det_b.txt
run replay-b none > /tmp/det_c.txt
# Meta must be deterministic at BOTH extremes. Zero and max legitimately differ
# from each other — a stronger player kills more — so each is compared to
# itself, never across.
run replay-a max  > /tmp/det_m1.txt
run replay-a max  > /tmp/det_m2.txt

status=0

stages_crossed=$(grep -c '=== STAGE' /tmp/det_a.txt || true)
if [ "$stages_crossed" -lt 3 ]; then
  echo "FAIL  only $stages_crossed stage(s) entered — the check must cross at"
  echo "      least 3, or it is silently only testing Stage 1."
  exit 1
fi

if diff -q /tmp/det_a.txt /tmp/det_b.txt > /dev/null; then
  echo "PASS  same seed at ZERO meta        -> identical end state ($stages_crossed stages)"
  sed 's/^/      /' /tmp/det_a.txt
else
  echo "FAIL  same seed + same player  -> DIVERGED"
  diff /tmp/det_a.txt /tmp/det_b.txt | sed 's/^/      /'
  status=1
fi

echo
if diff -q /tmp/det_m1.txt /tmp/det_m2.txt > /dev/null; then
  echo "PASS  same seed at MAX meta         -> identical end state"
else
  echo "FAIL  same seed at MAX meta         -> DIVERGED"
  diff /tmp/det_m1.txt /tmp/det_m2.txt | sed 's/^/      /'
  status=1
fi

if diff -q /tmp/det_a.txt /tmp/det_m1.txt > /dev/null; then
  echo "WARN  zero and max meta produced identical runs — meta may not be"
  echo "      applying at all."
  status=1
else
  echo "PASS  zero vs max meta differ, so the upgrades are actually landing"
fi

echo
if diff -q /tmp/det_a.txt /tmp/det_c.txt > /dev/null; then
  echo "FAIL  negative control: a different player produced an identical digest,"
  echo "      so this check is not actually sensitive to divergence."
  status=1
else
  echo "PASS  negative control: a different player diverges, so the check bites"
fi

exit $status
