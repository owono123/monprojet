extends Node

## Rend plusieurs vues de la scene principale et les enregistre en PNG.
##
## Sert a verifier l'image sans telephone ni ecran : Godot tourne ici sur un
## rendu logiciel. C'est ce qui permet de relire le tracage du terrain et la
## geometrie des buts avant de compiler un APK, plutot que de decouvrir un
## defaut une demi-heure plus tard sur le telephone.

## Le temps que les shaders soient compiles et que la camera de jeu se pose.
const IMAGES_DE_CHAUFFE := 40
const IMAGES_ENTRE_VUES := 3

## Chaque vue : nom du fichier, position de la camera, point vise.
## Une position nulle laisse la camera de jeu faire son travail.
var _vues := [
	["01_camera_de_jeu", null, null],
	["02_but", Vector3(34.0, 7.0, -24.0), Vector3(52.5, 1.0, 0.0)],
	["03_vue_entiere", Vector3(0.0, 64.0, -48.0), Vector3(0.0, 0.0, 0.0)],
	["04_rond_central", Vector3(-5.0, 2.0, -11.0), Vector3(0.0, 0.3, 0.0)],
]

## Vues rapprochees, visant un joueur precis plutot qu'un point du terrain :
## les joueurs bougent des le coup d'envoi, viser le rond central donnerait une
## image ou il n'y a personne. Chaque entree vaut [nom, equipe, rang, recul,
## hauteur de camera, hauteur visee].
var _gros_plans := [
	["05_joueur_en_pied", 0, 9, 3.6, 1.15, 0.95],
	["06_buste", 0, 9, 1.5, 1.58, 1.48],
	["07_gardien", 1, 0, 3.2, 1.20, 1.00],
	# Un visage ne se juge qu'a un demi-metre. C'est la distance des replays,
	# des celebrations et de l'editeur — la seule ou le travail se voit.
	["08_visage", 0, 9, 0.55, 1.66, 1.62],
	["09_visage_bis", 0, 4, 0.55, 1.66, 1.62],
	["10_visage_ter", 1, 7, 0.55, 1.66, 1.62],
]

var _dossier := "res://captures"
var _jeu: Node

func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() > 0:
		_dossier = arguments[0]
	DirAccess.make_dir_recursive_absolute(_dossier)
	_jeu = load("res://src/principal.tscn").instantiate()
	add_child(_jeu)
	_capturer_toutes_les_vues()

func _capturer_toutes_les_vues() -> void:
	await _patienter(IMAGES_DE_CHAUFFE)
	for vue in _vues:
		if vue[1] != null:
			_jeu.fixer_camera(vue[1], vue[2])
			await _patienter(IMAGES_ENTRE_VUES)
		if not await _enregistrer(vue[0]):
			return

	for plan in _gros_plans:
		var cible: Vector3 = _jeu.position_du_joueur(plan[1], plan[2])
		# On se place de biais plutot que de face : un profil de trois quarts
		# montre a la fois le visage et la silhouette.
		var recul: float = plan[3]
		var endroit := cible + Vector3(recul * 0.82, plan[4], recul * 0.58)
		_jeu.fixer_camera(endroit, cible + Vector3(0.0, plan[5], 0.0))
		await _patienter(IMAGES_ENTRE_VUES)
		if not await _enregistrer(plan[0]):
			return

	get_tree().quit(0)

func _enregistrer(nom: String) -> bool:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var chemin := "%s/%s.png" % [_dossier, nom]
	if image.save_png(chemin) != OK:
		printerr("Echec de l'enregistrement de %s" % chemin)
		get_tree().quit(1)
		return false
	print("Capture : %s" % chemin)
	return true

func _patienter(images: int) -> void:
	for _i in images:
		await get_tree().process_frame
