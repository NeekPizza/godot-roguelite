extends Node2D

# Scaffold smoke test. Phase 1 replaces this with the real run scene.

func _ready() -> void:
	print("[scaffold] Main scene ready. Godot ", Engine.get_version_info().string)
