class_name Score
extends RefCounted

## Scoring for the endless model — FORMULA ONLY. Weights live in balance.gd
## (GDD section 8).
##
## There is no clear bonus, because there is no clear. A run ends only on death
## and the board spreads by how deep players got.
##
## int32 headroom: the ramp bottoms out at a 0.16 s spawn interval against a
## 300-enemy live cap. Even an absurd sustained 60 kills/s at the richest
## per-type value (30, a Tank) for a full hour contributes ~6.5M; survival adds
## 5/s and XP 2 each, both trivial beside that. So a deliberately ridiculous
## one-hour run totals ~6.9M — about 0.3% of int32's 2,147,483,647. Real runs
## land in the low hundreds of thousands. Overflow is not a credible risk.

const PER_SECOND := Balance.SCORE_PER_SECOND
const PER_XP := Balance.SCORE_PER_XP


static func total(kill_score: int, elapsed: float, xp_collected: int) -> int:
	return kill_score \
		+ int(elapsed) * Balance.SCORE_PER_SECOND \
		+ xp_collected * Balance.SCORE_PER_XP


## Plausibility bound, not proof. The anti-cheat posture (GDD section 10) is
## deliberately minimal: local scores are editable and Steam submissions are
## client-side, and defending that properly is not worth it on a $1-5 game.
static func is_plausible(value: int) -> bool:
	return value >= 0 and value <= Balance.SCORE_CEILING


## Clamp before submitting anywhere (local table now, Steam in Phase 4).
static func bounded(value: int) -> int:
	return clampi(value, 0, Balance.SCORE_CEILING)
