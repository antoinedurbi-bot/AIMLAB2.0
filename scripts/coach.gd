extends RefCounted
## Coach : transforme les statistiques d'une session en conseils concrets.
##
## Chaque règle examine le rapport et, si elle s'applique, propose un conseil
## avec une priorité. Les trois conseils les plus prioritaires sont affichés :
## le premier comme conseil principal, les suivants comme pistes secondaires.
## Les seuils sont volontairement simples et lisibles : ajuste-les ici.

const TONE_FIX := "fix"
const TONE_GOOD := "good"
const TONE_INFO := "info"
const MAX_ADVICE := 3

const SessionHistoryScript := preload("res://scripts/session_history.gd")


## `previous` : sessions précédentes du même exercice, la plus récente en premier
## (sans la session en cours). Renvoie des dictionnaires {title, text, tone, priority}.
static func build_advice(drill_id: String, report: Dictionary, previous: Array[Dictionary]) -> Array[Dictionary]:
	var advice: Array[Dictionary] = []
	match drill_id:
		"gridshot", "microflick":
			_aim_rules(advice, report, true)
		"angle_hold":
			_angle_hold_rules(advice, report)
			_aim_rules(advice, report, false)
		"counter_strafe":
			_counter_strafe_rules(advice, report)
		"jiggle_peek":
			_jiggle_rules(advice, report)
		"pre_aim", "site_attack", "site_retake":
			_pre_aim_rules(advice, report)
		"benchmark":
			_benchmark_rules(advice, report)
		"duel", "tap_burst":
			_duel_rules(advice, report)
			if drill_id == "tap_burst" and _number(report, "avg_burst_length") > 3.5:
				_add(advice, 90.0, "Rafales trop longues pour cette distance",
						"%.1f balles par rafale en moyenne. À longue distance, seules les deux ou trois premières balles restent groupées : tire court, replace, recommence." % _number(report, "avg_burst_length"), TONE_FIX)
		"bomb_defense":
			_bomb_defense_rules(advice, report)
			_bot_combat_rules(advice, report)
		"skirmish":
			_bot_combat_rules(advice, report)
		"peek_duel":
			_peek_duel_rules(advice, report)
		"multi_target":
			_multi_target_rules(advice, report)
		"sound_locate":
			_sound_rules(advice, report)
		"defuse":
			_pre_aim_rules(advice, report)
			if not bool(report.get("defused", false)):
				_add(advice, 92.0, "La charge a explosé",
						"Tu n'as pas désamorcé à temps. Il faut 7 s immobile : commence à désamorcer au plus tard à 38 s, donc ne passe pas plus de 30 s à nettoyer le site.", TONE_FIX)
			elif _number(report, "defuse_margin_s") > 12.0:
				_add(advice, 40.0, "Désamorçage large",
						"%.1f s de marge. Tu peux te permettre de nettoyer plus prudemment, ou de prendre un trajet plus sûr." % _number(report, "defuse_margin_s"), TONE_GOOD)
		"free_roam":
			_add(advice, 50.0, "Carte reconnue",
					"%d m parcourus. Enchaîne maintenant avec « Attaque de site » ou « Reprise de site » sur cette carte pour mettre les trajets à l'épreuve." % _count(report, "distance_moved_m"), TONE_INFO)
		"charge_timer":
			_timer_rules(advice, report)
		_:
			_aim_rules(advice, report, true)
	_trend_rules(advice, report, previous)

	if advice.is_empty():
		_add(advice, 1.0, "Session enregistrée",
				"Pas assez de données pour un diagnostic précis. Refais l'exercice en entier pour obtenir une analyse.", TONE_INFO)
	# Sélection des conseils les plus prioritaires, du plus important au moins important.
	var selected: Array[Dictionary] = []
	while selected.size() < MAX_ADVICE and not advice.is_empty():
		var best_index := 0
		for index in advice.size():
			if _number(advice[index], "priority") > _number(advice[best_index], "priority"):
				best_index = index
		selected.append(advice[best_index])
		advice.remove_at(best_index)
	return selected


static func _add(advice: Array[Dictionary], priority: float, title: String, text: String, tone: String) -> void:
	advice.append({"title": title, "text": text, "tone": tone, "priority": priority})


static func _number(report: Dictionary, key: String) -> float:
	var value: Variant = report.get(key, 0.0)
	if value is float or value is int:
		var number: float = value
		return number
	return 0.0


static func _count(report: Dictionary, key: String) -> int:
	return roundi(_number(report, key))


# ---------------------------------------------------------------------------
# Visée (Gridshot, Microflicks, et en complément des autres exercices de tir)
# ---------------------------------------------------------------------------

static func _aim_rules(advice: Array[Dictionary], report: Dictionary, speed_matters: bool) -> void:
	var shot_count := _count(report, "shots")
	var accuracy := _number(report, "accuracy")
	var flicks := _count(report, "flick_count")
	var over_rate := _number(report, "overflick_rate")
	var under_rate := _number(report, "underflick_rate")
	var smoothness := _number(report, "smoothness")
	var cm: float = GameSettings.cm_per_360

	if shot_count < 10:
		if speed_matters:
			_add(advice, 60.0, "Trop peu de tirs pour un diagnostic",
					"Seulement %d tirs sur la session. Engage davantage : il faut au moins une trentaine de tirs pour mesurer précision, flicks et fluidité." % shot_count, TONE_INFO)
		return

	if speed_matters and accuracy < 75.0:
		_add(advice, 92.0 - accuracy * 0.3, "La précision d'abord",
				"Tu touches %.0f %% de tes tirs. Ralentis d'environ 10 à 15 %% jusqu'à repasser au-dessus de 85 %% : un tir raté coûte plus de temps qu'un tir légèrement retardé, et la vitesse revient d'elle-même quand le geste est propre." % accuracy, TONE_FIX)
	elif speed_matters and accuracy > 93.0 and shot_count >= 25:
		_add(advice, 42.0, "Tu as de la marge : accélère",
				"%.0f %% de précision, c'est le signe que tu joues en dessous de ta vitesse. Force-toi à cliquer plus tôt, quitte à descendre vers 88–90 %% : c'est là que le score progresse le plus vite." % accuracy, TONE_GOOD)

	if flicks >= 8:
		if over_rate >= 22.0 and over_rate > under_rate * 1.5:
			_add(advice, 70.0 + over_rate * 0.25, "Tu dépasses la cible (overflick)",
					"%.0f %% de tes flicks finissent au-delà de la cible, de %.1f° en moyenne. Freine plus tôt et laisse la cible « arrêter » ton geste. Si la tendance persiste sur plusieurs sessions, baisse légèrement la sensibilité : essaie %.1f cm/360° au lieu de %.1f." % [
						over_rate, _number(report, "avg_overshoot_deg"), cm * 1.1, cm], TONE_FIX)
		elif under_rate >= 22.0 and under_rate > over_rate * 1.5:
			_add(advice, 70.0 + under_rate * 0.25, "Tu t'arrêtes avant la cible (underflick)",
					"%.0f %% de tes flicks s'arrêtent trop court, de %.1f° en moyenne, puis tu dois corriger. Engage le geste jusqu'au bout au lieu de le retenir. Si la tendance persiste, monte légèrement la sensibilité : essaie %.1f cm/360° au lieu de %.1f." % [
						under_rate, _number(report, "avg_undershoot_deg"), cm * 0.9, cm], TONE_FIX)
		elif over_rate >= 20.0 and under_rate >= 20.0:
			_add(advice, 66.0, "Amplitude de flick irrégulière",
					"Tes flicks tombent tantôt trop long (%.0f %%), tantôt trop court (%.0f %%). Ce n'est pas un problème de sensibilité mais de régularité : garde la même position de bras et de poignet, et ne change aucun réglage pendant une semaine." % [over_rate, under_rate], TONE_FIX)
		elif over_rate < 12.0 and under_rate < 12.0:
			_add(advice, 30.0, "Flicks bien calibrés",
					"%.0f %% de tes flicks terminent dans la cible dès le premier mouvement. Ta sensibilité te convient : garde-la et travaille maintenant la vitesse." % _number(report, "precise_rate"), TONE_GOOD)

	if _count(report, "smoothness_samples") >= 5 and smoothness < 50.0:
		_add(advice, 58.0 - smoothness * 0.2, "Geste saccadé",
				"Indice de fluidité de %.0f / 100 : tes mouvements se font en plusieurs à-coups au lieu d'un seul geste. Relâche la prise sur la souris, pars d'un mouvement franc du bras puis termine au poignet, et évite de crisper la main entre deux cibles." % smoothness, TONE_FIX)

	var bias_value: Variant = report.get("miss_bias_deg", Vector2.ZERO)
	if bias_value is Vector2:
		var bias: Vector2 = bias_value
		var spread := _number(report, "avg_miss_distance_deg")
		if _count(report, "misses") >= 6 and spread > 0.0 and bias.length() >= spread * 0.4:
			_add(advice, 52.0, "Tes tirs ratés partent du même côté",
					"En moyenne, tes tirs ratés tombent %s de la cible. Un biais constant vient souvent de la posture : vérifie que ton avant-bras est dans l'axe de l'écran et que la souris ne pivote pas dans ta main pendant le flick." % _direction_text(bias), TONE_FIX)

	if speed_matters and _number(report, "avg_ttk_ms") > 0.0:
		var average := _number(report, "avg_ttk_ms")
		var consistency := _number(report, "ttk_consistency_ms")
		if consistency > average * 0.55 and _count(report, "hits") >= 15:
			_add(advice, 45.0, "Rythme irrégulier",
					"Le temps entre deux cibles varie beaucoup (± %d ms autour de %d ms). Cherche un tempo constant : repère la cible suivante avant même d'avoir tiré sur l'actuelle." % [roundi(consistency), roundi(average)], TONE_FIX)


static func _direction_text(bias: Vector2) -> String:
	var parts := PackedStringArray()
	if absf(bias.x) >= 0.1:
		parts.append("%.1f° à %s" % [absf(bias.x), "droite" if bias.x > 0.0 else "gauche"])
	if absf(bias.y) >= 0.1:
		parts.append("%.1f° %s" % [absf(bias.y), "au-dessus" if bias.y > 0.0 else "en dessous"])
	if parts.is_empty():
		return "près"
	return " et ".join(parts)


# ---------------------------------------------------------------------------
# Tenue d'angle
# ---------------------------------------------------------------------------

static func _angle_hold_rules(advice: Array[Dictionary], report: Dictionary) -> void:
	var reps := _count(report, "reps")
	var kills := _count(report, "kills")
	var premature := _count(report, "premature_shots")
	var reaction := _number(report, "reaction_median_ms")
	var lead := _number(report, "initial_lead_deg")
	var initial_offset := _number(report, "initial_offset_deg")
	var behind := _count(report, "misses_behind")
	var ahead := _count(report, "misses_ahead")
	var first_shot := _number(report, "first_shot_accuracy")

	if premature >= 3:
		_add(advice, 86.0 + float(premature), "Tu tires dans le vide",
				"%d tirs sans cible visible. En partie, un tir prématuré donne ta position et te laisse sans précision pour le vrai duel. Garde le doigt posé mais ne presse qu'à la vue de la cible." % premature, TONE_FIX)
	if kills >= 3:
		if reaction > 330.0:
			_add(advice, 72.0, "Réaction trop lente",
					"Réaction médiane de %d ms. Regarde le bord du passage, pas ton viseur, et attends un mouvement plutôt qu'une forme : la vision périphérique détecte le mouvement plus vite. En dessous de 280 ms tu gagnes la plupart des duels d'angle." % roundi(reaction), TONE_FIX)
		elif reaction < 240.0:
			_add(advice, 32.0, "Très bonne réaction",
					"Réaction médiane de %d ms : c'est rapide. Le prochain gain viendra de la régularité (écart-type actuel : %d ms) et de la réussite du premier tir." % [roundi(reaction), roundi(_number(report, "reaction_std_ms"))], TONE_GOOD)
	if reps >= 5 and lead < -0.4:
		_add(advice, 76.0, "Ton viseur attend derrière la cible",
				"À l'apparition de la cible, ton viseur est en moyenne %.1f° derrière elle : tu dois la rattraper. Décale-le d'environ 1° vers l'intérieur de l'ouverture pour que la cible vienne d'elle-même dessus." % absf(lead), TONE_FIX)
	elif reps >= 5 and initial_offset > 3.0:
		_add(advice, 68.0, "Viseur trop loin du point d'apparition",
				"La cible apparaît en moyenne à %.1f° de ton viseur. Tiens l'angle plus serré : place le viseur à environ 1° du bord d'où elle peut sortir, à hauteur de tête." % initial_offset, TONE_FIX)
	if behind >= 4 and behind > ahead * 2:
		_add(advice, 70.0, "Tu tires derrière la cible",
				"%d de tes tirs ratés passent derrière la cible en mouvement. Tu vises là où elle était : laisse-la entrer dans le viseur ou tire légèrement en avance sur sa trajectoire." % behind, TONE_FIX)
	if _count(report, "shots") >= 8 and first_shot < 50.0:
		_add(advice, 62.0, "Premier tir manqué trop souvent",
				"Ton premier tir ne touche que dans %.0f %% des cas. Mieux vaut 30 ms de plus et un tir qui touche : confirme l'alignement avant de cliquer, le premier tir est le seul à être parfaitement précis." % first_shot, TONE_FIX)
	if reps >= 5 and kills * 2 < reps:
		_add(advice, 55.0, "Trop de cibles s'échappent",
				"Seulement %d cibles abattues sur %d. Commence par les cibles qui s'arrêtent : ne cherche pas à suivre celles qui traversent, attends-les à un point fixe de l'ouverture." % [kills, reps], TONE_FIX)


# ---------------------------------------------------------------------------
# Strafe / contre-strafe
# ---------------------------------------------------------------------------

static func _counter_strafe_rules(advice: Array[Dictionary], report: Dictionary) -> void:
	var strafe_shots := _count(report, "strafe_shots")
	var static_shots := _count(report, "static_shots")
	var clean_rate := _number(report, "clean_rate")
	var too_early := _count(report, "too_early_shots")
	var too_late := _count(report, "too_late_shots")
	var counter_stops := _count(report, "counter_stops")
	var release_stops := _count(report, "release_stops")
	var speed := _number(report, "avg_speed_at_strafe_shot")
	var counter_ms := _number(report, "avg_counter_stop_ms")
	var release_ms := _number(report, "avg_release_stop_ms")
	var key_gap := _number(report, "avg_key_gap_ms")
	var accuracy := _number(report, "accuracy")

	if strafe_shots < 8:
		_add(advice, 95.0, "Bouge entre chaque tir",
				"Seulement %d tirs ont été précédés d'un vrai strafe (%d tirés sans bouger). L'exercice consiste à atteindre la pleine vitesse, s'arrêter, tirer, repartir : alterne gauche et droite à chaque cible." % [strafe_shots, static_shots], TONE_FIX)
		return

	if clean_rate < 70.0 and too_early >= too_late:
		_add(advice, 88.0, "Tu tires avant d'être arrêté",
				"%d tirs partis trop tôt : vitesse moyenne au tir de %.1f m/s alors que le tir n'est précis qu'en dessous de 1,5 m/s. Donne un coup bref sur la touche opposée, puis tire : compte « stop, clic » plutôt que de tout faire en même temps." % [too_early, speed], TONE_FIX)
	elif clean_rate < 70.0:
		_add(advice, 86.0, "Tu tiens la touche opposée trop longtemps",
				"%d tirs sont partis alors que tu repartais déjà dans l'autre sens. Le contre-strafe est une tape de 50 à 80 ms, pas un appui : relâche la touche opposée avant de cliquer." % too_late, TONE_FIX)
	elif too_late >= 4 and too_late > too_early:
		_add(advice, 64.0, "Quelques contre-strafes trop appuyés",
				"%d tirs déviés parce que tu repartais en sens inverse. Raccourcis la tape sur la touche opposée." % too_late, TONE_FIX)

	if counter_stops + release_stops >= 8 and counter_stops * 5 < (counter_stops + release_stops) * 2:
		var detail := "La touche opposée freine bien plus fort que la simple friction."
		if counter_ms > 0.0 and release_ms > 0.0:
			detail = "Sur tes tirs propres : arrêt en %d ms avec contre-strafe contre %d ms en relâchant." % [roundi(counter_ms), roundi(release_ms)]
		_add(advice, 66.0, "Tu t'arrêtes en relâchant seulement",
				"Tu n'utilises le contre-strafe que sur %.0f %% de tes arrêts. %s Prends l'habitude : gauche, tape à droite, tir." % [_number(report, "counter_rate"), detail], TONE_FIX)
	if key_gap > 45.0:
		_add(advice, 54.0, "Temps mort entre les deux touches",
				"Il s'écoule %d ms entre le moment où tu lâches une touche et celui où tu presses l'opposée. Enchaîne les deux sans pause (un léger chevauchement est même préférable)." % roundi(key_gap), TONE_FIX)
	if clean_rate >= 70.0 and accuracy < 60.0:
		_add(advice, 60.0, "Arrêts propres, visée à revoir",
				"%.0f %% de tirs propres mais seulement %.0f %% de précision : ton arrêt est bon, c'est le viseur qui n'est pas sur la cible au moment du stop. Place le viseur sur la cible pendant le strafe, pas après." % [clean_rate, accuracy], TONE_FIX)
	if clean_rate >= 85.0:
		_add(advice, 34.0, "Arrêts maîtrisés",
				"%.0f %% de tirs propres, arrêt moyen en %d ms. Objectif suivant : réduire ce temps d'arrêt et raccourcir le délai entre deux éliminations sans perdre la propreté." % [clean_rate, roundi(_number(report, "avg_stop_ms"))], TONE_GOOD)


# ---------------------------------------------------------------------------
# Jiggle peek
# ---------------------------------------------------------------------------

static func _jiggle_rules(advice: Array[Dictionary], report: Dictionary) -> void:
	var peeks := _count(report, "peeks")
	var successes := _count(report, "jiggle_success")
	var fails := _count(report, "jiggle_fail")
	var empty := _count(report, "empty_peeks")
	var exposure := _number(report, "avg_exposure_ms")
	var success_exposure := _number(report, "avg_success_exposure_ms")
	var overpeek := _number(report, "avg_overpeek_cm")
	var limit := _number(report, "enemy_reaction_ms")

	if peeks < 6:
		_add(advice, 95.0, "Sors plus souvent",
				"Seulement %d sorties sur la session. Le jiggle est un geste court et répété : gauche-droite, gauche-droite, sans pause à découvert." % peeks, TONE_FIX)
		return
	if fails >= 2 and fails * 2 >= successes:
		_add(advice, 90.0, "Tu restes exposé trop longtemps",
				"Touché %d fois : exposition moyenne de %d ms pour une limite de %d ms. N'attends pas de « bien voir » : inverse la direction dès que la silhouette apparaît. Colle-toi au coin au départ pour n'avoir qu'un demi-pas à faire." % [fails, roundi(exposure), roundi(limit)], TONE_FIX)
	if empty >= 3 and empty > successes:
		_add(advice, 82.0, "Tes sorties sont trop courtes",
				"%d sorties où tu t'es exposé sans rien voir : tes épaules dépassent avant ta caméra, donc tu prends le risque sans le gain. Sors de 20 à 30 cm de plus pour que tes yeux passent le coin." % empty, TONE_FIX)
	if successes >= 3 and overpeek > 35.0:
		_add(advice, 72.0, "Tu continues d'avancer après avoir vu",
				"Après avoir aperçu l'adversaire tu parcours encore %d cm en moyenne. L'information est déjà prise : inverse immédiatement avec la touche opposée." % roundi(overpeek), TONE_FIX)
	if peeks >= 8 and _number(report, "exposure_std_ms") > 90.0:
		_add(advice, 50.0, "Sorties irrégulières",
				"La durée de tes sorties varie de ± %d ms. Cherche un geste identique à chaque fois : même point de départ, même tape sur chaque touche." % roundi(_number(report, "exposure_std_ms")), TONE_FIX)
	if successes >= 5 and fails * 4 <= successes and success_exposure < 220.0:
		_add(advice, 36.0, "Jiggle propre",
				"%d informations prises pour une exposition moyenne de %d ms : difficile de te punir là-dessus. Varie maintenant le rythme pour rester imprévisible." % [successes, roundi(success_exposure)], TONE_GOOD)
	elif successes >= 3 and success_exposure >= 220.0:
		_add(advice, 58.0, "Raccourcis encore l'exposition",
				"Tes sorties réussies durent %d ms en moyenne. Vise moins de 200 ms : c'est en dessous du temps de réaction de la plupart des joueurs." % roundi(success_exposure), TONE_FIX)


# ---------------------------------------------------------------------------
# Pré-visée
# ---------------------------------------------------------------------------

static func _pre_aim_rules(advice: Array[Dictionary], report: Dictionary) -> void:
	var cleared := _count(report, "angles_cleared")
	var total := _count(report, "angles_total")
	var vertical := _number(report, "preaim_vertical_deg")
	var horizontal := _number(report, "preaim_horizontal_deg")
	var error := _number(report, "preaim_error_deg")
	var ttk := _number(report, "exposure_ttk_ms")
	var moving_rate := _number(report, "shots_moving_rate")

	if cleared < 3:
		_add(advice, 95.0, "Avance dans le parcours",
				"Seulement %d angles nettoyés sur %d. Prends le temps de finir le parcours une fois sans te presser : l'analyse a besoin de plusieurs angles." % [cleared, total], TONE_FIX)
		return
	if absf(vertical) >= 0.8:
		var side := "bas" if vertical > 0.0 else "haut"
		_add(advice, 88.0 + absf(vertical), "Viseur trop %s" % side,
				"Quand une cible apparaît, ton viseur est en moyenne %.1f° trop %s par rapport à sa tête. Garde-le à hauteur de tête en permanence, y compris en te déplaçant : choisis un repère du décor à cette hauteur et ne le quitte pas." % [absf(vertical), side], TONE_FIX)
	if horizontal >= 3.0:
		_add(advice, 80.0, "Viseur loin de l'angle",
				"%.1f° d'écart latéral en moyenne à la découverte d'une cible. Avant de sortir, colle le viseur au bord du mur, là où une tête apparaîtrait, puis tranche l'angle en te déplaçant : c'est le décor qui doit amener la cible sur ton viseur." % horizontal, TONE_FIX)
	if moving_rate >= 30.0:
		_add(advice, 76.0, "Tu tires en te déplaçant",
				"%.0f %% de tes tirs partent en mouvement et sont donc déviés. Arrête-toi (touche opposée) dès que la cible est visible, puis tire." % moving_rate, TONE_FIX)
	if ttk > 700.0:
		_add(advice, 64.0, "Lent à conclure",
				"Il te faut %d ms entre la découverte d'une cible et sa destruction. Avec un viseur bien placé il ne reste qu'un micro-ajustement : vise moins de 450 ms." % roundi(ttk), TONE_FIX)
	if cleared < total:
		_add(advice, 48.0, "Parcours inachevé",
				"%d angles sur %d dans le temps imparti. La vitesse viendra du placement : moins tu corriges, plus tu avances." % [cleared, total], TONE_INFO)
	if error < 1.5 and absf(vertical) < 0.8:
		_add(advice, 34.0, "Très bon placement de viseur",
				"Erreur de pré-visée de %.1f° seulement : les cibles apparaissent presque sur ton viseur. Travaille maintenant la vitesse de déplacement entre les angles." % error, TONE_GOOD)


# ---------------------------------------------------------------------------
# Chrono de la charge
# ---------------------------------------------------------------------------

static func _timer_rules(advice: Array[Dictionary], report: Dictionary) -> void:
	var reps := _count(report, "timer_reps")
	var rate := _number(report, "timer_rate_percent")
	var mean_abs := _number(report, "timer_mean_abs_error_s")
	var calm := _number(report, "timer_calm_abs_error_s")
	var pressure := _number(report, "timer_pressure_abs_error_s")
	var last_error := _number(report, "timer_last_error_s")
	var consistency := _number(report, "timer_consistency_percent")

	if reps < 2:
		_add(advice, 95.0, "Termine les manches",
				"Une seule manche jouée. Fais la série complète : c'est la comparaison entre les durées qui révèle ton rythme interne.", TONE_FIX)
		return
	if absf(rate) >= 4.0:
		var fast := rate < 0.0
		_add(advice, 90.0, "Tu comptes trop %s" % ("vite" if fast else "lentement"),
				"Ton rythme interne est décalé de %+.1f %% : sur 38 s, cela fait environ %.1f s %s. %s Refais l'exercice jusqu'à passer sous 3 %%." % [
					rate, absf(rate) * 0.38, "d'avance" if fast else "de retard",
					"Allonge chaque seconde en articulant « mille un, mille deux »." if fast else "Raccourcis ton décompte : compte sur un tempo régulier, par exemple en tapant du pied."], TONE_FIX)
	if bool(report.get("timer_has_pressure_reps", false)) and pressure - calm >= 0.6:
		_add(advice, 82.0, "Tu perds le fil sous pression",
				"Erreur de %.2f s au calme contre %.2f s en abattant des cibles. Ancre ton décompte sur des paliers (5, 10, 15...) que tu te répètes entre deux tirs, au lieu de compter chaque seconde." % [calm, pressure], TONE_FIX)
	if consistency > 6.0 and reps >= 3:
		_add(advice, 60.0, "Décompte irrégulier",
				"Ton rythme varie de ± %.1f %% d'une manche à l'autre : tantôt trop vite, tantôt trop lent. Utilise toujours la même méthode de comptage pour stabiliser ton tempo." % consistency, TONE_FIX)
	if last_error > 0.5:
		_add(advice, 70.0, "Trop tard sur la manche longue",
				"%.2f s de retard sur la dernière manche. Sur un désamorçage, ce retard ne se rattrape pas : dans le doute, engage une seconde plus tôt que ton estimation." % last_error, TONE_FIX)
	elif last_error < -2.0:
		_add(advice, 56.0, "Trop de marge sur la manche longue",
				"%.2f s d'avance sur la dernière manche : c'est sûr, mais ce sont des secondes que tu n'utilises pas pour te replacer. Cherche à réduire cette marge sous 1 s." % absf(last_error), TONE_INFO)
	if mean_abs < 0.6 and absf(rate) < 4.0:
		_add(advice, 36.0, "Horloge interne fiable",
				"Erreur moyenne de %.2f s seulement. Tu peux te fier à ton décompte en partie : entretiens-le en comptant systématiquement à chaque pose." % mean_abs, TONE_GOOD)


# ---------------------------------------------------------------------------
# Diagnostic et duel
# ---------------------------------------------------------------------------

static func _benchmark_rules(advice: Array[Dictionary], report: Dictionary) -> void:
	var names := {"flick": "le flick", "tracking": "le tracking", "reaction": "la réaction", "spray": "le contrôle du spray"}
	var plans := {
		"flick": "Fais Gridshot puis Microflicks en visant la précision avant la vitesse.",
		"tracking": "Fais l'exercice Duel : suis la tête pendant les strafes au lieu d'attendre l'arrêt.",
		"reaction": "Fais Tenue d'angle en regardant le bord du passage, pas ton viseur.",
		"spray": "Fais l'exercice Duel en rafales de 4 à 6 balles, viseur tiré vers le bas dès la 3e.",
	}
	var weakest: String = str(report.get("bench_weakest", "flick"))
	var lowest := _number(report, "bench_" + weakest)
	_add(advice, 95.0, "Priorité : %s" % str(names.get(weakest, weakest)),
			"C'est ta note la plus basse : %d / 100, pour une moyenne de %d. %s La routine du jour, dans le menu, lui consacre le plus de sessions." % [
				roundi(lowest), roundi(_number(report, "bench_overall")), str(plans.get(weakest, ""))], TONE_FIX)
	if _count(report, "bench_reaction_premature") >= 3:
		_add(advice, 70.0, "Tu anticipes au lieu de réagir",
				"%d tirs partis avant l'apparition de la cible. Chacun coûte 5 points de note, et en partie il révèle ta position. Garde le doigt posé et ne presse qu'à la vue de la cible." % _count(report, "bench_reaction_premature"), TONE_FIX)
	if _count(report, "bench_spray_bullets") < 12:
		_add(advice, 65.0, "Épreuve de spray non notée",
				"Moins de 12 balles tirées en rafale. Maintiens le clic pour des rafales de 8 à 10 balles : c'est la tenue du recul qui est mesurée, pas le premier tir.", TONE_INFO)
	var best_skill := "flick"
	for skill: String in names:
		if _number(report, "bench_" + skill) > _number(report, "bench_" + best_skill):
			best_skill = skill
	_add(advice, 30.0, "Point fort : %s" % str(names.get(best_skill, best_skill)),
			"%d / 100. Inutile d'y passer du temps cette semaine : entretiens-le avec l'échauffement." % roundi(_number(report, "bench_" + best_skill)), TONE_GOOD)


static func _duel_rules(advice: Array[Dictionary], report: Dictionary) -> void:
	var duels := _count(report, "duels")
	var win_rate := _number(report, "duel_win_rate")
	var headshots := _number(report, "headshot_rate")
	var bullets := _number(report, "bullets_per_kill")
	var shot_count := _count(report, "shots")
	var moving := _count(report, "shots_moving")
	if duels < 5:
		_add(advice, 95.0, "Trop peu de duels",
				"Seulement %d duels joués. Engage chaque cible dès qu'elle apparaît : il en faut une quinzaine pour un diagnostic." % duels, TONE_FIX)
		return
	if shot_count > 0 and moving * 100 >= shot_count * 30:
		_add(advice, 88.0, "Tu tires en te déplaçant",
				"%d %% de tes balles partent en mouvement et sont déviées. Arrête-toi d'une tape sur la touche opposée, tire ta rafale, puis repars." % roundi(100.0 * float(moving) / float(shot_count)), TONE_FIX)
	if headshots < 25.0 and _count(report, "hits") >= 10:
		_add(advice, 82.0, "Ton viseur est trop bas",
				"Seulement %.0f %% de tes balles au but touchent la tête. Tiens le viseur à hauteur de tête en permanence : une tête élimine en un tir, le corps en demande trois." % headshots, TONE_FIX)
	if bullets > 6.0:
		_add(advice, 74.0, "Rafales trop longues",
				"%.1f balles par élimination en moyenne. Au-delà de la 5e balle le recul t'emmène hors de la cible : coupe la rafale, replace le viseur, reprends." % bullets, TONE_FIX)
	if win_rate < 50.0:
		_add(advice, 78.0, "Tu perds le duel au temps",
				"%.0f %% de duels gagnés. Ne suis pas tous les strafes : attends l'arrêt bref de la cible ou son demi-tour, c'est là que sa tête est immobile." % win_rate, TONE_FIX)
	elif win_rate >= 80.0:
		_add(advice, 36.0, "Duels maîtrisés à ce niveau",
				"%.0f %% de duels gagnés : la difficulté monte pour la prochaine session (cible plus rapide, temps plus court)." % win_rate, TONE_GOOD)


static func _bot_combat_rules(advice: Array[Dictionary], report: Dictionary) -> void:
	var kills := _count(report, "bot_kills")
	var deaths := _count(report, "deaths")
	var bot_accuracy := _number(report, "bot_accuracy")
	var loud := _number(report, "loud_distance_m")
	if kills + deaths < 3:
		_add(advice, 60.0, "Peu de combats", "Seulement %d éliminations et %d morts : va au contact pour obtenir un diagnostic." % [kills, deaths], TONE_INFO)
		return
	if deaths > kills:
		_add(advice, 88.0, "Tu perds plus de duels que tu n'en gagnes",
				"%d morts pour %d éliminations. Les bots s'arrêtent pour tirer leur rafale puis strafent : tire pendant la rafale, mets-toi à couvert pendant le strafe." % [deaths, kills], TONE_FIX)
	if bot_accuracy > 45.0:
		_add(advice, 80.0, "Tu es une cible facile",
				"Les bots touchent %.0f %% de leurs balles. Ne reste pas immobile à découvert après ton tir : un pas de côté ou un retour à couvert divise leur précision." % bot_accuracy, TONE_FIX)
	if loud > 150.0 and deaths >= 2:
		_add(advice, 72.0, "Ils t'entendent venir",
				"%d m parcourus en courant. Les bots repèrent ta position au bruit dans un rayon de 18 m : marche (Maj) à l'approche d'un angle." % roundi(loud), TONE_FIX)
	if _number(report, "headshot_rate") < 25.0 and _count(report, "hits") >= 10:
		_add(advice, 70.0, "Vise la tête",
				"%.0f %% de tirs à la tête. Un tir à la tête élimine un bot avant la fin de sa rafale ; trois balles dans le corps lui laissent le temps de répondre." % _number(report, "headshot_rate"), TONE_FIX)
	if kills >= deaths * 3 and kills >= 4:
		_add(advice, 36.0, "Tu domines à ce niveau", "%d éliminations pour %d morts : les bots seront plus rapides et plus précis à la prochaine session." % [kills, deaths], TONE_GOOD)


static func _bomb_defense_rules(advice: Array[Dictionary], report: Dictionary) -> void:
	var defended := bool(report.get("bomb_defended", false))
	var reached := _count(report, "bomb_enemies_reached")
	var killed := _count(report, "bomb_enemies_killed")
	var max_defuse := _number(report, "bomb_max_enemy_defuse_s")
	if not defended:
		_add(advice, 95.0, "La charge a été désamorcée",
				"Un adversaire a tenu 7 s sur la charge. Dès que tu entends le bip changer de ton, quelqu'un désamorce : tire sur la charge elle-même, il est forcément dessus et immobile.", TONE_FIX)
	if reached >= 2:
		_add(advice, 80.0, "Trop d'adversaires atteignent la charge",
				"%d adversaires sont arrivés jusqu'à la charge. Place-toi là où tu vois à la fois la charge et son accès principal, plutôt que collé à elle." % reached, TONE_FIX)
	if defended and max_defuse > 3.5:
		_add(advice, 70.0, "Désamorçage stoppé de justesse",
				"Un adversaire a désamorcé pendant %.1f s sur 7. Au-delà de la moitié, la marge d'erreur disparaît : réagis au premier bip aigu, sans attendre de le voir." % max_defuse, TONE_FIX)
	if _number(report, "bomb_avg_kill_ms") > 3500.0 and killed >= 2:
		_add(advice, 64.0, "Lent à éliminer",
				"%d ms en moyenne entre l'apparition d'un adversaire et son élimination. Ils marchent en ligne droite vers la charge : pré-vise leur trajet à hauteur de tête." % roundi(_number(report, "bomb_avg_kill_ms")), TONE_FIX)
	if defended and reached == 0:
		_add(advice, 36.0, "Site verrouillé", "%d adversaires éliminés, aucun n'a touché la charge : les arrivées seront plus rapprochées à la prochaine session." % killed, TONE_GOOD)


static func _peek_duel_rules(advice: Array[Dictionary], report: Dictionary) -> void:
	var duels := _count(report, "duels")
	var win_rate := _number(report, "duel_win_rate")
	var exposure := _number(report, "avg_exposure_ms")
	var limit := _number(report, "enemy_reaction_ms")
	var wide := _count(report, "wide_peek_wins")
	var tight := _count(report, "tight_peek_wins")
	if duels < 5:
		_add(advice, 95.0, "Trop peu de duels", "Seulement %d duels joués. Sors du coin plus souvent : il en faut une dizaine pour un diagnostic." % duels, TONE_FIX)
		return
	if win_rate < 50.0:
		_add(advice, 90.0, "L'adversaire tire avant toi",
				"%.0f %% de duels gagnés face à une riposte à %d ms. Place ton viseur à hauteur de tête sur l'angle AVANT de sortir : tu n'as le temps que d'un micro-ajustement, pas d'un flick." % [win_rate, roundi(limit)], TONE_FIX)
	if _number(report, "headshot_rate") < 30.0 and _count(report, "hits") >= 8:
		_add(advice, 80.0, "Vise la tête en sortant",
				"%.0f %% de tirs à la tête. Derrière une caisse, seule la tête dépasse : un viseur trop bas tire dans la caisse." % _number(report, "headshot_rate"), TONE_FIX)
	if wide > tight * 2 and wide >= 4:
		_add(advice, 62.0, "Tu sors presque toujours large",
				"%d sorties larges contre %d serrées. La sortie large surprend, mais t'expose à tous les angles : garde-la pour quand tu connais la position, et tranche serré le reste du temps." % [wide, tight], TONE_INFO)
	if win_rate >= 50.0 and exposure > limit * 0.75:
		_add(advice, 60.0, "Tu gagnes de justesse",
				"Tu es exposé %d ms en moyenne avant d'éliminer, pour une riposte à %d ms. Si le premier tir ne touche pas, reviens à couvert et ressors plutôt que d'insister." % [roundi(exposure), roundi(limit)], TONE_FIX)
	elif win_rate >= 80.0:
		_add(advice, 36.0, "Sorties d'angle maîtrisées", "%.0f %% de duels gagnés : la riposte sera plus rapide à la prochaine session." % win_rate, TONE_GOOD)


static func _multi_target_rules(advice: Array[Dictionary], report: Dictionary) -> void:
	var waves := _count(report, "waves")
	var transfer := _number(report, "avg_transfer_ms")
	if waves < 3:
		_add(advice, 95.0, "Trop peu de vagues", "Seulement %d vagues nettoyées. Engage la première cible dès l'apparition de la vague." % waves, TONE_FIX)
		return
	if transfer > 800.0:
		_add(advice, 86.0, "Transferts lents",
				"%d ms entre deux éliminations. Repère la cible suivante AVANT d'avoir fini la première, et traite-les dans l'ordre où elles s'alignent, pas au hasard." % roundi(transfer), TONE_FIX)
	if _number(report, "bullets_per_kill") > 6.0:
		_add(advice, 78.0, "Trop de balles par cible",
				"%.1f balles par élimination. Au transfert, relâche une fraction de seconde pour remettre le recul à zéro si la cible suivante est loin." % _number(report, "bullets_per_kill"), TONE_FIX)
	if _number(report, "headshot_rate") < 25.0:
		_add(advice, 70.0, "Reste à hauteur de tête pendant le transfert",
				"%.0f %% de tirs à la tête. Déplace le viseur à l'horizontale d'une tête à l'autre : toutes sont à la même hauteur." % _number(report, "headshot_rate"), TONE_FIX)
	if transfer <= 500.0 and transfer > 0.0:
		_add(advice, 34.0, "Transferts rapides", "%d ms en moyenne entre deux cibles : la difficulté monte." % roundi(transfer), TONE_GOOD)


static func _sound_rules(advice: Array[Dictionary], report: Dictionary) -> void:
	var error := _number(report, "sound_mean_error_deg")
	if _count(report, "sound_reps") < 4:
		_add(advice, 95.0, "Trop peu d'essais", "Termine les dix essais pour obtenir une mesure fiable.", TONE_FIX)
		return
	if _count(report, "sound_side_confusions") >= 2:
		_add(advice, 92.0, "Gauche et droite inversées",
				"%d réponses du mauvais côté. Vérifie que ton casque n'est pas à l'envers et que la sortie audio est bien en stéréo, sans effet de spatialisation supplémentaire." % _count(report, "sound_side_confusions"), TONE_FIX)
	if _count(report, "sound_front_back_confusions") >= 2:
		_add(advice, 80.0, "Avant et arrière confondus",
				"%d confusions avant / arrière. C'est la limite du son stéréo : tourne légèrement la tête (le viseur) pendant le signal, le son se déplace alors d'un côté et lève le doute." % _count(report, "sound_front_back_confusions"), TONE_FIX)
	if error > 25.0:
		_add(advice, 70.0, "Localisation imprécise",
				"%d° d'erreur moyenne. Balaye lentement jusqu'à ce que le son soit centré entre les deux oreilles, puis clique." % roundi(error), TONE_FIX)
	else:
		_add(advice, 34.0, "Bonne oreille", "%d° d'erreur moyenne : assez précis pour pré-viser un angle au son." % roundi(error), TONE_GOOD)


# ---------------------------------------------------------------------------
# Progression d'une session à l'autre
# ---------------------------------------------------------------------------

static func _trend_rules(advice: Array[Dictionary], report: Dictionary, previous: Array[Dictionary]) -> void:
	var score := _number(report, "score")
	if previous.is_empty():
		_add(advice, 12.0, "Première session enregistrée",
				"Ces valeurs servent désormais de référence : les prochaines sessions de cet exercice seront comparées à celle-ci.", TONE_INFO)
		return
	var best := 0.0
	for entry in previous:
		best = maxf(best, _number(entry, "score"))
	var average := SessionHistoryScript.average(previous, "score")
	if score > best and best > 0.0:
		_add(advice, 40.0, "Nouveau record",
				"%d points : tu bats ton précédent record de %d. Note ce que tu as fait différemment aujourd'hui (posture, échauffement, sensibilité) et reproduis-le." % [roundi(score), roundi(best)], TONE_GOOD)
	elif previous.size() >= 3 and not is_nan(average) and average > 0.0:
		var change := (score - average) / average * 100.0
		if change <= -15.0:
			_add(advice, 44.0, "En dessous de ta moyenne",
					"Score inférieur de %.0f %% à la moyenne de tes %d dernières sessions. Si cela se répète, fais une pause : la fatigue dégrade d'abord la régularité, et s'entraîner fatigué ancre de mauvais gestes." % [absf(change), previous.size()], TONE_INFO)
		elif change >= 8.0:
			_add(advice, 26.0, "En progression",
					"Score supérieur de %.0f %% à la moyenne de tes %d dernières sessions. Continue sur ce rythme." % [change, previous.size()], TONE_GOOD)
