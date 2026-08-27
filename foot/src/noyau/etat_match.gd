class_name EtatMatch
extends RefCounted

## Tout ce qui decrit un match a un instant donne, et rien qui concerne
## l'affichage. Cet objet doit pouvoir etre serialise tel quel : c'est lui que
## l'hote envoie au client en match reseau, et c'est son empreinte qui sert a
## verifier qu'un replay redonne bien la meme partie.

var image: int = 0                    # numero de l'image simulee depuis le coup d'envoi
var buts_domicile: int = 0
var buts_exterieur: int = 0

## Position et vitesse du joueur pilote. Provisoire : la phase 1 remplace ce
## joueur unique par les vingt-deux de la feuille de match.
var joueur_position := Vector3.ZERO
var joueur_vitesse := Vector3.ZERO

var ballon_position := Vector3(0.0, Ballon.RAYON, 0.0)
var ballon_vitesse := Vector3.ZERO

## Temps ecoule dans la mi-temps, en secondes de jeu.
func secondes() -> float:
	return float(image) / 60.0

## Empreinte de l'etat, utilisee par les tests de determinisme.
##
## Les flottants sont arrondis au millimetre avant d'etre melanges : deux
## simulations identiques doivent donner la meme empreinte, mais on ne veut pas
## qu'un dernier bit d'arrondi sans consequence sur le jeu fasse echouer le test.
func empreinte() -> int:
	var somme: int = 1469598103934665603
	somme = _melanger(somme, image)
	somme = _melanger(somme, buts_domicile)
	somme = _melanger(somme, buts_exterieur)
	for vecteur in [joueur_position, joueur_vitesse, ballon_position, ballon_vitesse]:
		somme = _melanger(somme, int(roundf(vecteur.x * 1000.0)))
		somme = _melanger(somme, int(roundf(vecteur.y * 1000.0)))
		somme = _melanger(somme, int(roundf(vecteur.z * 1000.0)))
	return somme

static func _melanger(accumulateur: int, valeur: int) -> int:
	# Variante de FNV-1a : simple, sans table, et surtout identique partout.
	var resultat := accumulateur ^ valeur
	return resultat * 1099511628211
