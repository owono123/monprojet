class_name Formation
extends RefCounted

## Dispositions tactiques.
##
## Les positions sont donnees en coordonnees reduites, independantes des
## dimensions du terrain : la profondeur va de -1 (sa propre ligne de but) a +1
## (celle de l'adversaire), la largeur de -1 a +1. La conversion en metres se
## fait au dernier moment, ce qui permet de decrire une formation une seule fois
## sans se soucier du sens dans lequel l'equipe joue.
##
## Chaque entree vaut [poste, profondeur, largeur].

const QUATRE_QUATRE_DEUX := [
	[Postes.GARDIEN, -0.94, 0.00],
	[Postes.LATERAL_DROIT, -0.60, 0.70],
	[Postes.DEFENSEUR_CENTRAL, -0.66, 0.24],
	[Postes.DEFENSEUR_CENTRAL, -0.66, -0.24],
	[Postes.LATERAL_GAUCHE, -0.60, -0.70],
	[Postes.MILIEU_DROIT, -0.12, 0.72],
	[Postes.MILIEU_CENTRAL, -0.18, 0.24],
	[Postes.MILIEU_CENTRAL, -0.18, -0.24],
	[Postes.MILIEU_GAUCHE, -0.12, -0.72],
	[Postes.ATTAQUANT, 0.34, 0.18],
	[Postes.ATTAQUANT, 0.34, -0.18],
]

const QUATRE_TROIS_TROIS := [
	[Postes.GARDIEN, -0.94, 0.00],
	[Postes.LATERAL_DROIT, -0.58, 0.72],
	[Postes.DEFENSEUR_CENTRAL, -0.66, 0.24],
	[Postes.DEFENSEUR_CENTRAL, -0.66, -0.24],
	[Postes.LATERAL_GAUCHE, -0.58, -0.72],
	[Postes.MILIEU_DEFENSIF, -0.30, 0.00],
	[Postes.MILIEU_CENTRAL, -0.05, 0.30],
	[Postes.MILIEU_CENTRAL, -0.05, -0.30],
	[Postes.AILIER_DROIT, 0.40, 0.66],
	[Postes.ATTAQUANT, 0.46, 0.00],
	[Postes.AILIER_GAUCHE, 0.40, -0.66],
]

const TROIS_CINQ_DEUX := [
	[Postes.GARDIEN, -0.94, 0.00],
	[Postes.DEFENSEUR_CENTRAL, -0.68, 0.34],
	[Postes.DEFENSEUR_CENTRAL, -0.72, 0.00],
	[Postes.DEFENSEUR_CENTRAL, -0.68, -0.34],
	[Postes.MILIEU_DROIT, -0.10, 0.82],
	[Postes.MILIEU_CENTRAL, -0.22, 0.26],
	[Postes.MILIEU_DEFENSIF, -0.36, 0.00],
	[Postes.MILIEU_CENTRAL, -0.22, -0.26],
	[Postes.MILIEU_GAUCHE, -0.10, -0.82],
	[Postes.ATTAQUANT, 0.36, 0.20],
	[Postes.ATTAQUANT, 0.36, -0.20],
]

const CINQ_TROIS_DEUX := [
	[Postes.GARDIEN, -0.94, 0.00],
	[Postes.LATERAL_DROIT, -0.62, 0.78],
	[Postes.DEFENSEUR_CENTRAL, -0.72, 0.30],
	[Postes.DEFENSEUR_CENTRAL, -0.76, 0.00],
	[Postes.DEFENSEUR_CENTRAL, -0.72, -0.30],
	[Postes.LATERAL_GAUCHE, -0.62, -0.78],
	[Postes.MILIEU_CENTRAL, -0.24, 0.34],
	[Postes.MILIEU_DEFENSIF, -0.34, 0.00],
	[Postes.MILIEU_CENTRAL, -0.24, -0.34],
	[Postes.ATTAQUANT, 0.34, 0.20],
	[Postes.ATTAQUANT, 0.34, -0.20],
]

const QUATRE_DEUX_TROIS_UN := [
	[Postes.GARDIEN, -0.94, 0.00],
	[Postes.LATERAL_DROIT, -0.58, 0.72],
	[Postes.DEFENSEUR_CENTRAL, -0.66, 0.24],
	[Postes.DEFENSEUR_CENTRAL, -0.66, -0.24],
	[Postes.LATERAL_GAUCHE, -0.58, -0.72],
	[Postes.MILIEU_DEFENSIF, -0.34, 0.18],
	[Postes.MILIEU_DEFENSIF, -0.34, -0.18],
	[Postes.AILIER_DROIT, 0.14, 0.64],
	[Postes.MILIEU_OFFENSIF, 0.10, 0.00],
	[Postes.AILIER_GAUCHE, 0.14, -0.64],
	[Postes.ATTAQUANT, 0.44, 0.00],
]

const TOUTES := {
	"4-4-2": QUATRE_QUATRE_DEUX,
	"4-3-3": QUATRE_TROIS_TROIS,
	"3-5-2": TROIS_CINQ_DEUX,
	"5-3-2": CINQ_TROIS_DEUX,
	"4-2-3-1": QUATRE_DEUX_TROIS_UN,
}

## Marge laissee entre la formation et les lignes de touche : personne ne se
## place le pied sur la ligne au coup d'envoi.
const MARGE_BORD := 3.0

static func noms() -> Array:
	return TOUTES.keys()

static func par_nom(nom: String) -> Array:
	return TOUTES.get(nom, QUATRE_QUATRE_DEUX)

## Convertit une position reduite en metres sur le terrain.
## `sens` vaut +1 si l'equipe attaque vers les x positifs, -1 sinon.
##
## Les deux coordonnees changent de signe avec le sens de jeu, pas seulement la
## profondeur : c'est une rotation d'un demi-tour du dispositif, pas un miroir.
## Sans cela, le lateral droit d'une equipe se retrouverait du meme cote du
## terrain que le lateral droit de l'autre.
static func vers_metres(profondeur: float, largeur: float, sens: int) -> Vector3:
	var demi_x := Dimensions.DEMI_LONGUEUR - MARGE_BORD
	var demi_z := Dimensions.DEMI_LARGEUR - MARGE_BORD
	var signe := float(signi(sens))
	return Vector3(profondeur * demi_x * signe, 0.0, largeur * demi_z * signe)
