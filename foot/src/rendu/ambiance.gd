class_name Ambiance
extends Node3D

## Ciel, soleil et reglages d'image.
##
## Isole dans son propre fichier parce que c'est ici qu'arriveront la meteo et
## l'heure de la rencontre (jour, soir, nuit sous les projecteurs) : autant que
## le reste du rendu n'ait jamais a savoir comment la lumiere est fabriquee.

var soleil: DirectionalLight3D
var environnement: WorldEnvironment

func _ready() -> void:
	_construire_ciel()
	_construire_soleil()

func _construire_ciel() -> void:
	var ciel_materiau := ProceduralSkyMaterial.new()
	ciel_materiau.sky_top_color = Color(0.30, 0.50, 0.78)
	ciel_materiau.sky_horizon_color = Color(0.72, 0.80, 0.88)
	# Le sol du ciel est accorde au pourtour sombre construit par Terrain :
	# sans cela, une bande grise franche apparait a l'horizon.
	ciel_materiau.ground_bottom_color = Color(0.075, 0.085, 0.082)
	ciel_materiau.ground_horizon_color = Color(0.30, 0.36, 0.38)
	ciel_materiau.ground_curve = 0.04
	ciel_materiau.sun_angle_max = 6.0
	ciel_materiau.sun_curve = 0.12

	var ciel := Sky.new()
	ciel.sky_material = ciel_materiau

	var reglages := Environment.new()
	reglages.background_mode = Environment.BG_SKY
	reglages.sky = ciel
	# La lumiere ambiante vient du ciel : sans elle, tout ce qui est a l'ombre
	# du soleil serait parfaitement noir.
	reglages.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	reglages.ambient_light_sky_contribution = 1.0
	reglages.ambient_light_energy = 1.0
	reglages.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	reglages.tonemap_white = 4.0
	# Ni occlusion ambiante ni reflexions : le moteur de rendu compatible ne les
	# propose pas, et sur Vulkan mobile elles couteraient les 60 images par
	# seconde. L'ombrage vient des ombres portees et de l'ambiante du ciel.

	environnement = WorldEnvironment.new()
	environnement.name = "Environnement"
	environnement.environment = reglages
	add_child(environnement)

func _construire_soleil() -> void:
	soleil = DirectionalLight3D.new()
	soleil.name = "Soleil"
	# Soleil de fin d'apres-midi : l'ombre allongee des joueurs donne bien plus
	# de relief a l'image qu'une lumiere au zenith.
	soleil.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	soleil.light_energy = 1.35
	soleil.light_color = Color(1.0, 0.96, 0.89)
	soleil.shadow_enabled = true
	soleil.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# Une seule cascade d'ombre, resserree autour de l'action : quatre cascades
	# couteraient quatre rendus de la scene depuis le soleil.
	soleil.directional_shadow_max_distance = 70.0
	soleil.shadow_bias = 0.04
	soleil.shadow_normal_bias = 1.2
	add_child(soleil)

## Regle l'heure de la rencontre. Provisoire : la phase 3 y ajoutera les
## projecteurs et les vraies ambiances de nuit.
func regler_heure(fraction_du_jour: float) -> void:
	var hauteur := lerpf(12.0, 62.0, clampf(fraction_du_jour, 0.0, 1.0))
	soleil.rotation_degrees.x = -hauteur
