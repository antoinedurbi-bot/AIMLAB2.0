extends Control
## Interface en jeu : réticule, score, chronomètre, précision et compte à rebours.

const Crosshair := preload("res://ui/crosshair.gd")

var _countdown_tween: Tween
var _fps_timer: float = 0.0
var _last_time_text: String = ""

@onready var _crosshair: Crosshair = %Crosshair
@onready var _score_value: Label = %ScoreValue
@onready var _mode_label: Label = %ModeLabel
@onready var _time_value: Label = %TimeValue
@onready var _hits_label: Label = %HitsLabel
@onready var _accuracy_value: Label = %AccuracyValue
@onready var _fps_label: Label = %FpsLabel
@onready var _sens_label: Label = %SensLabel
@onready var _countdown: Label = %CountdownLabel


func _ready() -> void:
	GameSettings.sensitivity_changed.connect(_refresh_sensitivity)
	_refresh_sensitivity()


func _process(delta: float) -> void:
	_fps_timer -= delta
	if _fps_timer <= 0.0:
		_fps_timer = 0.25
		_fps_label.text = "%d FPS" % roundi(Engine.get_frames_per_second())


## Remet l'affichage à zéro au début d'une session.
func reset(mode_name: String, duration: float) -> void:
	_mode_label.text = mode_name
	_countdown.visible = false
	set_score(0)
	set_accuracy(0, 0)
	set_time_remaining(duration)


func set_score(score: int) -> void:
	_score_value.text = str(score)


func set_accuracy(hits: int, shots: int) -> void:
	_hits_label.text = "PRÉCISION · %d / %d" % [hits, shots]
	if shots <= 0:
		_accuracy_value.text = "—"
	else:
		_accuracy_value.text = "%.1f %%" % (100.0 * float(hits) / float(shots))


func set_time_remaining(seconds: float) -> void:
	var whole_minutes := int(seconds / 60.0)
	var time_text := "%d:%04.1f" % [whole_minutes, seconds - float(whole_minutes) * 60.0]
	if time_text != _last_time_text:
		_last_time_text = time_text
		_time_value.text = time_text


## Affiche un grand texte centré. Si `hide_after` > 0, il s'efface tout seul.
func show_countdown(text: String, hide_after: float = 0.0) -> void:
	if _countdown_tween != null and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown.text = text
	_countdown.visible = true
	_countdown.modulate = Color.WHITE
	_countdown.pivot_offset = _countdown.size * 0.5
	_countdown.scale = Vector2(1.35, 1.35)
	_countdown_tween = create_tween()
	_countdown_tween.tween_property(_countdown, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if hide_after > 0.0:
		_countdown_tween.tween_interval(hide_after)
		_countdown_tween.tween_property(_countdown, "modulate:a", 0.0, 0.2)
		_countdown_tween.tween_callback(_countdown.hide)


func flash_hit() -> void:
	_crosshair.flash_hit()


func flash_miss() -> void:
	_crosshair.flash_miss()


func _refresh_sensitivity() -> void:
	_sens_label.text = "%.1f cm/360° · %d DPI" % [GameSettings.cm_per_360, roundi(GameSettings.dpi)]
