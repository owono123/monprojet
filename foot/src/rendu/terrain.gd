class_name Terrain
extends Node3D

## Construit la pelouse et les buts par le code, a partir des dimensions
## reglementaires. Rien n'est importe : ni modele, ni texture. C'est ce qui
## permet de developper sans jamais ouvrir l'editeur Godot, et ce qui garantit
## que le trace du terrain est exact au centimetre plutot que dessine a l'oeil.

const CHEMIN_SHADER_PELOUSE := "res://src/rendu/terrain.gdshader"
const CHEMIN_SHADER_FILET := "res://src/rendu/filet.gdshader"

var _pelouse: MeshInstance3D

func _ready() -> void:
	_construire_pourtour()
	_construire_pelouse()
	for camp in [-1, 1]:
		_construire_but(camp)

## Regle l'aspect mouille de la pelouse (0 = sec, 1 = sous la pluie).
func regler_humidite(valeur: float) -> void:
	if _pelouse == null:
		return
	var matiere := _pelouse.material_override as ShaderMaterial
	if matiere != null:
		matiere.set_shader_parameter("humidite", clampf(valeur, 0.0, 1.0))

## Grande surface sombre sous la pelouse.
##
## Sans elle, le monde s'arrete net au bord du gazon et l'on voit le vide du
## ciel a l'horizon — le defaut le plus visible d'une scene sans stade. Un seul
## quadrilatere y suffit ; le stade proprement dit arrive en phase 3 et prendra
## sa place.
func _construire_pourtour() -> void:
	var plan := PlaneMesh.new()
	plan.size = Vector2(600.0, 600.0)

	var matiere := StandardMaterial3D.new()
	matiere.albedo_color = Color(0.085, 0.098, 0.092)
	matiere.roughness = 0.95
	matiere.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var pourtour := MeshInstance3D.new()
	pourtour.name = "Pourtour"
	pourtour.mesh = plan
	pourtour.material_override = matiere
	pourtour.position.y = -0.05
	pourtour.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pourtour)

func _construire_pelouse() -> void:
	var plan := PlaneMesh.new()
	plan.size = Vector2(
		Dimensions.LONGUEUR + Dimensions.MARGE_PELOUSE * 2.0,
		Dimensions.LARGEUR + Dimensions.MARGE_PELOUSE * 2.0)
	# Une seule subdivision suffit : l'eclairage est calcule par pixel, decouper
	# le sol en milliers de triangles ne changerait rien a l'image et couterait
	# du temps de sommet sur un Mali-G71.
	plan.subdivide_width = 1
	plan.subdivide_depth = 1

	var matiere := ShaderMaterial.new()
	matiere.shader = load(CHEMIN_SHADER_PELOUSE)
	matiere.set_shader_parameter("demi_longueur", Dimensions.DEMI_LONGUEUR)
	matiere.set_shader_parameter("demi_largeur", Dimensions.DEMI_LARGEUR)
	matiere.set_shader_parameter("largeur_trace", Dimensions.LARGEUR_TRACE)
	matiere.set_shader_parameter("rayon_rond_central", Dimensions.RAYON_ROND_CENTRAL)
	matiere.set_shader_parameter("surface_profondeur", Dimensions.SURFACE_REPARATION_PROFONDEUR)
	matiere.set_shader_parameter("surface_demi_largeur", Dimensions.SURFACE_REPARATION_DEMI_LARGEUR)
	matiere.set_shader_parameter("but_profondeur", Dimensions.SURFACE_BUT_PROFONDEUR)
	matiere.set_shader_parameter("but_demi_largeur", Dimensions.SURFACE_BUT_DEMI_LARGEUR)
	matiere.set_shader_parameter("point_penalty", Dimensions.POINT_PENALTY)
	matiere.set_shader_parameter("rayon_corner", Dimensions.RAYON_CORNER)

	_pelouse = MeshInstance3D.new()
	_pelouse.name = "Pelouse"
	_pelouse.mesh = plan
	_pelouse.material_override = matiere
	_pelouse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pelouse)

func _construire_but(camp: int) -> void:
	var x := float(signi(camp)) * Dimensions.DEMI_LONGUEUR
	var vers_exterieur := float(signi(camp))
	var groupe := Node3D.new()
	groupe.name = "But%s" % ("Droit" if camp > 0 else "Gauche")
	add_child(groupe)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.95, 0.95, 0.96)
	metal.roughness = 0.35
	metal.metallic = 0.1

	# Poteaux. Ils sont poses sur la ligne de but, pas devant : la ligne passe
	# par leur centre, c'est ce qui decide si un ballon est entre ou non.
	for cote in [-1.0, 1.0]:
		var poteau := MeshInstance3D.new()
		var cylindre := CylinderMesh.new()
		cylindre.top_radius = Dimensions.POTEAU_RAYON
		cylindre.bottom_radius = Dimensions.POTEAU_RAYON
		cylindre.height = Dimensions.BUT_HAUTEUR
		cylindre.radial_segments = 10
		cylindre.rings = 1
		poteau.mesh = cylindre
		poteau.material_override = metal
		poteau.position = Vector3(x, Dimensions.BUT_HAUTEUR * 0.5,
			cote * Dimensions.BUT_DEMI_LARGEUR)
		groupe.add_child(poteau)

	# Barre transversale.
	var barre := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = Dimensions.POTEAU_RAYON
	tube.bottom_radius = Dimensions.POTEAU_RAYON
	tube.height = Dimensions.BUT_DEMI_LARGEUR * 2.0
	tube.radial_segments = 10
	tube.rings = 1
	barre.mesh = tube
	barre.material_override = metal
	barre.position = Vector3(x, Dimensions.BUT_HAUTEUR, 0.0)
	barre.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	groupe.add_child(barre)

	groupe.add_child(_construire_filet(x, vers_exterieur))

func _construire_filet(x: float, vers_exterieur: float) -> MeshInstance3D:
	var demi := Dimensions.BUT_DEMI_LARGEUR
	var haut := Dimensions.BUT_HAUTEUR
	var fond := x + vers_exterieur * Dimensions.BUT_PROFONDEUR

	var outil := SurfaceTool.new()
	outil.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Panneau du fond.
	_ajouter_quadrilatere(outil,
		Vector3(fond, 0.0, -demi), Vector3(fond, 0.0, demi),
		Vector3(fond, haut, demi), Vector3(fond, haut, -demi),
		Vector2(demi * 2.0, haut))
	# Les deux cotes.
	for cote in [-1.0, 1.0]:
		_ajouter_quadrilatere(outil,
			Vector3(x, 0.0, cote * demi), Vector3(fond, 0.0, cote * demi),
			Vector3(fond, haut, cote * demi), Vector3(x, haut, cote * demi),
			Vector2(Dimensions.BUT_PROFONDEUR, haut))
	# Le toit.
	_ajouter_quadrilatere(outil,
		Vector3(x, haut, -demi), Vector3(fond, haut, -demi),
		Vector3(fond, haut, demi), Vector3(x, haut, demi),
		Vector2(Dimensions.BUT_PROFONDEUR, demi * 2.0))

	outil.generate_normals()

	var matiere := ShaderMaterial.new()
	matiere.shader = load(CHEMIN_SHADER_FILET)

	var filet := MeshInstance3D.new()
	filet.name = "Filet"
	filet.mesh = outil.commit()
	filet.material_override = matiere
	filet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return filet

## Ajoute un quadrilatere en deux triangles. L'UV porte des metres, pour que la
## maille du filet garde la meme taille sur tous les pans.
func _ajouter_quadrilatere(outil: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, etendue: Vector2) -> void:
	var uv_a := Vector2(0.0, 0.0)
	var uv_b := Vector2(etendue.x, 0.0)
	var uv_c := Vector2(etendue.x, etendue.y)
	var uv_d := Vector2(0.0, etendue.y)
	for sommet in [[a, uv_a], [b, uv_b], [c, uv_c], [a, uv_a], [c, uv_c], [d, uv_d]]:
		outil.set_uv(sommet[1])
		outil.add_vertex(sommet[0])
