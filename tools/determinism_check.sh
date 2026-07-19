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
SECONDS_LIMIT="${2:-900}"
SCALE="${3:-10}"

run() {  # $1 = scripted input seed
  godot --headless -- --save-file=determinism_check.json \
    --date="$DATE" --scripted-input="$1" \
    --time-scale="$SCALE" --max-seconds="$SECONDS_LIMIT" \
    --auto-pick --godmode --quit-on-end 2>&1 \
    | grep -E '^\[digest\]|^\[run\] over'
}

echo "seed date : $DATE"
echo "sim       : ${SECONDS_LIMIT}s at ${SCALE}x, scripted player, godmode"
echo

run replay-a > /tmp/det_a.txt
run replay-a > /tmp/det_b.txt
run replay-b > /tmp/det_c.txt

status=0

if diff -q /tmp/det_a.txt /tmp/det_b.txt > /dev/null; then
  echo "PASS  same seed + same player  -> identical end state"
  sed 's/^/      /' /tmp/det_a.txt
else
  echo "FAIL  same seed + same player  -> DIVERGED"
  diff /tmp/det_a.txt /tmp/det_b.txt | sed 's/^/      /'
  status=1
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
