class_name Equipe
extends RefCounted

## Une equipe de onze joueurs et la facon dont elle occupe le terrain.

## Part de la position du ballon repercutee sur toute l'equipe.
##
## C'est le « coulissement de la ligne » : quand le ballon monte, le bloc monte,
## et le defenseur central se retrouve trente metres plus haut qu'au coup
## d'envoi. Sans ce mecanisme, chacun resterait plante a sa place de formation
## et le jeu ressemblerait a un baby-foot.
const COULISSEMENT_LONGITUDINAL := 0.42
const COULISSEMENT_LATERAL := 0.30

## Le gardien sort au plus de tant de metres de sa ligne.
const SORTIE_MAXI_GARDIEN := 7.0

var nom := "Equipe"
var joueurs: Array[Joueur] = []
var sens: int = 1                  # +1 : attaque vers les x positifs
var nom_formation := "4-4-2"

func _init(index_equipe: int, sens_de_jeu: int, formation: String, appellation: String) -> void:
	nom = appellation
	sens = signi(sens_de_jeu)
	nom_formation = formation
	_composer(index_equipe)

func _composer(index_equipe: int) -> void:
	joueurs.clear()
	var disposition := Formation.par_nom(nom_formation)
	for rang in disposition.size():
		var entree: Array = disposition[rang]
		var joueur := Joueur.new()
		joueur.poste = entree[0]
		joueur.equipe = index_equipe
		joueur.rang = rang
		joueur.numero = 1 if Postes.est_gardien(entree[0]) else rang + 1
		joueur.base = Formation.vers_metres(entree[1], entree[2], sens)
		joueur.position = joueur.base
		if Postes.est_gardien(entree[0]):
			joueur.gardien = 72.0
		joueurs.append(joueur)

## Change de dispositif sans changer d'effectif : les postes et les places de
## formation sont reattribues, les caracteristiques suivent le joueur.
func changer_formation(nouvelle: String) -> void:
	nom_formation = nouvelle
	var disposition := Formation.par_nom(nouvelle)
	for rang in mini(disposition.size(), joueurs.size()):
		var entree: Array = disposition[rang]
		joueurs[rang].poste = entree[0]
		joueurs[rang].base = Formation.vers_metres(entree[1], entree[2], sens)

## Remet tout le monde dans son camp pour un coup d'envoi.
## L'equipe qui engage place deux joueurs autour du rond central.
func placer_coup_d_envoi(engage: bool) -> void:
	for joueur in joueurs:
		joueur.position = joueur.base
		# Personne ne franchit la ligne mediane avant le coup d'envoi.
		if float(sens) * joueur.position.x > -1.0:
			joueur.position.x = -1.0 * float(sens)
		joueur.vitesse = Vector3.ZERO
		joueur.orientation = atan2(float(sens), 0.0)
	if not engage:
		return
	var engageurs := _rangs_les_plus_avances(2)
	if engageurs.size() >= 1:
		joueurs[engageurs[0]].position = Vector3(-0.6 * float(sens), 0.0, 0.4)
	if engageurs.size() >= 2:
		joueurs[engageurs[1]].position = Vector3(-1.6 * float(sens), 0.0, -1.6)

func _rangs_les_plus_avances(combien: int) -> Array[int]:
	var classement: Array[int] = []
	for joueur in joueurs:
		classement.append(joueur.rang)
	# Tri par avancee dans le sens de jeu. Un tri explicite et total garantit le
	# meme ordre a chaque execution, ce que le determinisme exige.
	classement.sort_custom(func(a: int, b: int) -> bool:
		var avancee_a := joueurs[a].base.x * float(sens)
		var avancee_b := joueurs[b].base.x * float(sens)
		if is_equal_approx(avancee_a, avancee_b):
			return a < b
		return avancee_a > avancee_b)
	return classement.slice(0, combien)

## Ou ce joueur devrait se trouver, compte tenu de la position du ballon.
func place_souhaitee(joueur: Joueur, ballon_position: Vector3) -> Vector3:
	if Postes.est_gardien(joueur.poste):
		return _place_du_gardien(ballon_position)

	var liberte := Postes.liberte(joueur.poste)
	var glissement_x := clampf(
		ballon_position.x * COULISSEMENT_LONGITUDINAL, -liberte, liberte)
	var glissement_z := clampf(
		ballon_position.z * COULISSEMENT_LATERAL, -liberte * 0.6, liberte * 0.6)

	var souhaitee := joueur.base + Vector3(glissement_x, 0.0, glissement_z)
	# Le bloc reste dans le terrain, avec un metre de marge sur les lignes.
	souhaitee.x = clampf(souhaitee.x,
		-Dimensions.DEMI_LONGUEUR + 1.0, Dimensions.DEMI_LONGUEUR - 1.0)
	souhaitee.z = clampf(souhaitee.z,
		-Dimensions.DEMI_LARGEUR + 1.0, Dimensions.DEMI_LARGEUR - 1.0)
	return souhaitee

## Le gardien se place sur la bissectrice entre ses poteaux et le ballon, et
## avance d'autant plus que le ballon est proche : c'est ainsi qu'on ferme
## l'angle de tir. Il ne quitte jamais vraiment sa surface.
func _place_du_gardien(ballon_position: Vector3) -> Vector3:
	var centre_but := Vector3(-Dimensions.DEMI_LONGUEUR * float(sens), 0.0, 0.0)
	var vers_ballon := ballon_position - centre_but
	vers_ballon.y = 0.0
	var distance := vers_ballon.length()
	if distance < 0.1:
		return centre_but + Vector3(0.6 * float(sens), 0.0, 0.0)

	# De 0,8 m sur sa ligne quand le ballon est loin, jusqu'a 7 m a sa rencontre
	# quand il arrive dans la surface.
	var proximite := clampf(1.0 - distance / 40.0, 0.0, 1.0)
	var avance := lerpf(0.8, SORTIE_MAXI_GARDIEN, proximite)
	var place := centre_but + vers_ballon.normalized() * avance
	place.z = clampf(place.z,
		-Dimensions.BUT_DEMI_LARGEUR * 1.6, Dimensions.BUT_DEMI_LARGEUR * 1.6)
	return place

## Rang du joueur le plus proche d'un point, gardien exclu si demande.
func le_plus_proche(point: Vector3, avec_gardien: bool = false) -> int:
	var meilleur := -1
	var meilleure_distance := INF
	for joueur in joueurs:
		if not avec_gardien and Postes.est_gardien(joueur.poste):
			continue
		var distance := joueur.distance_a(point)
		# Egalite tranchee par le rang : sans cela, l'ordre dependrait de
		# l'arrondi et deux executions pourraient designer des joueurs
		# differents.
		if distance < meilleure_distance - 0.0001:
			meilleure_distance = distance
			meilleur = joueur.rang
	return meilleur

## Rangs tries du plus proche au plus eloigne d'un point.
func classes_par_proximite(point: Vector3, avec_gardien: bool = false) -> Array[int]:
	var rangs: Array[int] = []
	for joueur in joueurs:
		if avec_gardien or not Postes.est_gardien(joueur.poste):
			rangs.append(joueur.rang)
	rangs.sort_custom(func(a: int, b: int) -> bool:
		var da := joueurs[a].distance_a(point)
		var db := joueurs[b].distance_a(point)
		if is_equal_approx(da, db):
			return a < b
		return da < db)
	return rangs
