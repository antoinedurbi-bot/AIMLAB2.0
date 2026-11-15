shader_type spatial;
// Onde de choc : anneau additif toujours face caméra, piloté par `progress` (0 → 1).
// `progress` est un uniform d'instance : chaque effet l'anime indépendamment
// sans dupliquer le matériau.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled;

uniform vec4 ring_color : source_color = vec4(0.3, 0.95, 1.0, 1.0);
uniform float intensity = 3.0;
instance uniform float progress = 0.0;

void vertex() {
	// Billboard qui conserve l'échelle du nœud.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float radius = mix(0.2, 0.92, progress);
	float width = mix(0.12, 0.03, progress);
	float ring = 1.0 - smoothstep(0.0, width, abs(d - radius));
	float fade = (1.0 - progress) * (1.0 - progress);
	ALBEDO = ring_color.rgb * intensity * ring * fade;
	ALPHA = 1.0;
}
