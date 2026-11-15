extends Control
## Interface en jeu : réticule, score, chronomètre, statistique latérale,
## objectif de l'exercice, retour d'information et jauge de vitesse.

const Crosshair := preload("res://ui/crosshair.gd")
const SpeedGauge := preload("res://ui/speed_gauge.gd")

## Couleurs des retours d'information, utilisées par les exercices.
const COLOR_GOOD := Color(0.25, 1.0, 0.7)
const COLOR_BAD := Color(1.0, 0.32, 0.42)
const COLOR_INFO := Color(0.55, 0.9, 1.0)

var _countdown_tween: Tween
var _feedback_tween: Tween
var _fps_timer: float = 0.0
var _last_time_text: String = ""
## Vrai quand un exercice a remplacé l'affichage de la précision par sa propre statistique.
var _custom_side_stat: bool = false

@onready var _crosshair: Crosshair = %Crosshair
@onready var _score_value: Label = %ScoreValue
@onready var _mode_label: Label = %ModeLabel
@onready var _time_value: Label = %TimeValue
@onready var _hits_label: Label = %HitsLabel
@onready var _accuracy_value: Label = %AccuracyValue
@onready var _objective: Label = %ObjectiveLabel
@onready var _speed_gauge: SpeedGauge = %SpeedGauge
@onready var _fps_label: Label = %FpsLabel
@onready var _sens_label: Label = %SensLabel
@onready var _countdown: Label = %CountdownLabel
@onready var _feedback: Label = %FeedbackLabel


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
	_feedback.visible = false
	_objective.text = ""
	_speed_gauge.visible = false
	_custom_side_stat = false
	_last_time_text = ""
	set_score(0)
	set_accuracy(0, 0)
	set_time_remaining(duration)


func set_score(score: int) -> void:
	_score_value.text = str(score)


## Affiche la précision, sauf si l'exercice a défini sa propre statistique latérale.
func set_accuracy(hits: int, shots: int) -> void:
	if _custom_side_stat:
		return
	_hits_label.text = "PRÉCISION · %d / %d" % [hits, shots]
	if shots <= 0:
		_accuracy_value.text = "—"
	else:
		_accuracy_value.text = "%.1f %%" % (100.0 * float(hits) / float(shots))


## Remplace l'affichage de la précision par une statistique propre à l'exercice.
func set_side_stat(caption: String, value: String) -> void:
	_custom_side_stat = true
	_hits_label.text = caption
	_accuracy_value.text = value


func set_time_remaining(seconds: float) -> void:
	var whole_minutes := int(seconds / 60.0)
	set_clock_text("%d:%04.1f" % [whole_minutes, seconds - float(whole_minutes) * 60.0])


## Texte libre à la place du chronomètre (exercices où il est masqué).
func set_clock_text(text: String) -> void:
	if text != _last_time_text:
		_last_time_text = text
		_time_value.text = text


## Consigne permanente affichée sous la barre du haut.
func set_objective(text: String) -> void:
	_objective.text = text


## Message bref sous le réticule (résultat d'un tir, d'une sortie, d'une manche).
func show_feedback(text: String, color: Color, hold: float = 1.3) -> void:
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback.text = text
	_feedback.visible = true
	_feedback.modulate = color
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(hold)
	_feedback_tween.tween_property(_feedback, "modulate:a", 0.0, 0.3)
	_feedback_tween.tween_callback(_feedback.hide)


func set_speed_gauge_visible(gauge_visible: bool) -> void:
	_speed_gauge.visible = gauge_visible


func set_speed(speed: float, accurate_speed: float, run_speed: float) -> void:
	_speed_gauge.set_values(speed, accurate_speed, run_speed)


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
