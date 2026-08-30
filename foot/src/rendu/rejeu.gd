class_name Rejeu
extends RefCounted

## Enregistrement des dernieres secondes de jeu, pour le ralenti d'apres-but.
##
## Deux facons de rejouer une action existent, et le projet aura les deux.
##
## Celle de ce fichier garde les POSITIONS dans un tampon circulaire : dix
## secondes de jeu, ecrasees en continu. C'est ce qu'il faut pour un ralenti
## immediat apres un but, parce qu'on peut repartir de n'importe quelle image
## sans rien recalculer.
##
## L'autre, prevue plus tard, gardera les COMMANDES et rejouera la simulation
## par-dessus. Elle ne coute que quelques kilo-octets pour un match entier — la
## simulation etant deterministe, les memes commandes redonnent exactement le
## meme match — et c'est celle qui permettra d'enregistrer, de sauvegarder et
## d'echanger des actions. Mais elle oblige a resimuler depuis le coup d'envoi,
## ce qui ne convient pas a un ralenti qu'on veut voir dans la seconde.
##
## Chaque image occupe : trois nombres pour le ballon, puis cinq par joueur
## (position, orientation, allure). Dix secondes tiennent dans moins de trois
## cents kilo-octets.

const SECONDES_GARDEES := 10
const IMAGES_GARDEES := SECONDES_GARDEES * 60
const NOMBRE_DE_JOUEURS := 22
const NOMBRES_PAR_JOUEUR := 5
const NOMBRES_PAR_IMAGE := 3 + NOMBRE_DE_JOUEURS * NOMBRES_PAR_JOUEUR

var _tampon := PackedFloat32Array()
## Nombre total d'images enregistrees depuis le debut du match. Sert a savoir
## combien du tampon est reellement rempli.
var _ecrites := 0

func _init() -> void:
	_tampon.resize(IMAGES_GARDEES * NOMBRES_PAR_IMAGE)

## Nombre d'images disponibles pour un ralenti.
func disponibles() -> int:
	return mini(_ecrites, IMAGES_GARDEES)

## Enregistre l'etat courant. Appele une fois par pas de simulation.
func enregistrer(simulation: Simulation) -> void:
	var debut := (_ecrites % IMAGES_GARDEES) * NOMBRES_PAR_IMAGE
	var ballon := simulation.ballon.position
	_tampon[debut] = ballon.x
	_tampon[debut + 1] = ballon.y
	_tampon[debut + 2] = ballon.z

	var decalage := debut + 3
	for equipe in simulation.equipes:
		for joueur in equipe.joueurs:
			_tampon[decalage] = joueur.position.x
			_tampon[decalage + 1] = joueur.position.y
			_tampon[decalage + 2] = joueur.position.z
			_tampon[decalage + 3] = joueur.orientation
			_tampon[decalage + 4] = Vector2(joueur.vitesse.x, joueur.vitesse.z).length()
			decalage += NOMBRES_PAR_JOUEUR
	_ecrites += 1

## Position du ballon a l'image demandee, comptee depuis la plus ancienne
## disponible.
func ballon_a(image: int) -> Vector3:
	var debut := _debut_de(image)
	return Vector3(_tampon[debut], _tampon[debut + 1], _tampon[debut + 2])

## Etat d'un joueur : position, orientation et allure.
func joueur_a(image: int, index: int) -> Dictionary:
	var debut := _debut_de(image) + 3 + index * NOMBRES_PAR_JOUEUR
	return {
		"position": Vector3(_tampon[debut], _tampon[debut + 1], _tampon[debut + 2]),
		"orientation": _tampon[debut + 3],
		"allure": _tampon[debut + 4],
	}

## Convertit un numero d'image du ralenti en position dans le tampon circulaire.
func _debut_de(image: int) -> int:
	var nombre := disponibles()
	var plus_ancienne := _ecrites - nombre
	var absolue := plus_ancienne + clampi(image, 0, maxi(nombre - 1, 0))
	return (absolue % IMAGES_GARDEES) * NOMBRES_PAR_IMAGE
