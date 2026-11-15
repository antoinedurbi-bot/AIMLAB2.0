extends Control
## Écran de statistiques post-session : met en forme le rapport produit par
## l'autoload Telemetry (score, précision, TTK, flicks, fluidité, heatmap).

signal replay_requested
signal menu_requested

const FlickBar := preload("res://ui/flick_bar.gd")
const Heatmap := preload("res://ui/heatmap.gd")

## Délai avant d'activer les boutons : évite qu'un clic de fin de session ne
## relance ou ne ferme le rapport par accident.
const INPUT_LOCK_SECONDS := 0.6

@onready var _subtitle: Label = %Subtitle
@onready var _score_value: Label = %ScoreValue
@onready var _kpi_grid: GridContainer = %KpiGrid
@onready var _flick_bar: FlickBar = %FlickBar
@onready var _flick_details: Label = %FlickDetails
@onready var _smooth_value: Label = %SmoothValue
@onready var _smooth_gauge: ProgressBar = %SmoothGauge
@onready var _smooth_details: Label = %SmoothDetails
@onready var _heatmap: Heatmap = %Heatmap
@onready var _heat_legend: Label = %HeatLegend
@onready var _footer_info: Label = %FooterInfo
@onready var _back_button: Button = %BackButton
@onready var _replay_button: Button = %ReplayButton


func _ready() -> void:
	_replay_button.pressed.connect(_on_replay_pressed)
	_back_button.pressed.connect(_on_back_pressed)


## Affiche le rapport d'une session terminée.
func show_report(report: Dictionary) -> void:
	visible = true
	_fill_header(report)
	_fill_kpis(report)
	_fill_flicks(report)
	_fill_smoothness(report)
	_fill_heatmap(report)
	_fill_footer(report)
	_lock_buttons()


func _on_replay_pressed() -> void:
	replay_requested.emit()


func _on_back_pressed() -> void:
	menu_requested.emit()


func _lock_buttons() -> void:
	_replay_button.disabled = true
	_back_button.disabled = true
	await get_tree().create_timer(INPUT_LOCK_SECONDS).timeout
	_replay_button.disabled = false
	_back_button.disabled = false
	if is_visible_in_tree():
		_replay_button.grab_focus()


# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------

func _fill_header(report: Dictionary) -> void:
	var mode: String = report.get("mode", "SESSION")
	var duration: float = report.get("duration", 0.0)
	var score: int = report.get("score", 0)
	_subtitle.text = "%s · %d s" % [mode, roundi(duration)]
	_score_value.text = str(score)


func _fill_kpis(report: Dictionary) -> void:
	for child in _kpi_grid.get_children():
		_kpi_grid.remove_child(child)
		child.queue_free()

	var shots: int = report.get("shots", 0)
	var hits: int = report.get("hits", 0)
	var misses: int = report.get("misses", 0)
	var accuracy: float = report.get("accuracy", 0.0)
	var avg_ttk: float = report.get("avg_ttk_ms", 0.0)
	var median_ttk: float = report.get("median_ttk_ms", 0.0)
	var best_ttk: float = report.get("best_ttk_ms", 0.0)
	var kills_per_second: float = report.get("kills_per_second", 0.0)
	var peak_speed: float = report.get("avg_peak_speed", 0.0)
	var flick_distance: float = report.get("avg_flick_distance_deg", 0.0)

	_add_kpi("PRÉCISION", "%.1f %%" % accuracy if shots > 0 else "—", "%d touchés / %d tirs" % [hits, shots])
	_add_kpi("TEMPS MOYEN ENTRE CIBLES", "%d ms" % roundi(avg_ttk) if hits > 1 else "—",
			"médiane %d ms · record %d ms" % [roundi(median_ttk), roundi(best_ttk)])
	_add_kpi("CIBLES DÉTRUITES", str(hits), "%.2f cibles / seconde" % kills_per_second)
	_add_kpi("TIRS RATÉS", str(misses), "pénalité de score à chaque tir raté")
	_add_kpi("VITESSE DE POINTE MOY.", "%d °/s" % roundi(peak_speed) if peak_speed > 0.0 else "—", "pendant les flicks")
	_add_kpi("AMPLITUDE MOY. DES FLICKS", "%.1f°" % flick_distance if flick_distance > 0.0 else "—", "distance angulaire à parcourir")


func _fill_flicks(report: Dictionary) -> void:
	var flicks: int = report.get("flick_count", 0)
	var over_count: int = report.get("overflick_count", 0)
	var under_count: int = report.get("underflick_count", 0)
	var precise_count: int = report.get("precise_count", 0)
	var over_rate: float = report.get("overflick_rate", 0.0)
	var under_rate: float = report.get("underflick_rate", 0.0)
	var precise_rate: float = report.get("precise_rate", 0.0)
	var overshoot: float = report.get("avg_overshoot_deg", 0.0)
	var undershoot: float = report.get("avg_undershoot_deg", 0.0)
	var bias: float = report.get("flick_bias_deg", 0.0)

	_flick_bar.set_distribution(float(under_count), float(precise_count), float(over_count))
	if flicks <= 0:
		_flick_details.text = "Pas assez de mouvements rapides pour analyser les flicks (amplitude minimale : 3°)."
		return

	var lines := PackedStringArray()
	lines.append("Overflick : %.0f %% (%d flicks) · dépassement moyen %.2f° au-delà du centre de la cible" % [
		over_rate, over_count, overshoot])
	lines.append("Underflick : %.0f %% (%d flicks) · arrêt moyen %.2f° avant le centre de la cible" % [
		under_rate, under_count, undershoot])
	lines.append("Précis : %.0f %% (%d flicks) · %d flicks analysés, erreur signée moyenne %+.2f°" % [
		precise_rate, precise_count, flicks, bias])
	lines.append(_flick_advice(over_rate, under_rate))
	_flick_details.text = "\n".join(lines)


func _flick_advice(over_rate: float, under_rate: float) -> String:
	if over_rate < 12.0 and under_rate < 12.0:
		return "Diagnostic : flicks bien calibrés, le premier mouvement termine presque toujours dans la cible."
	if over_rate > under_rate * 1.5:
		return "Diagnostic : tendance à l'overflick. Freinez plus tôt, ou testez une sensibilité légèrement plus basse (cm/360° plus élevé)."
	if under_rate > over_rate * 1.5:
		return "Diagnostic : tendance à l'underflick. Engagez davantage le mouvement, ou testez une sensibilité légèrement plus haute (cm/360° plus bas)."
	return "Diagnostic : erreurs réparties des deux côtés. Travaillez la régularité de l'amplitude avant de toucher à la sensibilité."


func _fill_smoothness(report: Dictionary) -> void:
	var smoothness: float = report.get("smoothness", 0.0)
	var samples: int = report.get("smoothness_samples", 0)
	var accel_std: float = report.get("accel_std", 0.0)
	if samples <= 0:
		_smooth_value.text = "— / 100"
		_smooth_gauge.value = 0.0
		_smooth_details.text = "Pas assez de mouvements pour estimer la fluidité."
		return
	_smooth_value.text = "%d / 100" % roundi(smoothness)
	_smooth_gauge.value = smoothness
	_smooth_details.text = "%s\nCalculé sur %d mouvements à partir de la variance de l'accélération angulaire, rapportée à la variance minimale théorique pour la même amplitude et la même durée (100 = profil « minimum-jerk »). Accélération RMS : %d °/s²." % [
		_smoothness_label(smoothness), samples, roundi(accel_std)]


func _smoothness_label(smoothness: float) -> String:
	if smoothness >= 80.0:
		return "Mouvements très fluides : un seul geste balistique, sans corrections parasites."
	if smoothness >= 60.0:
		return "Mouvements fluides, avec quelques micro-corrections en fin de flick."
	if smoothness >= 40.0:
		return "Mouvements saccadés : plusieurs corrections successives avant le tir."
	return "Mouvements très irréguliers (jitter) : relâchez la prise et privilégiez un geste continu."


func _fill_heatmap(report: Dictionary) -> void:
	var misses: PackedVector2Array = report.get("miss_offsets", PackedVector2Array())
	var hits: PackedVector2Array = report.get("hit_offsets", PackedVector2Array())
	var bias: Vector2 = report.get("miss_bias_deg", Vector2.ZERO)
	var distance: float = report.get("avg_miss_distance_deg", 0.0)
	_heatmap.set_data(misses, hits)
	if misses.is_empty():
		_heat_legend.text = "Aucun tir raté. Les points cyan représentent les tirs réussis."
		return
	_heat_legend.text = "%d tirs ratés (magenta), tirs réussis en cyan. Écart moyen au centre : %.2f°. Biais moyen : %s. Échelle en rayons de cible (R)." % [
		misses.size(), distance, _bias_text(bias)]


func _bias_text(bias: Vector2) -> String:
	if bias.length() < 0.15:
		return "aucun biais marqué"
	var parts := PackedStringArray()
	if absf(bias.x) >= 0.1:
		parts.append("%.2f° à %s" % [absf(bias.x), "droite" if bias.x > 0.0 else "gauche"])
	if absf(bias.y) >= 0.1:
		parts.append("%.2f° vers le %s" % [absf(bias.y), "haut" if bias.y > 0.0 else "bas"])
	return ", ".join(parts)


func _fill_footer(report: Dictionary) -> void:
	var sample_count: int = report.get("sample_count", 0)
	var sample_rate: float = report.get("sample_rate_hz", 0.0)
	var input_rate: float = report.get("input_rate_hz", 0.0)
	_footer_info.text = "Télémétrie : %d échantillons à %d Hz · angles de visée rafraîchis à ~%d Hz (FPS moyen) · %.1f cm/360° à %d DPI" % [
		sample_count, roundi(sample_rate), roundi(input_rate), GameSettings.cm_per_360, roundi(GameSettings.dpi)]


# ---------------------------------------------------------------------------
# Cartes KPI
# ---------------------------------------------------------------------------

func _add_kpi(caption: String, value: String, hint: String) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	card.add_child(box)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.theme_type_variation = &"CaptionLabel"
	box.add_child(caption_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.theme_type_variation = &"ValueLabel"
	box.add_child(value_label)

	var hint_label := Label.new()
	hint_label.text = hint
	hint_label.theme_type_variation = &"CaptionLabel"
	box.add_child(hint_label)

	_kpi_grid.add_child(card)
