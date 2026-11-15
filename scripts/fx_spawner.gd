extends Node3D
## Fabrique d'effets visuels ponctuels (explosion de cible, impact, traceur).
## Attachée au nœud « Effects » de la scène principale ; les effets instanciés
## en deviennent les enfants et se libèrent tout seuls.

const EXPLOSION_SCENE: PackedScene = preload("res://scenes/effects/target_explosion.tscn")
const IMPACT_SCENE: PackedScene = preload("res://scenes/effects/impact.tscn")
const TRACER_SCENE: PackedScene = preload("res://scenes/effects/tracer.tscn")

const Tracer := preload("res://scripts/tracer.gd")


func explosion(at: Vector3) -> void:
	_spawn(EXPLOSION_SCENE, at, Vector3.ZERO)


## Impact sur une surface : l'axe +Z local de l'effet sort de la surface touchée.
func impact(at: Vector3, normal: Vector3) -> void:
	_spawn(IMPACT_SCENE, at, normal)


func tracer(from: Vector3, to: Vector3) -> void:
	var beam := TRACER_SCENE.instantiate() as Tracer
	add_child(beam)
	beam.fire(from, to)


## Instancie chaque effet une fois en `hidden_position` (un point masqué par un
## mur) pour que la compilation de leurs shaders ne tombe pas sur le premier tir.
func prewarm(hidden_position: Vector3) -> void:
	explosion(hidden_position)
	impact(hidden_position, Vector3.BACK)
	tracer(hidden_position, hidden_position + Vector3(0.0, 0.0, -2.0))


func _spawn(scene: PackedScene, at: Vector3, normal: Vector3) -> void:
	var effect := scene.instantiate() as Node3D
	if normal.length_squared() > 0.5:
		var up := Vector3.UP if absf(normal.y) < 0.99 else Vector3.RIGHT
		effect.transform = Transform3D(Basis.looking_at(-normal, up), at + normal * 0.03)
	else:
		effect.position = at
	add_child(effect)
