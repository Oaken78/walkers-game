class_name CombatLayers
extends RefCounted
## 3D physics layers as bit values for collision_layer and collision_mask (GDD 13: 1 world, 2 player, 3 enemies,
## 4 player_projectiles, 5 enemy_projectiles, 6 pickups, 7 triggers). The numbers are bits, not layer indices.

const WORLD: int = 1
const PLAYER: int = 2
const ENEMY: int = 4
const PLAYER_PROJECTILE: int = 8
const ENEMY_PROJECTILE: int = 16
const PICKUP: int = 32
const TRIGGER: int = 64
