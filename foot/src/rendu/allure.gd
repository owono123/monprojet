class_name Allure
extends RefCounted

## Animation de course, calculee plutot qu'enregistree.
##
## Aucune capture de mouvement n'est utilisee : les angles des membres sont
## produits par des sinusoides calees sur la foulee. C'est ce qui permet
## d'animer vingt-deux joueurs sans le moindre fichier d'animation, et
## d'enchainer marche, course et sprint sans transition brutale — il n'y a pas
## trois animations a melanger, il n'y en a qu'une dont l'amplitude change.
##
## Le point decisif est que la cadence suit la **distance parcourue**, jamais le
## temps. Si les jambes battaient a un rythme fixe, les pieds glisseraient sur
## le gazon des que l'allure change : c'est le defaut qui trahit immediatement
## une animation mal branchee. En avancant la foulee au prorata des metres
## parcourus, le pied reste pose la ou il touche le sol.

## Longueur d'un pas, en metres. Un joueur a l'arret pietine sur place ; en
## sprint la foulee depasse deux metres.
const FOULEE_MINIMALE := 0.95
const FOULEE_PAR_VITESSE := 0.115

## Angles maximaux, en radians.
const BALANCEMENT_HANCHE := 0.32
const BALANCEMENT_HANCHE_PAR_VITESSE := 0.055
const FLEXION_GENOU := 1.35
const BALANCEMENT_EPAULE := 0.42
const OUVERTURE_BRAS := 0.16      # ecarte les bras du buste
const FLEXION_COUDE := 0.45

## Duree des gestes ponctuels, en secondes.
const DUREE_FRAPPE := 0.40
const DUREE_PASSE := 0.28
const DUREE_TACLE := 0.85

## Position dans le cycle de foulee, de 0 a 1. Un cycle vaut deux pas.
var _phase := 0.0
## Balancement lent du corps a l'arret, pour qu'un joueur immobile respire.
var _repos := 0.0

## Geste ponctuel en cours — frappe, passe ou tacle — et depuis combien de temps.
## Il se superpose au cycle de course au lieu de le remplacer : un joueur qui
## frappe en pleine course continue de courir du haut du corps.
var _geste := ""
var _depuis := 0.0
## Fige le geste a l'instant demande au lieu de le laisser se derouler. Sert
## uniquement aux captures de controle : un geste dure quatre dixiemes de
## seconde et serait deja termine au moment ou l'image est prise.
var _fige := false

## Declenche un geste. Appele par l'affichage a partir des evenements que la
## simulation vient de produire.
##
## `avancement` permet de demarrer le geste en cours de route, et `fige` de l'y
## arreter — deux commodites reservees aux captures.
func declencher(geste: String, avancement: float = 0.0, fige: bool = false) -> void:
	_geste = geste
	_fige = fige
	_depuis = 0.0
	_depuis = clampf(avancement, 0.0, 0.999) * _duree_du_geste()

func _duree_du_geste() -> float:
	match _geste:
		"frappe": return DUREE_FRAPPE
		"passe": return DUREE_PASSE
		"tacle": return DUREE_TACLE
	return 0.0

## Interpole une suite de reperes [temps, valeur] : la facon la plus lisible de
## decrire un geste, et la plus facile a regler ensuite.
static func _entre_reperes(reperes: Array, t: float) -> float:
	if reperes.is_empty():
		return 0.0
	# Les valeurs sont extraites dans des variables typees : un element de
	# tableau non type est indetermine pour GDScript, qui refuse alors d'inferer
	# les calculs qu'on en tire.
	var premier: Array = reperes[0]
	var instant_premier: float = premier[0]
	if t <= instant_premier:
		return premier[1]

	for index in range(1, reperes.size()):
		var avant: Array = reperes[index - 1]
		var apres: Array = reperes[index]
		var instant_avant: float = avant[0]
		var instant_apres: float = apres[0]
		if t <= instant_apres:
			var part := (t - instant_avant) / maxf(instant_apres - instant_avant, 0.0001)
			var valeur_avant: float = avant[1]
			var valeur_apres: float = apres[1]
			# Lissage aux extremites : une interpolation droite donnerait des
			# ruptures de vitesse visibles a chaque repere.
			return lerpf(valeur_avant, valeur_apres, smoothstep(0.0, 1.0, part))

	var dernier: Array = reperes[reperes.size() - 1]
	return dernier[1]

## Avance le cycle. `distance` est le chemin parcouru au sol depuis la derniere
## image, `allure` la vitesse instantanee en metres par seconde.
func avancer(distance: float, allure: float, delta: float) -> void:
	var foulee := FOULEE_MINIMALE + allure * FOULEE_PAR_VITESSE
	_phase = fposmod(_phase + distance / (foulee * 2.0), 1.0)
	_repos = fposmod(_repos + delta * 0.35, 1.0)
	if _geste != "" and not _fige:
		_depuis += delta
		if _depuis >= _duree_du_geste():
			_geste = ""

## Applique la pose au corps. `allure` sert a doser l'amplitude : on marche avec
## les memes muscles qu'on sprinte, en plus petit.
func appliquer(corps: Corps, allure: float) -> void:
	var vivacite := clampf(allure / 7.0, 0.0, 1.0)
	var angle := _phase * TAU

	_poser_les_jambes(corps, angle, allure, vivacite)
	_poser_les_bras(corps, angle, vivacite)
	_poser_le_buste(corps, angle, vivacite)

	# Le geste passe par-dessus : il ne remplace que ce dont il a besoin, si bien
	# qu'un joueur qui frappe en pleine course continue de courir du haut du
	# corps. C'est ce qui evite l'impression de deux animations qui se coupent.
	match _geste:
		"frappe", "passe":
			_poser_la_frappe(corps, _depuis / _duree_du_geste())
		"tacle":
			_poser_le_tacle(corps, _depuis / _duree_du_geste())

## Frappe : armer la jambe vers l'arriere, la lancer, puis l'accompagner.
##
## L'essentiel tient dans le decalage entre la cuisse et le genou. Une jambe qui
## se tend d'un bloc donne un coup de pied de pantin ; c'est le genou qui reste
## plie pendant l'armement puis se detend au dernier moment qui fait la frappe.
func _poser_la_frappe(corps: Corps, t: float) -> void:
	var cuisse := _entre_reperes([
		[0.00, 0.0], [0.28, 0.80], [0.52, -0.72], [1.00, -0.12]], t)
	var genou := _entre_reperes([
		[0.00, 0.2], [0.28, 1.25], [0.48, 0.55], [0.62, 0.05], [1.00, 0.25]], t)
	var cheville := _entre_reperes([
		[0.00, 0.0], [0.30, 0.35], [0.55, -0.30], [1.00, 0.0]], t)

	corps.poser_os(Corps.OS_HANCHE_D, Quaternion(Vector3.RIGHT, cuisse))
	corps.poser_os(Corps.OS_GENOU_D, Quaternion(Vector3.RIGHT, genou))
	corps.poser_os(Corps.OS_CHEVILLE_D, Quaternion(Vector3.RIGHT, cheville))

	# La jambe d'appui se plie un peu pour encaisser, et le bras oppose part en
	# arriere pour equilibrer — sans ce contrepoids, le joueur a l'air de frapper
	# dans le vide.
	corps.poser_os(Corps.OS_GENOU_G, Quaternion(Vector3.RIGHT,
		_entre_reperes([[0.0, 0.10], [0.5, 0.42], [1.0, 0.15]], t)))
	corps.poser_os(Corps.OS_EPAULE_G, Quaternion(Vector3.RIGHT,
		_entre_reperes([[0.0, 0.0], [0.45, 0.95], [1.0, 0.2]], t))
		* Quaternion(Vector3.BACK, 0.30))
	corps.poser_os(Corps.OS_TORSE, Quaternion(Vector3.UP,
		_entre_reperes([[0.0, 0.0], [0.30, 0.22], [0.60, -0.20], [1.0, 0.0]], t)))

## Tacle glisse : le joueur se laisse tomber sur le cote, jambe tendue devant.
func _poser_le_tacle(corps: Corps, t: float) -> void:
	var bascule := _entre_reperes([
		[0.00, 0.0], [0.22, -1.15], [0.70, -1.25], [1.00, -0.15]], t)
	var descente := _entre_reperes([
		[0.00, 0.0], [0.22, -0.62], [0.70, -0.68], [1.00, -0.05]], t)

	# On couche tout le squelette plutot que chaque membre : un tacle est un
	# mouvement du corps entier, et le detailler os par os ne se verrait pas.
	corps.squelette.rotation.x = bascule
	corps.squelette.position.y = descente

	corps.poser_os(Corps.OS_HANCHE_D, Quaternion(Vector3.RIGHT,
		_entre_reperes([[0.0, 0.0], [0.25, -0.85], [0.75, -0.95], [1.0, -0.1]], t)))
	corps.poser_os(Corps.OS_GENOU_D, Quaternion(Vector3.RIGHT,
		_entre_reperes([[0.0, 0.0], [0.30, 0.08], [1.0, 0.2]], t)))
	corps.poser_os(Corps.OS_HANCHE_G, Quaternion(Vector3.RIGHT,
		_entre_reperes([[0.0, 0.0], [0.30, 0.55], [1.0, 0.1]], t)))
	corps.poser_os(Corps.OS_GENOU_G, Quaternion(Vector3.RIGHT,
		_entre_reperes([[0.0, 0.0], [0.30, 1.05], [1.0, 0.2]], t)))

func _poser_les_jambes(corps: Corps, angle: float, allure: float, vivacite: float) -> void:
	var amplitude := BALANCEMENT_HANCHE + allure * BALANCEMENT_HANCHE_PAR_VITESSE
	# A l'arret, les jambes ne battent pas : elles portent le poids du corps.
	amplitude *= vivacite

	for cote in [0, 1]:
		var decalage := 0.0 if cote == 0 else PI     # les jambes sont en opposition
		var hanche := Corps.OS_HANCHE_G if cote == 0 else Corps.OS_HANCHE_D
		var genou := Corps.OS_GENOU_G if cote == 0 else Corps.OS_GENOU_D
		var cheville := Corps.OS_CHEVILLE_G if cote == 0 else Corps.OS_CHEVILLE_D
		var phase_jambe := angle + decalage

		# Une valeur positive fait partir la cuisse vers l'arriere ; on inverse
		# donc pour que le debut du cycle envoie la jambe devant.
		var cuisse := -sin(phase_jambe) * amplitude
		corps.poser_os(hanche, Quaternion(Vector3.RIGHT, cuisse))

		# Le genou ne se plie que dans un sens, et surtout pendant le retour de
		# jambe : c'est ce repliement qui distingue une course d'un pas de
		# patinage. On le decale d'un quart de cycle par rapport a la cuisse.
		var repliement := maxf(sin(phase_jambe - PI * 0.45), 0.0)
		corps.poser_os(genou, Quaternion(Vector3.RIGHT,
			repliement * FLEXION_GENOU * vivacite))

		# La cheville rattrape une partie de l'angle pour que le pied reste a
		# plat quand il touche le sol.
		var pied := -cuisse * 0.35 - repliement * 0.35 * vivacite
		corps.poser_os(cheville, Quaternion(Vector3.RIGHT, pied))

func _poser_les_bras(corps: Corps, angle: float, vivacite: float) -> void:
	var amplitude := BALANCEMENT_EPAULE * vivacite
	for cote in [0, 1]:
		var signe := 1.0 if cote == 0 else -1.0
		# Le bras accompagne la jambe opposee : c'est ce qui equilibre la course.
		var decalage := PI if cote == 0 else 0.0
		var epaule := Corps.OS_EPAULE_G if cote == 0 else Corps.OS_EPAULE_D
		var coude := Corps.OS_COUDE_G if cote == 0 else Corps.OS_COUDE_D

		var balancement := -sin(angle + decalage) * amplitude
		# L'ouverture ecarte le bras du buste : sans elle, l'avant-bras
		# traverserait les cotes a chaque foulee.
		var ouverture := OUVERTURE_BRAS + vivacite * 0.10
		corps.poser_os(epaule, Quaternion(Vector3.RIGHT, balancement)
			* Quaternion(Vector3.BACK, signe * ouverture))
		# Le coude reste plie en course, presque tendu a l'arret.
		corps.poser_os(coude, Quaternion(Vector3.RIGHT,
			FLEXION_COUDE * (0.35 + vivacite * 0.9)))

func _poser_le_buste(corps: Corps, angle: float, vivacite: float) -> void:
	# Le buste se penche en avant avec l'allure, et pivote legerement en sens
	# inverse des epaules.
	var penche := vivacite * 0.16
	var pivot := sin(angle) * 0.09 * vivacite
	corps.poser_os(Corps.OS_TORSE,
		Quaternion(Vector3.RIGHT, -penche) * Quaternion(Vector3.UP, pivot))

	# La tete compense l'inclinaison du buste : un joueur regarde le jeu, pas
	# ses pieds. C'est un detail, mais c'est celui qui donne une intention au
	# personnage plutot qu'un pantin qui bascule d'un bloc.
	corps.poser_os(Corps.OS_TETE, Quaternion(Vector3.RIGHT, penche * 0.75))

	# Le corps monte et descend deux fois par cycle, et respire a l'arret.
	var rebond := absf(sin(angle)) * 0.035 * vivacite
	var respiration := sin(_repos * TAU) * 0.006 * (1.0 - vivacite)
	corps.squelette.position.y = rebond + respiration
	# Remise a plat systematique : le tacle couche le squelette entier, et sans
	# ce retour a zero le joueur resterait penche en arriere pour le reste du
	# match une fois le geste termine.
	corps.squelette.rotation.x = 0.0
