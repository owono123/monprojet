class_name Dimensions
extends RefCounted

## Dimensions reglementaires d'un terrain de football, en metres (Loi 1 du jeu).
## Regroupees ici parce qu'elles servent a la fois aux regles (hors-jeu, sorties,
## corners) et a l'affichage : une seule source, jamais deux valeurs qui derivent.
## Origine au point central, x dans le sens de la longueur, z dans la largeur.

const LONGUEUR := 105.0
const LARGEUR := 68.0
const DEMI_LONGUEUR := LONGUEUR * 0.5   # 52.5
const DEMI_LARGEUR := LARGEUR * 0.5     # 34.0

const RAYON_ROND_CENTRAL := 9.15
const RAYON_ARC_PENALTY := 9.15
const RAYON_CORNER := 1.0

const SURFACE_REPARATION_PROFONDEUR := 16.5
const SURFACE_REPARATION_DEMI_LARGEUR := 20.16   # 16.5 + 3.66 de demi-but
const SURFACE_BUT_PROFONDEUR := 5.5
const SURFACE_BUT_DEMI_LARGEUR := 9.16           # 5.5 + 3.66

const POINT_PENALTY := 11.0

const BUT_DEMI_LARGEUR := 3.66    # 7,32 m entre les poteaux
const BUT_HAUTEUR := 2.44
const BUT_PROFONDEUR := 2.0       # profondeur des filets
const POTEAU_RAYON := 0.06

const LARGEUR_TRACE := 0.12       # epaisseur des lignes peintes

## Bord de la pelouse au-dela des lignes de touche : sans cette marge, le regard
## bute sur le vide des que la camera s'abaisse.
const MARGE_PELOUSE := 6.0

## Vrai si le point est dans les limites du jeu (lignes comprises).
static func dans_le_terrain(point: Vector3) -> bool:
	return absf(point.x) <= DEMI_LONGUEUR and absf(point.z) <= DEMI_LARGEUR

## Vrai si le point est dans la surface de reparation du camp indique.
## `camp` vaut -1 pour le but situe en x negatif, +1 pour celui en x positif.
static func dans_la_surface(point: Vector3, camp: int) -> bool:
	if signi(camp) * point.x < DEMI_LONGUEUR - SURFACE_REPARATION_PROFONDEUR:
		return false
	return absf(point.x) <= DEMI_LONGUEUR and absf(point.z) <= SURFACE_REPARATION_DEMI_LARGEUR

## Position du point de penalty du camp indique.
static func point_de_penalty(camp: int) -> Vector3:
	return Vector3(signi(camp) * (DEMI_LONGUEUR - POINT_PENALTY), 0.0, 0.0)
