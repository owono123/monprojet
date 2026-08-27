class_name Alea
extends RefCounted

## Generateur pseudo-aleatoire a graine explicite.
##
## Le jeu n'appelle JAMAIS randf() ni randi() : ces fonctions puisent dans un
## etat global que rien ne controle, ce qui rendrait les replays irreproductibles
## et ferait diverger les deux telephones en match reseau. Tout tirage passe par
## une instance de cette classe, dont la graine est enregistree avec le match.
##
## Algorithme : xorshift64*, choisi pour tenir en quelques lignes exactes et
## donner le meme resultat sur tout processeur, ce qui est le seul critere ici.

const _MULT: int = 0x2545F4914F6CDD1D
# 0x9E3779B97F4A7C15 (nombre d'or en 64 bits). Ecrit en deux moities : un
# litteral de 16 chiffres hexadecimaux depasserait la capacite d'un entier signe.
const _OR_D_OR: int = (0x9E3779B9 << 32) | 0x7F4A7C15

var _etat: int = 0

func _init(graine: int = 12345) -> void:
	reamorcer(graine)

## Repart d'une graine connue. Deux instances reamorcees avec la meme valeur
## produisent exactement la meme suite de tirages.
func reamorcer(graine: int) -> void:
	_etat = graine if graine != 0 else _OR_D_OR
	# Quelques tours a vide : une graine pauvre en bits (0, 1, 42...) donnerait
	# sinon des premiers tirages tres correles.
	for _i in 4:
		_avancer()

## Decalage a droite NON signe. L'operateur >> de GDScript propage le bit de
## signe ; sans ce masque, l'algorithme divergerait des que l'etat devient
## negatif, et les replays ne seraient plus reproductibles.
static func _dec_droite(valeur: int, bits: int) -> int:
	return (valeur >> bits) & ((1 << (64 - bits)) - 1)

func _avancer() -> int:
	_etat ^= _dec_droite(_etat, 12)
	_etat ^= _etat << 25
	_etat ^= _dec_droite(_etat, 27)
	return _etat * _MULT

## Reel dans [0, 1). Construit sur les 53 bits de poids fort, soit exactement la
## precision d'un flottant double : aucun biais d'arrondi.
func reel() -> float:
	return float(_dec_droite(_avancer(), 11)) / 9007199254740992.0

## Reel dans [minimum, maximum).
func reel_entre(minimum: float, maximum: float) -> float:
	return minimum + reel() * (maximum - minimum)

## Entier dans [0, borne). Renvoie 0 si la borne est nulle ou negative.
func entier(borne: int) -> int:
	if borne <= 0:
		return 0
	return _dec_droite(_avancer(), 1) % borne

## Entier dans [minimum, maximum] inclus.
func entier_entre(minimum: int, maximum: int) -> int:
	if maximum <= minimum:
		return minimum
	return minimum + entier(maximum - minimum + 1)

## Vrai avec la probabilite donnee (0.0 = jamais, 1.0 = toujours).
func chance(probabilite: float) -> bool:
	return reel() < probabilite

## Etat interne, pour enregistrer un point de reprise dans un replay.
func etat() -> int:
	return _etat

func restaurer(etat_sauvegarde: int) -> void:
	_etat = etat_sauvegarde
