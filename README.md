# KINETIC // AIM

Aim trainer haute précision pour Godot 4 (renderer Forward+) : visée 1:1 sur l'entrée brute de la
souris, mode **Gridshot**, rendu PBR avec glow/SSAO, et un moteur de télémétrie qui échantillonne
la visée à 1000 Hz pour analyser chaque flick à la fin de la session.

## Lancer le projet

Prérequis : **Godot 4.3 ou plus récent** (version standard, GDScript).

1. Ouvrir Godot, cliquer sur **Importer**, sélectionner le fichier `project.godot` de ce dossier.
2. Laisser l'éditeur importer les ressources (quelques secondes au premier lancement).
3. Appuyer sur **F5** : la scène principale `scenes/main.tscn` démarre sur le menu.

En ligne de commande, depuis ce dossier (premier lancement : ouvrir une fois l'éditeur pour
générer le cache d'import) :

```bash
godot --editor --path .
```

```bash
godot --path .
```

## Contrôles

| Action | Touche |
| --- | --- |
| Viser | Souris (capturée pendant la session) |
| Tirer | Clic gauche |
| Abandonner la session / revenir au menu | Échap |
| Plein écran | F11 |
| Lancer / rejouer | Entrée ou clic sur le bouton |

Une session dure 60 secondes après un compte à rebours de 3 secondes. Perdre le focus de la
fenêtre pendant une session l'annule (les statistiques seraient faussées).

## Structure

```
project.godot                 Configuration (Forward+, physique 1000 Hz, autoloads, thème)
scenes/
  main.tscn                   Scène principale : arène + joueur + UI + gestionnaire de partie
  arena.tscn                  Environnement 3D : structure PBR, néons, éclairage, WorldEnvironment
  player.tscn                 Contrôleur FPS : Camera3D, RayCast3D de tir, point de bouche
  target.tscn                 Cible sphérique (StaticBody3D, couche « targets »)
  effects/                    Explosion de cible, impact de tir raté, traceur
scripts/
  game_manager.gd             États de jeu, Gridshot, score, effets
  player.gd                   Visée brute (counts → degrés), tir
  target.gd                   Cible : hitbox, apparition, destruction
  telemetry_manager.gd        Autoload « Telemetry » : capture 1000 Hz + analyse
  settings_manager.gd         Autoload « GameSettings » : sensibilité, réticule, graphismes
  one_shot_effect.gd, tracer.gd
ui/
  hud.tscn                    Réticule, score, chrono, précision, compte à rebours
  stats_dashboard.tscn        Rapport de fin de session
  main_menu.tscn              Menu + réglages
  crosshair.gd, heatmap.gd, flick_bar.gd, kinetic_theme.tres
materials/                    StandardMaterial3D (PBR) + matériaux de grille néon
shaders/                      Grille néon procédurale, onde de choc
environment/                  Environment : ciel procédural, glow, SSAO, SDFGI/SSR (Ultra)
```

## Visée et sensibilité

- La souris est capturée (`Input.MOUSE_MODE_CAPTURED`) et seul le déplacement relatif de
  `InputEventMouseMotion` est lu, dans `_input()`. Aucun lissage, aucune accélération.
- Le projet utilise le stretch `canvas_items` pour que l'interface s'adapte à la résolution. Avec
  ce mode, `relative` est mis à l'échelle par la taille de la fenêtre ; le script lit donc
  `screen_relative` (Godot 4.3+), qui est exactement la même donnée sans cette mise à l'échelle.
- La sensibilité est définie en **cm/360°** et **DPI** :
  `degrés par count = 360 × 2,54 / (cm/360° × DPI)`.
- Convertisseur intégré (yaw par count pour une sensibilité de 1) : Valorant 0,07 · CS2 0,022 ·
  Apex Legends 0,022 · Overwatch 2 0,0066.
- Le FOV se règle en FOV horizontal 16:9 (103° par défaut) et est converti en FOV vertical.
- Le réticule (croix, croix + point, point, cercle ; couleur, longueur, épaisseur, écart, contour,
  opacité) est dessiné au pixel physique près. Les réglages sont enregistrés dans
  `user://settings.cfg`.

## Gridshot

Une grille invisible de 5 × 5 cellules est placée à 9 m face au joueur. Trois sphères y sont
présentes en permanence ; un clic gauche lance un `RayCast3D` depuis la caméra : si une cible est
touchée elle explose (`GPUParticles3D`, flash, onde de choc) et une nouvelle apparaît aussitôt
dans une autre cellule libre. Les paramètres (taille de grille, espacement, distance, rayon,
nombre de cibles, barème) sont exportés sur le nœud `Main` de `scenes/main.tscn`.

Score : 100 points par cible, plus jusqu'à 100 points de bonus de vitesse (complet sous 150 ms
entre deux cibles, nul au-delà de 800 ms), moins 35 points par tir raté.

## Télémétrie

Pendant la session, l'autoload `Telemetry` enregistre à chaque tick physique (1000 Hz) le yaw et
le pitch de la caméra ainsi que la vitesse angulaire, et horodate chaque tir avec son écart
angulaire à la cible visée (la cible touchée, ou la plus proche du viseur en cas de tir raté).

Le rapport de fin de session affiche :

- **Score, précision, temps moyen entre deux cibles** (moyenne, médiane, record).
- **Overflick / Underflick** : chaque trajet entre deux tirs d'au moins 3° est analysé. On isole
  le mouvement balistique primaire (premier sous-mouvement rapide, après la fin de la décélération
  du tir précédent) et on projette sa position finale sur l'axe départ → cible. Au-delà du bord
  opposé de la cible : overflick. Avant le bord proche : underflick. Sinon : précis.
- **Indice de fluidité** : variance de l'accélération angulaire de chaque mouvement, rapportée à
  la variance minimale théorique pour la même amplitude et la même durée. 100 correspond à un
  geste unique de type « minimum-jerk » ; les corrections successives et le jitter font baisser
  l'indice.
- **Heatmap des tirs ratés** : dispersion des tirs autour du centre de la cible, en rayons de
  cible, générée dynamiquement (noyaux gaussiens → `ImageTexture`), avec le biais moyen.

### Résolution temporelle

Godot distribue les événements souris une fois par image rendue. L'échantillonnage est bien à
1000 Hz, mais l'angle de visée ne change qu'à la cadence du rendu : la finesse de l'analyse
dépend donc du FPS. C'est pourquoi la V-Sync est désactivée et le FPS illimité par défaut pendant
une session, et pourquoi la fenêtre de dérivation s'adapte au FPS mesuré. Viser 144 FPS ou plus
pour une analyse fiable des flicks.

## Qualité graphique

Trois préréglages dans le menu : **Performance** (sans MSAA ni SSAO), **Qualité** (MSAA 4x, SSAO,
glow, ombres douces — par défaut) et **Ultra** (ajoute SDFGI et réflexions SSR). Hors session, le
FPS est plafonné à 120 pour ménager le GPU.
