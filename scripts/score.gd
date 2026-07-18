class_name Score
extends RefCounted

## Scoring for the endless model (GDD section 8).
##
## There is no clear bonus any more — there is no clear. A run ends only on
## death, and the board spreads by how deep players got.

const PER_SECOND := 5
const PER_XP := 2

## Sanity ceiling for submitted scores.
##
## Headroom check: the ramp bottoms out at a 0.16 s spawn interval, and the live
## enemy cap is 300. Even assuming an absurd sustained 60 kills/s at the richest
## per-type value (30, a Tank) for a full hour, kills contribute ~6.5M. Survival
## adds 5/s and XP 2/each, both trivial beside that. A 30-minute run in practice
## lands in the low hundreds of thousands.
##
## So int32 (2,147,483,647) is never in danger from legitimate play, and this
## ceiling sits far above any real score while still rejecting the obviously
## fabricated. Anti-cheat posture remains deliberately minimal (GDD section 10):
## this is a plausibility bound, not a proof.
const CEILING := 50_000_000


static func total(kill_score: int, elapsed: float, xp_collected: int) -> int:
	return kill_score + int(elapsed) * PER_SECOND + xp_collected * PER_XP


static func is_plausible(value: int) -> bool:
	return value >= 0 and value <= CEILING


## Clamp before submitting anywhere (local table now, Steam in Phase 4).
static func bounded(value: int) -> int:
	return clampi(value, 0, CEILING)
