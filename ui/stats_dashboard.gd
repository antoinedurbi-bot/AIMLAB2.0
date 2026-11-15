extends Control
## Écran de fin de session : conseil du coach, cartes KPI de l'exercice,
## panneaux d'analyse (graphique par répétition, flicks et fluidité, heatmap)
## et, sur demande, la liste complète des données collectées.

signal replay_requested
signal menu_requested

const FlickBar := preload("res://ui/flick_bar.gd")
const Heatmap := preload("res://ui/heatmap.gd")
const BarChart := preload("res://ui/bar_chart.gd")

## Délai avant d'activer les boutons : évite qu'un clic de fin de session ne
## relance ou ne ferme le rapport par accident.
const INPUT_LOCK_SECONDS := 0.6
const TONE_COLORS := {
	"fix": Color(1.0, 0.45, 0.6),
	"good": Color(0.3, 1.0, 0.72),
	"info": Color(0.6, 0.9, 1.0),
}

@onready var _subtitle: Label = %Subtitle
@onready var _score_value: Label = %ScoreValue
@onready var _score_trend: Label = %ScoreTrend
@onready var _coach_title: Label = %CoachTitle
@onready var _coach_text: Label = %CoachText
@onready var _coach_action: Label = %CoachAction
@onready var _coach_cards: HBoxContainer = %CoachCards
@onready var _kpi_grid: GridContainer = %KpiGrid
@onready var _analysis: HBoxContainer = %Analysis
@onready var _chart_panel: PanelContainer = %ChartPanel
@onready var _chart: BarChart = %Chart
@onready var _flick_panel: PanelContainer = %FlickPanel
@onready var _flick_bar: FlickBar = %FlickBar
@onready var _flick_details: Label = %FlickDetails
@onready var _smooth_value: Label = %SmoothValue
@onready var _smooth_gauge: ProgressBar = %SmoothGauge
@onready var _smooth_details: Label = %SmoothDetails
@onready var _heat_panel: PanelContainer = %HeatPanel
@onready var _heatmap: Heatmap = %Heatmap
@onready var _heat_legend: Label = %HeatLegend
@onready var _data_panel: PanelContainer = %DataPanel
@onready var _data_title: Label = %DataTitle
@onready var _data_grid: GridContainer = %DataGrid
@onready var _footer_info: Label = %FooterInfo
@onready var _data_button: Button = %DataButton
@onready var _back_button: Button = %BackButton
@onready var _replay_button: Button = %ReplayButton


func _ready() -> void:
	_replay_button.pressed.connect(_on_replay_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_data_button.toggled.connect(_on_data_toggled)


## Affiche le rapport d'une session terminée.
## `advice` : conseils du coach, du plus au moins prioritaire.
## `previous` : sessions précédentes du même exercice (la plus récente en premier).
func show_report(drill_title: String, report: Dictionary, advice: Array[Dictionary], previous: Array[Dictionary]) -> void:
	visible = true
	_fill_header(drill_title, report, previous)
	_fill_coach(advice)
	_fill_kpis(report)
	_fill_panels(report)
	_fill_data(report)
	_fill_footer(report)
	_data_button.set_pressed_no_signal(false)
	_on_data_toggled(false)
	_lock_buttons()


func _on_replay_pressed() -> void:
	replay_requested.emit()


func _on_back_pressed() -> void:
	menu_requested.emit()


func _on_data_toggled(pressed: bool) -> void:
	_data_panel.visible = pressed
	_analysis.visible = not pressed
	_data_button.text = "ANALYSE" if pressed else "TOUTES LES DONNÉES"


func _lock_buttons() -> void:
	_replay_button.disabled = true
	_back_button.disabled = true
	await get_tree().create_timer(INPUT_LOCK_SECONDS).timeout
	_replay_button.disabled = false
	_back_button.disabled = false
	if is_visible_in_tree():
		_replay_button.grab_focus()


# ---------------------------------------------------------------------------
# En-tête, coach, KPI
# ---------------------------------------------------------------------------

func _fill_header(drill_title: String, report: Dictionary, previous: Array[Dictionary]) -> void:
	var elapsed: float = report.get("elapsed", 0.0)
	var score: int = report.get("score", 0)
	_subtitle.text = "%s · %d s" % [drill_title, roundi(elapsed)]
	_score_value.text = str(score)
	if previous.is_empty():
		_score_trend.text = "SCORE · première session de cet exercice"
		return
	var best := 0
	var total := 0
	for entry in previous:
		var past_score: int = int(entry.get("score", 0))
		best = maxi(best, past_score)
		total += past_score
	@warning_ignore("integer_division")
	var average := total / previous.size()
	_score_trend.text = "SCORE · record %d · moyenne des %d dernières : %d" % [best, previous.size(), average]


func _fill_coach(advice: Array[Dictionary]) -> void:
	for child in _coach_cards.get_children():
		_coach_cards.remove_child(child)
		child.queue_free()
	if advice.is_empty():
		_coach_title.text = "—"
		_coach_text.text = ""
		_coach_action.text = ""
		return
	var main := advice[0]
	var tone: String = main.get("tone", "info")
	var tone_color: Color = TONE_COLORS.get(tone, Color.WHITE)
	var parts := _split_advice(str(main.get("text", "")))
	_coach_title.text = main.get("title", "")
	_coach_title.add_theme_color_override(&"font_color", tone_color)
	_coach_text.text = parts[0]
	_coach_action.text = parts[1] if parts[1] != "" else "Continue ainsi."

	# Pistes secondaires : une carte par conseil, côte à côte.
	for index in range(1, advice.size()):
		var item := advice[index]
		var item_tone: String = item.get("tone", "info")
		var item_color: Color = TONE_COLORS.get(item_tone, Color.WHITE)
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanel"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := VBoxContainer.new()
		box.add_theme_constant_override(&"separation", 2)
		card.add_child(box)
		var title_label := Label.new()
		title_label.text = str(item.get("title", ""))
		title_label.add_theme_color_override(&"font_color", item_color)
		title_label.add_theme_font_size_override(&"font_size", 17)
		box.add_child(title_label)
		var text_label := Label.new()
		text_label.text = str(item.get("text", ""))
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.custom_minimum_size.x = 300.0
		text_label.add_theme_font_size_override(&"font_size", 14)
		text_label.add_theme_color_override(&"font_color", Color(0.72, 0.79, 0.88))
		box.add_child(text_label)
		_coach_cards.add_child(card)
	_coach_cards.visible = advice.size() > 1


## Sépare un conseil en deux : le constat (première phrase, celle qui cite les
## chiffres) et l'action à mener (la suite).
func _split_advice(text: String) -> PackedStringArray:
	var cut := text.find(". ")
	var colon := text.find(" : ")
	if colon >= 0 and (cut < 0 or colon < cut) and colon < 140:
		return PackedStringArray([text.substr(0, colon) + ".", text.substr(colon + 3, 1).to_upper() + text.substr(colon + 4)])
	if cut < 0:
		return PackedStringArray([text, ""])
	return PackedStringArray([text.substr(0, cut + 1), text.substr(cut + 2)])


func _fill_kpis(report: Dictionary) -> void:
	for child in _kpi_grid.get_children():
		_kpi_grid.remove_child(child)
		child.queue_free()
	var kpis: Array = report.get("kpis", [])
	for item: Variant in kpis:
		if item is Dictionary:
			var kpi: Dictionary = item
			var label: String = kpi.get("label", "")
			var value: String = kpi.get("value", "—")
			var hint: String = kpi.get("hint", "")
			_add_kpi(label, value, hint)


func _add_kpi(caption: String, value: String, hint: String) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 0)
	card.add_child(box)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.theme_type_variation = &"CaptionLabel"
	box.add_child(caption_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.theme_type_variation = &"ValueLabel"
	value_label.add_theme_font_size_override(&"font_size", 25)
	box.add_child(value_label)

	var hint_label := Label.new()
	hint_label.text = hint
	hint_label.theme_type_variation = &"CaptionLabel"
	hint_label.clip_text = true
	box.add_child(hint_label)

	_kpi_grid.add_child(card)


# ---------------------------------------------------------------------------
# Panneaux d'analyse
# ---------------------------------------------------------------------------

func _fill_panels(report: Dictionary) -> void:
	var panels: Array = report.get("panels", ["flicks", "heatmap"])
	var chart_value: Variant = report.get("chart")

	_chart_panel.visible = panels.has("chart") and chart_value is Dictionary
	if _chart_panel.visible:
		var chart: Dictionary = chart_value
		_chart.set_chart(chart)

	_flick_panel.visible = panels.has("flicks")
	if _flick_panel.visible:
		_fill_flicks(report)
		_fill_smoothness(report)

	_heat_panel.visible = panels.has("heatmap")
	if _heat_panel.visible:
		_fill_heatmap(report)


func _fill_flicks(report: Dictionary) -> void:
	var flicks: int = report.get("flick_count", 0)
	var over_count: int = report.get("overflick_count", 0)
	var under_count: int = report.get("underflick_count", 0)
	var precise_count: int = report.get("precise_count", 0)
	var over_rate: float = report.get("overflick_rate", 0.0)
	var under_rate: float = report.get("underflick_rate", 0.0)
	var overshoot: float = report.get("avg_overshoot_deg", 0.0)
	var undershoot: float = report.get("avg_undershoot_deg", 0.0)
	var bias: float = report.get("flick_bias_deg", 0.0)

	_flick_bar.set_distribution(float(under_count), float(precise_count), float(over_count))
	if flicks <= 0:
		_flick_details.text = "Pas assez de mouvements rapides pour analyser les flicks (amplitude minimale : 3°)."
		return
	_flick_details.text = "Overflick %.0f %% (%d) · dépassement moyen %.2f°\nUnderflick %.0f %% (%d) · arrêt moyen %.2f° avant la cible\n%d flicks analysés · erreur signée moyenne %+.2f°" % [
		over_rate, over_count, overshoot, under_rate, under_count, undershoot, flicks, bias]


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
	_smooth_details.text = "%s Variance de l'accélération angulaire sur %d mouvements (100 = geste idéal). Accélération RMS : %d °/s²." % [
		_smoothness_label(smoothness), samples, roundi(accel_std)]


func _smoothness_label(smoothness: float) -> String:
	if smoothness >= 80.0:
		return "Gestes très fluides."
	if smoothness >= 60.0:
		return "Gestes fluides, quelques micro-corrections."
	if smoothness >= 40.0:
		return "Gestes saccadés : plusieurs corrections avant le tir."
	return "Gestes très irréguliers (jitter)."


func _fill_heatmap(report: Dictionary) -> void:
	var misses: PackedVector2Array = report.get("miss_offsets", PackedVector2Array())
	var hits: PackedVector2Array = report.get("hit_offsets", PackedVector2Array())
	var bias: Vector2 = report.get("miss_bias_deg", Vector2.ZERO)
	var distance: float = report.get("avg_miss_distance_deg", 0.0)
	_heatmap.set_data(misses, hits)
	if misses.is_empty():
		_heat_legend.text = "Aucun tir raté analysable. Les points cyan sont les tirs réussis."
		return
	_heat_legend.text = "%d tirs ratés (magenta), réussis en cyan. Écart moyen %.2f°. Biais : %s. Échelle en rayons de cible (R)." % [
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


# ---------------------------------------------------------------------------
# Toutes les données
# ---------------------------------------------------------------------------

## Liste chaque statistique scalaire du rapport (nom technique → valeur), triée par nom.
func _fill_data(report: Dictionary) -> void:
	for child in _data_grid.get_children():
		_data_grid.remove_child(child)
		child.queue_free()

	var names := PackedStringArray()
	for key: Variant in report:
		var value: Variant = report[key]
		if value is int or value is float or value is bool or value is String:
			names.append(str(key))
	names.sort()
	for stat_name in names:
		var name_label := Label.new()
		name_label.text = stat_name
		name_label.theme_type_variation = &"CaptionLabel"
		_data_grid.add_child(name_label)
		var value_label := Label.new()
		value_label.text = _format_value(report[stat_name])
		value_label.add_theme_font_size_override(&"font_size", 15)
		_data_grid.add_child(value_label)

	var export_path: String = report.get("export_path", "")
	var shot_count: int = report.get("shots", 0)
	var event_count: int = report.get("event_count", 0)
	var sample_count: int = report.get("sample_count", 0)
	var summary := "%d STATISTIQUES · %d échantillons · %d tirs · %d événements" % [
		names.size(), sample_count, shot_count, event_count]
	if export_path != "":
		summary += " · export brut : %s" % export_path
	_data_title.text = summary


func _format_value(value: Variant) -> String:
	if value is bool:
		return "oui" if value else "non"
	if value is float:
		var number: float = value
		if absf(number) >= 1000.0:
			return "%d" % roundi(number)
		return "%.2f" % number
	return str(value)


func _fill_footer(report: Dictionary) -> void:
	var sample_count: int = report.get("sample_count", 0)
	var sample_rate: float = report.get("sample_rate_hz", 0.0)
	var input_rate: float = report.get("input_rate_hz", 0.0)
	var mouse_distance: float = report.get("mouse_distance_cm", 0.0)
	_footer_info.text = "%d échantillons à %d Hz · visée rafraîchie à ~%d Hz · souris : %.1f m parcourus · %.1f cm/360° à %d DPI" % [
		sample_count, roundi(sample_rate), roundi(input_rate), mouse_distance / 100.0,
		GameSettings.cm_per_360, roundi(GameSettings.dpi)]
