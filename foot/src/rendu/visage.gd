class_name Visage
extends RefCounted

## Tete et visage fabriques par le code, entierement reglables.
##
## Rien n'est importe : le crane, les orbites, le nez, la bouche, les oreilles
## et les cheveux sont de la geometrie calculee a partir d'une vingtaine de
## reglages. C'est ce qui remplace les visages de joueurs reels, qu'il n'est pas
## question de distribuer, et c'est aussi exactement la methode par laquelle un
## jeu de football fabrique l'immense majorite de ses propres joueurs.
##
## Les proportions de depart viennent des mesures anthropometriques courantes :
## une tete d'adulte fait environ 23,5 cm de haut, 15,5 cm de large et 19,5 cm
## de profondeur. Chaque reglage s'ecarte de cette base plutot que de partir de
## rien, ce qui evite les tetes impossibles.

const HAUTEUR_DE_BASE := 0.117    # demi-hauteur du crane
const LARGEUR_DE_BASE := 0.076
const PROFONDEUR_DE_BASE := 0.097

## Coupes de cheveux proposees.
enum { RASE, COURT, EPAIS, CREPU, CHAUVE }
## Pilosite du bas du visage.
enum { GLABRE, BOUC, BARBE }

## Reglages par defaut. Chaque valeur va de 0 a 1 sauf mention contraire ; 0,5
## correspond a la morphologie moyenne.
static func traits_par_defaut() -> Dictionary:
	return {
		"largeur_crane": 0.5, "hauteur_crane": 0.5, "profondeur_crane": 0.5,
		"largeur_machoire": 0.5, "menton": 0.5, "pommettes": 0.5, "arcades": 0.5,
		"ecartement_yeux": 0.5, "hauteur_yeux": 0.5, "taille_yeux": 0.5,
		"longueur_nez": 0.5, "largeur_nez": 0.5, "saillie_nez": 0.5,
		"largeur_bouche": 0.5, "epaisseur_levres": 0.5,
		"oreilles": 0.5,
		"coupe": COURT, "barbe": GLABRE,
	}

## Tire un visage au hasard, mais de facon reproductible. Le generateur passe en
## argument doit etre distinct de celui de la simulation : l'apparence ne doit
## jamais consommer l'alea du match, sous peine de fausser les replays.
static func traits_au_hasard(alea: Alea) -> Dictionary:
	var traits := traits_par_defaut()
	for reglage in ["largeur_crane", "hauteur_crane", "profondeur_crane",
			"largeur_machoire", "menton", "pommettes", "arcades",
			"ecartement_yeux", "hauteur_yeux", "taille_yeux",
			"longueur_nez", "largeur_nez", "saillie_nez",
			"largeur_bouche", "epaisseur_levres", "oreilles"]:
		# Loi en cloche approchee par la moyenne de deux tirages : les visages
		# tres marques restent rares, comme dans un effectif reel.
		traits[reglage] = (alea.reel() + alea.reel()) * 0.5
	traits["coupe"] = [RASE, COURT, COURT, COURT, EPAIS, EPAIS, CREPU, CHAUVE][alea.entier(8)]
	traits["barbe"] = [GLABRE, GLABRE, GLABRE, BOUC, BARBE][alea.entier(5)]
	return traits

## Ajoute la tete complete au maillage. `ancrage` est le sommet du cou, dans le
## repere du squelette ; `os` l'os de la tete.
static func ajouter(outil: SurfaceTool, ancrage: Vector3, os: int, traits: Dictionary) -> void:
	var rayons := Vector3(
		LARGEUR_DE_BASE * lerpf(0.90, 1.12, traits["largeur_crane"]),
		HAUTEUR_DE_BASE * lerpf(0.92, 1.10, traits["hauteur_crane"]),
		PROFONDEUR_DE_BASE * lerpf(0.92, 1.10, traits["profondeur_crane"]))
	# Le menton se pose juste au-dessus du cou : le crane est donc centre une
	# demi-hauteur plus haut.
	var centre := ancrage + Vector3(0.0, rayons.y * 0.97, 0.0)

	_ajouter_crane(outil, centre, rayons, os, traits)
	_ajouter_yeux(outil, centre, rayons, os, traits)
	_ajouter_sourcils(outil, centre, rayons, os, traits)
	_ajouter_nez(outil, centre, rayons, os, traits)
	_ajouter_bouche(outil, centre, rayons, os, traits)
	_ajouter_oreilles(outil, centre, rayons, os, traits)
	_ajouter_cheveux(outil, centre, rayons, os, traits)

# --- Crane ------------------------------------------------------------------

## Le crane n'est pas une bille : la machoire se retrecit vers le menton, les
## pommettes elargissent le milieu du visage, et l'arriere de la tete est plus
## rond que l'avant. Ce sont ces trois ecarts qui font la difference entre une
## tete et un oeuf.
static func _ajouter_crane(outil: SurfaceTool, centre: Vector3, rayons: Vector3,
		os: int, traits: Dictionary) -> void:
	var meridiens := 16
	var paralleles := 12
	var machoire := lerpf(0.82, 0.97, traits["largeur_machoire"])
	var menton := lerpf(0.0, 0.020, traits["menton"])
	var pommettes := lerpf(0.0, 0.010, traits["pommettes"])

	var grille: Array = []
	for anneau in paralleles + 1:
		var phi := PI * float(anneau) / float(paralleles)
		var ligne: Array = []
		for pas in meridiens:
			var theta := TAU * float(pas) / float(meridiens)
			var direction := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			ligne.append({
				"point": centre + _deformer_le_crane(direction, rayons, machoire,
					menton, pommettes),
				"uv": Vector2(float(pas) / float(meridiens), float(anneau) / float(paralleles)),
				"os": os, "parent": os, "melange": 0.0,
			})
		grille.append(ligne)

	for anneau in paralleles:
		for pas in meridiens:
			var suivant := (pas + 1) % meridiens
			Atelier.quadrilatere(outil, Atelier.ZONE_PEAU,
				grille[anneau][pas], grille[anneau][suivant],
				grille[anneau + 1][suivant], grille[anneau + 1][pas])

static func _deformer_le_crane(direction: Vector3, rayons: Vector3, machoire: float,
		menton: float, pommettes: float) -> Vector3:
	# En dessous des yeux le visage se resserre vers la machoire.
	var bas := smoothstep(0.10, -0.80, direction.y)
	var retrecissement := lerpf(1.0, machoire, bas)
	var point := Vector3(
		direction.x * rayons.x * retrecissement,
		direction.y * rayons.y,
		direction.z * rayons.z * lerpf(1.0, 0.90, bas))
	# Le menton avance sous la bouche.
	point.z += menton * bas * maxf(direction.z, 0.0)
	# Les pommettes elargissent le milieu du visage, cote face uniquement.
	var hauteur_pommettes := exp(-pow((direction.y + 0.05) * 3.4, 2.0))
	point.x += sign(direction.x) * pommettes * hauteur_pommettes * maxf(direction.z, 0.0)
	# L'arriere du crane est legerement plus plein que l'avant.
	point.z += maxf(-direction.z, 0.0) * rayons.z * 0.06
	return point

# --- Yeux -------------------------------------------------------------------

static func _ecart_des_yeux(rayons: Vector3, traits: Dictionary) -> float:
	return rayons.x * lerpf(0.36, 0.50, traits["ecartement_yeux"])

static func _hauteur_des_yeux(rayons: Vector3, traits: Dictionary) -> float:
	return rayons.y * lerpf(0.02, 0.16, traits["hauteur_yeux"])

## Profondeur a laquelle poser un element pose sur le visage, pour qu'il affleure
## la surface du crane au lieu de flotter devant ou de s'y enfoncer.
static func _affleurement(rayons: Vector3, ecart: float, hauteur: float) -> float:
	var reste := 1.0 - pow(ecart / rayons.x, 2.0) - pow(hauteur / rayons.y, 2.0)
	return rayons.z * sqrt(maxf(reste, 0.05))

static func _ajouter_yeux(outil: SurfaceTool, centre: Vector3, rayons: Vector3,
		os: int, traits: Dictionary) -> void:
	var ecart := _ecart_des_yeux(rayons, traits)
	var hauteur := _hauteur_des_yeux(rayons, traits)
	var surface := _affleurement(rayons, ecart, hauteur)
	var taille := lerpf(0.0115, 0.0155, traits["taille_yeux"])

	for cote in [1.0, -1.0]:
		var oeil := centre + Vector3(cote * ecart, hauteur, surface - taille * 0.55)
		# Le globe est ecrase en profondeur : un oeil entier ferait ressortir une
		# bille, alors qu'on n'en voit qu'une calotte entre les paupieres.
		Atelier.ellipsoide(outil, oeil, Vector3(taille, taille * 0.72, taille * 0.62),
			8, 5, os, Atelier.ZONE_OEIL)
		# Iris et pupille, poses juste devant le blanc.
		Atelier.ellipsoide(outil, oeil + Vector3(0.0, 0.0, taille * 0.42),
			Vector3(taille * 0.50, taille * 0.50, taille * 0.26),
			8, 4, os, Atelier.ZONE_IRIS)

## Les arcades sourcilieres font plus pour l'expression que les yeux eux-memes :
## sans elles, un visage a l'air etonne en permanence.
static func _ajouter_sourcils(outil: SurfaceTool, centre: Vector3, rayons: Vector3,
		os: int, traits: Dictionary) -> void:
	var ecart := _ecart_des_yeux(rayons, traits)
	var hauteur := _hauteur_des_yeux(rayons, traits) + rayons.y * 0.15
	var surface := _affleurement(rayons, ecart, hauteur)
	var epaisseur := lerpf(0.0035, 0.0065, traits["arcades"])

	for cote in [1.0, -1.0]:
		var repere := Transform3D(Basis(Vector3.BACK, cote * 0.16),
			centre + Vector3(cote * ecart, hauteur, surface - 0.004))
		Atelier.boite(outil, repere, Vector3(rayons.x * 0.34, epaisseur, 0.006),
			os, Atelier.ZONE_SOURCILS)

# --- Nez, bouche, oreilles --------------------------------------------------

static func _ajouter_nez(outil: SurfaceTool, centre: Vector3, rayons: Vector3,
		os: int, traits: Dictionary) -> void:
	var haut := _hauteur_des_yeux(rayons, traits) + rayons.y * 0.10
	var bas := haut - rayons.y * lerpf(0.34, 0.48, traits["longueur_nez"])
	# La racine s'enfonce dans le crane, la pointe en ressort franchement : un nez
	# reel avance de deux bons centimetres au bout. Avec un depassement d'un
	# centimetre, il disparaissait completement dans la silhouette.
	var racine := centre + Vector3(0.0, haut, _affleurement(rayons, 0.0, haut) - 0.016)
	var pointe := centre + Vector3(0.0, bas,
		_affleurement(rayons, 0.0, bas) + lerpf(0.013, 0.026, traits["saillie_nez"]))
	var largeur := lerpf(0.009, 0.016, traits["largeur_nez"])
	Atelier.tube(outil, racine, pointe, largeur * 0.55, largeur, 7, os, os,
		Atelier.ZONE_PEAU, 1.0, 3)
	# Les ailes du nez, deux petits volumes de part et d'autre de la pointe.
	for cote in [1.0, -1.0]:
		Atelier.ellipsoide(outil, pointe + Vector3(cote * largeur * 0.85, 0.002, -0.006),
			Vector3(largeur * 0.52, largeur * 0.60, largeur * 0.70),
			6, 4, os, Atelier.ZONE_PEAU)

static func _ajouter_bouche(outil: SurfaceTool, centre: Vector3, rayons: Vector3,
		os: int, traits: Dictionary) -> void:
	var hauteur := _hauteur_des_yeux(rayons, traits) - rayons.y * 0.52
	var surface := _affleurement(rayons, 0.0, hauteur)
	# La bouche est enfoncee dans le visage plutot que posee dessus : une boite
	# qui affleure attrape la lumiere et donne l'impression d'un pansement.
	var repere := Transform3D(Basis(), centre + Vector3(0.0, hauteur, surface - 0.009))
	Atelier.boite(outil, repere, Vector3(
		rayons.x * lerpf(0.26, 0.38, traits["largeur_bouche"]),
		lerpf(0.0030, 0.0062, traits["epaisseur_levres"]),
		0.008), os, Atelier.ZONE_LEVRES)

static func _ajouter_oreilles(outil: SurfaceTool, centre: Vector3, rayons: Vector3,
		os: int, traits: Dictionary) -> void:
	var taille := lerpf(0.017, 0.024, traits["oreilles"])
	for cote in [1.0, -1.0]:
		# L'oreille est plaquee contre le crane et legerement inclinee vers
		# l'arriere ; posee droite et ecartee, elle se detache et flotte.
		var repere := Basis(Vector3.RIGHT, 0.20)
		Atelier.ellipsoide(outil,
			centre + Vector3(cote * rayons.x * 0.90, rayons.y * 0.00, -rayons.z * 0.14),
			Vector3(taille * 0.34, taille, taille * 0.58),
			6, 4, os, Atelier.ZONE_PEAU, repere)

# --- Cheveux et barbe -------------------------------------------------------

## Les cheveux sont une calotte posee sur le crane : on parcourt la meme sphere
## et l'on ne garde que les quadrilateres situes au-dessus de la ligne de
## cheveux. Celle-ci descend plus bas derriere que devant, ce qui degage le
## front — sans cette inclinaison, le joueur porte un bonnet.
static func _ajouter_cheveux(outil: SurfaceTool, centre: Vector3, rayons: Vector3,
		os: int, traits: Dictionary) -> void:
	var coupe: int = traits["coupe"]
	if coupe == CHAUVE:
		_ajouter_barbe(outil, centre, rayons, os, traits)
		return

	# Epaisseur de la calotte et hauteur de la ligne de cheveux, par coupe.
	# Le type est declare : indexer un tableau litteral ne renvoie qu'une valeur
	# sans type, que GDScript refuse d'inferer.
	var epaisseur: float = [0.004, 0.010, 0.019, 0.032][coupe]
	# Hauteur de la ligne de cheveux a l'arriere du crane. Elle descend jusqu'a
	# la nuque, alors que devant elle s'arrete juste au-dessus des sourcils.
	# Une limite unique tout autour de la tete donnait un bonnet de bain.
	var nuque: float = [-0.34, -0.40, -0.46, -0.50][coupe]
	var pente: float = 0.70
	var enveloppe := rayons + Vector3(epaisseur, epaisseur, epaisseur)
	_ajouter_calotte(outil, centre, enveloppe, os, Atelier.ZONE_CHEVEUX,
		func(direction: Vector3) -> bool:
			# Le front est degage : la limite remonte du cote du visage.
			return direction.y > nuque + maxf(direction.z, 0.0) * pente)

	_ajouter_barbe(outil, centre, rayons, os, traits)

static func _ajouter_barbe(outil: SurfaceTool, centre: Vector3, rayons: Vector3,
		os: int, traits: Dictionary) -> void:
	var barbe: int = traits["barbe"]
	if barbe == GLABRE:
		return
	var enveloppe := rayons + Vector3(0.003, 0.003, 0.003)
	if barbe == BOUC:
		_ajouter_calotte(outil, centre, enveloppe, os, Atelier.ZONE_CHEVEUX,
			func(direction: Vector3) -> bool:
				return direction.y < -0.42 and direction.z > 0.45)
	else:
		_ajouter_calotte(outil, centre, enveloppe, os, Atelier.ZONE_CHEVEUX,
			func(direction: Vector3) -> bool:
				return direction.y < -0.22 and direction.z > 0.08)

## Parcourt une sphere et n'emet que les quadrilateres dont les quatre coins
## satisfont le critere. Sert aux cheveux comme a la barbe.
static func _ajouter_calotte(outil: SurfaceTool, centre: Vector3, rayons: Vector3,
		os: int, zone: float, garder: Callable) -> void:
	var meridiens := 16
	var paralleles := 12
	var directions: Array = []
	var points: Array = []
	for anneau in paralleles + 1:
		var phi := PI * float(anneau) / float(paralleles)
		var ligne_directions: Array = []
		var ligne_points: Array = []
		for pas in meridiens:
			var theta := TAU * float(pas) / float(meridiens)
			var direction := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			ligne_directions.append(direction)
			ligne_points.append({
				"point": centre + direction * rayons,
				"uv": Vector2(float(pas) / float(meridiens), float(anneau) / float(paralleles)),
				"os": os, "parent": os, "melange": 0.0,
			})
		directions.append(ligne_directions)
		points.append(ligne_points)

	for anneau in paralleles:
		for pas in meridiens:
			var suivant := (pas + 1) % meridiens
			var coins := [directions[anneau][pas], directions[anneau][suivant],
				directions[anneau + 1][suivant], directions[anneau + 1][pas]]
			var tous_gardes := true
			for coin in coins:
				if not garder.call(coin):
					tous_gardes = false
					break
			if tous_gardes:
				Atelier.quadrilatere(outil, zone, points[anneau][pas],
					points[anneau][suivant], points[anneau + 1][suivant],
					points[anneau + 1][pas])
