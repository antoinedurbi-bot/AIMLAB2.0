shader_type spatial;
// Grille néon procédurale, alignée sur le monde et anti-aliasée analytiquement.
// Utilisée en `next_pass` d'un StandardMaterial3D : la surface PBR est rendue
// normalement, puis cette passe ajoute les lignes émissives par-dessus.
render_mode blend_add, unshaded, depth_draw_never, cull_back;

uniform vec4 line_color : source_color = vec4(0.0, 0.85, 1.0, 1.0);
uniform vec4 major_color : source_color = vec4(0.0, 0.85, 1.0, 1.0);
// Taille d'une cellule en mètres.
uniform float cell_size = 1.0;
// Une ligne « majeure » toutes les N cellules.
uniform float major_every = 4.0;
// Épaisseur d'une ligne mineure en mètres (les majeures sont deux fois plus épaisses).
uniform float line_width = 0.02;
uniform float minor_energy = 0.3;
uniform float major_energy = 1.2;
// Atténuation avec la distance à la caméra (évite le scintillement au loin).
uniform float fade_start = 12.0;
uniform float fade_end = 60.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid_mask(vec2 coord, float half_width) {
	vec2 pixel = max(fwidth(coord), vec2(0.00001));
	vec2 dist = abs(fract(coord - 0.5) - 0.5);
	// Une ligne ne descend jamais sous un pixel : on compense par l'intensité.
	vec2 draw_width = max(vec2(half_width), pixel * 0.75);
	vec2 mask = vec2(1.0) - smoothstep(draw_width - pixel * 0.75, draw_width + pixel * 0.75, dist);
	mask *= clamp(vec2(half_width) / draw_width, 0.0, 1.0);
	return max(mask.x, mask.y);
}

void fragment() {
	vec3 n = abs(normalize(world_normal));
	// Projection sur le plan dominant de la face (sol, murs latéraux, murs avant/arrière).
	vec2 plane = world_position.xz;
	if (n.x > n.y && n.x > n.z) {
		plane = world_position.zy;
	} else if (n.z > n.y) {
		plane = world_position.xy;
	}

	vec2 minor_coord = plane / cell_size;
	vec2 major_coord = minor_coord / major_every;
	float minor = grid_mask(minor_coord, line_width * 0.5 / cell_size);
	float major = grid_mask(major_coord, line_width / (cell_size * major_every));

	float dist_to_camera = length(world_position - CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist_to_camera);

	vec3 glow = line_color.rgb * minor * minor_energy + major_color.rgb * major * major_energy;
	ALBEDO = glow * fade;
	ALPHA = 1.0;
}
