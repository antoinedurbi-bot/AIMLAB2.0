extends Control
## Menu principal : choix de l'exercice, lancement de la session et réglages
## (sensibilité, réticule, graphismes, son et données). La liste des exercices
## et les lignes de réglages sont construites par code pour garder la scène lisible.

## Émis avec l'identifiant de l'exercice choisi.
## `map_path` / `map_name` sont vides pour les exercices à carte fixe.
signal play_requested(drill_id: String, map_path: String, map_name: String)
signal quit_requested

const DrillCatalog := preload("res://scripts/drills/drill_catalog.gd")

const CROSSHAIR_STYLES := ["Croix", "Croix + point", "Point", "Cercle + point"]
const QUALITY_LEVELS := ["Performance", "Qualité (SSAO, MSAA 4x)", "Ultra (+ SDFGI, SSR)"]

## Vrai pendant qu'on écrit dans les champs par code : les signaux sont ignorés.
var _updating: bool = false

var _dpi_spin: SpinBox
var _cm_spin: SpinBox
var _game_option: OptionButton
var _game_sens_spin: SpinBox
var _sens_summary: Label
var _selected_drill: String = "gridshot"

@onready var _play_button: Button = %PlayButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings_list: VBoxContainer = %SettingsList
@onready var _drill_grid: GridContainer = %DrillGrid
@onready var _mode_name: Label = %ModeName
@onready var _mode_focus: Label = %ModeFocus
@onready var _mode_description: Label = %ModeDescription
@onready var _mode_stats: Label = %ModeStats
@onready var _map_row: HBoxContainer = %MapRow
@onready var _map_option: OptionButton = %MapOption


func _ready() -> void:
	_play_button.pressed.connect(_on_play_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	visibility_changed.connect(_on_visibility_changed)
	_map_option.item_selected.connect(_on_map_selected)
	_build_drill_list()
	_build_sensitivity_section()
	_build_crosshair_section()
	_build_graphics_section()
	_build_audio_section()
	_refresh_sensitivity_fields()
	_on_visibility_changed()


func _on_play_pressed() -> void:
	GameSettings.last_drill = _selected_drill
	GameSettings.save_settings()
	play_requested.emit(_selected_drill, _selected_map("path"), _selected_map("name"))


func _on_quit_pressed() -> void:
	quit_requested.emit()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh_drill_stats()
		_play_button.grab_focus.call_deferred()


# ---------------------------------------------------------------------------
# Exercices
# ---------------------------------------------------------------------------

func _build_drill_list() -> void:
	var known: Dictionary = DrillCatalog.find(GameSettings.last_drill)
	_selected_drill = known.get("id", "gridshot")
	var group := ButtonGroup.new()
	for item: Variant in DrillCatalog.DRILLS:
		var entry: Dictionary = item
		var drill_id: String = entry.get("id", "")
		var button := Button.new()
		button.text = "%s   ·   %s" % [entry.get("title", ""), entry.get("tag", "")]
		button.theme_type_variation = &"DrillButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_pressed_no_signal(drill_id == _selected_drill)
		button.pressed.connect(_on_drill_pressed.bind(drill_id))
		_drill_grid.add_child(button)
	_show_drill(_selected_drill)


func _on_map_selected(_index: int) -> void:
	_refresh_drill_stats()


func _on_drill_pressed(drill_id: String) -> void:
	_show_drill(drill_id)


func _show_drill(drill_id: String) -> void:
	var entry: Dictionary = DrillCatalog.find(drill_id)
	_selected_drill = entry.get("id", "gridshot")
	var duration: float = entry.get("duration", 60.0)
	_mode_name.text = "%s · %d s max" % [entry.get("title", ""), roundi(duration)]
	_mode_focus.text = entry.get("focus", "")
	_mode_description.text = entry.get("description", "")
	var maps: Array = entry.get("maps", [])
	var previous_choice := _map_option.selected
	_map_option.clear()
	for item: Variant in maps:
		var map_entry: Dictionary = item
		_map_option.add_item(str(map_entry.get("name", "")))
	_map_row.visible = not maps.is_empty()
	if not maps.is_empty():
		_map_option.select(clampi(previous_choice, 0, maps.size() - 1))
	_refresh_drill_stats()


## Champ (« path » ou « name ») de la carte choisie, vide si l'exercice a une carte fixe.
func _selected_map(field: String) -> String:
	var entry: Dictionary = DrillCatalog.find(_selected_drill)
	var maps: Array = entry.get("maps", [])
	if maps.is_empty():
		return ""
	var map_entry: Dictionary = maps[clampi(_map_option.selected, 0, maps.size() - 1)]
	return str(map_entry.get(field, ""))


## Clé d'historique : un exercice joué sur plusieurs cartes a un historique par carte.
func _history_key() -> String:
	var map_name := _selected_map("name")
	return _selected_drill if map_name == "" else "%s@%s" % [_selected_drill, map_name]


func _refresh_drill_stats() -> void:
	var sessions: int = SessionHistory.session_count(_history_key())
	if sessions <= 0:
		_mode_stats.text = "Aucune session enregistrée pour cet exercice"
	else:
		var best: int = SessionHistory.best_score(_history_key())
		_mode_stats.text = "%d sessions enregistrées · record : %d points" % [sessions, best]


# ---------------------------------------------------------------------------
# Sensibilité
# ---------------------------------------------------------------------------

func _build_sensitivity_section() -> void:
	_add_section("SENSIBILITÉ")

	_dpi_spin = _make_spin(50.0, 32000.0, 50.0, GameSettings.dpi, "")
	_dpi_spin.value_changed.connect(_on_dpi_changed)
	_add_row("DPI de la souris", _dpi_spin)

	_cm_spin = _make_spin(1.0, 300.0, 0.01, GameSettings.cm_per_360, " cm")
	_cm_spin.value_changed.connect(_on_cm_changed)
	_add_row("Distance pour 360°", _cm_spin)

	_game_option = OptionButton.new()
	for game: String in GameSettings.GAMES:
		_game_option.add_item(game)
	_game_option.select(GameSettings.reference_game)
	_game_option.item_selected.connect(_on_game_selected)
	_add_row("Convertir depuis / vers", _game_option)

	_game_sens_spin = _make_spin(0.001, 100.0, 0.001, 1.0, "")
	_game_sens_spin.value_changed.connect(_on_game_sens_changed)
	_add_row("Sensibilité dans ce jeu", _game_sens_spin)

	_sens_summary = Label.new()
	_sens_summary.theme_type_variation = &"CaptionLabel"
	_sens_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_list.add_child(_sens_summary)

	var fov_spin := _make_spin(60.0, 130.0, 1.0, GameSettings.fov_horizontal, "°")
	fov_spin.value_changed.connect(_on_fov_changed)
	_add_row("FOV horizontal (16:9)", fov_spin)


func _selected_game() -> String:
	var game: String = GameSettings.game_name(GameSettings.reference_game)
	return game


func _on_dpi_changed(value: float) -> void:
	if _updating:
		return
	# Le cm/360° est conservé : seule la sensibilité « en jeu » équivalente change.
	GameSettings.dpi = value
	_commit_sensitivity()


func _on_cm_changed(value: float) -> void:
	if _updating:
		return
	GameSettings.cm_per_360 = value
	_commit_sensitivity()


func _on_game_selected(index: int) -> void:
	GameSettings.reference_game = index
	_commit_sensitivity()


func _on_game_sens_changed(value: float) -> void:
	if _updating:
		return
	var converted: float = GameSettings.game_sens_to_cm(_selected_game(), value)
	GameSettings.cm_per_360 = clampf(converted, 1.0, 300.0)
	_commit_sensitivity()


func _on_fov_changed(value: float) -> void:
	GameSettings.fov_horizontal = value
	_commit_sensitivity()


func _commit_sensitivity() -> void:
	GameSettings.commit_sensitivity()
	_refresh_sensitivity_fields()


func _refresh_sensitivity_fields() -> void:
	_updating = true
	var cm: float = GameSettings.cm_per_360
	_dpi_spin.value = GameSettings.dpi
	_cm_spin.value = cm
	var game_sens: float = GameSettings.cm_to_game_sens(_selected_game(), cm)
	_game_sens_spin.value = game_sens

	var parts := PackedStringArray()
	for game: String in GameSettings.GAMES:
		var equivalent: float = GameSettings.cm_to_game_sens(game, cm)
		parts.append("%s %.3f" % [game, equivalent])
	var counts: float = GameSettings.counts_per_360()
	var per_count: float = GameSettings.degrees_per_count()
	_sens_summary.text = "Équivalences : %s\n%d counts pour 360° · %.4f° par count · entrée brute, sans accélération" % [
		" · ".join(parts), roundi(counts), per_count]
	_updating = false


# ---------------------------------------------------------------------------
# Réticule
# ---------------------------------------------------------------------------

func _build_crosshair_section() -> void:
	_add_section("RÉTICULE")

	var style_option := OptionButton.new()
	for style_name: String in CROSSHAIR_STYLES:
		style_option.add_item(style_name)
	style_option.select(GameSettings.crosshair_style)
	style_option.item_selected.connect(_on_crosshair_style_selected)
	_add_row("Forme", style_option)

	var color_button := ColorPickerButton.new()
	color_button.color = GameSettings.crosshair_color
	color_button.edit_alpha = false
	color_button.custom_minimum_size.y = 34.0
	color_button.color_changed.connect(_on_crosshair_color_changed)
	_add_row("Couleur", color_button)

	_add_crosshair_spin("Longueur des branches", &"crosshair_length", 0.0, 40.0, 1.0, " px")
	_add_crosshair_spin("Épaisseur", &"crosshair_thickness", 1.0, 10.0, 1.0, " px")
	_add_crosshair_spin("Écart central", &"crosshair_gap", 0.0, 30.0, 1.0, " px")
	_add_crosshair_spin("Taille du point", &"crosshair_dot_size", 1.0, 12.0, 1.0, " px")
	_add_crosshair_spin("Opacité", &"crosshair_opacity", 0.1, 1.0, 0.05, "")

	var outline_check := CheckBox.new()
	outline_check.text = "Activé"
	outline_check.button_pressed = GameSettings.crosshair_outline
	outline_check.toggled.connect(_on_crosshair_outline_toggled)
	_add_row("Contour noir", outline_check)


func _add_crosshair_spin(caption: String, property: StringName, minimum: float, maximum: float, step: float, suffix: String) -> void:
	var current: float = GameSettings.get(property)
	var spin := _make_spin(minimum, maximum, step, current, suffix)
	spin.value_changed.connect(_on_crosshair_value_changed.bind(property))
	_add_row(caption, spin)


func _on_crosshair_value_changed(value: float, property: StringName) -> void:
	GameSettings.set(property, value)
	_commit_crosshair()


func _on_crosshair_style_selected(index: int) -> void:
	GameSettings.crosshair_style = index
	_commit_crosshair()


func _on_crosshair_color_changed(color: Color) -> void:
	GameSettings.crosshair_color = color
	_commit_crosshair()


func _on_crosshair_outline_toggled(enabled: bool) -> void:
	GameSettings.crosshair_outline = enabled
	_commit_crosshair()


func _commit_crosshair() -> void:
	GameSettings.commit_crosshair()


# ---------------------------------------------------------------------------
# Graphismes
# ---------------------------------------------------------------------------

func _build_graphics_section() -> void:
	_add_section("GRAPHISMES")

	var quality_option := OptionButton.new()
	for level: String in QUALITY_LEVELS:
		quality_option.add_item(level)
	quality_option.select(GameSettings.quality)
	quality_option.item_selected.connect(_on_quality_selected)
	_add_row("Qualité", quality_option)

	var fps_spin := _make_spin(0.0, 1000.0, 10.0, float(GameSettings.max_fps), " FPS")
	fps_spin.value_changed.connect(_on_max_fps_changed)
	_add_row("Limite d'images (0 = illimité)", fps_spin)

	var vsync_check := CheckBox.new()
	vsync_check.text = "Activée (ajoute de la latence)"
	vsync_check.button_pressed = GameSettings.vsync
	vsync_check.toggled.connect(_on_vsync_toggled)
	_add_row("V-Sync", vsync_check)

	var fullscreen_check := CheckBox.new()
	fullscreen_check.text = "Activé (F11)"
	fullscreen_check.button_pressed = GameSettings.fullscreen
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_add_row("Plein écran", fullscreen_check)


func _on_quality_selected(index: int) -> void:
	GameSettings.quality = index
	_commit_graphics()


func _on_max_fps_changed(value: float) -> void:
	GameSettings.max_fps = roundi(value)
	_commit_graphics()


func _on_vsync_toggled(enabled: bool) -> void:
	GameSettings.vsync = enabled
	_commit_graphics()


func _on_fullscreen_toggled(enabled: bool) -> void:
	GameSettings.fullscreen = enabled
	_commit_graphics()


func _commit_graphics() -> void:
	GameSettings.commit_graphics()


# ---------------------------------------------------------------------------
# Son et données
# ---------------------------------------------------------------------------

func _build_audio_section() -> void:
	_add_section("SON ET DONNÉES")

	var volume_spin := _make_spin(0.0, 100.0, 5.0, GameSettings.sfx_volume * 100.0, " %")
	volume_spin.value_changed.connect(_on_volume_changed)
	_add_row("Volume des effets", volume_spin)

	var export_check := CheckBox.new()
	export_check.text = "CSV + JSON dans user://telemetry"
	export_check.button_pressed = GameSettings.export_raw_telemetry
	export_check.toggled.connect(_on_export_toggled)
	_add_row("Export de la télémétrie brute", export_check)


func _on_volume_changed(value: float) -> void:
	GameSettings.sfx_volume = value / 100.0
	GameSettings.commit_audio()
	Sfx.play(&"hit")


func _on_export_toggled(enabled: bool) -> void:
	GameSettings.export_raw_telemetry = enabled
	GameSettings.save_settings()


# ---------------------------------------------------------------------------
# Construction des lignes
# ---------------------------------------------------------------------------

func _add_section(title: String) -> void:
	if _settings_list.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 8.0
		_settings_list.add_child(gap)
	var label := Label.new()
	label.text = title
	label.theme_type_variation = &"SectionLabel"
	_settings_list.add_child(label)


func _add_row(caption: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	control.custom_minimum_size.x = 250.0
	row.add_child(control)
	_settings_list.add_child(row)


func _make_spin(minimum: float, maximum: float, step: float, current: float, suffix: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = current
	spin.suffix = suffix
	spin.select_all_on_focus = true
	return spin
