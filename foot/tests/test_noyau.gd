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
	_tester_determinisme()
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
	var moyenne := somme / 20000.0
	_verifier(absf(moyenne - 0.5) < 0.02, "moyenne proche de 0,5", "moyenne = %f" % moyenne)

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

func _tester_commandes() -> void:
	print("Commandes")
	var envoyees := Commandes.new(Vector2(0.5, -0.25), Commandes.TIR | Commandes.SPRINT)
	var octets := envoyees.vers_octets()
	_verifier(octets.size() == 4, "tiennent en 4 octets", "taille = %d" % octets.size())
	var recues := Commandes.depuis_octets(octets)
	_verifier(recues.boutons == envoyees.boutons, "boutons conserves")
	_verifier(recues.direction.distance_to(envoyees.direction) < 0.01, "direction conservee")
	_verifier(recues.appuye(Commandes.TIR) and not recues.appuye(Commandes.PASSE), "lecture d'un bouton")
	var diagonale := Commandes.new(Vector2(1.0, 1.0))
	_verifier(diagonale.direction_normalisee().length() <= 1.001, "diagonale non avantageuse")

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
	var distance_max := 0.0
	for _i in 300:
		tir.avancer(Simulation.PAS)
		distance_max = maxf(distance_max, tir.position.x)
	_verifier(distance_max > 25.0 and distance_max < 70.0,
		"une frappe a 26 m/s parcourt une distance plausible", "portee = %.1f m" % distance_max)

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

func _tester_determinisme() -> void:
	print("Determinisme")
	var suite := _fabriquer_suite_de_commandes(900)
	var premiere := _rejouer(suite)
	var seconde := _rejouer(suite)
	_verifier(premiere == seconde, "deux executions donnent la meme empreinte",
		"%d contre %d" % [premiere, seconde])

	var suite_modifiee := _fabriquer_suite_de_commandes(900)
	suite_modifiee[450] = Commandes.new(Vector2(-1.0, 0.4), Commandes.TIR)
	_verifier(_rejouer(suite_modifiee) != premiere,
		"une commande changee change le resultat")

## Fabrique une suite de commandes reproductible : c'est exactement ce qu'un
## fichier de replay contient.
func _fabriquer_suite_de_commandes(nombre: int) -> Array:
	var scenario := Alea.new(4242)
	var suite := []
	suite.resize(nombre)
	var boutons := Commandes.AUCUN
	for i in nombre:
		if i % 45 == 0:
			boutons = [Commandes.AUCUN, Commandes.PASSE, Commandes.TIR,
				Commandes.SPRINT, Commandes.LOB, Commandes.CENTRE][scenario.entier(6)]
		suite[i] = Commandes.new(
			Vector2(scenario.reel_entre(-1.0, 1.0), scenario.reel_entre(-1.0, 1.0)),
			boutons)
	return suite

func _rejouer(suite: Array) -> int:
	var simulation := Simulation.new(2026)
	for commandes in suite:
		simulation.simuler(commandes)
	return simulation.etat.empreinte()
