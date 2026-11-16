# KINETIC // AIM

Entraînement pour FPS tactiques, sous Godot 4 (renderer Forward+) : visée, déplacement, duels
contre des bots, charge et sites. Chaque session est enregistrée à 1000 Hz, analysée, comparée
aux précédentes, et se termine par un conseil.

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

## Lobby

Quatre pages, peu de texte sur chacune :

- **Accueil** : routine du jour (avancement et bouton « Continuer »), diagnostic, accès libre.
- **Jouer** : les exercices en cartes, triés en quatre catégories — Visée, Déplacement, Duels,
  Charge et sites. Une carte peut avoir des variantes (Flicks : larges ou micro ; Duel : proche
  ou longue distance ; Site : attaque, reprise ou désamorçage ; Utilitaires : lineups ou
  exploration). Le panneau de droite choisit la variante et la carte, puis lance.
- **Profil** : radar, notes du diagnostic, routine détaillée.
- **Réglages** : onglets Souris, Réticule, Touches, Vidéo, Jeu.

## Contrôles

Toutes les touches se changent dans **Réglages → Touches** : clique l'action, appuie sur la
touche ou le bouton de souris. Deux actions ne peuvent pas partager une touche (elles
s'échangent). Les touches sont physiques : ZQSD sur AZERTY correspond à WASD sur QWERTY.

| Action | Par défaut |
| --- | --- |
| Se déplacer | ZQSD / WASD |
| Marcher · s'accroupir · sauter | Maj · Ctrl · Espace |
| Tirer | Clic gauche |
| Utiliser / désamorcer | F |
| Fumigène (mini-carte) · incendiaire · flash | 1 · 2 · 3 |
| Lancer l'utilitaire | Clic droit |
| Menu · plein écran (fixes) | Échap · F11 |

Perdre le focus de la fenêtre pendant une session l'annule (les statistiques seraient faussées).

## Diagnostic, routine et difficulté adaptative

- **Diagnostic (2 minutes)** : quatre épreuves de 27 s — flick, tracking, réaction, contrôle du
  spray — notées sur 100 (barèmes en tête de `scripts/drills/benchmark_drill.gd`). La note la
  plus basse désigne la priorité. Les résultats sont enregistrés dans `user://profile.json` par
  l'autoload `PlayerProfile`.
- **Routine du jour** : `scripts/training_plan.gd` construit une routine d'environ 25 minutes à
  partir du dernier diagnostic (le point faible reçoit le plus de sessions, plus un socle fixe :
  arrêt avant le tir, placement du viseur, tenue d'angle). Le menu affiche l'avancement et un
  bouton lance la session suivante.
- **Difficulté adaptative** : chaque exercice qui publie un taux de réussite (`success_ratio`)
  voit son niveau monter de 8 % au-dessus de 75 % de réussite et baisser de 7 % en dessous de
  45 %. Aujourd'hui : Gridshot et Microflicks (cibles plus petites) et Duel (cible plus rapide,
  temps plus court).
- **Duel** : cible humanoïde (`scenes/humanoid_target.tscn`) qui strafe de façon erratique avec
  de brefs arrêts ; tête en un tir, corps en trois ; tir automatique avec recul.
- **Arme** : profil générique réglable en tête de `scripts/player.gd` (cadence, montée et
  balancement du recul). Ce ne sont pas les valeurs d'un jeu précis.

## Combat, déplacement avancé et réticule

- **Armes** (`scripts/weapons.gd`) : fusil automatique, mitraillette, pistolet semi-automatique,
  avec cadence, recul et dégâts propres. Profils génériques, choisis dans le menu.
- **Accroupi** : caméra plus basse, déplacement lent, recul et dispersion réduits de 20 %.
  **Saut** : un tir en l'air part n'importe où.
- **Bruits de pas** : courir s'entend, marcher ou s'accroupir non ; la distance parcourue en
  faisant du bruit est enregistrée.
- **Tap et rafales** : cible lointaine, longueur moyenne des rafales mesurée.
- **Duel d'angle** : l'adversaire riposte après un délai de réaction ; exposition, sortie serrée
  ou large, re-sorties.
- **Cibles multiples** : vagues de trois silhouettes ; temps de transfert, transferts dans la
  même rafale.
- **Désamorçage** : reprise de site avec une charge de 45 s à désamorcer en 7 s.
- **Charge** (`scenes/bomb.tscn`, `scripts/bomb.gd`) : objet posé au centre d'un site, qui
  clignote et bipe de plus en plus vite (son spatialisé) ; le ton du bip change quand quelqu'un
  la désamorce. Dans **Désamorçage**, c'est le joueur qui la désamorce ; dans **Défense de la
  charge**, des adversaires marchent jusqu'à elle et la désamorcent s'ils ne sont pas éliminés.
- **Réticule** : préréglages, éditeur, et un code texte (`KA1;forme;couleur;longueur;épaisseur;
  écart;point;contour;opacité`) pour exporter (copie dans le presse-papiers) ou importer.
  Ce format est propre à l'application.

## Intelligence artificielle des bots

- **Rangs** (`scripts/ai/bot_ranks.gd`) : neuf profils, de Fer à Radiant, choisis dans le menu
  (« Rang des bots ») ou laissés en adaptatif. Chaque profil règle le temps de réaction, l'écart
  de visée à la découverte et le temps pour le résorber, le retard sur une cible mobile, la
  maîtrise du recul, la part de tirs visés à la tête, le champ de vision, la vitesse de
  rotation, l'ouïe, la vitesse, la longueur des rafales, la tendance à tirer en marchant, l'usage
  du couvert et le partage d'information. Ce sont des estimations, à ajuster dans ce fichier.
- **Cerveau** (`scripts/ai/bot_brain.gd`) : machine à états — déplacement (A*), combat, mise à
  couvert puis ressortie, désamorçage.
  - *Perception* : ligne de vue dans un champ de vision orienté, ouïe, réaction aux dégâts,
    position partagée entre bots. Un bot ne connaît jamais ta position sans l'avoir perçue.
  - *Visée* : l'écart de visée retombe avec le temps passé à te voir, augmente si tu te déplaces
    latéralement et avec le recul non compensé. Chaque balle est un rayon réel : tête = mort
    immédiate, corps = trois balles.
- **Navigation** (`scripts/ai/nav_grid.gd`) : grille de 1 m construite depuis les collisions de
  la carte, chemins par `AStarGrid2D`.
- **Escouade** (`scripts/ai/bot_squad.gd`) : partage de ta position entre bots, rôles (entrée,
  contournement, soutien), tir croisé quand l'un d'eux engage, un seul désamorceur couvert par
  les autres et relevé s'il tombe. La part de bots qui obéissent dépend du rang (0 % Fer, 100 % Radiant).
- **Exercices** : Escarmouche (trois bots te traquent) et Défense de la charge (les bots
  viennent désamorcer et ripostent).

## Utilitaires et lineups

Utilitaires génériques (`scripts/utility/`), disponibles dans Escarmouche, Défense de la charge
(deux charges de chaque) et Lineups (illimités). Ce ne sont pas les compétences d'un personnage
précis.

- **Fumigène — touche 1** : ouvre la mini-carte (`ui/tactical_map.gd`). Clic gauche sur une zone
  praticable : le fumigène s'y déploie une seconde plus tard, pour 15 s. Clic droit ou 1 pour
  annuler. Il bloque la vue (la tienne et celle des bots), pas les balles.
- **Incendiaire — touche 2, puis clic droit** : lancé dans la direction du viseur, il rebondit
  et s'enflamme au premier contact avec le sol : zone de 3,5 m pendant 7 s, 35 points de dégâts
  par seconde pour quiconque s'y trouve, toi compris.
- **Flash — touche 3, puis clic droit** : explose en l'air après 0,9 s. Aveugle 2,2 s ceux qui
  l'ont dans leur champ de vision sans obstacle : les bots, et toi (écran blanc).
- **Lineups** : une cible est marquée sur un site ; fais-y atterrir un incendiaire. Un lancer
  réussi enregistre ta position, ton orientation et l'inclinaison du viseur dans
  `user://profile.json` ; aux sessions suivantes, un disque cyan marque l'endroit où te placer.

## Exercices

| Exercice | Ce qu'il travaille | Carte | Mesures principales |
| --- | --- | --- | --- |
| **Gridshot** | Flicks larges, vitesse d'enchaînement | Stand de tir | Précision, temps entre cibles, over/underflick, fluidité |
| **Microflicks** | Micro-ajustements sur cibles de la taille d'une tête | Stand de tir | Idem, sur de petites amplitudes |
| **Tenue d'angle** | Réaction, premier tir, placement du viseur | Hall d'angles | Réaction médiane, premier tir, tirs prématurés, avance du viseur, tirs derrière/devant |
| **Strafe / contre-strafe** | S'arrêter net avant de tirer | Couloir de strafe | Vitesse au tir, temps d'arrêt, méthode d'arrêt, délai entre touches, trop tôt / trop tard |
| **Jiggle peek** | Prendre une information sans se faire toucher | Hall d'angles | Durée d'exposition, sorties sans information, dépassement, régularité |
| **Pré-visée** | Placement du viseur en nettoyant des angles | Parcours | Erreur de pré-visée (verticale et horizontale), temps pour abattre, tirs en mouvement |
| **Dernière seconde** | Lire le rythme des bips d'une charge | Stand de tir | Écart au dernier instant possible, explosions, effet de la pression |

| **Attaque de site** | Entrer sur un site et nettoyer chaque angle | Grande carte au choix | Erreur de pré-visée, temps pour abattre, tirs en mouvement |
| **Reprise de site** | Revenir du spawn défenseur et reprendre un site | Grande carte au choix | Idem, départ côté défense |
| **Exploration libre** | Apprendre une carte | Grande carte au choix | Distance, temps en mouvement (Échap termine la session) |

Chaque exercice est un script dans `scripts/drills/` qui étend `drill_base.gd`, inscrit dans
`scripts/drills/drill_catalog.gd` (titre, description, carte, durée, paramètres). En ajouter un
revient à écrire un script et une entrée de catalogue.

### Déplacement et précision

Le déplacement vise le ressenti d'un FPS tactique moderne comme Valorant (`scripts/player.gd`) :

| | Valeur |
| --- | --- |
| Course | 5,4 m/s au fusil, 5,73 m/s à la mitraillette et au pistolet |
| Marche · accroupi | 54 % · 45 % de la course, silencieux |
| Départ | pleine vitesse en ~160 ms |
| Arrêt en relâchant | tir précis après ~85 ms |
| Contre-strafe | tir précis après ~50 ms |
| Tir précis | sous 1,5 m/s ; au-delà, déviation croissante ; en l'air, jusqu'à 8° |
| Première balle | dispersion propre à l'arme (0,25° au fusil), −20 % accroupi |
| Saut | 0,78 m, aucun gain de vitesse en l'air, ralentissement à l'atterrissage |
| Balle reçue | vitesse réduite à 30 %, rétablie en 0,5 s |

L'arrêt est franc même sans contre-strafe, qui reste un peu plus rapide. Ces valeurs sont des
estimations réglables en tête du fichier, pas des mesures du jeu.

### Dernière seconde

Une charge armée est posée devant toi : elle clignote et bipe de plus en plus vite, sans
chronomètre. Lance le désamorçage (touche « utiliser ») le plus tard possible ; il dure 7 s.
Repère : les bips passent à quatre par seconde 10 s avant l'explosion, il reste alors 3 s pour
lancer. Deux manches de 45 s, la seconde en abattant des cibles.

## Cartes

Les cartes sont des **tracés graybox originaux** (murs, caisses, repères), conçus pour chaque
situation d'entraînement ; ce ne sont pas des reproductions de cartes d'un jeu existant.

- `scenes/arena.tscn` — stand de tir.
- `scenes/maps/strafe_lane.tscn` — couloir de strafe : zone de déplacement derrière un comptoir,
  cibles à hauteur de tête à 16 m.
- `scenes/maps/angle_hall.tscn` — hall d'angles : un mur de couverture dont on tranche le coin
  (jiggle peek), et au fond une cloison percée d'un passage (tenue d'angle).
- `scenes/maps/kill_house.tscn` — parcours : cinq couloirs en serpentin, reliés par des passages
  alternés, avec caisses basses et hautes. Deux positions de cible possibles par angle.

### Grandes cartes tactiques

Sept cartes originales de 130 à 144 m sur 140 m, choisies dans le menu pour les exercices
« Attaque de site », « Reprise de site » et « Exploration libre » : **Citadelle**, **Triade**
(trois sites), **Faubourg**, **Entrepôt**, **Canal**, **Rotonde** et **Dédale**
(`scenes/maps/tactical_*.tscn`). Toutes suivent la même grammaire — spawn attaquants au sud,
spawn défenseurs au nord, un lobby et une entrée principale par site, une entrée secondaire
depuis le mid, une liaison défensive — avec des formes différentes : entrée en chicane, longue
ligne droite, goulot, double mid, cour centrale, couloir de contournement, site central.
Chaque site est délimité au sol par un contour magenta, signalé par sa lettre en hauteur, et
garni de caisses basses (1,2 à 1,3 m) et hautes (2,4 m). Seize positions de cible par site ;
huit sont tirées au sort à chaque session.

Chaque carte contient un nœud `Markers` dont les `Marker3D` nomment les points utilisés par les
exercices (apparition du joueur, positions de cibles). Elles s'éditent librement dans Godot :
déplacer un mur, une caisse ou un repère suffit.

## Données collectées

À chaque tick physique (1000 Hz) pendant une session :

- yaw et pitch de la caméra, vitesse angulaire ;
- position et vitesse de déplacement du joueur ;
- état des touches de déplacement.

À chaque événement :

- **tir** : touché ou non, écart angulaire à la cible visée, rayon apparent de la cible, vitesse
  du joueur, déviation appliquée, et données propres à l'exercice (méthode d'arrêt, temps de
  réaction, temps depuis la découverte de la cible...) ;
- **touche** enfoncée ou relâchée, avec la vitesse à cet instant ;
- **événement d'exercice** : apparition ou découverte d'une cible, début et fin d'une sortie de
  couverture, validation d'un décompte...

Le rapport de fin de session en tire, selon l'exercice : précision, temps entre cibles,
overflick / underflick, indice de fluidité, heatmap des tirs ratés, trajet total du viseur et
distance parcourue par la souris, distance et temps de déplacement, cadence de tir, plus toutes
les statistiques de l'exercice. Le bouton **TOUTES LES DONNÉES** du rapport liste chaque valeur.

### Fichiers écrits

Tout est rangé dans le dossier utilisateur du projet (`user://`, affiché par *Projet → Ouvrir le
dossier de données utilisateur* dans l'éditeur) :

- `settings.cfg` — réglages ;
- `history.json` — toutes les statistiques scalaires de chaque session, pour suivre la
  progression (2000 sessions conservées) ;
- `telemetry/<date>_<exercice>.csv` — un échantillon par ligne (1000 par seconde) ;
- `telemetry/<date>_<exercice>.json` — rapport complet, tirs et événements.

Les 20 dernières sessions sont conservées dans `telemetry/`. L'export brut se désactive dans le
menu (section *Son et données*).

## Conseil du coach

À la fin de chaque exercice, `scripts/coach.gd` passe les statistiques au crible de règles
propres à l'exercice et affiche le conseil le plus prioritaire, suivi de deux pistes
secondaires. Exemples :

- overflick fréquent → freiner plus tôt, avec une valeur de cm/360° à essayer ;
- tirs partis avant l'arrêt → vitesse moyenne au tir et rappel du geste de contre-strafe ;
- viseur trop bas à la découverte des cibles → de combien de degrés, et comment le corriger ;
- décompte trop rapide → décalage en pourcentage et ce qu'il représente sur 38 s.

Le coach compare aussi le score à l'historique de l'exercice (record, moyenne des cinq dernières
sessions). Les seuils sont de simples constantes dans le script.

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
- Le FOV se règle en FOV horizontal 16:9 (103° par défaut).
- Le réticule (croix, croix + point, point, cercle ; couleur, longueur, épaisseur, écart, contour,
  opacité) est dessiné au pixel physique près.

## Méthodes d'analyse

- **Overflick / Underflick** : chaque trajet entre deux tirs d'au moins 3° est analysé. On isole
  le mouvement balistique primaire (premier sous-mouvement rapide, après la fin de la décélération
  du tir précédent) et on projette sa position finale sur l'axe départ → cible. Au-delà du bord
  opposé de la cible : overflick. Avant le bord proche : underflick. Sinon : précis.
- **Indice de fluidité** : variance de l'accélération angulaire de chaque mouvement, rapportée à
  la variance minimale théorique pour la même amplitude et la même durée. 100 correspond à un
  geste unique de type « minimum-jerk ».
- **Exposition** (jiggle peek) : le joueur est exposé dès que l'adversaire a une ligne de vue sur
  sa tête ou une épaule ; il a l'information quand l'adversaire est à l'écran. Les épaules
  dépassent 30 cm avant la caméra.
- **Erreur de pré-visée** : écart angulaire entre le viseur et la cible à l'image où elle devient
  visible, décomposé en vertical (viseur trop bas / trop haut) et horizontal.

### Résolution temporelle

Godot distribue les événements souris et clavier une fois par image rendue. L'échantillonnage est
bien à 1000 Hz, mais la visée et les touches ne changent qu'à la cadence du rendu : la finesse de
l'analyse dépend donc du FPS. C'est pourquoi la V-Sync est désactivée et le FPS illimité par
défaut pendant une session. Viser 144 FPS ou plus.

## Structure

```
project.godot                 Configuration (Forward+, physique 1000 Hz, autoloads, thème)
scenes/
  main.tscn                   Scène principale : carte + joueur + exercice + UI
  arena.tscn, maps/           Cartes
  player.tscn, target.tscn    Joueur (CharacterBody3D), cible
  effects/                    Explosion de cible, impact, traceur
scripts/
  game_manager.gd             États de jeu, chargement de la carte et de l'exercice
  player.gd                   Visée brute, déplacement, tir, imprécision en mouvement
  telemetry_manager.gd        Autoload « Telemetry » : capture 1000 Hz, analyse, export
  session_history.gd          Autoload « SessionHistory » : historique des sessions
  settings_manager.gd         Autoload « GameSettings » : réglages
  sfx.gd                      Autoload « Sfx » : sons synthétisés
  coach.gd                    Règles de conseil
  drills/                     Classe de base, catalogue et exercices
  stats.gd, fx_spawner.gd, target.gd, tracer.gd, one_shot_effect.gd
ui/
  hud.tscn                    Réticule, score, chrono, objectif, retour, jauge de vitesse
  stats_dashboard.tscn        Rapport : coach, KPI, graphique, flicks, heatmap, données
  main_menu.tscn              Lobby : accueil, exercices par catégorie, profil
  settings_panel.gd           Réglages par onglets, dont les touches
  bar_chart.gd, heatmap.gd, flick_bar.gd, speed_gauge.gd, crosshair.gd, kinetic_theme.tres
materials/, shaders/, environment/
```

## Qualité graphique

Trois préréglages dans le menu : **Performance** (sans MSAA ni SSAO), **Qualité** (MSAA 4x, SSAO,
glow, ombres douces — par défaut) et **Ultra** (ajoute SDFGI et réflexions SSR). Hors session, le
FPS est plafonné à 120 pour ménager le GPU.
