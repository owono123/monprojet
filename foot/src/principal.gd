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

var _simulation: Simulation
var _manette: Manette
var _terrain: Terrain
var _ambiance: Ambiance
var _camera: Camera3D
var _ballon_visuel: MeshInstance3D
var _joueur_visuel: Node3D

var _accumulateur := 0.0
# Etat de l'image precedente, pour interpoler l'affichage entre deux pas de
# simulation : sans cela le ballon avancerait par saccades des que l'ecran
# rafraichit plus vite que la simulation.
var _ballon_precedent := Vector3.ZERO
var _joueur_precedent := Vector3.ZERO
var _orientation_ballon := Basis.IDENTITY
var _camera_libre := false

func _ready() -> void:
	_simulation = Simulation.new(2026)
	_ballon_precedent = _simulation.ballon.position
	_joueur_precedent = _simulation.etat.joueur_position

	_ambiance = Ambiance.new()
	add_child(_ambiance)

	_terrain = Terrain.new()
	add_child(_terrain)

	_ballon_visuel = _construire_ballon()
	add_child(_ballon_visuel)

	_joueur_visuel = _construire_joueur()
	add_child(_joueur_visuel)

	_camera = Camera3D.new()
	_camera.fov = 46.0
	_camera.far = 400.0
	add_child(_camera)
	_placer_camera(1.0)

	var interface := CanvasLayer.new()
	add_child(interface)
	_manette = Manette.new()
	interface.add_child(_manette)
	interface.add_child(Compteur.new())

func _process(delta: float) -> void:
	_accumulateur += delta
	var pas_effectues := 0
	while _accumulateur >= Simulation.PAS and pas_effectues < PAS_MAXI_PAR_IMAGE:
		_ballon_precedent = _simulation.ballon.position
		_joueur_precedent = _simulation.etat.joueur_position
		_simulation.simuler(_manette.lire())
		_accumulateur -= Simulation.PAS
		pas_effectues += 1
	if pas_effectues == PAS_MAXI_PAR_IMAGE:
		# L'appareil ne suit plus : on abandonne le retard plutot que de
		# s'enfoncer en simulant toujours plus a chaque image.
		_accumulateur = 0.0

	var avancement := clampf(_accumulateur / Simulation.PAS, 0.0, 1.0)
	_afficher(avancement, delta)

func _afficher(avancement: float, delta: float) -> void:
	var position_ballon := _ballon_precedent.lerp(_simulation.ballon.position, avancement)
	_ballon_visuel.position = position_ballon
	_faire_rouler_ballon(delta)

	var position_joueur := _joueur_precedent.lerp(_simulation.etat.joueur_position, avancement)
	_joueur_visuel.position = position_joueur
	var allure := _simulation.etat.joueur_vitesse
	if allure.length_squared() > 0.25:
		_joueur_visuel.rotation.y = atan2(allure.x, allure.z)

	_placer_camera(delta)

## Fait tourner le ballon selon son deplacement. C'est purement visuel : la
## simulation, elle, traite le ballon comme un point et n'a pas besoin de savoir
## comment il est oriente.
func _faire_rouler_ballon(delta: float) -> void:
	var vitesse := _simulation.ballon.vitesse
	var au_sol := Vector3(vitesse.x, 0.0, vitesse.z)
	var allure := au_sol.length()
	if allure > 0.05:
		var axe := Vector3.UP.cross(au_sol).normalized()
		_orientation_ballon = Basis(axe, allure / Ballon.RAYON * delta) * _orientation_ballon
	# Effet : rotation propre autour de la verticale.
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
	var douceur := 1.0 - pow(0.0015, delta)
	_camera.position = _camera.position.lerp(souhaitee, douceur)
	if _camera.position.distance_squared_to(regard) > 0.01:
		_camera.look_at(regard, Vector3.UP)

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

## Silhouette provisoire du joueur : une capsule et une tete, juste de quoi
## juger l'echelle et la lisibilite a distance de camera. Les corps et les
## visages fabriques par le code arrivent en phase 3.
func _construire_joueur() -> Node3D:
	var groupe := Node3D.new()
	groupe.name = "JoueurPilote"

	var maillot := StandardMaterial3D.new()
	maillot.albedo_color = Color(0.85, 0.16, 0.18)
	maillot.roughness = 0.85

	var peau := StandardMaterial3D.new()
	peau.albedo_color = Color(0.72, 0.55, 0.42)
	peau.roughness = 0.7

	var corps := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.26
	capsule.height = 1.42
	capsule.radial_segments = 12
	capsule.rings = 4
	corps.mesh = capsule
	corps.material_override = maillot
	corps.position = Vector3(0.0, 0.71, 0.0)
	groupe.add_child(corps)

	var tete := MeshInstance3D.new()
	var boule := SphereMesh.new()
	boule.radius = 0.115
	boule.height = 0.25
	boule.radial_segments = 12
	boule.rings = 6
	tete.mesh = boule
	tete.material_override = peau
	tete.position = Vector3(0.0, 1.56, 0.0)
	groupe.add_child(tete)

	return groupe
