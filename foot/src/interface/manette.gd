class_name Manette
extends Control

## Commandes tactiles : joystick virtuel a gauche, boutons a droite.
##
## Le joystick est flottant : il apparait la ou le pouce se pose au lieu d'etre
## fixe a un endroit de l'ecran. Sur un telephone tenu a deux mains, le pouce ne
## retombe jamais exactement au meme endroit, et un joystick fixe oblige a
## regarder ses mains au lieu du terrain.
##
## Les boutons sont contextuels : quand l'equipe a le ballon on propose TIR,
## PASSE, CENTRE et LOB ; sinon TACLE, PRESSING et CHANGER. Huit boutons
## permanents ne tiendraient pas sous un pouce, et surtout la moitie serait
## toujours inutile.
##
## Cette classe ne fait que traduire des doigts en objet Commandes. Elle
## n'appelle jamais la simulation : c'est la simulation qui vient lire.

const RAYON_JOYSTICK := 120.0
const RAYON_POUCE := 48.0
const RAYON_BOUTON := 52.0
const ZONE_GAUCHE := 0.48        # part de l'ecran reservee au joystick
const ZONE_MORTE := 0.14         # part du rayon ignoree au centre

## Contextes d'affichage d'un bouton.
const AVEC_BALLON := 1
const SANS_BALLON := 2
const TOUJOURS := 3

## Mis a jour par la scene principale a chaque image, selon qui tient le ballon.
var avec_ballon := false:
	set(valeur):
		if valeur != avec_ballon:
			avec_ballon = valeur
			_oublier_les_boutons_caches()
			queue_redraw()

var _doigt_joystick := -1
var _centre_joystick := Vector2.ZERO
var _position_pouce := Vector2.ZERO

## `momentane` distingue une frappe, prise en compte une seule fois par appui,
## d'un sprint, actif tant que le doigt reste pose.
var _boutons := [
	{"nom": "TIR", "bit": Commandes.TIR, "momentane": true, "contexte": AVEC_BALLON,
		"couleur": Color(0.86, 0.27, 0.25), "decalage": Vector2(0.0, -78.0)},
	{"nom": "CENTRE", "bit": Commandes.CENTRE, "momentane": true, "contexte": AVEC_BALLON,
		"couleur": Color(0.90, 0.66, 0.20), "decalage": Vector2(78.0, 0.0)},
	{"nom": "PASSE", "bit": Commandes.PASSE, "momentane": true, "contexte": AVEC_BALLON,
		"couleur": Color(0.30, 0.66, 0.35), "decalage": Vector2(0.0, 78.0)},
	{"nom": "LOB", "bit": Commandes.LOB, "momentane": true, "contexte": AVEC_BALLON,
		"couleur": Color(0.32, 0.55, 0.85), "decalage": Vector2(-78.0, 0.0)},
	{"nom": "TACLE", "bit": Commandes.TACLE, "momentane": true, "contexte": SANS_BALLON,
		"couleur": Color(0.86, 0.27, 0.25), "decalage": Vector2(0.0, -78.0)},
	{"nom": "PRESSING", "bit": Commandes.PRESSING, "momentane": false, "contexte": SANS_BALLON,
		"couleur": Color(0.90, 0.50, 0.20), "decalage": Vector2(78.0, 0.0)},
	{"nom": "CHANGER", "bit": Commandes.CHANGER, "momentane": true, "contexte": SANS_BALLON,
		"couleur": Color(0.45, 0.62, 0.88), "decalage": Vector2(0.0, 78.0)},
	{"nom": "SPRINT", "bit": Commandes.SPRINT, "momentane": false, "contexte": TOUJOURS,
		"couleur": Color(0.62, 0.62, 0.66), "decalage": Vector2(-196.0, 66.0)},
]

var _maintenus: int = Commandes.AUCUN
var _declenches: int = Commandes.AUCUN   # appuis pas encore lus par la simulation

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for bouton in _boutons:
		bouton["doigt"] = -1
		bouton["position"] = Vector2.ZERO
	resized.connect(_placer_boutons)
	_placer_boutons()

func _placer_boutons() -> void:
	var ancre := Vector2(size.x - 150.0, size.y - 150.0)
	for bouton in _boutons:
		bouton["position"] = ancre + bouton["decalage"]
	queue_redraw()

func _visible_maintenant(bouton: Dictionary) -> bool:
	var contexte: int = bouton["contexte"]
	if contexte == TOUJOURS:
		return true
	return contexte == (AVEC_BALLON if avec_ballon else SANS_BALLON)

## Quand la possession change, un bouton qui disparait ne doit pas rester
## enfonce : sans cela, un pressing declenche avant de recuperer le ballon
## resterait actif indefiniment.
func _oublier_les_boutons_caches() -> void:
	for bouton in _boutons:
		if not _visible_maintenant(bouton) and bouton["doigt"] != -1:
			bouton["doigt"] = -1
			_maintenus &= ~int(bouton["bit"])

## Renvoie les commandes de cette image, et consomme les appuis momentanes :
## un bouton de frappe ne declenche qu'une seule action par appui, meme si le
## doigt reste pose vingt images de plus.
func lire() -> Commandes:
	var direction := Vector2.ZERO
	if _doigt_joystick != -1:
		var ecart := _position_pouce - _centre_joystick
		var amplitude := ecart.length() / RAYON_JOYSTICK
		if amplitude > ZONE_MORTE:
			# La zone morte est retiree puis la course restante etiree, sinon la
			# vitesse ferait un saut des qu'on sort du centre.
			var utile := (amplitude - ZONE_MORTE) / (1.0 - ZONE_MORTE)
			direction = ecart.normalized() * minf(utile, 1.0)

	var commandes := Commandes.new(direction, _maintenus | _declenches)
	_declenches = Commandes.AUCUN
	return commandes

func _input(evenement: InputEvent) -> void:
	if evenement is InputEventScreenTouch:
		if evenement.pressed:
			_poser_doigt(evenement.index, evenement.position)
		else:
			_lever_doigt(evenement.index)
	elif evenement is InputEventScreenDrag:
		_deplacer_doigt(evenement.index, evenement.position)

func _poser_doigt(index: int, endroit: Vector2) -> void:
	for bouton in _boutons:
		if not _visible_maintenant(bouton) or bouton["doigt"] != -1:
			continue
		if endroit.distance_to(bouton["position"]) <= RAYON_BOUTON * 1.35:
			bouton["doigt"] = index
			_maintenus |= int(bouton["bit"])
			if bouton["momentane"]:
				_declenches |= int(bouton["bit"])
			queue_redraw()
			return

	if _doigt_joystick == -1 and endroit.x < size.x * ZONE_GAUCHE:
		_doigt_joystick = index
		_centre_joystick = endroit
		_position_pouce = endroit
		queue_redraw()

func _deplacer_doigt(index: int, endroit: Vector2) -> void:
	if index != _doigt_joystick:
		return
	_position_pouce = endroit
	# Si le pouce depasse le cercle, le centre suit au lieu de saturer : la
	# direction reste fidele meme quand la main derive vers le bas de l'ecran.
	var ecart := _position_pouce - _centre_joystick
	if ecart.length() > RAYON_JOYSTICK:
		_centre_joystick = _position_pouce - ecart.normalized() * RAYON_JOYSTICK
	queue_redraw()

func _lever_doigt(index: int) -> void:
	if index == _doigt_joystick:
		_doigt_joystick = -1
		queue_redraw()
	for bouton in _boutons:
		if bouton["doigt"] == index:
			bouton["doigt"] = -1
			# Le bit d'un bouton momentane a deja ete recopie dans _declenches
			# au moment de l'appui : le relacher ici n'efface donc pas l'action,
			# meme si le doigt s'est leve entre deux images.
			_maintenus &= ~int(bouton["bit"])
			queue_redraw()

func _draw() -> void:
	if _doigt_joystick != -1:
		draw_circle(_centre_joystick, RAYON_JOYSTICK, Color(1, 1, 1, 0.10))
		draw_arc(_centre_joystick, RAYON_JOYSTICK, 0.0, TAU, 48, Color(1, 1, 1, 0.30), 3.0, true)
		var ecart := (_position_pouce - _centre_joystick).limit_length(RAYON_JOYSTICK)
		draw_circle(_centre_joystick + ecart, RAYON_POUCE, Color(1, 1, 1, 0.28))
	else:
		# Rappel discret de l'endroit ou poser le pouce.
		var repere := Vector2(size.x * 0.16, size.y * 0.72)
		draw_arc(repere, RAYON_JOYSTICK * 0.7, 0.0, TAU, 40, Color(1, 1, 1, 0.13), 2.0, true)

	var police := get_theme_default_font()
	var taille_police := 19
	for bouton in _boutons:
		if not _visible_maintenant(bouton):
			continue
		var enfonce: bool = bouton["doigt"] != -1
		var couleur: Color = bouton["couleur"]
		var centre: Vector2 = bouton["position"]
		var rayon := RAYON_BOUTON * (0.92 if enfonce else 1.0)
		draw_circle(centre, rayon, Color(couleur.r, couleur.g, couleur.b, 0.40 if enfonce else 0.24))
		draw_arc(centre, rayon, 0.0, TAU, 32, Color(couleur.r, couleur.g, couleur.b, 0.85), 3.0, true)
		var texte: String = bouton["nom"]
		var largeur := police.get_string_size(texte, HORIZONTAL_ALIGNMENT_LEFT, -1, taille_police).x
		draw_string(police, centre + Vector2(-largeur * 0.5, taille_police * 0.36), texte,
			HORIZONTAL_ALIGNMENT_LEFT, -1, taille_police, Color(1, 1, 1, 0.94))
