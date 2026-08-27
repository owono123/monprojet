class_name Commandes
extends RefCounted

## Ce qu'un joueur demande pendant une image, et rien d'autre.
##
## La simulation ne lit jamais l'ecran tactile ni la manette : elle recoit cet
## objet. C'est ce qui permet trois choses avec le meme code — jouer, rejouer un
## replay (on relit les commandes enregistrees) et jouer en reseau (on recoit
## les commandes de l'autre telephone).
##
## Tenir en 4 octets n'est pas un exercice de style : a 60 images par seconde,
## un match de 20 minutes represente 72 000 images. En 4 octets cela fait 288 ko
## pour un match entier, contre plusieurs gigaoctets pour une video.

# Boutons, un bit chacun.
const AUCUN      := 0
const PASSE      := 1 << 0
const TIR        := 1 << 1
const SPRINT     := 1 << 2
const CENTRE     := 1 << 3
const LOB        := 1 << 4
const CHANGER    := 1 << 5
const TACLE      := 1 << 6
const PRESSING   := 1 << 7

## Direction demandee, dans [-1, 1] sur chaque axe. x suit la longueur du
## terrain, y la largeur (c'est un vecteur a plat, pas une hauteur).
var direction := Vector2.ZERO

## Etat des boutons enfonces, combinaison des constantes ci-dessus.
var boutons: int = AUCUN

func _init(direction_demandee: Vector2 = Vector2.ZERO, boutons_enfonces: int = AUCUN) -> void:
	direction = direction_demandee
	boutons = boutons_enfonces

func appuye(bouton: int) -> bool:
	return (boutons & bouton) != 0

## Serialise en 4 octets. La direction est quantifiee sur un octet signe par
## axe : 1/127 de course de joystick, tres en dessous de ce qu'un pouce peut
## viser, donc la perte est sans effet sur le jeu.
func vers_octets() -> PackedByteArray:
	var tampon := PackedByteArray()
	tampon.resize(4)
	tampon.encode_s8(0, _quantifier(direction.x))
	tampon.encode_s8(1, _quantifier(direction.y))
	tampon.encode_u16(2, boutons & 0xFFFF)
	return tampon

static func depuis_octets(tampon: PackedByteArray, decalage: int = 0) -> Commandes:
	var lues := Commandes.new()
	lues.direction = Vector2(
		float(tampon.decode_s8(decalage)) / 127.0,
		float(tampon.decode_s8(decalage + 1)) / 127.0)
	lues.boutons = tampon.decode_u16(decalage + 2)
	return lues

static func _quantifier(valeur: float) -> int:
	return int(roundf(clampf(valeur, -1.0, 1.0) * 127.0))

## Renvoie la direction telle que la simulation doit la lire : quantifiee
## exactement comme apres un aller-retour reseau. Sans cela, l'hote et le client
## calculeraient a partir de valeurs legerement differentes.
func direction_normalisee() -> Vector2:
	var quantifiee := Vector2(
		float(_quantifier(direction.x)) / 127.0,
		float(_quantifier(direction.y)) / 127.0)
	if quantifiee.length_squared() > 1.0:
		return quantifiee.normalized()
	return quantifiee
