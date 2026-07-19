class_name Steering
extends RefCounted

## Resolves the player's movement direction from every input source.
##
## Pulled out of player.gd as a PURE FUNCTION so it can be unit-tested: mouse
## and keyboard state live in engine globals that a headless test cannot set,
## but the decision logic is the part worth testing and this way it is reachable.

## Priority: scripted (tests) > keyboard/stick > pointer-hold.
##
## Keyboard wins over the pointer while both are active, so a player steering
## with the mouse can still nudge with WASD without the two fighting. Releasing
## the keys hands control straight back to the pointer.
static func direction(keyboard: Vector2, pointer_held: bool,
		pointer_position: Vector2, player_position: Vector2,
		deadzone: float = Balance.POINTER_DEADZONE) -> Vector2:
	if keyboard.length_squared() > 0.0:
		return keyboard.normalized()

	if pointer_held:
		var to_pointer := pointer_position - player_position
		# Inside the deadzone the cursor is effectively on the player; without
		# this the direction flips wildly frame to frame and the ship jitters.
		if to_pointer.length() > deadzone:
			return to_pointer.normalized()

	return Vector2.ZERO
