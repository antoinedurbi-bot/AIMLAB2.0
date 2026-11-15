extends RefCounted
## Profils de bots par rang, de Fer à Radiant. Chaque champ décrit une facette
## du niveau d'un joueur ; les valeurs sont des estimations à ajuster à l'usage.
##
##   reaction        : délai entre « je te vois » et le premier tir (s)
##   aim_error       : écart de visée au moment où le bot te découvre (°)
##   settle          : temps pour que cet écart retombe (s) — vitesse du flick
##   steady_error    : écart résiduel une fois la visée posée (°)
##   tracking_lag    : retard sur une cible qui bouge (s)
##   recoil_control  : part du recul compensée pendant la rafale (0 à 1)
##   head_aim        : probabilité de viser la tête plutôt que le torse
##   fov             : demi-champ de vision (°)
##   turn_speed      : vitesse de rotation quand il est alerté (°/s)
##   hearing         : distance à laquelle il entend courir (m)
##   speed           : vitesse de déplacement (m/s)
##   burst           : balles par rafale
##   run_and_gun     : probabilité de tirer sans s'arrêter (mauvaise habitude)
##   cover           : probabilité de se remettre à couvert après une rafale
##   teamwork        : partage la position du joueur avec les autres bots

const NAMES := ["Fer", "Bronze", "Argent", "Or", "Platine", "Diamant", "Ascendant", "Immortel", "Radiant"]

const PROFILES := [
	{"reaction": 0.75, "aim_error": 6.5, "settle": 0.95, "steady_error": 1.6, "tracking_lag": 0.3, "recoil_control": 0.1, "head_aim": 0.08, "fov": 50.0, "turn_speed": 160.0, "hearing": 9.0, "speed": 3.8, "burst": 8, "run_and_gun": 0.7, "cover": 0.0, "teamwork": false},
	{"reaction": 0.62, "aim_error": 5.4, "settle": 0.8, "steady_error": 1.3, "tracking_lag": 0.26, "recoil_control": 0.2, "head_aim": 0.14, "fov": 55.0, "turn_speed": 200.0, "hearing": 11.0, "speed": 4.1, "burst": 7, "run_and_gun": 0.5, "cover": 0.05, "teamwork": false},
	{"reaction": 0.52, "aim_error": 4.4, "settle": 0.68, "steady_error": 1.05, "tracking_lag": 0.22, "recoil_control": 0.32, "head_aim": 0.22, "fov": 60.0, "turn_speed": 240.0, "hearing": 13.0, "speed": 4.4, "burst": 6, "run_and_gun": 0.32, "cover": 0.15, "teamwork": false},
	{"reaction": 0.44, "aim_error": 3.6, "settle": 0.56, "steady_error": 0.85, "tracking_lag": 0.18, "recoil_control": 0.45, "head_aim": 0.32, "fov": 65.0, "turn_speed": 290.0, "hearing": 15.0, "speed": 4.7, "burst": 5, "run_and_gun": 0.18, "cover": 0.3, "teamwork": true},
	{"reaction": 0.37, "aim_error": 2.9, "settle": 0.46, "steady_error": 0.68, "tracking_lag": 0.15, "recoil_control": 0.56, "head_aim": 0.42, "fov": 70.0, "turn_speed": 340.0, "hearing": 17.0, "speed": 4.9, "burst": 5, "run_and_gun": 0.1, "cover": 0.42, "teamwork": true},
	{"reaction": 0.31, "aim_error": 2.3, "settle": 0.38, "steady_error": 0.54, "tracking_lag": 0.12, "recoil_control": 0.66, "head_aim": 0.52, "fov": 75.0, "turn_speed": 400.0, "hearing": 19.0, "speed": 5.1, "burst": 4, "run_and_gun": 0.05, "cover": 0.55, "teamwork": true},
	{"reaction": 0.26, "aim_error": 1.8, "settle": 0.31, "steady_error": 0.42, "tracking_lag": 0.1, "recoil_control": 0.75, "head_aim": 0.62, "fov": 80.0, "turn_speed": 460.0, "hearing": 21.0, "speed": 5.2, "burst": 4, "run_and_gun": 0.02, "cover": 0.65, "teamwork": true},
	{"reaction": 0.22, "aim_error": 1.4, "settle": 0.25, "steady_error": 0.33, "tracking_lag": 0.08, "recoil_control": 0.83, "head_aim": 0.72, "fov": 85.0, "turn_speed": 520.0, "hearing": 23.0, "speed": 5.3, "burst": 3, "run_and_gun": 0.0, "cover": 0.75, "teamwork": true},
	{"reaction": 0.18, "aim_error": 1.0, "settle": 0.2, "steady_error": 0.25, "tracking_lag": 0.06, "recoil_control": 0.9, "head_aim": 0.82, "fov": 90.0, "turn_speed": 600.0, "hearing": 25.0, "speed": 5.4, "burst": 3, "run_and_gun": 0.0, "cover": 0.85, "teamwork": true},
]


static func count() -> int:
	return PROFILES.size()


static func profile(rank: int) -> Dictionary:
	var entry: Dictionary = PROFILES[clampi(rank, 0, PROFILES.size() - 1)]
	return entry


static func rank_name(rank: int) -> String:
	return str(NAMES[clampi(rank, 0, NAMES.size() - 1)])


## Rang correspondant à un niveau continu de 0 (Fer) à 1 (Radiant).
static func rank_from_skill(skill: float) -> int:
	return clampi(roundi(clampf(skill, 0.0, 1.0) * float(PROFILES.size() - 1)), 0, PROFILES.size() - 1)
