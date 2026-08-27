class_name Simulation
extends RefCounted

## Le coeur du jeu : simuler(commandes) fait avancer le match d'exactement une
## image, et ne sait rien de l'affichage.
##
## Trois regles tenues sans exception dans ce fichier et tous ceux du dossier
## noyau/ :
##   1. pas de temps FIXE — jamais de delta variable, sinon deux appareils qui
##      n'affichent pas au meme rythme divergent ;
##   2. aucun appel a randf() — tout tirage passe par `alea`, dont la graine est
##      enregistree avec le match ;
##   3. aucune reference a un Node, une texture ou une camera.
##
## Ces trois regles donnent gratuitement les replays et le match en reseau
## local. Les ajouter apres coup obligerait a tout reecrire, c'est pourquoi
## elles sont posees des la premiere ligne.

const PAS := 1.0 / 60.0
const IMAGES_PAR_SECONDE := 60

# Joueur pilote — valeurs provisoires, remplacees en phase 1 par les
# caracteristiques individuelles de chaque joueur de la feuille de match.
const ALLURE_COURSE := 6.4        # m/s
const ALLURE_SPRINT := 8.6        # m/s
const ACCELERATION := 22.0        # m/s2
const FREINAGE := 26.0            # m/s2
const PORTEE_CONTROLE := 0.85     # distance a laquelle le ballon est jouable

var alea: Alea
var etat: EtatMatch
var ballon: Ballon

## Adherence du gazon, fixee par la meteo. 1.0 par temps sec.
var glisse := 1.0

func _init(graine: int = 1) -> void:
	alea = Alea.new(graine)
	etat = EtatMatch.new()
	ballon = Ballon.new()
	placer_coup_d_envoi()

## Remet ballon et joueur en position de coup d'envoi.
func placer_coup_d_envoi() -> void:
	ballon.placer(Vector3.ZERO)
	etat.joueur_position = Vector3(-2.0, 0.0, 0.0)
	etat.joueur_vitesse = Vector3.ZERO
	_recopier_dans_etat()

## Avance d'une image. C'est la seule facon de faire progresser le match.
func simuler(commandes: Commandes) -> void:
	_deplacer_joueur(commandes)
	_jouer_le_ballon(commandes)
	ballon.avancer(PAS, glisse)
	_contenir_ballon()
	etat.image += 1
	_recopier_dans_etat()

func _deplacer_joueur(commandes: Commandes) -> void:
	var demande := commandes.direction_normalisee()
	var voulue := Vector3(demande.x, 0.0, demande.y)
	var allure_max := ALLURE_SPRINT if commandes.appuye(Commandes.SPRINT) else ALLURE_COURSE
	var cible := voulue * allure_max

	var ecart := cible - etat.joueur_vitesse
	var poussee := ACCELERATION if voulue.length_squared() > 0.0 else FREINAGE
	var variation := poussee * PAS
	if ecart.length() <= variation:
		etat.joueur_vitesse = cible
	else:
		etat.joueur_vitesse += ecart.normalized() * variation

	etat.joueur_position += etat.joueur_vitesse * PAS
	# Le joueur reste sur la pelouse, marge comprise.
	var bord_x := Dimensions.DEMI_LONGUEUR + Dimensions.MARGE_PELOUSE
	var bord_z := Dimensions.DEMI_LARGEUR + Dimensions.MARGE_PELOUSE
	etat.joueur_position.x = clampf(etat.joueur_position.x, -bord_x, bord_x)
	etat.joueur_position.z = clampf(etat.joueur_position.z, -bord_z, bord_z)
	etat.joueur_position.y = 0.0

func _jouer_le_ballon(commandes: Commandes) -> void:
	var vers_ballon := ballon.position - etat.joueur_position
	vers_ballon.y = 0.0
	var distance := vers_ballon.length()
	if distance > PORTEE_CONTROLE or ballon.position.y > 1.2:
		return

	var orientation := etat.joueur_vitesse
	orientation.y = 0.0
	if orientation.length_squared() < 0.01:
		orientation = vers_ballon if distance > 0.01 else Vector3(1.0, 0.0, 0.0)
	orientation = orientation.normalized()

	if commandes.appuye(Commandes.TIR):
		ballon.frapper(orientation, 26.0, 9.0, _effet(commandes))
	elif commandes.appuye(Commandes.LOB):
		ballon.frapper(orientation, 15.0, 42.0, _effet(commandes))
	elif commandes.appuye(Commandes.CENTRE):
		ballon.frapper(orientation, 19.0, 26.0, _effet(commandes) + 1.5)
	elif commandes.appuye(Commandes.PASSE):
		ballon.frapper(orientation, 13.0, 2.0, _effet(commandes))
	elif ballon.au_sol:
		# Conduite de balle : le ballon est pousse devant, pas colle au pied.
		var allure := etat.joueur_vitesse.length()
		if allure > 0.4:
			ballon.vitesse.x = orientation.x * allure * 1.15
			ballon.vitesse.z = orientation.z * allure * 1.15

## Un peu d'effet selon l'inclinaison du joystick au moment de la frappe : c'est
## ce qui permet d'enrouler sans bouton dedie.
func _effet(commandes: Commandes) -> float:
	return commandes.direction_normalisee().y * 2.5

## Empeche le ballon de partir a l'infini tant que les regles de sortie ne sont
## pas ecrites (phase 2). Il rebondit sur une cloture invisible.
func _contenir_ballon() -> void:
	var bord_x := Dimensions.DEMI_LONGUEUR + Dimensions.MARGE_PELOUSE
	var bord_z := Dimensions.DEMI_LARGEUR + Dimensions.MARGE_PELOUSE
	if absf(ballon.position.x) > bord_x:
		ballon.position.x = clampf(ballon.position.x, -bord_x, bord_x)
		ballon.vitesse.x = -ballon.vitesse.x * 0.4
	if absf(ballon.position.z) > bord_z:
		ballon.position.z = clampf(ballon.position.z, -bord_z, bord_z)
		ballon.vitesse.z = -ballon.vitesse.z * 0.4

func _recopier_dans_etat() -> void:
	etat.ballon_position = ballon.position
	etat.ballon_vitesse = ballon.vitesse
