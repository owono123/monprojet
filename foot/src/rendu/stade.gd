class_name Stade
extends Node3D

## Le stade : gradins, foule, panneaux publicitaires et projecteurs, fabriques
## par le code a partir de quelques dimensions.
##
## C'est la piece qui fait le plus pour l'impression d'ensemble. Un terrain
## parfaitement trace pose au milieu du vide a toujours l'air d'un essai
## technique ; les memes joueurs dans une enceinte pleine ont l'air d'un match.
##
## Le budget est tenu par deux choix. Les sieges ne sont pas de la geometrie :
## ils sont dessines dans le pixel sur la pente des gradins, ce qui evite
## quarante mille petits volumes. Et la foule est un unique MultiMesh — plusieurs
## milliers de spectateurs en un seul appel de rendu, la ou autant de noeuds
## separes mettraient un telephone a genoux.

## Empreinte au sol de la premiere rangee, au-dela de la pelouse.
const DEMI_LONGUEUR_INTERIEURE := 62.0
const DEMI_LARGEUR_INTERIEURE := 44.0
const RAYON_DES_ANGLES := 16.0

## Profil des gradins : de combien on s'eloigne et de combien on monte a chaque
## rangee. Une pente d'environ 30 degres, celle des enceintes modernes — assez
## raide pour que le rang du dessus voie par-dessus le rang du dessous.
const RANGEES := 12
const RECUL_PAR_RANGEE := 2.15
const MONTEE_PAR_RANGEE := 1.24
const HAUTEUR_PREMIERE_RANGEE := 1.6

## Finesse du contour. Soixante-douze points suffisent : au-dela, les angles
## arrondis ne gagnent plus rien de visible et l'on paye des sommets pour rien.
const POINTS_DU_CONTOUR := 72

## Espacement des spectateurs le long d'une rangee, en metres.
const ESPACEMENT_FOULE := 0.72
## Part des places occupees.
const TAUX_DE_REMPLISSAGE := 0.88

const CHEMIN_SHADER_GRADINS := "res://src/rendu/gradins.gdshader"
const CHEMIN_SHADER_FOULE := "res://src/rendu/foule.gdshader"
const CHEMIN_SHADER_PANNEAUX := "res://src/rendu/panneaux.gdshader"

var _foule: MultiMeshInstance3D

func _ready() -> void:
	_construire_les_gradins()
	_construire_la_foule()
	_construire_les_panneaux()
	_construire_les_projecteurs()

## Contour de l'enceinte a une distance donnee de la premiere rangee : un
## rectangle aux angles arrondis. Ecarter le contour revient a agrandir ses
## demi-dimensions et le rayon de ses angles de la meme quantite, ce qui garde
## des rangees regulierement espacees jusque dans les virages.
static func contour(ecart: float) -> PackedVector2Array:
	var demi_x := DEMI_LONGUEUR_INTERIEURE + ecart
	var demi_z := DEMI_LARGEUR_INTERIEURE + ecart
	var rayon := RAYON_DES_ANGLES + ecart
	var droit_x := maxf(demi_x - rayon, 0.0)
	var droit_z := maxf(demi_z - rayon, 0.0)

	var points := PackedVector2Array()
	for pas in POINTS_DU_CONTOUR:
		var angle := TAU * float(pas) / float(POINTS_DU_CONTOUR)
		# Un rectangle arrondi se decrit comme un cercle dont le centre glisse
		# le long des cotes : le signe du cosinus et du sinus indique dans quel
		# angle l'on se trouve.
		points.append(Vector2(
			signf(cos(angle)) * droit_x + cos(angle) * rayon,
			signf(sin(angle)) * droit_z + sin(angle) * rayon))
	return points

# --- Gradins ----------------------------------------------------------------

func _construire_les_gradins() -> void:
	var outil := SurfaceTool.new()
	outil.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Le tableau est typé : sans cela, chacun de ses elements est une valeur sans
	# type et GDScript refuse d'inferer ce qu'on en tire.
	var contours: Array[PackedVector2Array] = []
	for rangee in RANGEES + 1:
		contours.append(contour(float(rangee) * RECUL_PAR_RANGEE))

	for rangee in RANGEES:
		var bas := contours[rangee]
		var haut := contours[rangee + 1]
		var y_bas := HAUTEUR_PREMIERE_RANGEE + float(rangee) * MONTEE_PAR_RANGEE
		var y_haut := y_bas + MONTEE_PAR_RANGEE
		var v_bas := float(rangee) / float(RANGEES)
		var v_haut := float(rangee + 1) / float(RANGEES)

		for pas in POINTS_DU_CONTOUR:
			var suivant := (pas + 1) % POINTS_DU_CONTOUR
			var u := float(pas) / float(POINTS_DU_CONTOUR)
			var u_suivant := float(pas + 1) / float(POINTS_DU_CONTOUR)
			# Les sommets tournent dans le sens qui presente la face au terrain.
			_quadrilatere(outil,
				Vector3(bas[suivant].x, y_bas, bas[suivant].y), Vector2(u_suivant, v_bas),
				Vector3(bas[pas].x, y_bas, bas[pas].y), Vector2(u, v_bas),
				Vector3(haut[pas].x, y_haut, haut[pas].y), Vector2(u, v_haut),
				Vector3(haut[suivant].x, y_haut, haut[suivant].y), Vector2(u_suivant, v_haut))

	# Mur de soutenement entre la pelouse et la premiere rangee : sans lui, les
	# gradins semblent leviter au-dessus du terrain.
	var pied := contours[0]
	for pas in POINTS_DU_CONTOUR:
		var suivant := (pas + 1) % POINTS_DU_CONTOUR
		var u := float(pas) / float(POINTS_DU_CONTOUR)
		var u_suivant := float(pas + 1) / float(POINTS_DU_CONTOUR)
		_quadrilatere(outil,
			Vector3(pied[suivant].x, 0.0, pied[suivant].y), Vector2(u_suivant, -1.0),
			Vector3(pied[pas].x, 0.0, pied[pas].y), Vector2(u, -1.0),
			Vector3(pied[pas].x, HAUTEUR_PREMIERE_RANGEE, pied[pas].y), Vector2(u, -1.0),
			Vector3(pied[suivant].x, HAUTEUR_PREMIERE_RANGEE, pied[suivant].y),
			Vector2(u_suivant, -1.0))

	outil.generate_normals()

	var matiere := ShaderMaterial.new()
	matiere.shader = load(CHEMIN_SHADER_GRADINS)
	matiere.set_shader_parameter("rangees", float(RANGEES))
	matiere.set_shader_parameter("places_par_rangee",
		float(POINTS_DU_CONTOUR) * 6.0)

	var gradins := MeshInstance3D.new()
	gradins.name = "Gradins"
	gradins.mesh = outil.commit()
	gradins.material_override = matiere
	gradins.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gradins)

func _quadrilatere(outil: SurfaceTool, a: Vector3, uv_a: Vector2, b: Vector3, uv_b: Vector2,
		c: Vector3, uv_c: Vector2, d: Vector3, uv_d: Vector2) -> void:
	for sommet in [[a, uv_a], [b, uv_b], [c, uv_c], [a, uv_a], [c, uv_c], [d, uv_d]]:
		outil.set_uv(sommet[1])
		outil.add_vertex(sommet[0])

# --- Foule ------------------------------------------------------------------

## Plusieurs milliers de spectateurs en un seul appel de rendu.
##
## Chacun est un simple quadrilatere tourne vers le centre du terrain. On
## pourrait le faire pivoter vers la camera a chaque image, mais c'est inutile
## ici : le public regarde le jeu, et la camera reste toujours du meme cote.
## Un quadrilatere fixe coute donc exactement rien de plus qu'un panneau
## d'affichage, et evite tout calcul par sommet.
func _construire_la_foule() -> void:
	var quadrilatere := QuadMesh.new()
	quadrilatere.size = Vector2(0.52, 1.05)

	var matiere := ShaderMaterial.new()
	matiere.shader = load(CHEMIN_SHADER_FOULE)
	quadrilatere.material = matiere

	var multiple := MultiMesh.new()
	multiple.transform_format = MultiMesh.TRANSFORM_3D
	multiple.use_colors = true
	multiple.mesh = quadrilatere

	# Un generateur a graine dediee : le placement doit etre identique d'un
	# lancement a l'autre, sans jamais puiser dans l'alea de la simulation.
	var alea := Alea.new(1907)
	var places: Array[Transform3D] = []
	var couleurs: Array[Color] = []

	var demi_hauteur: float = quadrilatere.size.y * 0.5
	for rangee in range(1, RANGEES):
		# Les spectateurs sont semes au milieu de la marche, il faut donc les
		# poser a la hauteur qu'a la PENTE a cet endroit, pas a celle du bas de
		# la marche. Sans cette demi-montee, ils s'enfoncent dans le gradin et
		# l'on ne voit plus que le sommet de leur crane.
		var surface := HAUTEUR_PREMIERE_RANGEE + float(rangee) * MONTEE_PAR_RANGEE \
			+ MONTEE_PAR_RANGEE * 0.5
		var ligne := contour(float(rangee) * RECUL_PAR_RANGEE + RECUL_PAR_RANGEE * 0.5)
		_semer_une_rangee(ligne, surface + demi_hauteur, alea, places, couleurs)

	multiple.instance_count = places.size()
	for index in places.size():
		multiple.set_instance_transform(index, places[index])
		multiple.set_instance_color(index, couleurs[index])

	_foule = MultiMeshInstance3D.new()
	_foule.name = "Foule"
	_foule.multimesh = multiple
	_foule.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_foule)

func _semer_une_rangee(ligne: PackedVector2Array, hauteur: float, alea: Alea,
		places: Array[Transform3D], couleurs: Array[Color]) -> void:
	for pas in ligne.size():
		var depart := ligne[pas]
		var arrivee := ligne[(pas + 1) % ligne.size()]
		var segment := arrivee - depart
		var longueur := segment.length()
		var combien := int(longueur / ESPACEMENT_FOULE)
		for index in combien:
			if not alea.chance(TAUX_DE_REMPLISSAGE):
				continue
			var avancee := (float(index) + alea.reel_entre(0.25, 0.75)) / float(maxi(combien, 1))
			var point := depart + segment * avancee
			var endroit := Vector3(point.x, hauteur + alea.reel_entre(-0.06, 0.06), point.y)
			# Chacun regarde le centre du terrain, avec un peu de flottement.
			var vers_centre := -Vector3(point.x, 0.0, point.y).normalized()
			var angle := atan2(vers_centre.x, vers_centre.z) + alea.reel_entre(-0.25, 0.25)
			places.append(Transform3D(Basis(Vector3.UP, angle), endroit))
			couleurs.append(_couleur_de_spectateur(alea))

## Le public n'est pas uniforme : quelques couleurs dominantes pour les maillots
## de l'equipe qui recoit, et beaucoup de teintes ternes autour. Un stade tout
## en couleurs vives ressemble a des confettis.
func _couleur_de_spectateur(alea: Alea) -> Color:
	var tirage := alea.reel()
	if tirage < 0.34:
		return Color(0.62, 0.13, 0.15).lightened(alea.reel_entre(-0.1, 0.25))
	if tirage < 0.50:
		return Color(0.88, 0.88, 0.90).darkened(alea.reel_entre(0.0, 0.3))
	var gris := alea.reel_entre(0.16, 0.46)
	return Color(gris * alea.reel_entre(0.9, 1.25), gris, gris * alea.reel_entre(0.9, 1.2))

# --- Panneaux publicitaires -------------------------------------------------

## Bandeau tout autour du terrain. Les panneaux ne portent aucune marque : ce
## sont des aplats de couleur, que l'editeur de stade laissera regler.
func _construire_les_panneaux() -> void:
	var hauteur := 0.95
	var ligne := contour(-2.4)
	var outil := SurfaceTool.new()
	outil.begin(Mesh.PRIMITIVE_TRIANGLES)

	var parcouru := 0.0
	for pas in ligne.size():
		var depart := ligne[pas]
		var arrivee := ligne[(pas + 1) % ligne.size()]
		var longueur := depart.distance_to(arrivee)
		# L'UV porte des metres : la largeur d'un panneau reste la meme partout,
		# y compris dans les virages ou les segments sont plus courts.
		_quadrilatere(outil,
			Vector3(arrivee.x, 0.0, arrivee.y), Vector2(parcouru + longueur, 1.0),
			Vector3(depart.x, 0.0, depart.y), Vector2(parcouru, 1.0),
			Vector3(depart.x, hauteur, depart.y), Vector2(parcouru, 0.0),
			Vector3(arrivee.x, hauteur, arrivee.y), Vector2(parcouru + longueur, 0.0))
		parcouru += longueur

	outil.generate_normals()

	var matiere := ShaderMaterial.new()
	matiere.shader = load(CHEMIN_SHADER_PANNEAUX)

	var panneaux := MeshInstance3D.new()
	panneaux.name = "Panneaux"
	panneaux.mesh = outil.commit()
	panneaux.material_override = matiere
	panneaux.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(panneaux)

# --- Projecteurs ------------------------------------------------------------

## Quatre pylones aux angles. Ils n'eclairent rien pour l'instant — la lumiere
## vient du soleil — mais ils ferment la silhouette de l'enceinte, et serviront
## de support aux matchs en nocturne.
func _construire_les_projecteurs() -> void:
	var hauteur := HAUTEUR_PREMIERE_RANGEE + RANGEES * MONTEE_PAR_RANGEE + 11.0
	var ecart := RANGEES * RECUL_PAR_RANGEE

	var mat_pylone := StandardMaterial3D.new()
	mat_pylone.albedo_color = Color(0.24, 0.25, 0.27)
	mat_pylone.roughness = 0.7

	var mat_lampes := StandardMaterial3D.new()
	mat_lampes.albedo_color = Color(0.90, 0.92, 0.85)
	mat_lampes.emission_enabled = true
	mat_lampes.emission = Color(1.0, 0.97, 0.88)
	mat_lampes.emission_energy_multiplier = 1.4

	# Les variables de boucle sont typees : sans cela GDScript les prend pour des
	# valeurs sans type et refuse d'inferer ce qu'on en construit.
	for cote_x: float in [1.0, -1.0]:
		for cote_z: float in [1.0, -1.0]:
			var pied := Vector3(
				cote_x * (DEMI_LONGUEUR_INTERIEURE + ecart * 0.62), 0.0,
				cote_z * (DEMI_LARGEUR_INTERIEURE + ecart * 0.62))

			var mat := MeshInstance3D.new()
			var poteau := BoxMesh.new()
			poteau.size = Vector3(1.1, hauteur, 1.1)
			mat.mesh = poteau
			mat.material_override = mat_pylone
			mat.position = pied + Vector3(0.0, hauteur * 0.5, 0.0)
			add_child(mat)

			var rampe := MeshInstance3D.new()
			var bloc := BoxMesh.new()
			bloc.size = Vector3(7.5, 2.6, 1.0)
			rampe.mesh = bloc
			rampe.material_override = mat_lampes
			rampe.position = pied + Vector3(0.0, hauteur + 1.0, 0.0)
			# La rampe est tournee vers le centre du terrain.
			rampe.rotation.y = atan2(-pied.x, -pied.z) + PI * 0.5
			add_child(rampe)
