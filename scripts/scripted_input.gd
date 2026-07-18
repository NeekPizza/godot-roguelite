class_name ScriptedInput
extends RefCounted

## A synthetic player, for the determinism test.
##
## The old determinism check ran with no input at all, so both runs followed an
## identical code path and proved almost nothing. Real desync risk comes from
## the player MOVING — different positions mean different kills, different gem
## pickups, different level-up timings — so a meaningful test needs a player
## that moves reproducibly.
##
## Direction is a PURE FUNCTION of (seed, elapsed): no stored state, nothing to
## get out of step. It draws from its own hash rather than any gameplay stream,
## so simulating a player cannot itself perturb spawn_rng.

const CHANGE_INTERVAL := 0.7


static func direction(seed_string: String, elapsed: float) -> Vector2:
	if seed_string == "":
		return Vector2.ZERO
	var step := floori(elapsed / CHANGE_INTERVAL)
	var hashed := GameSeed.hash_string("%s#move#%d" % [seed_string, step])
	# Take the low bits as an angle; the sign of the hash is irrelevant.
	var angle := float(absi(hashed) % 36000) / 36000.0 * TAU
	return Vector2.RIGHT.rotated(angle)
