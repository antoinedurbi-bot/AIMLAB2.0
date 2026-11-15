extends Node3D
## Traceur de tir : un faisceau émissif tendu entre la bouche du canon et le
## point d'impact, qui s'affine jusqu'à disparaître en une dizaine de millisecondes.

@export var duration: float = 0.09
@export var thickness: float = 0.022

@onready var _beam: MeshInstance3D = $Beam


## À appeler une fois le traceur ajouté à l'arbre.
func fire(from: Vector3, to: Vector3) -> void:
	var span: Vector3 = to - from
	var beam_length := span.length()
	if beam_length < 0.05:
		queue_free()
		return
	var direction: Vector3 = span / beam_length
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(direction, up), (from + to) * 0.5)
	_beam.scale = Vector3(thickness, thickness, beam_length)

	var thin := thickness * 0.04
	var tween := create_tween()
	tween.tween_property(_beam, "scale", Vector3(thin, thin, beam_length), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
