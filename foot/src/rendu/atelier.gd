class_name Atelier
extends RefCounted

## Formes de base pour fabriquer de la geometrie par le code.
##
## Regroupe ce qui servait au corps et ce dont le visage a besoin : un sommet
## sait a quel os il appartient et a quelle zone de couleur il se rattache, un
## quadrilatere se decoupe en deux triangles, et l'on peut poser des tubes, des
## ellipsoides et des boites orientes n'importe ou.
##
## Un sommet est decrit par un dictionnaire :
##   point   Vector3, dans le repere du squelette
##   uv      Vector2, pour les motifs de maillot
##   os      index de l'os qui l'emporte
##   parent  index de l'os qui le tire un peu, ou le meme que `os`
##   melange part revenant au parent, de 0 a 1

## Diviseur applique a l'identifiant de zone avant de le ranger dans UV2.
## Le shader multiplie par la meme valeur pour le retrouver.
const ECHELLE_ZONE := 16.0

## Zones de couleur. C'est le vocabulaire partage entre la geometrie et le
## shader : le maillage ne transporte pas de couleur, seulement l'indication de
## ce qu'il represente, et le nuancier arrive a part.
const ZONE_PEAU := 0.0
const ZONE_MAILLOT := 1.0
const ZONE_SHORT := 2.0
const ZONE_CHAUSSETTES := 3.0
const ZONE_CHAUSSURES := 4.0
const ZONE_OEIL := 5.0
const ZONE_IRIS := 6.0
const ZONE_CHEVEUX := 7.0
const ZONE_LEVRES := 8.0
const ZONE_SOURCILS := 9.0

static func sommet(outil: SurfaceTool, description: Dictionary, zone: float) -> void:
	var os: int = description["os"]
	var parent: int = description.get("parent", os)
	var melange: float = description.get("melange", 0.0)
	if parent == os or melange <= 0.0:
		outil.set_bones(PackedInt32Array([os, 0, 0, 0]))
		outil.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	else:
		outil.set_bones(PackedInt32Array([os, parent, 0, 0]))
		outil.set_weights(PackedFloat32Array([1.0 - melange, melange, 0.0, 0.0]))
	outil.set_uv(description.get("uv", Vector2(0.5, 0.5)))
	outil.set_uv2(Vector2(zone / ECHELLE_ZONE, 0.0))
	outil.add_vertex(description["point"])

static func quadrilatere(outil: SurfaceTool, zone: float,
		a: Dictionary, b: Dictionary, c: Dictionary, d: Dictionary) -> void:
	for description in [a, b, c, a, c, d]:
		sommet(outil, description, zone)

## Tronc de cone entre deux points. `aplatissement` ecrase la section sur l'axe
## de la profondeur : a 0,62 on obtient une ellipse, ce qu'est reellement un
## torse. Le poids de chaque sommet est reparti entre `os` et `os_parent`, ce
## qui evite qu'une epaule ou une hanche ne s'ouvre en deux quand le membre
## pivote.
static func tube(outil: SurfaceTool, depart: Vector3, arrivee: Vector3,
		rayon_depart: float, rayon_arrivee: float, cotes: int, os: int, os_parent: int,
		zone: float, aplatissement: float = 1.0, anneaux: int = 3) -> void:
	var axe := arrivee - depart
	var longueur := axe.length()
	if longueur < 0.0001:
		return
	var haut := axe / longueur
	var cote_x := Vector3.RIGHT if absf(haut.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var avant := haut.cross(cote_x).normalized()
	cote_x = avant.cross(haut).normalized()

	var grille: Array = []
	for anneau in anneaux + 1:
		var t := float(anneau) / float(anneaux)
		var centre := depart + axe * t
		var rayon := lerpf(rayon_depart, rayon_arrivee, t)
		var ligne: Array = []
		for pas in cotes:
			var angle := TAU * float(pas) / float(cotes)
			ligne.append({
				"point": centre + cote_x * (cos(angle) * rayon)
					+ avant * (sin(angle) * rayon * aplatissement),
				"uv": Vector2(float(pas) / float(cotes), t),
				"os": os, "parent": os_parent, "melange": part_du_parent(t),
			})
		grille.append(ligne)

	for anneau in anneaux:
		for pas in cotes:
			var suivant := (pas + 1) % cotes
			quadrilatere(outil, zone, grille[anneau][pas], grille[anneau][suivant],
				grille[anneau + 1][suivant], grille[anneau + 1][pas])

## Part du poids revenant a l'os parent le long d'un membre. Pres du depart,
## l'os parent tire encore la peau ; passe le tiers du segment, le membre suit
## entierement son propre os.
static func part_du_parent(t: float) -> float:
	return (1.0 - smoothstep(0.0, 0.34, t)) * 0.5

## Ellipsoide oriente. `rayons` donne les trois demi-axes, `orientation` permet
## de l'incliner — c'est ainsi qu'on pose une oreille ou une paupiere.
static func ellipsoide(outil: SurfaceTool, centre: Vector3, rayons: Vector3,
		meridiens: int, paralleles: int, os: int, zone: float,
		orientation: Basis = Basis()) -> void:
	var grille: Array = []
	for anneau in paralleles + 1:
		var phi := PI * float(anneau) / float(paralleles)
		var ligne: Array = []
		for pas in meridiens:
			var theta := TAU * float(pas) / float(meridiens)
			var direction := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			ligne.append({
				"point": centre + orientation * (direction * rayons),
				"uv": Vector2(float(pas) / float(meridiens), float(anneau) / float(paralleles)),
				"os": os, "parent": os, "melange": 0.0,
			})
		grille.append(ligne)
	for anneau in paralleles:
		for pas in meridiens:
			var suivant := (pas + 1) % meridiens
			quadrilatere(outil, zone, grille[anneau][pas], grille[anneau][suivant],
				grille[anneau + 1][suivant], grille[anneau + 1][pas])

## Boite orientee, decrite par un repere et ses trois demi-dimensions.
static func boite(outil: SurfaceTool, repere: Transform3D, demi: Vector3,
		os: int, zone: float) -> void:
	var coins: Array = []
	for devant in [-1.0, 1.0]:
		for cote in [-1.0, 1.0]:
			for haut in [-1.0, 1.0]:
				coins.append(repere * Vector3(cote * demi.x, haut * demi.y, devant * demi.z))
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 2, 6, 4], [1, 5, 7, 3],
		[2, 3, 7, 6], [0, 4, 5, 1]]
	for face in faces:
		var quatre: Array = []
		for index in face:
			quatre.append({"point": coins[index], "uv": Vector2(0.5, 0.5),
				"os": os, "parent": os, "melange": 0.0})
		quadrilatere(outil, zone, quatre[0], quatre[1], quatre[2], quatre[3])
