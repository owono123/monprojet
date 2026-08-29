class_name EtatMatch
extends RefCounted

## Ce qui decrit le match au niveau de la rencontre : le temps, le score, la
## phase en cours. Les positions des joueurs et du ballon vivent dans les objets
## Equipe et Ballon, et ne sont pas recopiees ici — a soixante images par
## seconde, recopier vingt-deux positions pour rien couterait plus cher que tout
## le reste de la simulation.

enum {
	COUP_D_ENVOI,
	EN_JEU,
	ARRETEE,          # ballon sorti ou faute, en attente de remise en jeu
	MI_TEMPS,
	TERMINE,
}

var image: int = 0                    # images simulees depuis le debut de la periode
var periode: int = 1
var phase: int = COUP_D_ENVOI
var buts_domicile: int = 0
var buts_exterieur: int = 0

## Duree d'une mi-temps, en images. Cinq minutes par defaut ; le menu de la
## phase 2 proposera 5, 10, 15 et 20 minutes.
var duree_periode: int = 5 * 60 * 60

## Temps ecoule dans la periode, en secondes de jeu.
func secondes() -> float:
	return float(image) / 60.0

func minutes_affichees() -> int:
	return int(secondes()) / 60 + (0 if periode == 1 else int(duree_periode / 3600))

func periode_terminee() -> bool:
	return image >= duree_periode

func marquer(pour_domicile: bool) -> void:
	if pour_domicile:
		buts_domicile += 1
	else:
		buts_exterieur += 1
