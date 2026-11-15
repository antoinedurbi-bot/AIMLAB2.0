extends StaticBody3D
## Cible sphérique du Gridshot (couche de collision 2 « targets »).
##
## La hitbox a toujours sa taille finale ; seule la sphère visible est animée
## à l'apparition, pour ne jamais fausser la détection des tirs.

var target_id: int = -1
var grid_cell: Vector2i = Vector2i.ZERO
var radius: float = 0.38
var alive: bool = true

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $CollisionShape3D


## À appeler avant d'ajouter la cible à l'arbre.
func configure(id: int, cell: Vector2i, target_radius: float) -> void:
	target_id = id
	grid_cell = cell
	radius = target_radius


func _ready() -> void:
	var sphere := _collision.shape as SphereShape3D
	if sphere != null:
		sphere.radius = radius
	# Le SphereMesh de la scène a un diamètre de 1 m : l'échelle vaut donc le diamètre voulu.
	var full_scale := Vector3.ONE * (radius * 2.0)
	_mesh.scale = full_scale * 0.6
	var tween := create_tween()
	tween.tween_property(_mesh, "scale", full_scale, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Désactive immédiatement la hitbox puis libère la cible.
func destroy() -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	queue_free()
