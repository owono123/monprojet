class_name Ballon
extends RefCounted

## Physique du ballon : vitesse, hauteur, rebond, frottement, effet.
##
## Ecrit a la main plutot que confie au moteur physique de Godot, pour deux
## raisons. D'abord le determinisme : Jolt et Godot Physics resolvent les
## contacts dans un ordre qui depend de l'agencement interne des donnees, donc
## un meme replay ne redonne pas la meme trajectoire. Ensuite le controle : un
## ballon de football ne se comporte pas comme une sphere rigide generique, il
## faut pouvoir regler la portance, l'effet et le roulement separement.
##
## Unites : metres, secondes, radians par seconde. L'origine est le point
## central du terrain, y est la hauteur, x la longueur, z la largeur.

const RAYON := 0.11            # ballon taille 5
const GRAVITE := 9.81

## Trainee de l'air : acceleration = K_TRAINEE * |v| * v.
## Derive de 0.5 * rho * Cx * A / m avec rho=1.225, Cx=0.25, A=0.038, m=0.43.
## A 30 m/s cela freine d'environ 12 m/s2, ce qui correspond aux mesures reelles
## sur une frappe tendue.
const K_TRAINEE := 0.0135

## Effet Magnus : acceleration = K_MAGNUS * (rotation x vitesse).
## Calee pour qu'un coup franc a 25 m/s avec 10 tours par seconde devie
## d'environ 1,5 m sur 25 m, ce qui est la courbe d'une frappe enroulee reelle.
## Le calcul aerodynamique complet donnerait davantage ; on reste volontairement
## dans le bas de la fourchette pour que le ballon reste pilotable au pouce.
const K_MAGNUS := 0.0019

const RESTITUTION := 0.55       # part de vitesse verticale rendue au rebond
const FROTTEMENT_REBOND := 0.35 # part de vitesse horizontale perdue au rebond
const DECEL_ROULEMENT := 0.70   # m/s2, resistance du gazon sur un ballon qui roule

## En dessous de cette vitesse de chute, le ballon se pose au lieu de rebondir.
##
## Le seuil ne peut pas etre choisi librement : en un pas de 1/60 s la gravite
## ajoute deja 9,81/60 = 0,16 m/s de vitesse descendante. Un seuil plus bas
## ferait rebondir le ballon a chaque image meme pose au sol, et le frottement
## de rebond lui mangerait toute sa vitesse horizontale en quelques images —
## un ballon pousse ne roulerait pas, il collerait au gazon.
const VITESSE_MINI_REBOND := 0.4

## L'effet perdu par seconde. Un ballon en vol garde sa rotation longtemps : le
## couple aerodynamique qui la freine est faible devant son inertie.
const AMORTI_ROTATION := 0.12

const SEUIL_REPOS := 0.05       # en dessous, le ballon est considere immobile

var position := Vector3(0.0, RAYON, 0.0)
var vitesse := Vector3.ZERO
var rotation := Vector3.ZERO     # vecteur axial : direction = axe, longueur = rad/s
var au_sol := true

## Avance d'un pas de temps.
## `glisse` vient de la meteo : 1.0 par temps sec, plus de 1 sur pelouse mouillee
## (le ballon file), moins de 1 sur la neige (il s'enfonce).
func avancer(pas: float, glisse: float = 1.0) -> void:
	var acceleration := Vector3(0.0, -GRAVITE, 0.0)

	var norme := vitesse.length()
	if norme > 0.0:
		acceleration -= vitesse * (K_TRAINEE * norme)

	# L'effet ne produit de force que si le ballon avance : une balle qui tourne
	# sur place ne devie pas.
	if norme > 0.5 and rotation.length_squared() > 0.0:
		acceleration += rotation.cross(vitesse) * K_MAGNUS

	# Integration semi-implicite : on met a jour la vitesse avant la position.
	# Plus stable que l'Euler explicite pour un cout identique, et surtout
	# parfaitement reproductible d'une execution a l'autre.
	vitesse += acceleration * pas
	position += vitesse * pas

	_amortir_rotation(pas)
	_traiter_sol(pas, glisse)

func _amortir_rotation(pas: float) -> void:
	var reste := 1.0 - AMORTI_ROTATION * pas
	rotation *= maxf(reste, 0.0)

func _traiter_sol(pas: float, glisse: float) -> void:
	if position.y > RAYON:
		au_sol = false
		return

	position.y = RAYON

	if vitesse.y < -VITESSE_MINI_REBOND:
		# Rebond franc.
		vitesse.y = -vitesse.y * RESTITUTION
		var horizontal := Vector3(vitesse.x, 0.0, vitesse.z)
		vitesse.x = horizontal.x * (1.0 - FROTTEMENT_REBOND)
		vitesse.z = horizontal.z * (1.0 - FROTTEMENT_REBOND)
		# Le contact convertit une part de l'effet en trajectoire : c'est ce qui
		# fait qu'un ballon coupe repart de travers apres le premier bond.
		vitesse.x += rotation.z * RAYON * 0.35
		vitesse.z -= rotation.x * RAYON * 0.35
		rotation *= 0.6
		au_sol = false
		return

	# Le ballon roule.
	vitesse.y = 0.0
	au_sol = true
	var vitesse_sol := Vector3(vitesse.x, 0.0, vitesse.z)
	var allure := vitesse_sol.length()
	if allure <= 0.0:
		return
	var frein := (DECEL_ROULEMENT / maxf(glisse, 0.05)) * pas
	if frein >= allure:
		vitesse.x = 0.0
		vitesse.z = 0.0
		rotation = Vector3.ZERO
	else:
		var restant := (allure - frein) / allure
		vitesse.x *= restant
		vitesse.z *= restant

## Frappe le ballon. `direction` est horizontale, `elevation` en degres,
## `effet` en tours par seconde autour de l'axe vertical (positif = brosse a
## droite). Une seule porte d'entree pour toutes les frappes du jeu : passe,
## tir, centre, lob et degagement n'en sont que des reglages.
func frapper(direction: Vector3, puissance: float, elevation: float, effet: float) -> void:
	var plat := Vector3(direction.x, 0.0, direction.z)
	if plat.length_squared() < 0.000001:
		plat = Vector3(1.0, 0.0, 0.0)
	plat = plat.normalized()
	var angle := deg_to_rad(clampf(elevation, 0.0, 80.0))
	vitesse = plat * (puissance * cos(angle))
	vitesse.y = puissance * sin(angle)
	rotation = Vector3(0.0, effet * TAU, 0.0)
	if position.y < RAYON:
		position.y = RAYON
	au_sol = false

## Remet le ballon a un endroit precis, immobile.
func placer(endroit: Vector3) -> void:
	position = Vector3(endroit.x, maxf(endroit.y, RAYON), endroit.z)
	vitesse = Vector3.ZERO
	rotation = Vector3.ZERO
	au_sol = is_equal_approx(position.y, RAYON)

## Vrai quand le ballon ne bouge plus assez pour que quoi que ce soit change.
func immobile() -> bool:
	return au_sol and vitesse.length_squared() < SEUIL_REPOS * SEUIL_REPOS
