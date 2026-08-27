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
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var chemin := "%s/%s.png" % [_dossier, vue[0]]
		if image.save_png(chemin) != OK:
			printerr("Echec de l'enregistrement de %s" % chemin)
			get_tree().quit(1)
			return
		print("Capture : %s" % chemin)
	get_tree().quit(0)

func _patienter(images: int) -> void:
	for _i in images:
		await get_tree().process_frame
