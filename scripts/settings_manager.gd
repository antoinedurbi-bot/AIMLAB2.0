extends Node
## Autoload « GameSettings » : sensibilité, réticule et options graphiques.
##
## La sensibilité est exprimée en cm/360° (distance physique parcourue par la
## souris pour un tour complet) : c'est la seule unité indépendante du jeu et
## du DPI. Les convertisseurs vers/depuis les sensibilités « en jeu » utilisent
## le yaw de chaque moteur (degrés tournés par count pour une sensibilité de 1).

signal sensitivity_changed
signal crosshair_changed
signal graphics_changed
signal audio_changed

enum CrosshairStyle { CROSS, CROSS_DOT, DOT, CIRCLE }
enum Quality { PERFORMANCE, QUALITY, ULTRA }

const SAVE_PATH := "user://settings.cfg"
const CM_PER_INCH := 2.54

## Jeux supportés par le convertisseur (ordre d'affichage).
const GAMES := ["Valorant", "CS2", "Apex Legends", "Overwatch 2"]
## Degrés de rotation par count souris pour une sensibilité en jeu de 1.0.
const GAME_YAW := {
	"Valorant": 0.07,
	"CS2": 0.022,
	"Apex Legends": 0.022,
	"Overwatch 2": 0.0066,
}

# --- Sensibilité ---
var dpi: float = 800.0
var cm_per_360: float = 35.0
## FOV horizontal de référence en 16:9 (103° = Valorant / Overwatch).
var fov_horizontal: float = 103.0
## Index dans GAMES du jeu utilisé par le convertisseur.
var reference_game: int = 0

# --- Réticule (dimensions en pixels physiques) ---
var crosshair_style: int = CrosshairStyle.CROSS_DOT
var crosshair_color: Color = Color(0.0, 1.0, 0.85)
var crosshair_length: float = 7.0
var crosshair_thickness: float = 2.0
var crosshair_gap: float = 4.0
var crosshair_dot_size: float = 2.0
var crosshair_outline: bool = true
var crosshair_opacity: float = 1.0

# --- Graphismes ---
var quality: int = Quality.QUALITY
var vsync: bool = false
var fullscreen: bool = false
## 0 = illimité (recommandé : la télémétrie gagne en résolution temporelle).
var max_fps: int = 0

# --- Audio et données ---
var sfx_volume: float = 0.6
## Écrit la télémétrie brute (CSV + JSON) de chaque session dans user://telemetry.
var export_raw_telemetry: bool = true
## Identifiant du dernier exercice lancé (présélectionné dans le menu).
var last_drill: String = "gridshot"
## Identifiant du profil d'arme (voir scripts/weapons.gd).
var weapon: String = "rifle"


func _ready() -> void:
	load_settings()


# ---------------------------------------------------------------------------
# Sensibilité
# ---------------------------------------------------------------------------

## Nombre de counts souris nécessaires pour un tour complet.
func counts_per_360() -> float:
	return cm_per_360 / CM_PER_INCH * dpi


## Degrés de rotation appliqués par count souris (aucun lissage, aucune accélération).
func degrees_per_count() -> float:
	return 360.0 / maxf(counts_per_360(), 1.0)


## Convertit une sensibilité « en jeu » en cm/360° pour le DPI courant.
func game_sens_to_cm(game: String, sens: float) -> float:
	var yaw: float = GAME_YAW.get(game, 0.022)
	return 360.0 * CM_PER_INCH / maxf(dpi * yaw * sens, 0.000001)


## Convertit des cm/360° en sensibilité « en jeu » pour le DPI courant.
func cm_to_game_sens(game: String, cm: float) -> float:
	var yaw: float = GAME_YAW.get(game, 0.022)
	return 360.0 * CM_PER_INCH / maxf(dpi * yaw * cm, 0.000001)


func game_name(index: int) -> String:
	var name_value: String = GAMES[clampi(index, 0, GAMES.size() - 1)]
	return name_value


## FOV vertical à donner à la Camera3D (Godot travaille en FOV vertical).
func vertical_fov() -> float:
	var half_horizontal := deg_to_rad(fov_horizontal) * 0.5
	return rad_to_deg(2.0 * atan(tan(half_horizontal) * 9.0 / 16.0))


# ---------------------------------------------------------------------------
# Réticule : préréglages et code d'échange
# ---------------------------------------------------------------------------

## Préréglages proposés dans le menu (nom -> code).
const CROSSHAIR_PRESETS := {
	"Croix + point": "KA1;1;00ffd9;7;2;4;2;1;1.00",
	"Petite croix": "KA1;0;ffffff;4;2;3;2;1;1.00",
	"Point seul": "KA1;2;00ff66;0;2;0;4;1;1.00",
	"Cercle + point": "KA1;3;ff4fd8;6;2;5;2;1;0.90",
	"Croix fine large": "KA1;0;ffe600;10;1;6;2;0;0.85",
}


## Code texte du réticule courant, à copier pour le partager ou le sauvegarder :
## KA1;forme;couleur hex;longueur;épaisseur;écart;point;contour;opacité.
func crosshair_to_code() -> String:
	return "KA1;%d;%s;%d;%d;%d;%d;%d;%.2f" % [
		crosshair_style, crosshair_color.to_html(false), roundi(crosshair_length), roundi(crosshair_thickness),
		roundi(crosshair_gap), roundi(crosshair_dot_size), 1 if crosshair_outline else 0, crosshair_opacity]


## Applique un code produit par crosshair_to_code(). Renvoie faux si le code est invalide
## (le réticule courant est alors conservé).
func crosshair_from_code(code: String) -> bool:
	var parts := code.strip_edges().split(";")
	if parts.size() != 9 or parts[0] != "KA1":
		return false
	if not Color.html_is_valid(parts[2]):
		return false
	for index in [1, 3, 4, 5, 6, 7]:
		var field: String = parts[index]
		if not field.is_valid_int():
			return false
	if not parts[8].is_valid_float():
		return false
	crosshair_style = clampi(parts[1].to_int(), 0, CrosshairStyle.size() - 1)
	crosshair_color = Color.html(parts[2])
	crosshair_length = clampf(parts[3].to_float(), 0.0, 60.0)
	crosshair_thickness = clampf(parts[4].to_float(), 1.0, 12.0)
	crosshair_gap = clampf(parts[5].to_float(), 0.0, 40.0)
	crosshair_dot_size = clampf(parts[6].to_float(), 1.0, 16.0)
	crosshair_outline = parts[7].to_int() != 0
	crosshair_opacity = clampf(parts[8].to_float(), 0.1, 1.0)
	return true


# ---------------------------------------------------------------------------
# Validation des changements : notifie les abonnés puis enregistre sur disque
# ---------------------------------------------------------------------------

func commit_sensitivity() -> void:
	sensitivity_changed.emit()
	save_settings()


func commit_crosshair() -> void:
	crosshair_changed.emit()
	save_settings()


func commit_graphics() -> void:
	graphics_changed.emit()
	save_settings()


func commit_audio() -> void:
	audio_changed.emit()
	save_settings()


# ---------------------------------------------------------------------------
# Persistance
# ---------------------------------------------------------------------------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sensitivity", "dpi", dpi)
	cfg.set_value("sensitivity", "cm_per_360", cm_per_360)
	cfg.set_value("sensitivity", "fov_horizontal", fov_horizontal)
	cfg.set_value("sensitivity", "reference_game", reference_game)
	cfg.set_value("crosshair", "style", crosshair_style)
	cfg.set_value("crosshair", "color", crosshair_color)
	cfg.set_value("crosshair", "length", crosshair_length)
	cfg.set_value("crosshair", "thickness", crosshair_thickness)
	cfg.set_value("crosshair", "gap", crosshair_gap)
	cfg.set_value("crosshair", "dot_size", crosshair_dot_size)
	cfg.set_value("crosshair", "outline", crosshair_outline)
	cfg.set_value("crosshair", "opacity", crosshair_opacity)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "max_fps", max_fps)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("data", "export_raw_telemetry", export_raw_telemetry)
	cfg.set_value("data", "last_drill", last_drill)
	cfg.set_value("data", "weapon", weapon)
	var error := cfg.save(SAVE_PATH)
	if error != OK:
		push_warning("KINETIC // AIM : impossible d'enregistrer %s (erreur %d)." % [SAVE_PATH, error])


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	dpi = clampf(_read_float(cfg, "sensitivity", "dpi", dpi), 50.0, 64000.0)
	cm_per_360 = clampf(_read_float(cfg, "sensitivity", "cm_per_360", cm_per_360), 1.0, 500.0)
	fov_horizontal = clampf(_read_float(cfg, "sensitivity", "fov_horizontal", fov_horizontal), 60.0, 130.0)
	reference_game = clampi(_read_int(cfg, "sensitivity", "reference_game", reference_game), 0, GAMES.size() - 1)
	crosshair_style = clampi(_read_int(cfg, "crosshair", "style", crosshair_style), 0, CrosshairStyle.size() - 1)
	var stored_color: Variant = cfg.get_value("crosshair", "color", crosshair_color)
	if stored_color is Color:
		crosshair_color = stored_color
	crosshair_length = clampf(_read_float(cfg, "crosshair", "length", crosshair_length), 0.0, 60.0)
	crosshair_thickness = clampf(_read_float(cfg, "crosshair", "thickness", crosshair_thickness), 1.0, 12.0)
	crosshair_gap = clampf(_read_float(cfg, "crosshair", "gap", crosshair_gap), 0.0, 40.0)
	crosshair_dot_size = clampf(_read_float(cfg, "crosshair", "dot_size", crosshair_dot_size), 1.0, 16.0)
	crosshair_outline = _read_bool(cfg, "crosshair", "outline", crosshair_outline)
	crosshair_opacity = clampf(_read_float(cfg, "crosshair", "opacity", crosshair_opacity), 0.1, 1.0)
	quality = clampi(_read_int(cfg, "graphics", "quality", quality), 0, Quality.size() - 1)
	vsync = _read_bool(cfg, "graphics", "vsync", vsync)
	fullscreen = _read_bool(cfg, "graphics", "fullscreen", fullscreen)
	max_fps = clampi(_read_int(cfg, "graphics", "max_fps", max_fps), 0, 2000)
	sfx_volume = clampf(_read_float(cfg, "audio", "sfx_volume", sfx_volume), 0.0, 1.0)
	export_raw_telemetry = _read_bool(cfg, "data", "export_raw_telemetry", export_raw_telemetry)
	var stored_drill: Variant = cfg.get_value("data", "last_drill", last_drill)
	if stored_drill is String:
		last_drill = stored_drill
	var stored_weapon: Variant = cfg.get_value("data", "weapon", weapon)
	if stored_weapon is String:
		weapon = stored_weapon


func _read_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var value: Variant = cfg.get_value(section, key, fallback)
	if value is float or value is int:
		var number: float = value
		return number
	return fallback


func _read_int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	var value: Variant = cfg.get_value(section, key, fallback)
	if value is float or value is int:
		var number: int = int(value)
		return number
	return fallback


func _read_bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value: Variant = cfg.get_value(section, key, fallback)
	if value is bool:
		var flag: bool = value
		return flag
	return fallback
