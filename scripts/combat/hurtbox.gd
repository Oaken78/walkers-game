class_name Hurtbox
extends Area3D
## Where a shot lands (GDD 5, 13). Enemy hurtboxes sit on layer 3; the player's is a PlayerHurtbox on layer 2.
## A projectile calls take_hit() once. The owner connects hit_taken, or sets `health` and lets the hurtbox
## apply the damage itself.

signal hit_taken(damage: float, source: Node, point: Vector3)

## Optional: damaged by every hit.
var health: Health = null
var hits_taken: int = 0


func _init() -> void:
	collision_layer = CombatLayers.ENEMY
	collision_mask = 0
	monitoring = false
	monitorable = true


func take_hit(damage: float, source: Node, point: Vector3) -> void:
	hits_taken += 1
	if health != null:
		health.damage(damage)
	hit_taken.emit(damage, source, point)
