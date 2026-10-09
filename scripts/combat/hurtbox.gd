class_name Hurtbox
extends Area3D
## Where a shot lands (GDD 5, 13). Enemy hurtboxes sit on layer 3; the player's is a PlayerHurtbox on layer 2.
## A projectile calls take_hit() once. The owner connects hit_taken, or sets `health` and lets the hurtbox
## apply the damage itself. A hit on a wreck (the `health` already depleted) does nothing and signals nothing, so a
## drone that keeps its hurtbox through a death fall is not hit twice.

signal hit_taken(damage: float, source: Node, point: Vector3)

## Optional: damaged by every hit.
var health: Health = null
var hits_taken: int = 0


func _init() -> void:
	collision_layer = CombatLayers.ENEMY
	collision_mask = 0
	monitoring = false
	monitorable = true


## Returns true when the hit counted, false for a hit on a wreck.
func take_hit(damage: float, source: Node, point: Vector3) -> bool:
	if health != null and health.is_depleted():
		return false
	hits_taken += 1
	if health != null:
		health.damage(damage)
	hit_taken.emit(damage, source, point)
	return true
