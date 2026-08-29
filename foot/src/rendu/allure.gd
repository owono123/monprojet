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

## Position dans le cycle de foulee, de 0 a 1. Un cycle vaut deux pas.
var _phase := 0.0
## Balancement lent du corps a l'arret, pour qu'un joueur immobile respire.
var _repos := 0.0

## Avance le cycle. `distance` est le chemin parcouru au sol depuis la derniere
## image, `allure` la vitesse instantanee en metres par seconde.
func avancer(distance: float, allure: float, delta: float) -> void:
	var foulee := FOULEE_MINIMALE + allure * FOULEE_PAR_VITESSE
	_phase = fposmod(_phase + distance / (foulee * 2.0), 1.0)
	_repos = fposmod(_repos + delta * 0.35, 1.0)

## Applique la pose au corps. `allure` sert a doser l'amplitude : on marche avec
## les memes muscles qu'on sprinte, en plus petit.
func appliquer(corps: Corps, allure: float) -> void:
	var vivacite := clampf(allure / 7.0, 0.0, 1.0)
	var angle := _phase * TAU

	_poser_les_jambes(corps, angle, allure, vivacite)
	_poser_les_bras(corps, angle, vivacite)
	_poser_le_buste(corps, angle, vivacite)

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
