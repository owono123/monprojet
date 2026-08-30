extends SceneTree

## Tests du noyau de simulation, executes sans affichage.
## Lancement : godot --headless --path foot --script res://tests/test_noyau.gd
## Sort avec un code d'erreur non nul si un test echoue, ce qui casse la
## compilation en integration continue.

var _echecs: int = 0

func _initialize() -> void:
	_tester_alea()
	_tester_commandes()
	_tester_ballon()
	_tester_formations()
	_tester_coup_d_envoi()
	_tester_coulissement()
	_tester_gardien()
	_tester_buts()
	_tester_changement_de_joueur()
	_tester_sorties()
	_tester_hors_jeu()
	_tester_reprise_de_jeu()
	_tester_determinisme()
	_mesurer_le_cout()
	if _echecs == 0:
		print("\nTous les tests du noyau passent.")
	else:
		printerr("\n%d test(s) en echec." % _echecs)
	quit(1 if _echecs > 0 else 0)

func _verifier(condition: bool, intitule: String, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % intitule)
	else:
		_echecs += 1
		printerr("  ECHEC %s %s" % [intitule, detail])

# --- Generateur pseudo-aleatoire -------------------------------------------

func _tester_alea() -> void:
	print("Generateur pseudo-aleatoire")
	var a := Alea.new(2026)
	var b := Alea.new(2026)
	var identiques := true
	for _i in 1000:
		if not is_equal_approx(a.reel(), b.reel()):
			identiques = false
			break
	_verifier(identiques, "meme graine, meme suite de tirages")

	var c := Alea.new(2026)
	var d := Alea.new(2027)
	_verifier(not is_equal_approx(c.reel(), d.reel()), "graines differentes, tirages differents")

	var e := Alea.new(7)
	var dans_bornes := true
	var somme := 0.0
	for _i in 20000:
		var tirage := e.reel()
		if tirage < 0.0 or tirage >= 1.0:
			dans_bornes = false
		somme += tirage
	_verifier(dans_bornes, "reel() reste dans [0, 1)")
	_verifier(absf(somme / 20000.0 - 0.5) < 0.02, "moyenne proche de 0,5")

	var f := Alea.new(99)
	var compte := [0, 0, 0, 0, 0, 0]
	for _i in 60000:
		compte[f.entier(6)] += 1
	var ecart_max := 0
	for valeur in compte:
		ecart_max = maxi(ecart_max, absi(valeur - 10000))
	_verifier(ecart_max < 600, "entier(6) reparti uniformement", "ecart max = %d" % ecart_max)

	var g := Alea.new(5)
	for _i in 50:
		g.reel()
	var point := g.etat()
	var attendu := g.reel()
	g.restaurer(point)
	_verifier(is_equal_approx(g.reel(), attendu), "sauvegarde et reprise de l'etat")

# --- Commandes -------------------------------------------------------------

func _tester_commandes() -> void:
	print("Commandes")
	var envoyees := Commandes.new(Vector2(0.5, -0.25), Commandes.TIR | Commandes.SPRINT)
	var octets := envoyees.vers_octets()
	_verifier(octets.size() == 4, "tiennent en 4 octets", "taille = %d" % octets.size())
	var recues := Commandes.depuis_octets(octets)
	_verifier(recues.boutons == envoyees.boutons, "boutons conserves")
	_verifier(recues.direction.distance_to(envoyees.direction) < 0.01, "direction conservee")
	_verifier(recues.appuye(Commandes.TIR) and not recues.appuye(Commandes.PASSE),
		"lecture d'un bouton")
	_verifier(Commandes.new(Vector2(1.0, 1.0)).direction_normalisee().length() <= 1.001,
		"diagonale non avantageuse")

# --- Ballon ----------------------------------------------------------------

func _tester_ballon() -> void:
	print("Ballon")
	var b := Ballon.new()
	b.placer(Vector3(0.0, 8.0, 0.0))
	for _i in 600:
		b.avancer(Simulation.PAS)
	_verifier(absf(b.position.y - Ballon.RAYON) < 0.02, "retombe et se stabilise au sol",
		"y = %f" % b.position.y)
	_verifier(b.immobile(), "finit immobile")

	var tir := Ballon.new()
	tir.frapper(Vector3(1.0, 0.0, 0.0), 26.0, 9.0, 0.0)
	var portee := 0.0
	for _i in 300:
		tir.avancer(Simulation.PAS)
		portee = maxf(portee, tir.position.x)
	_verifier(portee > 25.0 and portee < 70.0,
		"une frappe a 26 m/s parcourt une distance plausible", "portee = %.1f m" % portee)

	var brosse := Ballon.new()
	brosse.frapper(Vector3(1.0, 0.0, 0.0), 25.0, 12.0, 8.0)
	for _i in 90:
		brosse.avancer(Simulation.PAS)
	_verifier(absf(brosse.position.z) > 0.3, "l'effet devie la trajectoire",
		"deviation = %.2f m" % brosse.position.z)

	var mouille := Ballon.new()
	mouille.placer(Vector3.ZERO)
	mouille.vitesse = Vector3(6.0, 0.0, 0.0)
	var sec := Ballon.new()
	sec.placer(Vector3.ZERO)
	sec.vitesse = Vector3(6.0, 0.0, 0.0)
	for _i in 180:
		mouille.avancer(Simulation.PAS, 1.4)
		sec.avancer(Simulation.PAS, 1.0)
	_verifier(mouille.position.x > sec.position.x + 0.5,
		"le ballon file davantage sur pelouse mouillee",
		"mouille = %.1f m, sec = %.1f m" % [mouille.position.x, sec.position.x])

# --- Formations ------------------------------------------------------------

func _tester_formations() -> void:
	print("Formations")
	var noms := Formation.noms()
	_verifier(noms.size() == 5, "cinq dispositions proposees", "%d trouvees" % noms.size())

	var toutes_completes := true
	var toutes_avec_gardien := true
	for nom in noms:
		var disposition := Formation.par_nom(nom)
		if disposition.size() != 11:
			toutes_completes = false
		var gardiens := 0
		for entree in disposition:
			if entree[0] == Postes.GARDIEN:
				gardiens += 1
		if gardiens != 1:
			toutes_avec_gardien = false
	_verifier(toutes_completes, "chaque disposition aligne onze joueurs")
	_verifier(toutes_avec_gardien, "chaque disposition compte un seul gardien")

	# Le changement de sens est un demi-tour, pas un miroir : le lateral droit
	# doit changer de cote du terrain en meme temps que de camp.
	var droit_positif := Formation.vers_metres(-0.60, 0.70, 1)
	var droit_negatif := Formation.vers_metres(-0.60, 0.70, -1)
	_verifier(droit_positif.x * droit_negatif.x < 0.0 and droit_positif.z * droit_negatif.z < 0.0,
		"changer de sens retourne le dispositif d'un demi-tour")

	# Personne ne doit etre place hors du terrain.
	var tous_dedans := true
	for nom in noms:
		for entree in Formation.par_nom(nom):
			if not Dimensions.dans_le_terrain(Formation.vers_metres(entree[1], entree[2], 1)):
				tous_dedans = false
	_verifier(tous_dedans, "aucune place de formation hors du terrain")

# --- Coup d'envoi ----------------------------------------------------------

func _tester_coup_d_envoi() -> void:
	print("Coup d'envoi")
	var simulation := Simulation.new(2026)
	var chacun_chez_soi := true
	var faute := ""
	for equipe in simulation.equipes:
		for joueur in equipe.joueurs:
			# Le camp d'une equipe est du cote oppose a celui qu'elle attaque.
			if float(equipe.sens) * joueur.position.x > 0.01:
				chacun_chez_soi = false
				faute = "%s n%d en x = %.1f" % [
					Postes.abreviation(joueur.poste), joueur.numero, joueur.position.x]
	_verifier(chacun_chez_soi, "chaque equipe se place dans son camp", faute)

	_verifier(simulation.equipes[0].joueurs.size() == 11
		and simulation.equipes[1].joueurs.size() == 11,
		"vingt-deux joueurs sur le terrain")

	_verifier(simulation.ballon.position.distance_to(Vector3(0.0, Ballon.RAYON, 0.0)) < 0.01,
		"le ballon est au point central")

	# Deux joueurs ne peuvent pas occuper exactement la meme place.
	var tous: Array[Joueur] = []
	for equipe in simulation.equipes:
		tous.append_array(equipe.joueurs)
	var superposes := false
	for i in tous.size():
		for j in range(i + 1, tous.size()):
			if tous[i].position.distance_to(tous[j].position) < 0.5:
				superposes = true
	_verifier(not superposes, "personne ne se superpose au coup d'envoi")

# --- Coulissement de la ligne ----------------------------------------------

func _tester_coulissement() -> void:
	print("Coulissement de la ligne")
	var equipe := Equipe.new(0, 1, "4-4-2", "Essai")
	var defenseur: Joueur = null
	for joueur in equipe.joueurs:
		if joueur.poste == Postes.DEFENSEUR_CENTRAL:
			defenseur = joueur
			break
	_verifier(defenseur != null, "un defenseur central existe en 4-4-2")
	if defenseur == null:
		return

	var au_centre := equipe.place_souhaitee(defenseur, Vector3.ZERO)
	var ballon_haut := equipe.place_souhaitee(defenseur, Vector3(35.0, 0.0, 0.0))
	var ballon_bas := equipe.place_souhaitee(defenseur, Vector3(-35.0, 0.0, 0.0))
	_verifier(ballon_haut.x > au_centre.x + 4.0,
		"le bloc monte quand le ballon monte",
		"%.1f m contre %.1f m" % [ballon_haut.x, au_centre.x])
	_verifier(ballon_bas.x < au_centre.x - 4.0,
		"le bloc redescend quand le ballon recule",
		"%.1f m contre %.1f m" % [ballon_bas.x, au_centre.x])
	_verifier(equipe.place_souhaitee(defenseur, Vector3(0.0, 0.0, 25.0)).z > au_centre.z + 2.0,
		"le bloc glisse du cote du ballon")

	# La liberte de mouvement borne le coulissement : un defenseur central ne
	# doit pas se retrouver dans la surface adverse parce que le ballon y est.
	var liberte := Postes.liberte(Postes.DEFENSEUR_CENTRAL)
	_verifier(absf(ballon_haut.x - defenseur.base.x) <= liberte + 0.01,
		"le defenseur central ne depasse pas sa liberte de poste",
		"ecart de %.1f m pour une liberte de %.1f m" % [
			absf(ballon_haut.x - defenseur.base.x), liberte])

	var toujours_dedans := true
	for x in [-50.0, -20.0, 0.0, 20.0, 50.0]:
		for z in [-33.0, 0.0, 33.0]:
			for joueur in equipe.joueurs:
				if not Dimensions.dans_le_terrain(
						equipe.place_souhaitee(joueur, Vector3(x, 0.0, z))):
					toujours_dedans = false
	_verifier(toujours_dedans, "le bloc reste dans le terrain en toute position du ballon")

# --- Gardien ---------------------------------------------------------------

func _tester_gardien() -> void:
	print("Gardien")
	var equipe := Equipe.new(0, 1, "4-4-2", "Essai")
	var gardien: Joueur = equipe.joueurs[0]
	_verifier(Postes.est_gardien(gardien.poste), "le premier joueur est le gardien")

	var son_but := Vector3(-Dimensions.DEMI_LONGUEUR, 0.0, 0.0)
	var jeu_loin := equipe.place_souhaitee(gardien, Vector3(40.0, 0.0, 0.0))
	var jeu_proche := equipe.place_souhaitee(gardien, Vector3(-40.0, 0.0, 0.0))

	_verifier(jeu_loin.distance_to(son_but) < 2.0,
		"il reste sur sa ligne quand le jeu est loin",
		"a %.1f m de son but" % jeu_loin.distance_to(son_but))
	_verifier(jeu_proche.distance_to(son_but) > jeu_loin.distance_to(son_but),
		"il avance quand le ballon approche")

	var jamais_trop_loin := true
	var trop_lateral := false
	for x in [-52.0, -40.0, -20.0, 0.0, 30.0]:
		for z in [-30.0, -10.0, 0.0, 10.0, 30.0]:
			var place := equipe.place_souhaitee(gardien, Vector3(x, 0.0, z))
			if place.distance_to(son_but) > Equipe.SORTIE_MAXI_GARDIEN + 0.01:
				jamais_trop_loin = false
			if absf(place.z) > Dimensions.BUT_DEMI_LARGEUR * 1.6 + 0.01:
				trop_lateral = true
	_verifier(jamais_trop_loin, "il ne quitte jamais sa surface")
	_verifier(not trop_lateral, "il ne s'ecarte pas au-dela de ses poteaux")

# --- Buts ------------------------------------------------------------------

func _tester_buts() -> void:
	print("Buts")
	var cadre := Simulation.new(2026)
	cadre.ballon.placer(Vector3(Dimensions.DEMI_LONGUEUR + 0.5, 1.0, 0.0))
	cadre.simuler(Commandes.new())
	_verifier(cadre.etat.buts_domicile == 1 and cadre.etat.buts_exterieur == 0,
		"un ballon entre les poteaux est un but",
		"score %d - %d" % [cadre.etat.buts_domicile, cadre.etat.buts_exterieur])

	var a_cote := Simulation.new(2026)
	a_cote.ballon.placer(Vector3(Dimensions.DEMI_LONGUEUR + 0.5, 1.0, 8.0))
	a_cote.simuler(Commandes.new())
	_verifier(a_cote.etat.buts_domicile == 0 and a_cote.etat.buts_exterieur == 0,
		"un ballon a cote du but n'est pas un but")

	var au_dessus := Simulation.new(2026)
	au_dessus.ballon.placer(Vector3(Dimensions.DEMI_LONGUEUR + 0.5, 4.0, 0.0))
	au_dessus.simuler(Commandes.new())
	_verifier(au_dessus.etat.buts_domicile == 0,
		"un ballon au-dessus de la barre n'est pas un but")

	var autre_camp := Simulation.new(2026)
	autre_camp.ballon.placer(Vector3(-Dimensions.DEMI_LONGUEUR - 0.5, 1.0, 0.0))
	autre_camp.simuler(Commandes.new())
	_verifier(autre_camp.etat.buts_exterieur == 1,
		"le but oppose compte pour l'autre equipe",
		"score %d - %d" % [autre_camp.etat.buts_domicile, autre_camp.etat.buts_exterieur])

	# La reprise est differee, le temps que l'image montre le but. On verifie
	# donc a l'image exacte de la remise en jeu : quelques images plus tard, le
	# jeu a repris et le ballon a deja bouge, ce qui ne prouverait rien.
	for _i in 90:
		cadre.simuler(Commandes.new())
	_verifier(cadre.ballon.position.distance_to(Vector3(0.0, Ballon.RAYON, 0.0)) < 0.01,
		"le jeu repart du rond central apres un but",
		"ballon en %.1f, %.1f" % [cadre.ballon.position.x, cadre.ballon.position.z])
	_verifier(cadre.etat.buts_domicile == 1, "le score est conserve a la reprise")

	var chacun_chez_soi := true
	for equipe in cadre.equipes:
		for joueur in equipe.joueurs:
			if float(equipe.sens) * joueur.position.x > 0.01:
				chacun_chez_soi = false
	_verifier(chacun_chez_soi, "chacun regagne son camp pour l'engagement")

# --- Changement de joueur --------------------------------------------------

func _tester_changement_de_joueur() -> void:
	print("Changement de joueur")
	var simulation := Simulation.new(2026)
	var rien := Commandes.new()

	# On pose le ballon sur un milieu pour que le changement automatique ait une
	# cible evidente, et on l'y maintient pendant tout le test.
	var vise: Joueur = simulation.equipes[0].joueurs[6]
	simulation.ballon.placer(vise.position)
	simulation.simuler(rien)
	_verifier(simulation.joueur_actif == vise.rang,
		"le changement automatique prend le plus proche du ballon",
		"actif = %d, attendu = %d" % [simulation.joueur_actif, vise.rang])

	simulation.ballon.placer(vise.position)
	simulation.simuler(Commandes.new(Vector2.ZERO, Commandes.CHANGER))
	var choisi := simulation.joueur_actif
	_verifier(choisi != vise.rang, "le bouton CHANGER donne la main a un autre joueur")

	# Une seconde et demie de priorite : le jeu ne doit pas reprendre le joueur.
	var tenu := true
	for _i in 80:
		simulation.ballon.placer(vise.position)
		simulation.simuler(rien)
		if simulation.joueur_actif != choisi:
			tenu = false
			break
	_verifier(tenu, "le choix manuel resiste pendant une seconde et demie")

	# Passe ce delai, le changement automatique reprend la main.
	var repris := false
	for _i in 40:
		simulation.ballon.placer(vise.position)
		simulation.simuler(rien)
		if simulation.joueur_actif != choisi:
			repris = true
			break
	_verifier(repris, "le changement automatique reprend apres la priorite")

# --- Sorties de ballon -----------------------------------------------------

func _tester_sorties() -> void:
	print("Sorties de ballon")
	# L'equipe 0 attaque vers les x positifs, l'equipe 1 vers les x negatifs.
	var sens := [1, -1]

	_verifier(not Regles.est_sorti(Vector3(52.4, 0.1, 33.9)),
		"un ballon dans les limites est en jeu")
	_verifier(not Regles.est_sorti(Vector3(Dimensions.DEMI_LONGUEUR, 0.1, 0.0)),
		"un ballon pile sur la ligne est encore en jeu")
	_verifier(Regles.est_sorti(Vector3(52.6, 0.1, 0.0)),
		"un ballon au-dela de la ligne est sorti")

	# Touche : elle revient a l'adversaire du dernier joueur a l'avoir touche.
	var touche := Regles.decider(Vector3(12.0, 0.2, 34.6), 0, sens)
	_verifier(touche["decision"] == Regles.TOUCHE, "sortie sur le cote : touche")
	_verifier(int(touche["equipe"]) == 1, "la touche revient a l'adversaire")
	var point_touche: Vector3 = touche["point"]
	_verifier(is_equal_approx(point_touche.z, Dimensions.DEMI_LARGEUR)
		and is_equal_approx(point_touche.x, 12.0),
		"la touche se joue la ou le ballon est sorti",
		"point = %.1f, %.1f" % [point_touche.x, point_touche.z])

	# Ligne de but franchie par la defense : corner. L'equipe 1 defend le but
	# situe en x positif, puisqu'elle attaque vers les x negatifs.
	var corner := Regles.decider(Vector3(53.0, 0.2, 20.0), 1, sens)
	_verifier(corner["decision"] == Regles.CORNER,
		"ballon sorti par la defense : corner")
	_verifier(int(corner["equipe"]) == 0, "le corner revient a l'attaque")
	var point_corner: Vector3 = corner["point"]
	_verifier(is_equal_approx(absf(point_corner.x), Dimensions.DEMI_LONGUEUR)
		and is_equal_approx(absf(point_corner.z), Dimensions.DEMI_LARGEUR),
		"le corner se joue dans l'angle")

	# Meme ligne, mais poussee dehors par l'attaque : six metres.
	var six := Regles.decider(Vector3(53.0, 0.2, 20.0), 0, sens)
	_verifier(six["decision"] == Regles.SIX_METRES,
		"ballon sorti par l'attaque : six metres")
	_verifier(int(six["equipe"]) == 1, "les six metres reviennent a la defense")

	# Entre les poteaux et sous la barre : but, quelle que soit la sortie.
	var but := Regles.decider(Vector3(53.0, 1.0, 0.0), 0, sens)
	_verifier(but["decision"] == Regles.BUT, "entre les poteaux : but")
	_verifier(int(but["equipe"]) == 0, "le but revient a l'equipe qui attaque de ce cote")
	_verifier(Regles.decider(Vector3(53.0, 3.0, 0.0), 0, sens)["decision"] != Regles.BUT,
		"au-dessus de la barre : pas de but")

# --- Hors-jeu ---------------------------------------------------------------

func _tester_hors_jeu() -> void:
	print("Hors-jeu")
	# L'equipe etudiee attaque vers les x positifs. Les adversaires sont donnes
	# par leur seule abscisse : gardien a 50, defenseurs a 30 et 28.
	var defense := [50.0, 30.0, 28.0, 10.0]

	_verifier(Regles.est_hors_jeu(35.0, 20.0, defense, 1),
		"devant l'avant-dernier defenseur : hors-jeu")
	_verifier(not Regles.est_hors_jeu(25.0, 20.0, defense, 1),
		"derriere l'avant-dernier defenseur : en jeu")
	_verifier(not Regles.est_hors_jeu(30.0, 20.0, defense, 1),
		"a hauteur du defenseur : en jeu")
	_verifier(not Regles.est_hors_jeu(-5.0, -20.0, defense, 1),
		"dans son propre camp : jamais hors-jeu")
	_verifier(not Regles.est_hors_jeu(35.0, 40.0, defense, 1),
		"en retrait du ballon : jamais hors-jeu")

	# Le meme cas dans l'autre sens de jeu doit donner la meme reponse.
	var defense_miroir := [-50.0, -30.0, -28.0, -10.0]
	_verifier(Regles.est_hors_jeu(-35.0, -20.0, defense_miroir, -1),
		"la regle vaut dans les deux sens de jeu")

	# Un gardien sorti tres haut change l'avant-dernier defenseur : c'est
	# exactement le cas ou une regle qui supposerait le gardien dernier se
	# tromperait.
	var gardien_sorti := [12.0, 30.0, 28.0]
	_verifier(Regles.est_hors_jeu(31.0, 20.0, gardien_sorti, 1),
		"gardien sorti : l'avant-dernier defenseur est recalcule")

# --- Reprise de jeu ---------------------------------------------------------

func _tester_reprise_de_jeu() -> void:
	print("Reprise de jeu")
	var simulation := Simulation.new(2026)
	var rien := Commandes.new()

	# On envoie le ballon franchement en touche.
	simulation.ballon.placer(Vector3(10.0, 0.3, 30.0))
	simulation.ballon.vitesse = Vector3(0.0, 0.0, 30.0)
	for _i in 20:
		simulation.simuler(rien)

	_verifier(simulation.au_repos(), "une sortie arrete le jeu")
	_verifier(absf(simulation.ballon.position.z) <= Dimensions.DEMI_LARGEUR + 0.01,
		"le ballon est ramene sur la ligne de touche",
		"z = %.2f" % simulation.ballon.position.z)

	# Le jeu doit repartir tout seul, sans intervention.
	var reparti := false
	for _i in 150:
		simulation.simuler(rien)
		if not simulation.au_repos():
			reparti = true
			break
	_verifier(reparti, "le jeu repart apres la remise en jeu")

	# Et le ballon ne doit plus jamais s'echapper : sur un match complet, chaque
	# sortie doit etre rattrapee par une remise en jeu.
	var scenario := Alea.new(31)
	var loin := false
	for _i in 2400:
		simulation.simuler(Commandes.new(
			Vector2(scenario.reel_entre(-1.0, 1.0), scenario.reel_entre(-1.0, 1.0)),
			Commandes.TIR if scenario.chance(0.02) else Commandes.AUCUN))
		if absf(simulation.ballon.position.x) > Dimensions.DEMI_LONGUEUR + 12.0 \
				or absf(simulation.ballon.position.z) > Dimensions.DEMI_LARGEUR + 12.0:
			loin = true
			break
	_verifier(not loin, "le ballon ne s'echappe jamais du terrain",
		"ballon en %.1f, %.1f" % [simulation.ballon.position.x, simulation.ballon.position.z])

# --- Determinisme ----------------------------------------------------------

func _tester_determinisme() -> void:
	print("Determinisme")
	var suite := _fabriquer_suite_de_commandes(900)
	var premiere := _rejouer(suite)
	var seconde := _rejouer(suite)
	_verifier(premiere == seconde, "deux executions donnent la meme empreinte",
		"%d contre %d" % [premiere, seconde])

	# La commande modifiee est placee tres tot, et la comparaison faite peu
	# apres. Comparer en fin de match serait trompeur : un but remet les
	# vingt-deux joueurs et le ballon a des places fixes, ce qui efface d'un coup
	# tous les ecarts accumules avant lui. Deux matchs pourtant differents
	# peuvent alors se retrouver dans exactement le meme etat, et le test
	# passerait a cote d'une vraie perte de determinisme.
	var modifiee := _fabriquer_suite_de_commandes(900)
	modifiee[5] = Commandes.new(Vector2(-1.0, 0.4), Commandes.TIR)
	_verifier(_rejouer(modifiee, 120) != _rejouer(suite, 120),
		"une commande changee change le resultat")

	# Une graine differente doit produire un match different : sans cela, le
	# generateur ne serait pas reellement branche sur la simulation.
	var autre_graine := Simulation.new(777)
	for commandes in suite:
		autre_graine.simuler(commandes)
	_verifier(autre_graine.empreinte() != premiere, "une autre graine donne un autre match")

	# Personne ne doit sortir de la pelouse au fil d'un match complet.
	var controle := Simulation.new(2026)
	var deborde := false
	var bord_x := Dimensions.DEMI_LONGUEUR + Dimensions.MARGE_PELOUSE
	var bord_z := Dimensions.DEMI_LARGEUR + Dimensions.MARGE_PELOUSE
	for commandes in suite:
		controle.simuler(commandes)
		for equipe in controle.equipes:
			for joueur in equipe.joueurs:
				if absf(joueur.position.x) > bord_x or absf(joueur.position.z) > bord_z:
					deborde = true
	_verifier(not deborde, "aucun joueur ne quitte la pelouse")

## Fabrique une suite de commandes reproductible : c'est exactement ce qu'un
## fichier de replay contient.
func _fabriquer_suite_de_commandes(nombre: int) -> Array:
	var scenario := Alea.new(4242)
	var suite := []
	suite.resize(nombre)
	var boutons := Commandes.AUCUN
	for i in nombre:
		if i % 45 == 0:
			boutons = [Commandes.AUCUN, Commandes.PASSE, Commandes.TIR, Commandes.SPRINT,
				Commandes.LOB, Commandes.CENTRE, Commandes.CHANGER, Commandes.TACLE,
				Commandes.PRESSING][scenario.entier(9)]
		suite[i] = Commandes.new(
			Vector2(scenario.reel_entre(-1.0, 1.0), scenario.reel_entre(-1.0, 1.0)), boutons)
	return suite

## Rejoue une suite de commandes et renvoie l'empreinte finale. `limite` permet
## de s'arreter avant la fin, pour comparer deux matchs a un instant precis.
func _rejouer(suite: Array, limite: int = -1) -> int:
	var simulation := Simulation.new(2026)
	var nombre := suite.size() if limite < 0 else mini(limite, suite.size())
	for i in nombre:
		simulation.simuler(suite[i])
	return simulation.empreinte()

# --- Cout de calcul --------------------------------------------------------

## Mesure indicative, pas un test de reussite : la machine d'integration
## continue n'a rien a voir avec un Note 8. Le chiffre sert a reperer une
## degradation brutale d'une version a l'autre.
func _mesurer_le_cout() -> void:
	print("Cout de calcul")
	var suite := _fabriquer_suite_de_commandes(3600)   # une minute de jeu
	var simulation := Simulation.new(2026)
	var depart := Time.get_ticks_usec()
	for commandes in suite:
		simulation.simuler(commandes)
	var par_image_us := float(Time.get_ticks_usec() - depart) / 3600.0
	# A 60 images par seconde, une image entiere dure 16 666 microsecondes.
	print("  %.0f us par image simulee, soit %.1f %% du budget d'une image a 60 img/s"
		% [par_image_us, par_image_us / 16666.0 * 100.0])
	_verifier(par_image_us < 4000.0,
		"la simulation reste loin du budget d'une image sur cette machine",
		"%.0f us" % par_image_us)
