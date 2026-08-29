class_name Simulation
extends RefCounted

## Le coeur du jeu : simuler(commandes) fait avancer le match d'exactement une
## image, et ne sait rien de l'affichage.
##
## Trois regles tenues sans exception dans ce fichier et tous ceux du dossier
## noyau/ :
##   1. pas de temps FIXE — jamais de delta variable, sinon deux appareils qui
##      n'affichent pas au meme rythme divergent ;
##   2. aucun appel a randf() — tout tirage passe par `alea`, dont la graine est
##      enregistree avec le match ;
##   3. aucune reference a un Node, une texture ou une camera.
##
## Ces trois regles donnent gratuitement les replays et le match en reseau
## local. Les ajouter apres coup obligerait a tout reecrire, c'est pourquoi
## elles sont posees des la premiere ligne.

const PAS := 1.0 / 60.0
const IMAGES_PAR_SECONDE := 60

## Distance a laquelle un joueur peut jouer le ballon.
const PORTEE_CONTROLE := 0.95
## Hauteur au-dessus de laquelle le ballon passe au-dessus des tetes.
const HAUTEUR_JOUABLE := 1.35

## Duree pendant laquelle un changement manuel resiste au changement
## automatique, en images. Une seconde et demie : le temps de lancer une course
## sans que le jeu vous reprenne le joueur des que le ballon bouge.
const DUREE_PRIORITE_MANUELLE := 90

const PORTEE_TACLE := 2.2

var alea: Alea
var etat: EtatMatch
var ballon: Ballon
var equipes: Array[Equipe] = []

## Adherence du gazon, fixee par la meteo. 1.0 par temps sec.
var glisse := 1.0

var equipe_humaine := 0
var joueur_actif := 10

## Qui tient le ballon : (equipe, rang), ou (-1, -1) s'il est libre. Public
## parce que l'interface en a besoin — c'est ce qui decide si les boutons
## affiches sont ceux du porteur ou ceux du defenseur.
var porteur := Vector2i(-1, -1)

var _priorite_manuelle := 0
var _changer_enfonce := false
var _tacle_enfonce := false
var _dernier_toucheur := -1
var _repos_apres_but := 0

func _init(graine: int = 1, formation_domicile: String = "4-4-2",
		formation_exterieur: String = "4-3-3") -> void:
	alea = Alea.new(graine)
	etat = EtatMatch.new()
	ballon = Ballon.new()
	equipes = [
		Equipe.new(0, 1, formation_domicile, "Domicile"),
		Equipe.new(1, -1, formation_exterieur, "Exterieur"),
	]
	placer_coup_d_envoi(0)

## Remet le ballon au centre et chacun dans son camp.
func placer_coup_d_envoi(equipe_qui_engage: int) -> void:
	ballon.placer(Vector3.ZERO)
	for index in equipes.size():
		equipes[index].placer_coup_d_envoi(index == equipe_qui_engage)
	var proche := equipes[equipe_humaine].le_plus_proche(Vector3.ZERO)
	joueur_actif = proche if proche >= 0 else 10
	_priorite_manuelle = 0
	_dernier_toucheur = -1
	etat.phase = EtatMatch.EN_JEU

## Avance d'une image. C'est la seule facon de faire progresser le match.
func simuler(commandes: Commandes) -> void:
	if _repos_apres_but > 0:
		# Petite pause apres un but, le temps que l'image montre la remise en jeu.
		_repos_apres_but -= 1
		if _repos_apres_but == 0:
			placer_coup_d_envoi(_equipe_qui_engage_apres_but())
		etat.image += 1
		return

	_choisir_joueur_actif(commandes)
	porteur = _trouver_porteur()
	_deplacer_equipe_humaine(commandes, porteur)
	_deplacer_equipe_ordinateur()
	_tenter_tacle(commandes, porteur)
	_jouer_le_ballon(commandes, porteur)
	ballon.avancer(PAS, glisse)
	_verifier_but()
	_contenir_ballon()
	etat.image += 1

# --- Choix du joueur pilote ------------------------------------------------

## Changement automatique vers le joueur le plus proche du ballon, sauf si le
## joueur a choisi lui-meme : son choix tient une seconde et demie.
##
## Sans cette priorite, le jeu reprendrait la main des que le ballon se
## rapproche d'un coequipier, en plein milieu de la course qu'on venait de
## lancer — le defaut le plus agacant des jeux de football mal regles.
func _choisir_joueur_actif(commandes: Commandes) -> void:
	var demande := commandes.appuye(Commandes.CHANGER)
	var front_montant := demande and not _changer_enfonce
	_changer_enfonce = demande

	if front_montant:
		var classement := equipes[equipe_humaine].classes_par_proximite(ballon.position)
		if classement.is_empty():
			return
		var place := classement.find(joueur_actif)
		joueur_actif = classement[(place + 1) % classement.size()] if place >= 0 else classement[0]
		_priorite_manuelle = DUREE_PRIORITE_MANUELLE
		return

	if _priorite_manuelle > 0:
		_priorite_manuelle -= 1
		return

	var proche := equipes[equipe_humaine].le_plus_proche(ballon.position)
	if proche >= 0:
		joueur_actif = proche

# --- Deplacements ----------------------------------------------------------

func _deplacer_equipe_humaine(commandes: Commandes, porteur: Vector2i) -> void:
	var equipe := equipes[equipe_humaine]
	var demande := commandes.direction_normalisee()
	var direction := Vector3(demande.x, 0.0, demande.y)
	var sprint := commandes.appuye(Commandes.SPRINT)

	# Le pressing envoie un deuxieme joueur au contact, sans lacher celui qu'on
	# pilote : c'est ce qui permet de fermer un porteur a deux.
	var presseur := -1
	if commandes.appuye(Commandes.PRESSING):
		for rang in equipe.classes_par_proximite(ballon.position):
			if rang != joueur_actif:
				presseur = rang
				break

	for joueur in equipe.joueurs:
		if joueur.rang == joueur_actif:
			joueur.avancer(PAS, direction, sprint)
		elif joueur.rang == presseur:
			joueur.rejoindre(PAS, ballon.position, 1.0)
		elif porteur.x == equipe_humaine:
			# Balle au pied : les coequipiers proposent la solution un peu plus
			# haut que leur place de formation.
			joueur.rejoindre(PAS, _appel_de_balle(equipe, joueur), 0.85)
		else:
			joueur.rejoindre(PAS, equipe.place_souhaitee(joueur, ballon.position), 0.85)

func _deplacer_equipe_ordinateur() -> void:
	var equipe := equipes[1 - equipe_humaine]
	var chasseur := equipe.le_plus_proche(ballon.position)
	for joueur in equipe.joueurs:
		if Postes.est_gardien(joueur.poste):
			joueur.rejoindre(PAS, equipe.place_souhaitee(joueur, ballon.position), 0.95)
		elif joueur.rang == chasseur:
			joueur.rejoindre(PAS, ballon.position, 1.0)
		else:
			joueur.rejoindre(PAS, equipe.place_souhaitee(joueur, ballon.position), 0.85)

## Place demandee a un coequipier quand l'equipe a le ballon : quelques metres
## plus haut, pour offrir une solution vers l'avant plutot que rester en ligne.
func _appel_de_balle(equipe: Equipe, joueur: Joueur) -> Vector3:
	var place := equipe.place_souhaitee(joueur, ballon.position)
	if Postes.est_gardien(joueur.poste):
		return place
	place.x += float(equipe.sens) * 4.0
	place.x = clampf(place.x,
		-Dimensions.DEMI_LONGUEUR + 1.0, Dimensions.DEMI_LONGUEUR - 1.0)
	return place

# --- Ballon ----------------------------------------------------------------

## Le joueur le plus proche du ballon, s'il est assez pres pour le jouer.
## Renvoie (-1, -1) si le ballon est libre.
func _trouver_porteur() -> Vector2i:
	if ballon.position.y > HAUTEUR_JOUABLE:
		return Vector2i(-1, -1)
	var meilleur := Vector2i(-1, -1)
	var meilleure_distance := PORTEE_CONTROLE
	for index in equipes.size():
		for joueur in equipes[index].joueurs:
			var distance := joueur.distance_a(ballon.position)
			# Comparaison stricte et parcours dans un ordre fixe : deux
			# executions designent forcement le meme joueur.
			if distance < meilleure_distance - 0.0001:
				meilleure_distance = distance
				meilleur = Vector2i(index, joueur.rang)
	return meilleur

func _jouer_le_ballon(commandes: Commandes, porteur: Vector2i) -> void:
	if porteur.x < 0:
		return
	var equipe := equipes[porteur.x]
	var joueur := equipe.joueurs[porteur.y]
	_dernier_toucheur = porteur.x

	if porteur.x == equipe_humaine and porteur.y == joueur_actif:
		_action_du_joueur(commandes, equipe, joueur)
	else:
		_action_de_l_ordinateur(equipe, joueur)

func _action_du_joueur(commandes: Commandes, equipe: Equipe, joueur: Joueur) -> void:
	var regard := _regard(joueur, equipe)
	var effet := commandes.direction_normalisee().y * 2.0

	if commandes.appuye(Commandes.TIR):
		_frapper_au_but(equipe, joueur)
	elif commandes.appuye(Commandes.LOB):
		ballon.frapper(regard, 15.0, 44.0, effet)
	elif commandes.appuye(Commandes.CENTRE):
		_centrer(equipe, joueur)
	elif commandes.appuye(Commandes.PASSE):
		_passer(equipe, joueur, regard)
	else:
		_conduire(joueur, regard)

func _action_de_l_ordinateur(equipe: Equipe, joueur: Joueur) -> void:
	var but_adverse := Vector3(Dimensions.DEMI_LONGUEUR * float(equipe.sens), 0.0, 0.0)
	var distance_au_but := joueur.distance_a(but_adverse)

	# A moins de vingt metres et dans un angle raisonnable, on tente sa chance.
	if distance_au_but < 20.0 and absf(joueur.position.z) < 18.0:
		_frapper_au_but(equipe, joueur)
		return

	var receveur := _meilleur_receveur(equipe, joueur)
	if receveur >= 0:
		_passer_a(equipe, joueur, equipe.joueurs[receveur])
		return

	_conduire(joueur, _regard(joueur, equipe))

## Direction dans laquelle le joueur joue : son deplacement s'il court, sinon le
## but adverse. Un joueur a l'arret ne frappe pas au hasard.
func _regard(joueur: Joueur, equipe: Equipe) -> Vector3:
	var course := Vector3(joueur.vitesse.x, 0.0, joueur.vitesse.z)
	if course.length_squared() > 0.36:
		return course.normalized()
	var but := Vector3(Dimensions.DEMI_LONGUEUR * float(equipe.sens), 0.0, 0.0)
	var vers_but := but - joueur.position
	vers_but.y = 0.0
	return vers_but.normalized() if vers_but.length_squared() > 0.01 else Vector3(float(equipe.sens), 0.0, 0.0)

func _conduire(joueur: Joueur, regard: Vector3) -> void:
	if not ballon.au_sol:
		return
	# Le ballon est pousse devant le pied, pas colle : c'est cet ecart qui rend
	# la conduite de balle disputable par un defenseur.
	var allure := Vector3(joueur.vitesse.x, 0.0, joueur.vitesse.z).length()
	if allure > 0.4:
		ballon.vitesse.x = regard.x * allure * 1.18
		ballon.vitesse.z = regard.z * allure * 1.18

func _frapper_au_but(equipe: Equipe, joueur: Joueur) -> void:
	var but := Vector3(Dimensions.DEMI_LONGUEUR * float(equipe.sens), 0.0, 0.0)
	# On ne vise pas le centre du but mais un des cotes, tire au hasard mais
	# reproductible. La precision depend de la caracteristique de tir et de la
	# distance : de loin, meme un bon tireur cadre moins.
	var distance := joueur.distance_a(but)
	var maitrise := clampf(joueur.tir / 100.0, 0.0, 1.0)
	var dispersion := lerpf(4.2, 1.1, maitrise) * clampf(distance / 25.0, 0.4, 2.0)
	var visee := but + Vector3(0.0, 0.0, alea.reel_entre(-1.0, 1.0) * dispersion)

	var direction := visee - joueur.position
	direction.y = 0.0
	var puissance := clampf(16.0 + distance * 0.55, 16.0, 31.0)
	ballon.frapper(direction, puissance, alea.reel_entre(5.0, 13.0),
		alea.reel_entre(-1.2, 1.2))

func _centrer(equipe: Equipe, joueur: Joueur) -> void:
	var point_de_chute := Vector3(
		Dimensions.DEMI_LONGUEUR * float(equipe.sens) - 9.0 * float(equipe.sens),
		0.0, -signf(joueur.position.z) * 3.0)
	var direction := point_de_chute - joueur.position
	direction.y = 0.0
	var distance := direction.length()
	ballon.frapper(direction, clampf(distance * 0.85, 12.0, 24.0), 28.0, 1.2)

func _passer(equipe: Equipe, joueur: Joueur, regard: Vector3) -> void:
	var receveur := _meilleur_receveur(equipe, joueur, regard)
	if receveur >= 0:
		_passer_a(equipe, joueur, equipe.joueurs[receveur])
	else:
		ballon.frapper(regard, 13.0, 2.0, 0.0)

## Passe calee sur la distance : trop faible, elle se fait intercepter ; trop
## forte, elle file en touche. On vise legerement devant le coequipier pour
## qu'il la prenne en courant.
func _passer_a(equipe: Equipe, passeur: Joueur, receveur: Joueur) -> void:
	var devant := Vector3(receveur.vitesse.x, 0.0, receveur.vitesse.z) * 0.35
	var cible := receveur.position + devant
	var direction := cible - passeur.position
	direction.y = 0.0
	var distance := direction.length()
	var maitrise := clampf(passeur.passe / 100.0, 0.0, 1.0)
	# Le defaut de precision est d'autant plus grand que la passe est longue.
	var erreur := lerpf(2.4, 0.5, maitrise) * clampf(distance / 25.0, 0.3, 1.8)
	direction += Vector3(alea.reel_entre(-1.0, 1.0) * erreur, 0.0,
		alea.reel_entre(-1.0, 1.0) * erreur)
	ballon.frapper(direction, clampf(6.0 + distance * 0.62, 7.0, 22.0), 1.5, 0.0)

## Choisit a qui donner : un coequipier devant, degage, et pas trop loin.
func _meilleur_receveur(equipe: Equipe, passeur: Joueur, regard := Vector3.ZERO) -> int:
	var adversaires := equipes[1 - passeur.equipe]
	var meilleur := -1
	var meilleure_note := 0.0

	for candidat in equipe.joueurs:
		if candidat.rang == passeur.rang or Postes.est_gardien(candidat.poste):
			continue
		var vers := candidat.position - passeur.position
		vers.y = 0.0
		var distance := vers.length()
		if distance < 4.0 or distance > 38.0:
			continue

		# Gain de terrain : une passe vers l'avant vaut mieux qu'une passe en retrait.
		var progression := (candidat.position.x - passeur.position.x) * float(equipe.sens)
		var note := 22.0 + progression

		# Une passe dans la direction regardee est privilegiee, si elle est connue.
		if regard.length_squared() > 0.01:
			note += vers.normalized().dot(regard) * 14.0

		# On retire des points si un adversaire est sur la trajectoire.
		var couloir := _adversaire_le_plus_gene(adversaires, passeur.position, candidat.position)
		note -= couloir * 26.0

		note -= distance * 0.25

		if note > meilleure_note + 0.0001:
			meilleure_note = note
			meilleur = candidat.rang

	return meilleur

## A quel point la trajectoire est bouchee, de 0 (libre) a 1 (adversaire pile
## dessus). Mesure la distance de chaque adversaire au segment de passe.
func _adversaire_le_plus_gene(adversaires: Equipe, depart: Vector3, arrivee: Vector3) -> float:
	var segment := arrivee - depart
	segment.y = 0.0
	var longueur_carree := segment.length_squared()
	if longueur_carree < 0.01:
		return 0.0
	var pire := 0.0
	for adversaire in adversaires.joueurs:
		var vers := adversaire.position - depart
		vers.y = 0.0
		var avancement := clampf(vers.dot(segment) / longueur_carree, 0.0, 1.0)
		var ecart := (vers - segment * avancement).length()
		pire = maxf(pire, clampf(1.0 - ecart / 3.0, 0.0, 1.0))
	return pire

# --- Tacle -----------------------------------------------------------------

## Le joueur pilote tente de reprendre le ballon. La reussite depend de sa
## defense face au dribble du porteur : une caracteristique, pas un tirage pur.
func _tenter_tacle(commandes: Commandes, porteur: Vector2i) -> void:
	var demande := commandes.appuye(Commandes.TACLE)
	var front_montant := demande and not _tacle_enfonce
	_tacle_enfonce = demande
	if not front_montant or porteur.x < 0 or porteur.x == equipe_humaine:
		return

	var tacleur := equipes[equipe_humaine].joueurs[joueur_actif]
	if tacleur.distance_a(ballon.position) > PORTEE_TACLE:
		return

	var vole := equipes[porteur.x].joueurs[porteur.y]
	var rapport := tacleur.defense / maxf(tacleur.defense + vole.dribble, 1.0)
	if alea.chance(rapport):
		# Le ballon est degage vers le camp adverse, pas capte proprement : un
		# tacle reussi n'est pas un controle.
		var vers_avant := Vector3(float(equipes[equipe_humaine].sens), 0.0,
			alea.reel_entre(-0.5, 0.5))
		ballon.frapper(vers_avant, alea.reel_entre(5.0, 9.0), 6.0, 0.0)
		_dernier_toucheur = equipe_humaine

# --- Buts et limites -------------------------------------------------------

func _verifier_but() -> void:
	if absf(ballon.position.x) < Dimensions.DEMI_LONGUEUR:
		return
	if absf(ballon.position.z) > Dimensions.BUT_DEMI_LARGEUR:
		return
	if ballon.position.y > Dimensions.BUT_HAUTEUR:
		return
	# Le ballon a franchi la ligne entre les poteaux et sous la barre.
	var but_a_droite := ballon.position.x > 0.0
	# L'equipe qui attaque vers les x positifs marque dans le but de droite.
	var marque_domicile := (equipes[0].sens > 0) == but_a_droite
	etat.marquer(marque_domicile)
	etat.phase = EtatMatch.ARRETEE
	_repos_apres_but = 90

func _equipe_qui_engage_apres_but() -> int:
	# L'equipe encaissee engage.
	var domicile_a_marque := etat.buts_domicile > etat.buts_exterieur
	return 1 if domicile_a_marque else 0

## Empeche le ballon de partir a l'infini tant que les regles de sortie ne sont
## pas ecrites (phase 2). Il rebondit sur une cloture invisible.
func _contenir_ballon() -> void:
	var bord_x := Dimensions.DEMI_LONGUEUR + Dimensions.MARGE_PELOUSE
	var bord_z := Dimensions.DEMI_LARGEUR + Dimensions.MARGE_PELOUSE
	if absf(ballon.position.x) > bord_x:
		ballon.position.x = clampf(ballon.position.x, -bord_x, bord_x)
		ballon.vitesse.x = -ballon.vitesse.x * 0.4
	if absf(ballon.position.z) > bord_z:
		ballon.position.z = clampf(ballon.position.z, -bord_z, bord_z)
		ballon.vitesse.z = -ballon.vitesse.z * 0.4

# --- Determinisme ----------------------------------------------------------

## Empreinte de l'etat complet du match. Deux simulations menees a partir de la
## meme graine et des memes commandes doivent donner exactement la meme valeur ;
## c'est ce que verifie le test de determinisme, et ce dont dependent les
## replays.
##
## Les flottants sont arrondis au millimetre : on veut detecter une divergence
## de jeu, pas un dernier bit d'arrondi sans consequence.
func empreinte() -> int:
	var somme: int = 1469598103934665603
	somme = _melanger(somme, etat.image)
	somme = _melanger(somme, etat.buts_domicile)
	somme = _melanger(somme, etat.buts_exterieur)
	somme = _melanger(somme, joueur_actif)
	somme = _melanger_vecteur(somme, ballon.position)
	somme = _melanger_vecteur(somme, ballon.vitesse)
	somme = _melanger_vecteur(somme, ballon.rotation)
	for equipe in equipes:
		for joueur in equipe.joueurs:
			somme = _melanger_vecteur(somme, joueur.position)
			somme = _melanger_vecteur(somme, joueur.vitesse)
	return somme

static func _melanger_vecteur(accumulateur: int, vecteur: Vector3) -> int:
	var somme := _melanger(accumulateur, int(roundf(vecteur.x * 1000.0)))
	somme = _melanger(somme, int(roundf(vecteur.y * 1000.0)))
	return _melanger(somme, int(roundf(vecteur.z * 1000.0)))

static func _melanger(accumulateur: int, valeur: int) -> int:
	# Variante de FNV-1a : simple, sans table, et surtout identique partout.
	return (accumulateur ^ valeur) * 1099511628211
