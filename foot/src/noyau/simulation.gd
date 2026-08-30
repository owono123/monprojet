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

## Le hors-jeu peut etre desactive, comme le demande le menu des reglages.
var hors_jeu_actif := true

var equipe_humaine := 0
var joueur_actif := 10

## Qui tient le ballon : (equipe, rang), ou (-1, -1) s'il est libre. Public
## parce que l'interface en a besoin — c'est ce qui decide si les boutons
## affiches sont ceux du porteur ou ceux du defenseur.
var porteur := Vector2i(-1, -1)

## Dernier joueur a avoir touche le ballon, et auteur du dernier but. Servent a
## l'affichage : c'est sur lui que la camera se braque pour la celebration.
var dernier_toucheur_joueur := Vector2i(-1, -1)
var buteur := Vector2i(-1, -1)

## Gestes survenus pendant l'image qui vient d'etre simulee : frappes, tacles.
##
## C'est de l'information a sens unique, du noyau vers l'affichage. La
## simulation ne s'en sert jamais elle-meme : elle sait deja tout ce qu'il lui
## faut. Cette liste existe seulement pour que le rendu puisse declencher la
## bonne animation au bon moment, sans avoir a deviner apres coup qu'un ballon
## est parti. Elle est videe au debut de chaque pas ; l'affichage la lit juste
## apres son appel a simuler().
var gestes: Array[Dictionary] = []

var _priorite_manuelle := 0
var _changer_enfonce := false
var _tacle_enfonce := false
var _dernier_toucheur := -1
var _repos_apres_but := 0
var _equipe_qui_a_encaisse := 1

## Remise en jeu en cours : touche, corner ou six metres. Vide quand le jeu
## court. Contient la decision rendue par Regles, le tireur designe et le temps
## restant avant l'execution.
var _arret := {}
var _compte_a_rebours := 0

## Passe adressee a un joueur en position de hors-jeu. La faute n'est signalee
## qu'au moment ou il touche le ballon, comme le veut la regle : tant qu'il n'y
## touche pas, il n'y a rien a sanctionner.
var _hors_jeu_en_attente := Vector2i(-1, -1)

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
	gestes.clear()
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

	if _arret.is_empty():
		_tenter_tacle(commandes, porteur)
		_jouer_le_ballon(commandes, porteur)
	else:
		_conduire_la_remise_en_jeu()

	_contenir_les_joueurs()
	ballon.avancer(PAS, glisse)
	_arbitrer()
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

	# Le hors-jeu ne se siffle qu'au moment ou le joueur signale touche le
	# ballon : tant qu'il n'y touche pas, il n'y a rien a sanctionner. Si
	# quelqu'un d'autre intervient avant lui, la position est effacee.
	if _hors_jeu_en_attente.x >= 0:
		if porteur == _hors_jeu_en_attente:
			_siffler_le_hors_jeu(joueur)
			return
		_hors_jeu_en_attente = Vector2i(-1, -1)

	_dernier_toucheur = porteur.x
	dernier_toucheur_joueur = porteur

	var geste := ""
	if porteur.x == equipe_humaine and porteur.y == joueur_actif:
		geste = _action_du_joueur(commandes, equipe, joueur)
	else:
		geste = _action_de_l_ordinateur(equipe, joueur)
	if geste != "":
		gestes.append({"equipe": porteur.x, "rang": porteur.y, "geste": geste})

## Renvoie le nom du geste a jouer a l'ecran, ou une chaine vide si le joueur
## s'est contente de pousser le ballon devant lui.
func _action_du_joueur(commandes: Commandes, equipe: Equipe, joueur: Joueur) -> String:
	var regard := _regard(joueur, equipe)
	var effet := commandes.direction_normalisee().y * 2.0

	if commandes.appuye(Commandes.TIR):
		_frapper_au_but(equipe, joueur)
		return "frappe"
	if commandes.appuye(Commandes.LOB):
		ballon.frapper(regard, 15.0, 44.0, effet)
		return "frappe"
	if commandes.appuye(Commandes.CENTRE):
		_centrer(equipe, joueur)
		return "frappe"
	if commandes.appuye(Commandes.PASSE):
		_passer(equipe, joueur, regard)
		return "passe"
	_conduire(joueur, regard)
	return ""

func _action_de_l_ordinateur(equipe: Equipe, joueur: Joueur) -> String:
	var but_adverse := Vector3(Dimensions.DEMI_LONGUEUR * float(equipe.sens), 0.0, 0.0)
	var distance_au_but := joueur.distance_a(but_adverse)

	# A moins de vingt metres et dans un angle raisonnable, on tente sa chance.
	if distance_au_but < 20.0 and absf(joueur.position.z) < 18.0:
		_frapper_au_but(equipe, joueur)
		return "frappe"

	var receveur := _meilleur_receveur(equipe, joueur)
	if receveur >= 0:
		_passer_a(equipe, joueur, equipe.joueurs[receveur])
		return "passe"

	_conduire(joueur, _regard(joueur, equipe))
	return ""

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
##
## C'est ici que la position de hors-jeu est jugee : la regle s'apprecie au
## moment ou le ballon est joue, pas au moment ou il est recu.
func _passer_a(equipe: Equipe, passeur: Joueur, receveur: Joueur) -> void:
	if hors_jeu_actif and _est_hors_jeu(equipe, receveur):
		_hors_jeu_en_attente = Vector2i(receveur.equipe, receveur.rang)
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

func _est_hors_jeu(equipe: Equipe, receveur: Joueur) -> bool:
	var x_adverses: Array = []
	for adversaire in equipes[1 - receveur.equipe].joueurs:
		x_adverses.append(adversaire.position.x)
	return Regles.est_hors_jeu(receveur.position.x, ballon.position.x,
		x_adverses, equipe.sens)

## Coup franc indirect pour l'adversaire, la ou la faute a ete constatee.
func _siffler_le_hors_jeu(fautif: Joueur) -> void:
	var point := Vector3(
		clampf(fautif.position.x, -Dimensions.DEMI_LONGUEUR + 1.0,
			Dimensions.DEMI_LONGUEUR - 1.0),
		0.0,
		clampf(fautif.position.z, -Dimensions.DEMI_LARGEUR + 1.0,
			Dimensions.DEMI_LARGEUR - 1.0))
	_hors_jeu_en_attente = Vector2i(-1, -1)
	_preparer_la_remise_en_jeu({
		"decision": Regles.COUP_FRANC,
		"point": point,
		"equipe": 1 - fautif.equipe,
	})

## Garde-fou : personne ne s'echappe de la pelouse. Un joueur peut sortir des
## lignes — pour une touche, ou en poursuivant un ballon — mais pas quitter le
## terrain tout court.
func _contenir_les_joueurs() -> void:
	var bord_x := Dimensions.DEMI_LONGUEUR + Dimensions.MARGE_PELOUSE
	var bord_z := Dimensions.DEMI_LARGEUR + Dimensions.MARGE_PELOUSE
	for equipe in equipes:
		for joueur in equipe.joueurs:
			joueur.position.x = clampf(joueur.position.x, -bord_x, bord_x)
			joueur.position.z = clampf(joueur.position.z, -bord_z, bord_z)

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
	gestes.append({"equipe": equipe_humaine, "rang": joueur_actif, "geste": "tacle"})
	var rapport := tacleur.defense / maxf(tacleur.defense + vole.dribble, 1.0)
	if alea.chance(rapport):
		# Le ballon est degage vers le camp adverse, pas capte proprement : un
		# tacle reussi n'est pas un controle.
		var vers_avant := Vector3(float(equipes[equipe_humaine].sens), 0.0,
			alea.reel_entre(-0.5, 0.5))
		ballon.frapper(vers_avant, alea.reel_entre(5.0, 9.0), 6.0, 0.0)
		_dernier_toucheur = equipe_humaine

# --- Arbitrage -------------------------------------------------------------

## Examine la position du ballon apres son deplacement et applique les Lois du
## jeu. C'est le seul endroit qui decide d'un but ou d'une sortie.
func _arbitrer() -> void:
	if not _arret.is_empty():
		return
	if not Regles.est_sorti(ballon.position):
		return

	var decision := Regles.decider(ballon.position, _dernier_toucheur,
		[equipes[0].sens, equipes[1].sens])
	match decision["decision"]:
		Regles.BUT:
			_accorder_le_but(int(decision["equipe"]))
		Regles.TOUCHE, Regles.CORNER, Regles.SIX_METRES:
			_preparer_la_remise_en_jeu(decision)

func _accorder_le_but(marqueur: int) -> void:
	# Le buteur est le dernier joueur a avoir touche le ballon, s'il est bien de
	# l'equipe qui marque — sinon c'est un but contre son camp, et l'on preferera
	# braquer la camera sur un attaquant plutot que sur le malheureux.
	buteur = dernier_toucheur_joueur if dernier_toucheur_joueur.x == marqueur \
		else Vector2i(marqueur, equipes[marqueur].le_plus_proche(ballon.position))
	etat.marquer(marqueur == 0)
	_equipe_qui_a_encaisse = 1 - marqueur
	etat.phase = EtatMatch.ARRETEE
	_hors_jeu_en_attente = Vector2i(-1, -1)
	_repos_apres_but = 90

func _equipe_qui_engage_apres_but() -> int:
	# L'equipe qui vient d'encaisser engage.
	return _equipe_qui_a_encaisse

## Pose le ballon sur son point de remise en jeu et designe un tireur.
##
## Le jeu s'arrete une seconde et demie : le temps que le tireur rejoigne le
## ballon et que le joueur comprenne ce qui vient d'etre siffle. Sans cette
## pause, une touche ressemblerait a un rebond et le match deviendrait illisible.
func _preparer_la_remise_en_jeu(decision: Dictionary) -> void:
	var point: Vector3 = decision["point"]
	ballon.placer(point)
	etat.phase = EtatMatch.ARRETEE
	_hors_jeu_en_attente = Vector2i(-1, -1)

	var equipe_beneficiaire := int(decision["equipe"])
	var tireur := equipes[equipe_beneficiaire].le_plus_proche(point)
	_arret = {
		"decision": decision["decision"],
		"point": point,
		"equipe": equipe_beneficiaire,
		"tireur": tireur,
	}
	_compte_a_rebours = 90
	_dernier_toucheur = equipe_beneficiaire

## Pendant l'arret : le ballon reste pose, le tireur vient le chercher, puis le
## joue quand le decompte tombe a zero.
func _conduire_la_remise_en_jeu() -> void:
	var point: Vector3 = _arret["point"]
	ballon.placer(point)

	var equipe_beneficiaire := int(_arret["equipe"])
	var rang := int(_arret["tireur"])
	if rang >= 0:
		var tireur := equipes[equipe_beneficiaire].joueurs[rang]
		# Le tireur se place a cote du ballon, pas dessus.
		var approche := point - Vector3(0.0, 0.0, signf(point.z) * 0.8)
		tireur.rejoindre(PAS, approche, 1.0)

	_compte_a_rebours -= 1
	if _compte_a_rebours > 0:
		return

	if rang >= 0:
		var tireur := equipes[equipe_beneficiaire].joueurs[rang]
		var receveur := _meilleur_receveur(equipes[equipe_beneficiaire], tireur)
		if receveur >= 0:
			_passer_a(equipes[equipe_beneficiaire], tireur,
				equipes[equipe_beneficiaire].joueurs[receveur])
		else:
			# Personne de disponible : on degage vers l'avant.
			ballon.frapper(Vector3(float(equipes[equipe_beneficiaire].sens), 0.0, 0.0),
				16.0, 22.0, 0.0)
		gestes.append({"equipe": equipe_beneficiaire, "rang": rang, "geste": "passe"})

	_arret = {}
	etat.phase = EtatMatch.EN_JEU

## Vrai si une remise en jeu est en cours. L'interface s'en sert pour afficher
## ce qui a ete siffle.
func au_repos() -> bool:
	return not _arret.is_empty() or _repos_apres_but > 0

## Ce qui vient d'etre siffle, en clair. Chaine vide quand le jeu court.
func libelle_de_l_arret() -> String:
	if _repos_apres_but > 0:
		return "BUT"
	if _arret.is_empty():
		return ""
	var equipe := equipes[int(_arret["equipe"])].nom
	match int(_arret["decision"]):
		Regles.TOUCHE: return "TOUCHE  %s" % equipe
		Regles.CORNER: return "CORNER  %s" % equipe
		Regles.SIX_METRES: return "SIX METRES  %s" % equipe
		Regles.COUP_FRANC: return "HORS-JEU  coup franc  %s" % equipe
	return ""

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
