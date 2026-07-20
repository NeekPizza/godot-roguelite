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

const DEFAULT_META_FILE := "meta.json"

## Tests pass --meta-file=... so exercising real persistence never touches a
## player's actual profile. It is a redirect, not a grant, but it still forces
## the run to practice via RunConfig.TEST_HOOK_ARGS — a hook that writes the
## progression file has no business near a ranked submission.
var _meta_file := DEFAULT_META_FILE

var points := 0
var purchases := {}
var lifetime := {}

## Cosmetics live APART from `purchases` on purpose: they spend the same points
## but never enter the budget, so they can never move the +10% ceiling. `owned`
## is a list of option ids; `equipped` maps category -> id. `title` is the
## equipped milestone label.
var cosmetics := {}
var title := ""

var _test_profile := ""          # non-empty means "never touch disk"


func meta_path() -> String:
	return "user://" + _meta_file


func is_test_profile() -> bool:
	return _test_profile != ""


func _ready() -> void:
	purchases = Meta.profile_none()
	lifetime = _default_lifetime()
	cosmetics = _default_cosmetics()
	title = Balance.TITLES[0]["id"]

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--meta-profile="):
			_test_profile = arg.split("=")[1]
		elif arg.begins_with("--meta-file="):
			_meta_file = arg.split("=")[1]

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
			"best_seconds": 0, "best_kills": 0,
			"kills": 0, "bosses": 0, "seconds": 0}


func _default_cosmetics() -> Dictionary:
	return {"owned": Cosmetics.default_owned(), "equipped": Cosmetics.default_equipped()}


func load_from_disk() -> void:
	if not FileAccess.file_exists(meta_path()):
		return
	var file := FileAccess.open(meta_path(), FileAccess.READ)
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

	_load_cosmetics(parsed.get("cosmetics", {}))
	# An equipped title that is no longer valid (renamed catalog, hand-edited
	# save) falls back to the always-unlocked default rather than displaying junk.
	var stored_title := str(parsed.get("title", Balance.TITLES[0]["id"]))
	title = stored_title if not Cosmetics.title(stored_title).is_empty() \
		else str(Balance.TITLES[0]["id"])


## Rebuilt from defaults so a save that predates a category — or one written by
## a newer build with an option this build lacks — still yields a valid,
## fully-owned set of defaults plus whatever stored ids are still real.
func _load_cosmetics(stored: Dictionary) -> void:
	cosmetics = _default_cosmetics()
	for id in stored.get("owned", []):
		if not Cosmetics.option(str(id)).is_empty() and not cosmetics["owned"].has(id):
			cosmetics["owned"].append(str(id))
	var stored_equipped: Dictionary = stored.get("equipped", {})
	for category in Balance.COSMETICS:
		var id := str(stored_equipped.get(category, ""))
		# Only equip something actually owned; anything else stays the default.
		if cosmetics["owned"].has(id) and Cosmetics.category_of(id) == category:
			cosmetics["equipped"][category] = id


func save_to_disk() -> void:
	if is_test_profile():
		return                       # test profiles never persist
	var file := FileAccess.open(meta_path(), FileAccess.WRITE)
	if file == null:
		push_error("MetaStore: cannot write %s" % meta_path())
		return
	file.store_string(JSON.stringify({
		"points": points, "purchases": purchases, "lifetime": lifetime,
		"cosmetics": cosmetics, "title": title,
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


# --- Cosmetics (8d) ----------------------------------------------------------
#
# A separate spend path from buy(). It touches `cosmetics` and `points` and
# nothing in `purchases`, so no amount of cosmetic spending can move the budget.

func cosmetic_owned(id: String) -> bool:
	return cosmetics["owned"].has(id)


func can_buy_cosmetic(id: String) -> bool:
	var entry := Cosmetics.option(id)
	if entry.is_empty() or cosmetic_owned(id):
		return false
	return points >= int(entry["cost"])


func buy_cosmetic(id: String) -> bool:
	if not can_buy_cosmetic(id):
		return false
	points -= int(Cosmetics.option(id)["cost"])
	cosmetics["owned"].append(id)
	save_to_disk()
	return true


func equip_cosmetic(id: String) -> bool:
	var category := Cosmetics.category_of(id)
	if category == "" or not cosmetic_owned(id):
		return false
	cosmetics["equipped"][category] = id
	save_to_disk()
	return true


func equip_title(id: String) -> bool:
	if not Cosmetics.title_unlocked(lifetime, id):
		return false
	title = id
	save_to_disk()
	return true


func title_text() -> String:
	return Cosmetics.title_text(title)


## Files the run and returns the labels of any records it broke, newest values
## already stored.
##
## Detection and the update live in ONE call on purpose. Split across two, a
## caller that updated first would compare every value against itself and report
## a personal best on literally every run.
func record_run(ranked: bool, stage: int, score: int, kills: int, bosses: int,
		seconds: int) -> Array:
	var run := {"score": score, "stage": stage, "seconds": seconds, "kills": kills}

	# The first run beats zero at everything. Setting four records on a player's
	# very first attempt makes the banner meaningless, so run one silently
	# establishes the baseline and run two onward can celebrate.
	var broken := []
	if int(lifetime["runs"]) > 0:
		for record in Balance.META_RECORDS:
			if int(run[record["id"]]) > int(lifetime.get(record["field"], 0)):
				broken.append(str(record["label"]))

	lifetime["runs"] = int(lifetime["runs"]) + 1
	if ranked:
		lifetime["ranked_runs"] = int(lifetime["ranked_runs"]) + 1
	for record in Balance.META_RECORDS:
		var field: String = record["field"]
		lifetime[field] = maxi(int(lifetime.get(field, 0)), int(run[record["id"]]))
	lifetime["kills"] = int(lifetime["kills"]) + kills
	lifetime["bosses"] = int(lifetime["bosses"]) + bosses
	lifetime["seconds"] = int(lifetime["seconds"]) + seconds
	save_to_disk()
	return broken


## For the transparency readout: "+4.2%" style.
func bonus_text() -> String:
	return "+%.1f%%" % (Meta.effective_bonus(purchases) * 100.0)
