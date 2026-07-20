class_name GameSeed
extends RefCounted

## Daily-seed derivation. See docs/GDD.md section 9 — this file is the single
## source of truth for the determinism contract.
##
## The seed is a pure function of a UTC date string, which is what makes the
## practice archive free: any past day is reproducible with no storage.

const FNV_OFFSET_BASIS := 1469598103934665603
const FNV_PRIME := 1099511628211


## FNV-1a over the UTF-8 bytes of `text`.
## GDScript ints are signed 64-bit and wrap on overflow, which is exactly the
## modular arithmetic FNV wants — so this is stable across platforms.
static func hash_string(text: String) -> int:
	var hash_value := FNV_OFFSET_BASIS
	for byte in text.to_utf8_buffer():
		hash_value ^= byte
		hash_value *= FNV_PRIME
	return hash_value


## "YYYY-MM-DD" for today in UTC. Never local time: a local-time rollover would
## mean players in different timezones compete on different runs.
static func today_utc() -> String:
	var now := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02d" % [now["year"], now["month"], now["day"]]


## Shift a "YYYY-MM-DD" string by whole days, for the practice archive.
## Goes through Unix time so month and year boundaries and leap years are the
## calendar's problem rather than ours.
static func days_before(date_string: String, days: int) -> String:
	var parts := date_string.split("-")
	if parts.size() != 3:
		return date_string
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
		"hour": 12, "minute": 0, "second": 0,   # midday avoids DST edge cases
	})
	var shifted := Time.get_datetime_dict_from_unix_time(int(unix) - days * 86400)
	return "%04d-%02d-%02d" % [shifted["year"], shifted["month"], shifted["day"]]


## True if `date_string` is a real calendar date not in the future (UTC).
static func is_valid_past_or_today(date_string: String) -> bool:
	var parts := date_string.split("-")
	if parts.size() != 3:
		return false
	for part in parts:
		if not part.is_valid_int():
			return false
	var month := int(parts[1])
	var day := int(parts[2])
	if month < 1 or month > 12 or day < 1 or day > 31:
		return false
	return date_string <= today_utc()   # ISO dates sort lexicographically


static func for_date(date_string: String) -> int:
	return hash_string(date_string)


## Enemy waves. Consumed only by the wave scheduler, in a fixed
## order at fixed times.
static func make_spawn_rng(date_string: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = for_date(date_string)
	return rng


## Legacy per-level stream, retained for the upgrade path; card draws use
## make_card_rng so rerolls stay indexed.
static func make_upgrade_rng(date_string: String, level_index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_string("%s#upgrade#%d" % [date_string, level_index])
	return rng


## Card draws. Indexed by (level, action) rather than running, so a reroll --
## which happens on player-dependent timing -- cannot shift any other stream.
static func make_card_rng(date_string: String, level_index: int,
		action_index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_string("%s#card#%d#%d" % [date_string, level_index, action_index])
	return rng


## Per-day rules drawn once at run start: weapon slots now, the enemy roster at
## 6e. Separate salt so adding a draw here can never disturb wave spawning.
static func make_daily_rng(date_string: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_string("%s#daily" % date_string)
	return rng


## Per-stage streams (v1.3). Keyed by STAGE INDEX, never a single running
## stream — that is what contains divergence. How long a player takes to kill
## the Stage 3 boss is player-dependent, and a shared stream would let that
## reshape Stage 4 for them alone.
static func make_stage_rng(date_string: String, stage: int,
		purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_string("%s#stage#%d#%s" % [date_string, stage, purpose])
	return rng


## Ground drops. Consumed only while BUILDING the schedule at run start, never
## during play, so no player action can advance it.
static func make_drops_rng(date_string: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_string("%s#drops" % date_string)
	return rng


## Boss slots. Indexed, not running: slot 3 cannot be shifted by what happened
## at slot 1, and a boss killed early or late changes nothing.
static func make_boss_rng(date_string: String, slot: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_string("%s#boss#%d" % [date_string, slot])
	return rng


## Stream: cosmetics only. Deliberately unseeded. Must never influence
## gameplay state.
static func make_fx_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng
