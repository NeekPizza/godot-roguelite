extends Node

var _ok := true

func _check(label: String, passed: bool) -> void:
	if not passed:
		_ok = false
	print("  %-56s %s" % [label, "OK" if passed else "FAIL"])

func _ready() -> void:
	var player := Vector2(1000, 1000)
	var none := Vector2.ZERO

	print("=== pointer steering ===")
	var right := Steering.direction(none, true, player + Vector2(300, 0), player)
	_check("cursor right of player -> move right", right.is_equal_approx(Vector2.RIGHT))

	var up := Steering.direction(none, true, player + Vector2(0, -250), player)
	_check("cursor above player -> move up", up.is_equal_approx(Vector2.UP))

	var diagonal := Steering.direction(none, true, player + Vector2(200, 200), player)
	_check("diagonal is normalised (len %.3f)" % diagonal.length(),
		absf(diagonal.length() - 1.0) < 0.001)

	print("\n=== deadzone stops jitter ===")
	var inside := Steering.direction(none, true, player + Vector2(5, 5), player)
	_check("cursor on the player -> no movement", inside == Vector2.ZERO)
	var edge := Steering.direction(none, true,
		player + Vector2(Balance.POINTER_DEADZONE + 5.0, 0), player)
	_check("just outside the deadzone -> moves", edge != Vector2.ZERO)

	print("\n=== priority and release ===")
	var both := Steering.direction(Vector2(-1, 0), true, player + Vector2(500, 0), player)
	_check("keyboard wins while both are active", both.is_equal_approx(Vector2.LEFT))
	var released := Steering.direction(none, true, player + Vector2(500, 0), player)
	_check("releasing keys hands control back to the pointer",
		released.is_equal_approx(Vector2.RIGHT))

	print("\n=== idle ===")
	_check("nothing held -> no movement",
		Steering.direction(none, false, player + Vector2(500, 0), player) == Vector2.ZERO)
	_check("pointer far but not held -> no movement",
		Steering.direction(none, false, player + Vector2(9999, 0), player) == Vector2.ZERO)

	print("\n=== keyboard normalisation ===")
	var diag_keys := Steering.direction(Vector2(1, 1), false, player, player)
	_check("diagonal WASD normalised (len %.3f, no speed boost)" % diag_keys.length(),
		absf(diag_keys.length() - 1.0) < 0.001)

	print("\nRESULT: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
