extends StaticBody3D
## Cible sphérique (couche de collision 2 « targets »).
##
## La hitbox a toujours sa taille finale ; seule la sphère visible est animée
## à l'apparition, pour ne jamais fausser la détection des tirs.

const ENEMY_MATERIAL: Material = preload("res://materials/target_enemy.tres")
const ENEMY_GLOW_COLOR := Color(1.0, 0.15, 0.55)

var target_id: int = -1
var grid_cell: Vector2i = Vector2i.ZERO
var radius: float = 0.38
var alive: bool = true
## Affiche la cible en magenta (adversaire à observer plutôt qu'à abattre).
var enemy_style: bool = false

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _glow: OmniLight3D = $Glow


## À appeler avant d'ajouter la cible à l'arbre.
func configure(id: int, cell: Vector2i, target_radius: float) -> void:
	target_id = id
	grid_cell = cell
	radius = target_radius


func _ready() -> void:
	var sphere := _collision.shape as SphereShape3D
	if sphere != null:
		sphere.radius = radius
	if enemy_style:
		_mesh.set_surface_override_material(0, ENEMY_MATERIAL)
		_glow.light_color = ENEMY_GLOW_COLOR
	# Les petites cibles éclairent moins leur environnement.
	_glow.omni_range = clampf(radius * 12.0, 1.5, 4.5)
	# Le SphereMesh de la scène a un diamètre de 1 m : l'échelle vaut donc le diamètre voulu.
	var full_scale := Vector3.ONE * (radius * 2.0)
	_mesh.scale = full_scale * 0.6
	var tween := create_tween()
	tween.tween_property(_mesh, "scale", full_scale, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Active ou désactive la hitbox sans toucher à l'affichage.
func set_hittable(hittable: bool) -> void:
	collision_layer = 2 if hittable and alive else 0


## Désactive immédiatement la hitbox puis libère la cible.
func destroy() -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	queue_free()
