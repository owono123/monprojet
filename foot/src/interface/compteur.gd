class_name Compteur
extends Control

## Compteur d'images par seconde et fiche technique du rendu.
##
## Ce n'est pas un outil de mise au point accessoire : c'est le seul moyen de
## savoir si le jeu tient ses 60 images par seconde sur l'appareil vise, et
## lequel des deux moteurs de rendu tourne reellement (Vulkan quand le pilote
## suit, OpenGL ES en repli). Il affiche aussi le minimum sur la derniere
## minute, parce qu'un telephone donne toujours de beaux chiffres a froid et
## ralentit apres dix minutes de jeu : c'est ce minimum-la qui compte.

const FENETRE_MINIMUM := 60.0   # secondes sur lesquelles on retient le pire cas

var _fiche_technique := ""
var _historique: Array[float] = []
var _horodatages: Array[float] = []
var _depuis_le_lancement := 0.0
var _minimum_absolu := 9999.0
var _etiquette: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_etiquette = Label.new()
	_etiquette.position = Vector2(18.0, 12.0)
	_etiquette.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_etiquette.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_etiquette.add_theme_constant_override("outline_size", 5)
	_etiquette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_etiquette)

	_relever_fiche_technique()

func _relever_fiche_technique() -> void:
	# Le moteur reellement utilise, pas celui demande dans les reglages : si le
	# pilote Vulkan du telephone est refuse, Godot bascule sur OpenGL et c'est
	# cette ligne qui le revele.
	var methode := RenderingServer.get_current_rendering_method()
	var pilote := RenderingServer.get_current_rendering_driver_name()
	var carte := RenderingServer.get_video_adapter_name()
	var version := RenderingServer.get_video_adapter_api_version()
	var ecran := DisplayServer.window_get_size()
	var echelle: float = ProjectSettings.get_setting("rendering/scaling_3d/scale", 1.0)
	_fiche_technique = "%s / %s\n%s\n%s\n%d x %d, rendu 3D a %d%%" % [
		methode, pilote, carte, version, ecran.x, ecran.y, int(round(echelle * 100.0))]

func _process(delta: float) -> void:
	_depuis_le_lancement += delta
	var actuel := float(Engine.get_frames_per_second())

	_historique.append(actuel)
	_horodatages.append(_depuis_le_lancement)
	while _horodatages.size() > 0 and _horodatages[0] < _depuis_le_lancement - FENETRE_MINIMUM:
		_horodatages.remove_at(0)
		_historique.remove_at(0)

	# Les toutes premieres images comptent la compilation des shaders : les
	# retenir comme minimum donnerait un chiffre faux et alarmant.
	if _depuis_le_lancement > 3.0:
		_minimum_absolu = minf(_minimum_absolu, actuel)

	var pire := actuel
	for valeur in _historique:
		pire = minf(pire, valeur)

	_etiquette.text = "%d img/s   (min 60 s : %d   min total : %d)\n%s\n%s" % [
		int(actuel), int(pire),
		int(_minimum_absolu) if _minimum_absolu < 9999.0 else int(actuel),
		_duree_lisible(_depuis_le_lancement), _fiche_technique]

static func _duree_lisible(secondes: float) -> String:
	return "en jeu depuis %d min %02d s" % [int(secondes) / 60, int(secondes) % 60]
