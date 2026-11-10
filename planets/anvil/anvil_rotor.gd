class_name AnvilRotor
extends Node3D
## [planet-anvil] Spins a turbine rotor about its local forward axis (site prefabs have no manager).

@export var speed: float = 0.7


func _process(delta: float) -> void:
	rotate_object_local(Vector3.FORWARD, delta * speed)
