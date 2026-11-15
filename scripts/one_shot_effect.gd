extends Node3D
## Effet ponctuel (explosion de cible, impact) : relance les GPUParticles3D
## enfants, éteint le flash lumineux, dilate l'onde de choc, puis se libère.
##
## Nœuds enfants optionnels reconnus par leur nom : « Flash » (OmniLight3D)
## et « Ring » (MeshInstance3D utilisant shaders/shockwave_ring.gdshader).

@export var lifetime: float = 1.0
@export var flash_duration: float = 0.2
@export var ring_duration: float = 0.3
@export var ring_start_scale: float = 0.4
@export var ring_end_scale: float = 3.0


func _ready() -> void:
	for child in get_children():
		var particles := child as GPUParticles3D
		if particles != null:
			particles.restart()

	var flash := get_node_or_null(^"Flash") as OmniLight3D
	if flash != null:
		var flash_tween := create_tween()
		flash_tween.tween_property(flash, "light_energy", 0.0, flash_duration).set_ease(Tween.EASE_OUT)

	var ring := get_node_or_null(^"Ring") as MeshInstance3D
	if ring != null:
		ring.scale = Vector3.ONE * ring_start_scale
		ring.set_instance_shader_parameter(&"progress", 0.0)
		var ring_tween := create_tween().set_parallel(true)
		ring_tween.tween_property(ring, "scale", Vector3.ONE * ring_end_scale, ring_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ring_tween.tween_method(_set_ring_progress.bind(ring), 0.0, 1.0, ring_duration)

	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func _set_ring_progress(value: float, ring: MeshInstance3D) -> void:
	ring.set_instance_shader_parameter(&"progress", value)
