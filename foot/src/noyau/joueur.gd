class_name Joueur
extends RefCounted

## Un joueur dans la simulation. Aucune notion d'affichage : ni maillot, ni
## visage, ni animation — seulement une position, une vitesse et des
## caracteristiques.

## Caracteristiques, de 0 a 100. Elles sont toutes a 70 pour l'instant ;
## l'editeur de la phase 4 viendra les remplir joueur par joueur.
var vitesse_max := 70.0
var acceleration := 70.0
var passe := 70.0
var tir := 70.0
var dribble := 70.0
var defense := 70.0
var physique := 70.0
var gardien := 20.0

var numero: int = 0
var poste: int = Postes.MILIEU_CENTRAL
var equipe: int = 0
var rang: int = 0            # place dans l'effectif, de 0 a 10

var position := Vector3.ZERO
var vitesse := Vector3.ZERO
var orientation := 0.0       # radians, direction du regard
var base := Vector3.ZERO     # place de formation, en metres

## Allure de course, en metres par seconde.
##
## Les bornes viennent du jeu reel : un joueur lent tient 4,6 m/s en course de
## fond, un tres rapide 7,0 ; en sprint on va de 6,4 a 9,8, cette derniere
## valeur etant celle d'un ailier de tres haut niveau sur vingt metres.
func allure(sprint: bool) -> float:
	var part := clampf(vitesse_max, 0.0, 100.0) / 100.0
	if sprint:
		return 6.4 + part * 3.4
	return 4.6 + part * 2.4

## Acceleration disponible, en metres par seconde carree. Volontairement plus
## vive que dans la realite : au pouce, un joueur qui met deux secondes a
## atteindre son allure donne l'impression de patiner.
func poussee() -> float:
	return 9.0 + clampf(acceleration, 0.0, 100.0) / 100.0 * 5.0

func freinage() -> float:
	return poussee() * 1.7

## Avance d'un pas vers la direction demandee (vecteur a plat, longueur au plus 1).
func avancer(pas: float, direction: Vector3, sprint: bool) -> void:
	var voulue := Vector3(direction.x, 0.0, direction.z)
	if voulue.length() > 1.0:
		voulue = voulue.normalized()
	var cible := voulue * allure(sprint)

	var ecart := cible - vitesse
	var variation := (poussee() if voulue.length_squared() > 0.0 else freinage()) * pas
	if ecart.length() <= variation:
		vitesse = cible
	else:
		vitesse += ecart.normalized() * variation

	position += vitesse * pas
	position.y = 0.0
	if vitesse.length_squared() > 0.09:
		orientation = atan2(vitesse.x, vitesse.z)

## Envoie le joueur vers un point, en marchant, courant ou sprintant selon la
## distance restante. Sans ce dosage, les joueurs oscilleraient autour de leur
## place au lieu de s'y poser.
func rejoindre(pas: float, point: Vector3, empressement: float = 1.0) -> void:
	var ecart := point - position
	ecart.y = 0.0
	var distance := ecart.length()
	if distance < 0.35:
		avancer(pas, Vector3.ZERO, false)
		return
	var direction := ecart / distance
	# En dessous de trois metres on ralentit progressivement pour arriver pose.
	var intensite := clampf(distance / 3.0, 0.0, 1.0) * clampf(empressement, 0.0, 1.0)
	avancer(pas, direction * intensite, distance > 12.0 and empressement > 0.9)

## Distance au ballon, mesuree a plat : un ballon en cloche au-dessus de la tete
## n'est pas « proche » au sens du controle.
func distance_a(point: Vector3) -> float:
	return Vector2(position.x - point.x, position.z - point.z).length()
