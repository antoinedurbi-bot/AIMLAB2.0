extends RefCounted
## Profils d'armes génériques. Ce ne sont pas les valeurs d'un jeu précis :
## ajuste-les ou ajoutes-en ici, le menu et le joueur les prennent en compte.
##
##   automatic   : tir continu tant que le clic est maintenu ;
##   interval    : temps entre deux balles (s) ;
##   climb       : montée verticale du recul par balle (°), sur `climb_shots` balles ;
##   sway        : amplitude du balancement horizontal ensuite (°) ;
##   head / body : dégâts (une cible a 100 points de vie).

const ORDER := ["rifle", "smg", "pistol"]
const PROFILES := {
	"rifle": {"name": "Fusil automatique", "automatic": true, "interval": 0.1, "climb": 0.6, "climb_shots": 8, "sway": 1.5, "head": 150.0, "body": 40.0},
	"smg": {"name": "Mitraillette", "automatic": true, "interval": 0.075, "climb": 0.4, "climb_shots": 10, "sway": 2.2, "head": 80.0, "body": 27.0},
	"pistol": {"name": "Pistolet semi-automatique", "automatic": false, "interval": 0.16, "climb": 0.9, "climb_shots": 3, "sway": 0.4, "head": 105.0, "body": 30.0},
}


static func get_profile(weapon_id: String) -> Dictionary:
	var profile: Dictionary = PROFILES.get(weapon_id, PROFILES["rifle"])
	return profile
