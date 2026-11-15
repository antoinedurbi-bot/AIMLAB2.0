extends Control
## Menu principal : choix de l'exercice, lancement de la session et réglages
## (sensibilité, réticule, graphismes, son et données). La liste des exercices
## et les lignes de réglages sont construites par code pour garder la scène lisible.

## Émis avec l'identifiant de l'exercice choisi.
## `map_path` / `map_name` sont vides pour les exercices à carte fixe.
signal play_requested(drill_id: String, map_path: String, map_name: String)
signal quit_requested

const DrillCatalog := preload("res://scripts/drills/drill_catalog.gd")
const TrainingPlan := preload("res://scripts/training_plan.gd")
const RadarChart := preload("res://ui/radar_chart.gd")
const Weapons := preload("res://scripts/weapons.gd")

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
var _profile_label: Label
var _radar: RadarChart
var _routine_label: Label
var _routine_button: Button
var _next_routine_drill: String = ""
var _drill_buttons: Dictionary = {}
## Contrôles de l'éditeur de réticule, pour les resynchroniser après un import.
var _crosshair_spins: Dictionary = {}
var _crosshair_style_option: OptionButton
var _crosshair_color_button: ColorPickerButton
var _crosshair_outline_check: CheckBox
var _crosshair_code_edit: LineEdit
var _crosshair_status: Label

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
	_build_profile_section()
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
		_refresh_profile()
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
		button.text = str(entry.get("title", ""))
		button.tooltip_text = str(entry.get("focus", ""))
		button.clip_text = true
		button.theme_type_variation = &"DrillButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_pressed_no_signal(drill_id == _selected_drill)
		button.pressed.connect(_on_drill_pressed.bind(drill_id))
		_drill_grid.add_child(button)
		_drill_buttons[drill_id] = button
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
# Profil et routine du jour
# ---------------------------------------------------------------------------

func _build_profile_section() -> void:
	_add_section("PROFIL ET ROUTINE DU JOUR")
	_radar = RadarChart.new()
	_radar.custom_minimum_size = Vector2(0.0, 250.0)
	_settings_list.add_child(_radar)
	_profile_label = Label.new()
	_profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_list.add_child(_profile_label)
	_routine_label = Label.new()
	_routine_label.theme_type_variation = &"CaptionLabel"
	_routine_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_list.add_child(_routine_label)
	_routine_button = Button.new()
	_routine_button.pressed.connect(_on_routine_pressed)
	_settings_list.add_child(_routine_button)


## Met à jour les notes du diagnostic et la liste des sessions restantes aujourd'hui.
func _refresh_profile() -> void:
	if _profile_label == null:
		return
	_radar.set_profile(PlayerProfile.radar_labels(), PlayerProfile.radar_values())
	var has_benchmark: bool = PlayerProfile.has_benchmark()
	var ordered: Array[String] = PlayerProfile.skills_by_weakness()
	if has_benchmark:
		var latest: Dictionary = PlayerProfile.latest_benchmark()
		var notes := PackedStringArray()
		for skill: String in PlayerProfile.SKILLS:
			var note: float = latest.get(skill, 0.0)
			notes.append("%s %d" % [PlayerProfile.skill_name(skill), roundi(note)])
		var overall: float = latest.get("overall", 0.0)
		_profile_label.text = "Diagnostic : %s (moyenne %d / 100)\nPriorité : %s" % [
			"  ·  ".join(notes), roundi(overall), PlayerProfile.skill_name(ordered[0])]
	else:
		_profile_label.text = "Aucun diagnostic. Passe-le (2 minutes) pour obtenir une routine adaptée à ton point faible."

	var plan: Array[Dictionary] = TrainingPlan.build(ordered, has_benchmark)
	var lines := PackedStringArray()
	_next_routine_drill = ""
	for item in plan:
		var drill_id: String = item.get("drill_id", "")
		var wanted: int = item.get("sessions", 0)
		var done: int = mini(PlayerProfile.sessions_today(drill_id), wanted)
		var entry: Dictionary = DrillCatalog.find(drill_id)
		var mark := "✓" if done >= wanted else "○"
		lines.append("%s  %s — %d / %d sessions · %s" % [mark, entry.get("title", drill_id), done, wanted, item.get("reason", "")])
		if done < wanted and _next_routine_drill == "":
			_next_routine_drill = drill_id
	_routine_label.text = "Routine du jour (environ %d min)\n%s" % [roundi(TrainingPlan.total_minutes(plan)), "\n".join(lines)]

	if not has_benchmark:
		_routine_button.text = "PASSER LE DIAGNOSTIC (2 MIN)"
		_next_routine_drill = "benchmark"
	elif _next_routine_drill == "":
		_routine_button.text = "ROUTINE TERMINÉE · REFAIRE LE DIAGNOSTIC"
		_next_routine_drill = "benchmark"
	else:
		var next_entry: Dictionary = DrillCatalog.find(_next_routine_drill)
		_routine_button.text = "SUIVANT : %s" % next_entry.get("title", "")


func _on_routine_pressed() -> void:
	if _next_routine_drill == "":
		return
	var button := _drill_buttons.get(_next_routine_drill) as Button
	if button != null:
		button.button_pressed = true
	_show_drill(_next_routine_drill)
	_on_play_pressed()


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

	var weapon_option := OptionButton.new()
	var weapon_index := 0
	for weapon_id: String in Weapons.ORDER:
		var profile: Dictionary = Weapons.get_profile(weapon_id)
		weapon_option.add_item(str(profile.get("name", weapon_id)))
		if weapon_id == GameSettings.weapon:
			weapon_index = weapon_option.item_count - 1
	weapon_option.select(weapon_index)
	weapon_option.item_selected.connect(_on_weapon_selected)
	_add_row("Arme (exercices de combat)", weapon_option)

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


func _on_weapon_selected(index: int) -> void:
	GameSettings.weapon = str(Weapons.ORDER[clampi(index, 0, Weapons.ORDER.size() - 1)])
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

	# Créer : partir d'un préréglage.
	var preset_option := OptionButton.new()
	preset_option.add_item("Choisir un préréglage…")
	for preset_name: String in GameSettings.CROSSHAIR_PRESETS:
		preset_option.add_item(preset_name)
	preset_option.item_selected.connect(_on_crosshair_preset_selected.bind(preset_option))
	_add_row("Préréglage", preset_option)

	# Importer / exporter : un code texte à coller ou à copier.
	_crosshair_code_edit = LineEdit.new()
	_crosshair_code_edit.placeholder_text = "Colle un code KA1;… puis IMPORTER"
	_crosshair_code_edit.text_submitted.connect(_on_crosshair_code_submitted)
	_add_row("Code du réticule", _crosshair_code_edit)
	var code_buttons := HBoxContainer.new()
	code_buttons.add_theme_constant_override(&"separation", 8)
	var import_button := Button.new()
	import_button.text = "IMPORTER"
	import_button.pressed.connect(_on_crosshair_import_pressed)
	code_buttons.add_child(import_button)
	var export_button := Button.new()
	export_button.text = "COPIER MON CODE"
	export_button.pressed.connect(_on_crosshair_export_pressed)
	code_buttons.add_child(export_button)
	_settings_list.add_child(code_buttons)
	_crosshair_status = Label.new()
	_crosshair_status.theme_type_variation = &"CaptionLabel"
	_crosshair_status.text = "Le code contient forme, couleur, tailles, contour et opacité."
	_settings_list.add_child(_crosshair_status)

	var style_option := OptionButton.new()
	for style_name: String in CROSSHAIR_STYLES:
		style_option.add_item(style_name)
	style_option.select(GameSettings.crosshair_style)
	style_option.item_selected.connect(_on_crosshair_style_selected)
	_add_row("Forme", style_option)
	_crosshair_style_option = style_option

	var color_button := ColorPickerButton.new()
	color_button.color = GameSettings.crosshair_color
	color_button.edit_alpha = false
	color_button.custom_minimum_size.y = 34.0
	color_button.color_changed.connect(_on_crosshair_color_changed)
	_add_row("Couleur", color_button)
	_crosshair_color_button = color_button

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
	_crosshair_outline_check = outline_check


func _on_crosshair_preset_selected(index: int, option: OptionButton) -> void:
	if index <= 0:
		return
	var code: String = GameSettings.CROSSHAIR_PRESETS.get(option.get_item_text(index), "")
	_apply_crosshair_code(code, "Préréglage appliqué : modifie-le librement ci-dessous.")
	option.select(0)


func _on_crosshair_code_submitted(_text: String) -> void:
	_on_crosshair_import_pressed()


func _on_crosshair_import_pressed() -> void:
	_apply_crosshair_code(_crosshair_code_edit.text, "Réticule importé.")


func _on_crosshair_export_pressed() -> void:
	var code: String = GameSettings.crosshair_to_code()
	DisplayServer.clipboard_set(code)
	_crosshair_code_edit.text = code
	_crosshair_status.text = "Code copié dans le presse-papiers."


## Applique un code de réticule et met à jour tous les champs de l'éditeur.
func _apply_crosshair_code(code: String, success_message: String) -> void:
	var valid: bool = GameSettings.crosshair_from_code(code)
	if not valid:
		_crosshair_status.text = "Code invalide : il doit commencer par KA1 et compter 9 champs séparés par « ; »."
		return
	_updating = true
	for property: Variant in _crosshair_spins:
		var spin := _crosshair_spins[property] as SpinBox
		var current: float = GameSettings.get(str(property))
		spin.value = current
	_crosshair_style_option.select(GameSettings.crosshair_style)
	_crosshair_color_button.color = GameSettings.crosshair_color
	_crosshair_outline_check.set_pressed_no_signal(GameSettings.crosshair_outline)
	_updating = false
	_crosshair_status.text = success_message
	_commit_crosshair()


func _add_crosshair_spin(caption: String, property: StringName, minimum: float, maximum: float, step: float, suffix: String) -> void:
	var current: float = GameSettings.get(property)
	var spin := _make_spin(minimum, maximum, step, current, suffix)
	spin.value_changed.connect(_on_crosshair_value_changed.bind(property))
	_add_row(caption, spin)
	_crosshair_spins[property] = spin


func _on_crosshair_value_changed(value: float, property: StringName) -> void:
	if _updating:
		return
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
