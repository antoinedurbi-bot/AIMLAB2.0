extends Node3D
## Projectile lancé à la main (incendiaire ou flash) : trajectoire balistique
## simulée pas à pas, rebonds amortis sur le décor.
##   INCENDIARY : explose au premier contact avec le sol.
##   FLASH      : explose en l'air après un court délai.

signal detonated(kind: int, at: Vector3)

enum Kind { INCENDIARY, FLASH }

const WORLD_MASK := 1
const GRAVITY := 12.0
const BOUNCE := 0.4
const FLASH_FUSE := 0.9
const MAX_LIFETIME := 5.0

var kind: int = Kind.INCENDIARY
var velocity: Vector3 = Vector3.ZERO

var _age: float = 0.0
var _done: bool = false


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.emission_enabled = true
	material.emission = Color(1.0, 0.5, 0.1) if kind == Kind.INCENDIARY else Color(1.0, 1.0, 0.8)
	material.emission_energy_multiplier = 4.0
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)


func _process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if (kind == Kind.FLASH and _age >= FLASH_FUSE) or _age >= MAX_LIFETIME:
		_detonate(global_position)
		return
	velocity.y -= GRAVITY * delta
	var next: Vector3 = global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next, WORLD_MASK)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		global_position = next
		return
	var normal: Vector3 = result["normal"]
	var point: Vector3 = result["position"]
	global_position = point + normal * 0.06
	if kind == Kind.INCENDIARY and normal.y > 0.6:
		_detonate(point)
		return
	velocity = velocity.bounce(normal) * BOUNCE


func _detonate(at: Vector3) -> void:
	_done = true
	detonated.emit(kind, at)
	queue_free()
