class_name Regles
extends RefCounted

## Les Lois du jeu, ecrites comme des fonctions pures.
##
## Rien ici ne modifie quoi que ce soit : on donne une position de ballon et
## quelques faits, on recoit une decision. C'est ce qui permet de verifier
## l'arbitrage par des tests directs — un hors-jeu limite, un corner, une sortie
## sur la ligne de but — sans avoir a jouer un match entier pour provoquer la
## situation.

## Ce qui peut arriver au ballon.
enum {
	RIEN,
	TOUCHE,          # sortie par une ligne de touche
	CORNER,          # sortie par la ligne de but, touchee en dernier par la defense
	SIX_METRES,      # sortie par la ligne de but, touchee en dernier par l'attaque
	COUP_FRANC,      # faute ou hors-jeu
	BUT,
}

## Le ballon est sorti si son centre a entierement franchi la ligne. La ligne
## fait partie du terrain : un ballon dont le centre est pile dessus est encore
## en jeu, ce qui est la regle et non une approximation.
static func est_sorti(position: Vector3) -> bool:
	return absf(position.x) > Dimensions.DEMI_LONGUEUR \
		or absf(position.z) > Dimensions.DEMI_LARGEUR

## Vrai si le ballon a franchi la ligne de but entre les poteaux et sous la barre.
static func est_un_but(position: Vector3) -> bool:
	return absf(position.x) > Dimensions.DEMI_LONGUEUR \
		and absf(position.z) <= Dimensions.BUT_DEMI_LARGEUR \
		and position.y <= Dimensions.BUT_HAUTEUR

## Que faire du ballon sorti.
##
## `dernier_toucheur` est l'index de l'equipe qui a touche le ballon en dernier,
## `sens` le sens d'attaque de chaque equipe (+1 vers les x positifs).
## Renvoie {"decision": ..., "point": Vector3, "equipe": int}, ou `equipe` est
## celle qui benefficie de la remise en jeu.
static func decider(position: Vector3, dernier_toucheur: int,
		sens: Array) -> Dictionary:
	if est_un_but(position):
		# Le but appartient a l'equipe qui attaque de ce cote.
		var vers_les_x_positifs := position.x > 0.0
		var marqueur := 0 if (int(sens[0]) > 0) == vers_les_x_positifs else 1
		return {"decision": BUT, "point": Vector3.ZERO, "equipe": marqueur}

	if absf(position.z) > Dimensions.DEMI_LARGEUR:
		# Touche pour l'adversaire du dernier joueur a avoir touche le ballon.
		return {
			"decision": TOUCHE,
			"point": Vector3(
				clampf(position.x, -Dimensions.DEMI_LONGUEUR, Dimensions.DEMI_LONGUEUR),
				0.0, signf(position.z) * Dimensions.DEMI_LARGEUR),
			"equipe": 1 - _equipe_valide(dernier_toucheur),
		}

	if absf(position.x) > Dimensions.DEMI_LONGUEUR:
		var cote := signf(position.x)
		# Qui defend ce but : celle qui attaque dans l'autre sens.
		var defenseur := 0 if float(signi(int(sens[0]))) != cote else 1
		var toucheur := _equipe_valide(dernier_toucheur)
		if toucheur == defenseur:
			# La defense a mis le ballon derriere sa propre ligne : corner.
			return {
				"decision": CORNER,
				"point": Vector3(cote * Dimensions.DEMI_LONGUEUR, 0.0,
					signf(position.z) * Dimensions.DEMI_LARGEUR),
				"equipe": 1 - defenseur,
			}
		# L'attaque a mis le ballon dehors : six metres pour la defense.
		return {
			"decision": SIX_METRES,
			"point": Vector3(
				cote * (Dimensions.DEMI_LONGUEUR - Dimensions.SURFACE_BUT_PROFONDEUR),
				0.0, signf(position.z) * Dimensions.SURFACE_BUT_DEMI_LARGEUR * 0.6),
			"equipe": defenseur,
		}

	return {"decision": RIEN, "point": Vector3.ZERO, "equipe": -1}

## Un dernier toucheur inconnu — un ballon sorti sans que personne ne l'ait joue,
## juste apres un coup d'envoi par exemple — est attribue a l'equipe 0 par
## convention, pour que la remise en jeu ait toujours un beneficiaire.
static func _equipe_valide(equipe: int) -> int:
	return equipe if equipe == 0 or equipe == 1 else 0

## Hors-jeu.
##
## Un joueur est hors-jeu s'il se trouve, au moment de la passe, plus pres de la
## ligne de but adverse que le ballon ET que l'avant-dernier adversaire. Trois
## exceptions retenues ici : etre dans son propre camp, etre a hauteur, et
## recevoir le ballon d'une remise en touche.
##
## `positions_adverses` liste les x de tous les adversaires, gardien compris.
static func est_hors_jeu(x_receveur: float, x_ballon: float,
		positions_adverses: Array, sens: int) -> bool:
	var direction := float(signi(sens))
	# Dans son propre camp, jamais de hors-jeu.
	if x_receveur * direction <= 0.0:
		return false
	# Jamais devant le ballon n'est pas un hors-jeu : c'est etre devant LE BALLON
	# qui compte, donc un joueur en retrait est toujours en jeu.
	if x_receveur * direction <= x_ballon * direction + 0.05:
		return false

	# On cherche l'avant-dernier adversaire, c'est-a-dire le deuxieme plus
	# proche de sa propre ligne de but. Le gardien est generalement le dernier,
	# mais la regle ne le suppose pas, et un gardien sorti change tout.
	var avancees: Array[float] = []
	for x in positions_adverses:
		avancees.append(float(x) * direction)
	avancees.sort()
	if avancees.size() < 2:
		return false
	# Le plus avance dans notre sens est en fin de tableau.
	var avant_dernier := avancees[avancees.size() - 2]
	return x_receveur * direction > avant_dernier + 0.05
