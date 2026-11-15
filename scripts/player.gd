extends Node3D
## Contrôleur FPS statique : visée 1:1 à partir des counts bruts de la souris.
##
## Aucune interpolation, aucun lissage, aucune accélération : chaque count est
## converti en degrés via la sensibilité cm/360° de GameSettings. Les angles sont
## cumulés en double précision puis appliqués au nœud (yaw) et au pivot (pitch).

## Émis à chaque tir. `collider` est nul si le rayon n'a rien touché.
signal fired(collider: Object, hit_position: Vector3, hit_normal: Vector3, muzzle_position: Vector3)

const MAX_PITCH_DEG := 89.0

## Autorise la rotation de la caméra.
var look_enabled: bool = false
## Autorise le tir.
var fire_enabled: bool = false
var yaw_deg: float = 0.0
var pitch_deg: float = 0.0

var _degrees_per_count: float = 0.04

@onready var pivot: Node3D = $Pivot
@onready var camera: Camera3D = $Pivot/Camera3D
@onready var aim_ray: RayCast3D = $Pivot/Camera3D/AimRay
@onready var muzzle: Marker3D = $Pivot/Camera3D/Muzzle


func _ready() -> void:
	GameSettings.sensitivity_changed.connect(_refresh_settings)
	_refresh_settings()


func _input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		if look_enabled:
			_look(event as InputEventMouseMotion)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if fire_enabled and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			_fire()


## Recentre la vue face à la grille.
func reset_view() -> void:
	yaw_deg = 0.0
	pitch_deg = 0.0
	_apply_rotation()


func _refresh_settings() -> void:
	_degrees_per_count = GameSettings.degrees_per_count()
	camera.fov = GameSettings.vertical_fov()


func _look(motion: InputEventMouseMotion) -> void:
	var counts := _raw_counts(motion)
	yaw_deg -= counts.x * _degrees_per_count
	pitch_deg = clampf(pitch_deg - counts.y * _degrees_per_count, -MAX_PITCH_DEG, MAX_PITCH_DEG)
	_apply_rotation()


## Déplacement brut de la souris en counts.
## `screen_relative` (Godot 4.3+) est la variante de `relative` qui n'est pas
## mise à l'échelle par le stretch de la fenêtre : c'est la seule valeur 1:1
## quelle que soit la résolution. Sur une version antérieure, on retombe sur
## `relative` en annulant le facteur de stretch.
func _raw_counts(motion: InputEventMouseMotion) -> Vector2:
	var raw: Variant = motion.get(&"screen_relative")
	if raw is Vector2:
		var counts: Vector2 = raw
		return counts
	var visible_width := get_viewport().get_visible_rect().size.x
	var stretch := float(get_window().size.x) / maxf(visible_width, 1.0)
	return motion.relative * stretch


func _apply_rotation() -> void:
	rotation.y = deg_to_rad(wrapf(yaw_deg, -180.0, 180.0))
	pivot.rotation.x = deg_to_rad(pitch_deg)


func _fire() -> void:
	aim_ray.force_raycast_update()
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var hit_position := origin + direction * absf(aim_ray.target_position.z)
	var hit_normal := -direction
	var collider: Object = null
	if aim_ray.is_colliding():
		collider = aim_ray.get_collider()
		hit_position = aim_ray.get_collision_point()
		hit_normal = aim_ray.get_collision_normal()
	fired.emit(collider, hit_position, hit_normal, muzzle.global_position)
