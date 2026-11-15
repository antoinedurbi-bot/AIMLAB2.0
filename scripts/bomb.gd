extends Node3D
## Charge posée sur un site. Elle bipe de plus en plus vite à l'approche de
## l'explosion (son spatialisé : on l'entend depuis sa position) et clignote à
## chaque bip. Quelqu'un — le joueur ou un adversaire — peut la désamorcer en
## restant dessus `defuse_seconds` ; toute interruption remet la progression à zéro.
##
## L'exercice pilote la charge : il appelle `set_defusing()` à chaque image et
## écoute les signaux `exploded` et `defused`.

signal exploded
signal defused(by_player: bool)

## Délai avant l'explosion et durée d'un désamorçage complet (s).
var fuse_seconds: float = 45.0
var defuse_seconds: float = 7.0

var time_left: float = 45.0
var defuse_progress: float = 0.0
var active: bool = false

var _defusing: bool = false
var _defuser_is_player: bool = false
var _beep_timer: float = 0.0

@onready var _light: OmniLight3D = $Light
@onready var _beeper: AudioStreamPlayer3D = $Beeper


func _ready() -> void:
	_beeper.stream = Sfx.get_stream(&"beep")


## Arme la charge : le compte à rebours démarre.
func arm() -> void:
	time_left = fuse_seconds
	defuse_progress = 0.0
	active = true
	_beep_timer = 0.0


## Arrête la charge sans signal (fin de session).
func stop() -> void:
	active = false
	_light.light_energy = 0.0


## À appeler à chaque image : indique si quelqu'un est en train de désamorcer.
func set_defusing(defusing: bool, by_player: bool) -> void:
	if not defusing and _defusing:
		defuse_progress = 0.0
	_defusing = defusing
	_defuser_is_player = by_player


func is_being_defused() -> bool:
	return _defusing


func _process(delta: float) -> void:
	if not active:
		return
	time_left -= delta
	# Flash qui retombe entre deux bips.
	_light.light_energy = move_toward(_light.light_energy, 0.0, 12.0 * delta)
	_beep_timer -= delta
	if _beep_timer <= 0.0:
		_beep_timer = _beep_interval()
		_light.light_energy = 3.0
		_beeper.pitch_scale = 1.5 if _defusing else 1.0
		_beeper.play()

	if _defusing:
		defuse_progress += delta
		if defuse_progress >= defuse_seconds:
			active = false
			_light.light_energy = 0.0
			defused.emit(_defuser_is_player)
			return
	if time_left <= 0.0:
		active = false
		_light.light_energy = 6.0
		exploded.emit()


## Un bip par seconde au début, jusqu'à sept par seconde dans les cinq dernières secondes.
func _beep_interval() -> float:
	if time_left > 25.0:
		return 1.0
	if time_left > 10.0:
		return 0.5
	if time_left > 5.0:
		return 0.25
	return 0.14
