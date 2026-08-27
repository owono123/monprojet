class_name Postes
extends RefCounted

## Postes des joueurs. Le numero sert d'index dans les tableaux de la
## simulation : il ne doit jamais changer une fois des donnees enregistrees.

enum {
	GARDIEN,
	DEFENSEUR_CENTRAL,
	LATERAL_DROIT,
	LATERAL_GAUCHE,
	MILIEU_DEFENSIF,
	MILIEU_CENTRAL,
	MILIEU_DROIT,
	MILIEU_GAUCHE,
	MILIEU_OFFENSIF,
	AILIER_DROIT,
	AILIER_GAUCHE,
	ATTAQUANT,
}

const ABREVIATIONS := {
	GARDIEN: "GB",
	DEFENSEUR_CENTRAL: "DC",
	LATERAL_DROIT: "DD",
	LATERAL_GAUCHE: "DG",
	MILIEU_DEFENSIF: "MDC",
	MILIEU_CENTRAL: "MC",
	MILIEU_DROIT: "MD",
	MILIEU_GAUCHE: "MG",
	MILIEU_OFFENSIF: "MOC",
	AILIER_DROIT: "AID",
	AILIER_GAUCHE: "AIG",
	ATTAQUANT: "BU",
}

## Jusqu'ou un joueur de ce poste accepte de remonter ou de descendre par
## rapport a sa position de formation, en metres. Un defenseur central qui
## suivrait le ballon jusque dans la surface adverse laisserait un trou beant ;
## un attaquant qui redescendrait defendre ne servirait plus a rien devant.
const LIBERTE_LONGITUDINALE := {
	GARDIEN: 6.0,
	DEFENSEUR_CENTRAL: 16.0,
	LATERAL_DROIT: 26.0,
	LATERAL_GAUCHE: 26.0,
	MILIEU_DEFENSIF: 20.0,
	MILIEU_CENTRAL: 28.0,
	MILIEU_DROIT: 30.0,
	MILIEU_GAUCHE: 30.0,
	MILIEU_OFFENSIF: 30.0,
	AILIER_DROIT: 32.0,
	AILIER_GAUCHE: 32.0,
	ATTAQUANT: 26.0,
}

static func abreviation(poste: int) -> String:
	return ABREVIATIONS.get(poste, "??")

static func est_gardien(poste: int) -> bool:
	return poste == GARDIEN

static func liberte(poste: int) -> float:
	return LIBERTE_LONGITUDINALE.get(poste, 24.0)
