class_name Corps
extends Node3D

## Fabrique un joueur complet par le code : squelette, corps, visage et tenue.
## Aucun modele n'est importe.
##
## Deux decisions commandent tout ce fichier.
##
## D'abord, **un seul maillage par joueur**. Assembler un corps a partir de
## morceaux separes serait plus simple a ecrire, mais ferait une quinzaine
## d'appels de rendu par joueur, soit plus de trois cents pour un match : un
## Mali-G71 s'effondre bien avant. Le corps est donc un maillage unique attache
## a un squelette, ce qui ramene le cout a vingt-deux appels. C'est aussi la
## seule facon d'avoir des articulations qui se plient au lieu de se disloquer.
##
## Ensuite, **aucune texture**. Chaque sommet transporte l'indication de ce
## qu'il represente — peau, maillot, short, cheveux, iris — et le nuancier
## arrive par des parametres propres a l'instance. Deux joueurs partagent donc
## le meme materiau en memoire tout en ayant teint, tenue et couleur de cheveux
## differents.

# Os du squelette. L'ordre est fige : il sert d'index dans toutes les poses.
const OS_BASSIN := 0
const OS_TORSE := 1
const OS_COU := 2
const OS_TETE := 3
const OS_EPAULE_G := 4
const OS_COUDE_G := 5
const OS_MAIN_G := 6
const OS_EPAULE_D := 7
const OS_COUDE_D := 8
const OS_MAIN_D := 9
const OS_HANCHE_G := 10
const OS_GENOU_G := 11
const OS_CHEVILLE_G := 12
const OS_HANCHE_D := 13
const OS_GENOU_D := 14
const OS_CHEVILLE_D := 15

## Proportions d'un joueur de reference, en metres depuis le sol. Elles suivent
## les rapports anatomiques courants : l'entrejambe a peu pres a la moitie de la
## taille, l'epaule aux quatre cinquiemes, une largeur d'epaules d'environ un
## quart de la hauteur.
const TAILLE_DE_REFERENCE := 1.80
const HAUTEUR_BASSIN := 0.92
const HAUTEUR_TORSE := 0.13      # du bassin au bas de la cage thoracique
const LONGUEUR_TORSE := 0.37     # du bas du torse a la base du cou
const LONGUEUR_COU := 0.075
const DEMI_EPAULES := 0.215
const LONGUEUR_BRAS := 0.29
const LONGUEUR_AVANT_BRAS := 0.26
const DEMI_HANCHES := 0.095
const LONGUEUR_CUISSE := 0.45
const LONGUEUR_MOLLET := 0.39
const HAUTEUR_CHEVILLE := 0.08

const CHEMIN_SHADER := "res://src/rendu/joueur.gdshader"

var squelette: Skeleton3D
var maillage: MeshInstance3D

var _corpulence := 0.5

## Construit un joueur. `taille` en metres, `corpulence` de 0 (fin) a 1 (epais),
## `traits` les reglages du visage (voir Visage.traits_par_defaut).
static func construire(taille: float, corpulence: float, tenue: Dictionary,
		traits: Dictionary = {}) -> Corps:
	var corps := Corps.new()
	corps._corpulence = clampf(corpulence, 0.0, 1.0)
	corps._batir(tenue, traits if not traits.is_empty() else Visage.traits_par_defaut())
	# Une taille differente de la reference se fait par une mise a l'echelle :
	# refabriquer un maillage entier par joueur couterait de la memoire pour une
	# difference que personne ne voit a quinze metres.
	var facteur := clampf(taille, 1.55, 2.05) / TAILLE_DE_REFERENCE
	corps.squelette.scale = Vector3(facteur, facteur, facteur)
	return corps

func _batir(tenue: Dictionary, traits: Dictionary) -> void:
	squelette = Skeleton3D.new()
	squelette.name = "Squelette"
	_poser_les_os()
	add_child(squelette)

	maillage = MeshInstance3D.new()
	maillage.name = "Corps"
	maillage.mesh = _construire_le_maillage(traits)
	squelette.add_child(maillage)
	# Le lien vers le squelette doit etre pose explicitement. Un MeshInstance3D
	# cree par le code naquit avec un chemin VIDE, et non le « .. » que l'editeur
	# renseigne : sans cette ligne, le maillage n'est relie a aucun squelette et
	# s'affiche eternellement dans sa pose de repos. Les animations tournaient
	# bien, elles ne se voyaient simplement nulle part.
	maillage.skeleton = NodePath("..")
	maillage.skin = squelette.create_skin_from_rest_transforms()
	var matiere := ShaderMaterial.new()
	matiere.shader = load(CHEMIN_SHADER)
	maillage.material_override = matiere
	_appliquer_la_tenue(tenue)

# --- Squelette --------------------------------------------------------------

func _poser_les_os() -> void:
	# Chaque os est place par rapport a son parent. Le squelette est construit
	# dans la pose de repos, exactement celle dans laquelle le maillage est
	# dessine : c'est ce qui permet a create_skin_from_rest_transforms() de
	# calculer seule les matrices de liaison.
	_ajouter_os("bassin", -1, Vector3(0.0, HAUTEUR_BASSIN, 0.0))
	_ajouter_os("torse", OS_BASSIN, Vector3(0.0, HAUTEUR_TORSE, 0.0))
	_ajouter_os("cou", OS_TORSE, Vector3(0.0, LONGUEUR_TORSE, 0.0))
	_ajouter_os("tete", OS_COU, Vector3(0.0, LONGUEUR_COU, 0.0))

	for cote in [1.0, -1.0]:
		var suffixe := "_g" if cote > 0.0 else "_d"
		var epaule := _ajouter_os("epaule" + suffixe, OS_TORSE,
			Vector3(cote * DEMI_EPAULES, LONGUEUR_TORSE - 0.06, 0.0))
		var coude := _ajouter_os("coude" + suffixe, epaule,
			Vector3(0.0, -LONGUEUR_BRAS, 0.0))
		_ajouter_os("main" + suffixe, coude, Vector3(0.0, -LONGUEUR_AVANT_BRAS, 0.0))

	for cote in [1.0, -1.0]:
		var suffixe := "_g" if cote > 0.0 else "_d"
		var hanche := _ajouter_os("hanche" + suffixe, OS_BASSIN,
			Vector3(cote * DEMI_HANCHES, 0.0, 0.0))
		var genou := _ajouter_os("genou" + suffixe, hanche,
			Vector3(0.0, -LONGUEUR_CUISSE, 0.0))
		_ajouter_os("cheville" + suffixe, genou, Vector3(0.0, -LONGUEUR_MOLLET, 0.0))

func _ajouter_os(nom: String, parent: int, position_relative: Vector3) -> int:
	var index := squelette.get_bone_count()
	squelette.add_bone(nom)
	if parent >= 0:
		squelette.set_bone_parent(index, parent)
	squelette.set_bone_rest(index, Transform3D(Basis(), position_relative))
	squelette.reset_bone_pose(index)
	return index

## Position d'un os dans le repere du squelette, pose de repos. Sert a dessiner
## le maillage au bon endroit.
func _endroit_de_l_os(index: int) -> Vector3:
	var endroit := Vector3.ZERO
	var courant := index
	while courant >= 0:
		endroit += squelette.get_bone_rest(courant).origin
		courant = squelette.get_bone_parent(courant)
	return endroit

# --- Maillage ---------------------------------------------------------------

func _construire_le_maillage(traits: Dictionary) -> ArrayMesh:
	var epaisseur := 0.90 + _corpulence * 0.26
	var outil := SurfaceTool.new()
	outil.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Tronc, en sections elliptiques : un torse est nettement plus large que
	# profond, une section ronde donnerait un bonhomme en tuyau. Il s'evase des
	# hanches aux epaules, ce qui est la silhouette d'un athlete.
	Atelier.tube(outil, _endroit_de_l_os(OS_BASSIN), _endroit_de_l_os(OS_TORSE),
		0.160 * epaisseur, 0.152 * epaisseur, 14, OS_BASSIN, OS_BASSIN,
		Atelier.ZONE_SHORT, 0.66)
	Atelier.tube(outil, _endroit_de_l_os(OS_TORSE), _endroit_de_l_os(OS_COU),
		0.152 * epaisseur, 0.205 * epaisseur, 14, OS_TORSE, OS_BASSIN,
		Atelier.ZONE_MAILLOT, 0.62)
	Atelier.tube(outil, _endroit_de_l_os(OS_COU), _endroit_de_l_os(OS_TETE),
		0.056, 0.050, 8, OS_COU, OS_TORSE, Atelier.ZONE_PEAU, 0.90)
	Visage.ajouter(outil, _endroit_de_l_os(OS_TETE), OS_TETE, traits)

	for cote in [1, -1]:
		var epaule := OS_EPAULE_G if cote > 0 else OS_EPAULE_D
		var coude := OS_COUDE_G if cote > 0 else OS_COUDE_D
		var main := OS_MAIN_G if cote > 0 else OS_MAIN_D
		# La manche couvre le haut du bras : c'est elle qui donne au joueur sa
		# silhouette de footballeur plutot que de nageur.
		Atelier.tube(outil, _endroit_de_l_os(epaule), _endroit_de_l_os(coude),
			0.054 * epaisseur, 0.041 * epaisseur, 8, epaule, OS_TORSE,
			Atelier.ZONE_MAILLOT)
		Atelier.tube(outil, _endroit_de_l_os(coude), _endroit_de_l_os(main),
			0.041 * epaisseur, 0.030, 8, coude, epaule, Atelier.ZONE_PEAU)
		_articulation(outil, _endroit_de_l_os(epaule), 0.066 * epaisseur, epaule,
			Atelier.ZONE_MAILLOT)
		_articulation(outil, _endroit_de_l_os(coude), 0.043 * epaisseur, coude,
			Atelier.ZONE_PEAU)
		# La main est allongee, pas ronde.
		Atelier.ellipsoide(outil, _endroit_de_l_os(main), Vector3(0.028, 0.045, 0.018),
			6, 4, main, Atelier.ZONE_PEAU)

	for cote in [1, -1]:
		var hanche := OS_HANCHE_G if cote > 0 else OS_HANCHE_D
		var genou := OS_GENOU_G if cote > 0 else OS_GENOU_D
		var cheville := OS_CHEVILLE_G if cote > 0 else OS_CHEVILLE_D
		var haut := _endroit_de_l_os(hanche)
		var milieu := _endroit_de_l_os(genou)
		var bas := _endroit_de_l_os(cheville)
		# Le short s'arrete a mi-cuisse et la chaussette monte sous le genou :
		# c'est ce decoupage qui fait lire une tenue de football.
		var mi_cuisse := haut.lerp(milieu, 0.45)
		var haut_chaussette := milieu.lerp(bas, 0.18)
		Atelier.tube(outil, haut, mi_cuisse, 0.092 * epaisseur, 0.078 * epaisseur,
			10, hanche, OS_BASSIN, Atelier.ZONE_SHORT)
		Atelier.tube(outil, mi_cuisse, milieu, 0.078 * epaisseur, 0.060 * epaisseur,
			10, hanche, hanche, Atelier.ZONE_PEAU)
		Atelier.tube(outil, milieu, haut_chaussette, 0.060 * epaisseur,
			0.058 * epaisseur, 10, genou, hanche, Atelier.ZONE_PEAU)
		Atelier.tube(outil, haut_chaussette, bas, 0.058 * epaisseur, 0.038, 10,
			genou, genou, Atelier.ZONE_CHAUSSETTES)
		_articulation(outil, milieu, 0.062 * epaisseur, genou, Atelier.ZONE_PEAU)
		_chaussure(outil, bas, cheville)

	outil.generate_normals()
	outil.generate_tangents()
	return outil.commit()

## Boule posee sur une articulation, pour que le coude ou le genou reste plein
## quand il se plie.
func _articulation(outil: SurfaceTool, centre: Vector3, rayon: float,
		os: int, zone: float) -> void:
	Atelier.ellipsoide(outil, centre, Vector3(rayon, rayon, rayon), 8, 5, os, zone)

## Chaussure : un bloc allonge vers l'avant, pose au sol.
func _chaussure(outil: SurfaceTool, cheville: Vector3, os: int) -> void:
	var hauteur := 0.062
	var repere := Transform3D(Basis(),
		cheville + Vector3(0.0, -HAUTEUR_CHEVILLE + hauteur * 0.5, 0.045))
	Atelier.boite(outil, repere, Vector3(0.050, hauteur * 0.5, 0.130),
		os, Atelier.ZONE_CHAUSSURES)

# --- Habillage --------------------------------------------------------------

## Applique un nuancier. Les couleurs passent par des parametres propres a
## l'instance : deux joueurs partagent ainsi le meme materiau tout en portant
## des tenues, des teints et des cheveux differents.
func _appliquer_la_tenue(tenue: Dictionary) -> void:
	var reglages := {
		"couleur_peau": tenue.get("peau", Color(0.72, 0.55, 0.42)),
		"couleur_maillot": tenue.get("maillot", Color(0.85, 0.16, 0.18)),
		"couleur_maillot_secondaire": tenue.get("maillot_secondaire", Color(1, 1, 1)),
		"couleur_short": tenue.get("short", Color(0.12, 0.12, 0.14)),
		"couleur_chaussettes": tenue.get("chaussettes", Color(0.85, 0.16, 0.18)),
		"couleur_chaussures": tenue.get("chaussures", Color(0.08, 0.08, 0.09)),
		"couleur_cheveux": tenue.get("cheveux", Color(0.12, 0.09, 0.07)),
		"couleur_iris": tenue.get("iris", Color(0.28, 0.19, 0.12)),
		"motif": float(tenue.get("motif", 0)),
	}
	for nom in reglages:
		maillage.set_instance_shader_parameter(nom, reglages[nom])

## Oriente un os. Utilise par l'animation, image par image.
func poser_os(index: int, rotation: Quaternion) -> void:
	squelette.set_bone_pose_rotation(index, rotation)
