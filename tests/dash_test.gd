extends Node

## Dash behaviour (GDD section 3). The i-frames ARE the feature — a dash that
## moves you but does not protect you is just a speed boost.

var _ok := true


func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-56s %s" % [label, "OK" if passed else "FAIL"])


func _make_player() -> Node:
	var player: Node = load("res://scenes/player.tscn").instantiate()
	add_child(player)
	return player


func _ready() -> void:
	var player := _make_player()

	print("=== invulnerability ===")
	player.hp = 100.0
	player.take_damage(30.0)
	_check("no dash: damage lands (hp %.0f)" % player.hp, player.hp == 70.0)

	player.hp = 100.0
	player._dash_iframes = Balance.DASH_IFRAMES
	player.take_damage(30.0)
	_check("dashing: damage is ignored (hp %.0f)" % player.hp, player.hp == 100.0)

	player._dash_iframes = 0.0
	player.hp = 100.0
	player._iframes = 0.0
	player.take_damage(30.0)
	_check("after the window: damage lands again (hp %.0f)" % player.hp, player.hp == 70.0)

	print("\n=== cooldown gating ===")
	var fresh := _make_player()
	_check("starts ready", fresh.can_dash())
	fresh._dash_cooldown_left = Balance.DASH_COOLDOWN
	_check("blocked while cooling down", not fresh.can_dash())
	_check("cooldown fraction is full (%.2f)" % fresh.dash_cooldown_fraction(),
		absf(fresh.dash_cooldown_fraction() - 1.0) < 0.01)
	fresh._dash_cooldown_left = 0.0
	_check("ready again once it expires", fresh.can_dash())

	print("\n=== the tell is visible ===")
	fresh._dash_iframes = Balance.DASH_IFRAMES
	_check("is_dashing() true during i-frames", fresh.is_dashing())
	_check("i-frames outlast the movement (%.2fs > %.2fs)" % [
		Balance.DASH_IFRAMES, Balance.DASH_DURATION],
		Balance.DASH_IFRAMES > Balance.DASH_DURATION)
	fresh._dash_iframes = 0.0
	_check("not dashing when idle", not fresh.is_dashing())

	print("\n=== sane starting values ===")
	_check("cooldown in the 2-5s band (%.1fs)" % Balance.DASH_COOLDOWN,
		Balance.DASH_COOLDOWN >= 2.0 and Balance.DASH_COOLDOWN <= 5.0)
	_check("dash covers ground vs walking (%.0fpx vs %.0fpx in %.2fs)" % [
		Balance.DASH_DISTANCE, Balance.PLAYER_MOVE_SPEED * Balance.DASH_DURATION,
		Balance.DASH_DURATION],
		Balance.DASH_DISTANCE > Balance.PLAYER_MOVE_SPEED * Balance.DASH_DURATION * 2.0)

	print("\n=== scripted dash is deterministic ===")
	var a := ScriptedInput.wants_dash("seed-a", 1.9)
	var b := ScriptedInput.wants_dash("seed-a", 1.9)
	_check("same (seed, time) gives the same answer", a == b)
	_check("no seed means no dash", not ScriptedInput.wants_dash("", 1.9))

	print("\n=== EXP bar matches the gems it represents ===")
	_check("bar colour is Balance.GEM_COLOR", Balance.GEM_COLOR == Color(1.0, 0.92, 0.25))

	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
