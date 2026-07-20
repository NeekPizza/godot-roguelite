extends Node

## Meta profile persistence: point balance, purchases, lifetime records.
##
## Kept in its own file rather than inside SaveStore so that losing progression
## can never take the ranked ledger with it, and vice versa.
##
## TEST OVERRIDE: `--meta-profile=none|max` replaces the profile in memory and
## disables saving entirely, because a determinism run that read the tester's
## real profile would verify differently on two machines — exactly the failure
## the check exists to catch.

const META_PATH := "user://meta.json"

var points := 0
var purchases := {}
var lifetime := {}

var _test_profile := ""          # non-empty means "never touch disk"


func is_test_profile() -> bool:
	return _test_profile != ""


func _ready() -> void:
	purchases = Meta.profile_none()
	lifetime = _default_lifetime()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--meta-profile="):
			_test_profile = arg.split("=")[1]

	match _test_profile:
		"none":
			print("[meta] test profile: none (zero upgrades, save disabled)")
			return
		"max":
			purchases = Meta.profile_max()
			print("[meta] test profile: max (+%.1f%% total, save disabled)"
				% (Meta.effective_bonus(purchases) * 100.0))
			return
		"":
			load_from_disk()
		_:
			push_warning("MetaStore: unknown --meta-profile '%s'" % _test_profile)
			_test_profile = ""
			load_from_disk()


func _default_lifetime() -> Dictionary:
	return {"runs": 0, "ranked_runs": 0, "best_stage": 0, "best_score": 0,
			"kills": 0, "bosses": 0}


func load_from_disk() -> void:
	if not FileAccess.file_exists(META_PATH):
		return
	var file := FileAccess.open(META_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MetaStore: profile unreadable, starting fresh")
		return

	points = int(parsed.get("points", 0))
	var stored: Dictionary = parsed.get("purchases", {})
	for stat_id in Balance.META_STATS:
		purchases[stat_id] = clampi(int(stored.get(stat_id, 0)), 0, Balance.META_MAX_BUYS)
	var stored_lifetime: Dictionary = parsed.get("lifetime", {})
	for key in lifetime:
		lifetime[key] = int(stored_lifetime.get(key, 0))


func save_to_disk() -> void:
	if is_test_profile():
		return                       # test profiles never persist
	var file := FileAccess.open(META_PATH, FileAccess.WRITE)
	if file == null:
		push_error("MetaStore: cannot write %s" % META_PATH)
		return
	file.store_string(JSON.stringify({
		"points": points, "purchases": purchases, "lifetime": lifetime,
	}, "\t"))
	file.close()


# --- Spending ----------------------------------------------------------------

func can_buy(stat_id: String) -> bool:
	var owned := int(purchases.get(stat_id, 0))
	if owned >= Balance.META_MAX_BUYS:
		return false
	# Buying past the aggregate ceiling would dilute rather than add, so the
	# store simply refuses rather than letting players waste points.
	if Meta.total_purchases(purchases) >= Meta.max_total_purchases():
		return false
	return points >= Meta.next_cost(owned)


func buy(stat_id: String) -> bool:
	if not can_buy(stat_id):
		return false
	points -= Meta.next_cost(int(purchases[stat_id]))
	purchases[stat_id] = int(purchases[stat_id]) + 1
	save_to_disk()
	return true


## Free by design: allocation should be a decision between runs, not a
## commitment a player regrets for weeks.
func respec() -> void:
	points += Meta.total_spent(purchases)
	purchases = Meta.profile_none()
	save_to_disk()


func award_points(amount: int) -> void:
	points += amount
	save_to_disk()


func record_run(ranked: bool, stage: int, score: int, kills: int, bosses: int) -> void:
	lifetime["runs"] = int(lifetime["runs"]) + 1
	if ranked:
		lifetime["ranked_runs"] = int(lifetime["ranked_runs"]) + 1
	lifetime["best_stage"] = maxi(int(lifetime["best_stage"]), stage)
	lifetime["best_score"] = maxi(int(lifetime["best_score"]), score)
	lifetime["kills"] = int(lifetime["kills"]) + kills
	lifetime["bosses"] = int(lifetime["bosses"]) + bosses
	save_to_disk()


## For the transparency readout: "+4.2%" style.
func bonus_text() -> String:
	return "+%.1f%%" % (Meta.effective_bonus(purchases) * 100.0)
