extends Node3D

## Scene principale : elle relie la simulation (qui ne sait rien de l'image) au
## rendu (qui ne decide rien du jeu).
##
## Le point important est la boucle a pas fixe. Le telephone n'affiche pas
## toujours a 60 images par seconde : il peut tomber a 45 puis remonter. Si la
## simulation avancait du temps ecoule reel, la physique du ballon changerait
## avec la charge de la machine, et deux appareils ne verraient pas le meme
## match. On accumule donc le temps et on avance par pas de 1/60 s exactement,
## quitte a en faire deux dans la meme image ou aucun.

const PAS_MAXI_PAR_IMAGE := 5   # garde-fou : au-dela, on laisse filer le temps
const JOUEURS_PAR_EQUIPE := 11

var _simulation: Simulation
var _manette: Manette
var _terrain: Terrain
var _ambiance: Ambiance
var _camera: Camera3D
var _ballon_visuel: MeshInstance3D
var _tableau: Label

## Silhouettes des vingt-deux joueurs, rangees equipe par equipe.
var _silhouettes: Array[Node3D] = []
## Anneau pose sous les pieds du joueur pilote.
var _repere: MeshInstance3D

var _accumulateur := 0.0
# Etat de l'image precedente, pour interpoler l'affichage entre deux pas de
# simulation : sans cela tout avancerait par saccades des que l'ecran rafraichit
# plus vite que la simulation.
var _ballon_precedent := Vector3.ZERO
var _positions_precedentes: PackedVector3Array = PackedVector3Array()
var _orientation_ballon := Basis.IDENTITY
var _camera_libre := false

func _ready() -> void:
	_simulation = Simulation.new(2026)
	_ballon_precedent = _simulation.ballon.position

	_ambiance = Ambiance.new()
	add_child(_ambiance)

	_terrain = Terrain.new()
	add_child(_terrain)

	_ballon_visuel = _construire_ballon()
	add_child(_ballon_visuel)

	_repere = _construire_repere()
	add_child(_repere)

	_construire_les_joueurs()

	_camera = Camera3D.new()
	_camera.fov = 46.0
	_camera.far = 400.0
	add_child(_camera)
	_placer_camera(1.0)

	var interface := CanvasLayer.new()
	add_child(interface)
	_manette = Manette.new()
	interface.add_child(_manette)
	_tableau = _construire_tableau()
	interface.add_child(_tableau)
	interface.add_child(Compteur.new())

func _process(delta: float) -> void:
	_accumulateur += delta
	var pas_effectues := 0
	while _accumulateur >= Simulation.PAS and pas_effectues < PAS_MAXI_PAR_IMAGE:
		_memoriser_positions()
		_simulation.simuler(_commandes_de_l_image())
		_accumulateur -= Simulation.PAS
		pas_effectues += 1
	if pas_effectues == PAS_MAXI_PAR_IMAGE:
		# L'appareil ne suit plus : on abandonne le retard plutot que de
		# s'enfoncer en simulant toujours plus a chaque image.
		_accumulateur = 0.0

	_afficher(clampf(_accumulateur / Simulation.PAS, 0.0, 1.0), delta)

## Traduit les commandes de la manette du repere de l'ecran vers celui du
## terrain.
##
## La manette ne connait que des pouces et des pixels ; la simulation ne connait
## que des metres. Faire la conversion ici, avant de fabriquer l'objet
## Commandes, est essentiel : ce qui part dans un replay ou sur le reseau est
## alors une direction de terrain, independante de la camera utilisee au moment
## du match. Si on enregistrait la direction de l'ecran, rejouer le meme fichier
## avec une autre camera donnerait un match different.
func _commandes_de_l_image() -> Commandes:
	# Les boutons proposes dependent de qui tient le ballon : frapper et passer
	# quand on l'a, tacler et presser quand on ne l'a pas.
	_manette.avec_ballon = _simulation.porteur.x == _simulation.equipe_humaine
	var commandes := _manette.lire()
	var avant := -_camera.global_transform.basis.z
	var droite := _camera.global_transform.basis.x
	avant.y = 0.0
	droite.y = 0.0
	if avant.length_squared() < 0.0001 or droite.length_squared() < 0.0001:
		return commandes
	avant = avant.normalized()
	droite = droite.normalized()
	# L'axe vertical de l'ecran descend : pousser le pouce vers le haut doit
	# envoyer le joueur vers le fond du terrain, d'ou le signe negatif.
	var monde := avant * (-commandes.direction.y) + droite * commandes.direction.x
	commandes.direction = Vector2(monde.x, monde.z)
	return commandes

func _memoriser_positions() -> void:
	_ballon_precedent = _simulation.ballon.position
	var index := 0
	for equipe in _simulation.equipes:
		for joueur in equipe.joueurs:
			_positions_precedentes[index] = joueur.position
			index += 1

func _afficher(avancement: float, delta: float) -> void:
	_ballon_visuel.position = _ballon_precedent.lerp(_simulation.ballon.position, avancement)
	_faire_rouler_ballon(delta)

	var index := 0
	for equipe in _simulation.equipes:
		for joueur in equipe.joueurs:
			var silhouette := _silhouettes[index]
			silhouette.position = _positions_precedentes[index].lerp(joueur.position, avancement)
			# Rotation amortie : un joueur qui pivote d'un bloc a chaque image
			# donne une impression de pantin.
			var voulue := joueur.orientation
			silhouette.rotation.y = lerp_angle(silhouette.rotation.y, voulue, 1.0 - pow(0.001, delta))
			index += 1

	var pilote := _silhouettes[_simulation.equipe_humaine * JOUEURS_PAR_EQUIPE
		+ _simulation.joueur_actif]
	_repere.position = Vector3(pilote.position.x, 0.02, pilote.position.z)

	_mettre_a_jour_le_tableau()
	_placer_camera(delta)

func _mettre_a_jour_le_tableau() -> void:
	var etat := _simulation.etat
	var secondes := int(etat.secondes())
	_tableau.text = "%s  %d - %d  %s      %02d:%02d" % [
		_simulation.equipes[0].nom.substr(0, 3).to_upper(),
		etat.buts_domicile, etat.buts_exterieur,
		_simulation.equipes[1].nom.substr(0, 3).to_upper(),
		secondes / 60, secondes % 60]

## Fait tourner le ballon selon son deplacement. C'est purement visuel : la
## simulation, elle, traite le ballon comme un point et n'a pas besoin de savoir
## comment il est oriente.
func _faire_rouler_ballon(delta: float) -> void:
	var au_sol := Vector3(_simulation.ballon.vitesse.x, 0.0, _simulation.ballon.vitesse.z)
	var allure := au_sol.length()
	if allure > 0.05:
		var axe := Vector3.UP.cross(au_sol).normalized()
		_orientation_ballon = Basis(axe, allure / Ballon.RAYON * delta) * _orientation_ballon
	var effet := _simulation.ballon.rotation.y
	if absf(effet) > 0.01:
		_orientation_ballon = Basis(Vector3.UP, effet * delta) * _orientation_ballon
	_orientation_ballon = _orientation_ballon.orthonormalized()
	_ballon_visuel.basis = _orientation_ballon

## Fige la camera a un endroit precis et coupe le suivi automatique. Utilise par
## les captures de controle, et base de la camera libre des replays.
func fixer_camera(endroit: Vector3, cible: Vector3) -> void:
	_camera_libre = true
	_camera.position = endroit
	_camera.look_at(cible, Vector3.UP)

## Camera « large », celle des retransmissions : placee sur le cote, en hauteur,
## elle suit le ballon sans jamais le coller, ce qui laisse voir le jeu qui se
## construit autour.
##
## Le compromis de hauteur est le nerf de l'affaire. Trop bas, on ne voit que
## l'avant-plan et les appels dans le dos echappent au joueur ; trop haut, les
## joueurs deviennent des pastilles et le match perd toute presence. Quinze
## metres a une trentaine de metres du bord donnent environ cinquante metres de
## terrain lisibles, ce qui couvre une action complete.
func _placer_camera(delta: float) -> void:
	if _camera_libre:
		return
	var ballon := _simulation.ballon.position
	var vise_x := clampf(ballon.x * 0.78, -Dimensions.DEMI_LONGUEUR, Dimensions.DEMI_LONGUEUR)
	var souhaitee := Vector3(vise_x, 15.0, ballon.z * 0.22 - Dimensions.DEMI_LARGEUR - 4.0)
	var regard := Vector3(ballon.x * 0.96, 1.1, ballon.z * 0.55)

	# Suivi amorti : la camera rattrape une fraction de son retard par seconde,
	# ce qui donne un mouvement souple et independant du nombre d'images.
	_camera.position = _camera.position.lerp(souhaitee, 1.0 - pow(0.0015, delta))
	if _camera.position.distance_squared_to(regard) > 0.01:
		_camera.look_at(regard, Vector3.UP)

# --- Construction de la scene ----------------------------------------------

func _construire_ballon() -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = Ballon.RAYON
	sphere.height = Ballon.RAYON * 2.0
	# 24 x 12 : la silhouette est deja ronde a l'ecran, et le ballon n'occupe
	# jamais plus de quelques dizaines de pixels pendant le jeu.
	sphere.radial_segments = 24
	sphere.rings = 12

	var matiere := ShaderMaterial.new()
	matiere.shader = load("res://src/rendu/ballon.gdshader")

	var visuel := MeshInstance3D.new()
	visuel.name = "Ballon"
	visuel.mesh = sphere
	visuel.material_override = matiere
	return visuel

func _construire_les_joueurs() -> void:
	# Deux jeux de couleurs bien separes : a quinze metres de hauteur, il faut
	# distinguer les camps d'un coup d'oeil, sans lire les numeros.
	var tenues := [
		{"maillot": Color(0.82, 0.14, 0.16), "short": Color(0.12, 0.12, 0.14),
			"gardien": Color(0.20, 0.68, 0.32)},
		{"maillot": Color(0.94, 0.94, 0.95), "short": Color(0.16, 0.24, 0.55),
			"gardien": Color(0.92, 0.72, 0.12)},
	]

	_positions_precedentes.resize(_simulation.equipes.size() * JOUEURS_PAR_EQUIPE)
	var index := 0
	for numero_equipe in _simulation.equipes.size():
		var equipe := _simulation.equipes[numero_equipe]
		var tenue: Dictionary = tenues[numero_equipe % tenues.size()]
		for joueur in equipe.joueurs:
			var couleur: Color = tenue["gardien"] if Postes.est_gardien(joueur.poste) \
				else tenue["maillot"]
			var silhouette := _construire_silhouette(couleur, tenue["short"])
			silhouette.name = "%s_%s%d" % [equipe.nom,
				Postes.abreviation(joueur.poste), joueur.numero]
			silhouette.position = joueur.position
			add_child(silhouette)
			_silhouettes.append(silhouette)
			_positions_precedentes[index] = joueur.position
			index += 1

## Silhouette provisoire d'un joueur : un tronc, des jambes et une tete, juste
## de quoi juger l'echelle et la lisibilite a distance de camera. Les corps et
## les visages fabriques par le code arrivent en phase 3.
func _construire_silhouette(couleur_maillot: Color, couleur_short: Color) -> Node3D:
	var groupe := Node3D.new()

	var maillot := StandardMaterial3D.new()
	maillot.albedo_color = couleur_maillot
	maillot.roughness = 0.85

	var short := StandardMaterial3D.new()
	short.albedo_color = couleur_short
	short.roughness = 0.85

	var peau := StandardMaterial3D.new()
	peau.albedo_color = Color(0.72, 0.55, 0.42)
	peau.roughness = 0.7

	var tronc := MeshInstance3D.new()
	var buste := CapsuleMesh.new()
	buste.radius = 0.22
	buste.height = 0.86
	buste.radial_segments = 10
	buste.rings = 3
	tronc.mesh = buste
	tronc.material_override = maillot
	tronc.position = Vector3(0.0, 1.12, 0.0)
	groupe.add_child(tronc)

	var jambes := MeshInstance3D.new()
	var bas := CapsuleMesh.new()
	bas.radius = 0.19
	bas.height = 0.86
	bas.radial_segments = 8
	bas.rings = 2
	jambes.mesh = bas
	jambes.material_override = short
	jambes.position = Vector3(0.0, 0.44, 0.0)
	groupe.add_child(jambes)

	var tete := MeshInstance3D.new()
	var boule := SphereMesh.new()
	boule.radius = 0.115
	boule.height = 0.25
	boule.radial_segments = 10
	boule.rings = 5
	tete.mesh = boule
	tete.material_override = peau
	tete.position = Vector3(0.0, 1.66, 0.0)
	groupe.add_child(tete)

	return groupe

## Anneau pose au sol sous le joueur pilote. Sans ce repere, on perd sans cesse
## de vue lequel des onze on dirige.
func _construire_repere() -> MeshInstance3D:
	var anneau := TorusMesh.new()
	anneau.inner_radius = 0.42
	anneau.outer_radius = 0.52
	anneau.rings = 24
	anneau.ring_segments = 6

	var matiere := StandardMaterial3D.new()
	matiere.albedo_color = Color(1.0, 0.95, 0.45)
	# Sans eclairage, l'anneau garde la meme lisibilite le soir comme en plein
	# soleil, et ne coute rien a calculer.
	matiere.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	matiere.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	matiere.albedo_color.a = 0.75

	var visuel := MeshInstance3D.new()
	visuel.name = "RepereJoueurPilote"
	visuel.mesh = anneau
	visuel.material_override = matiere
	visuel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visuel

func _construire_tableau() -> Label:
	var etiquette := Label.new()
	etiquette.set_anchors_preset(Control.PRESET_CENTER_TOP)
	etiquette.position = Vector2(-160.0, 14.0)
	etiquette.custom_minimum_size = Vector2(320.0, 0.0)
	etiquette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiquette.add_theme_font_size_override("font_size", 26)
	etiquette.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	etiquette.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	etiquette.add_theme_constant_override("outline_size", 6)
	etiquette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return etiquette
