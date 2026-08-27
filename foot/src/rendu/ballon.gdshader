shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Ballon classique a 32 panneaux, dessine sans aucune texture.
//
// Les 12 pentagones noirs d'un ballon de football sont centres exactement sur
// les 12 sommets d'un icosaedre. Ces sommets vont par paires diametralement
// opposees : en prenant la valeur absolue du produit scalaire, six axes
// suffisent pour les retrouver tous les douze. Le panneau se reduit alors a
// six produits scalaires par pixel, moins cher qu'une lecture de texture.

uniform vec3 couleur_claire : source_color = vec3(0.93, 0.93, 0.91);
uniform vec3 couleur_sombre : source_color = vec3(0.07, 0.07, 0.08);
uniform float usure : hint_range(0.0, 1.0) = 0.25;

varying vec3 direction_locale;

void vertex() {
	direction_locale = normalize(VERTEX);
}

void fragment() {
	// Nombre d'or : c'est lui qui place les sommets d'un icosaedre.
	const float phi = 1.6180339887;
	vec3 axes[6] = {
		normalize(vec3(0.0, 1.0, phi)),
		normalize(vec3(0.0, 1.0, -phi)),
		normalize(vec3(1.0, phi, 0.0)),
		normalize(vec3(1.0, -phi, 0.0)),
		normalize(vec3(phi, 0.0, 1.0)),
		normalize(vec3(-phi, 0.0, 1.0))
	};

	vec3 d = normalize(direction_locale);
	float meilleur = 0.0;
	float second = 0.0;
	for (int i = 0; i < 6; i++) {
		float alignement = abs(dot(d, axes[i]));
		if (alignement > meilleur) {
			second = meilleur;
			meilleur = alignement;
		} else if (alignement > second) {
			second = alignement;
		}
	}

	float empreinte = fwidth(meilleur);
	float flou = empreinte * 1.5 + 0.002;
	// De loin, le ballon ne fait qu'une dizaine de pixels : un pixel couvre
	// alors plusieurs panneaux. Le lissage devient si large qu'il ramene tout
	// vers la valeur intermediaire, et le ballon vire au gris fonce — c'est le
	// defaut qu'avait la version precedente. On bascule donc vers la proportion
	// MOYENNE de noir (28 %), qui est la bonne reponse quand le motif n'est
	// plus resolvable, et le ballon reste blanc et lisible a distance.
	float fondu_lointain = smoothstep(0.02, 0.14, empreinte);
	// Pres d'un sommet d'icosaedre : panneau noir.
	//
	// Le seuil n'est pas choisi a l'oeil. Sur un icosaedre tronque les douze
	// pentagones occupent environ 28 % de la surface. La calotte spherique
	// autour d'un sommet vaut 2*PI*(1-cos a) ; en resolvant pour douze calottes
	// couvrant 28 % de 4*PI on trouve cos a = 0,953. Un seuil plus bas donne un
	// ballon presque noir, ce qui est exactement le defaut qu'avait la premiere
	// version.
	float pentagone = smoothstep(0.952 - flou, 0.952 + flou, meilleur);
	pentagone = mix(pentagone, 0.28, fondu_lointain);
	// La ou les deux axes les plus proches s'equivalent, on est sur une couture.
	float couture = (1.0 - smoothstep(0.0, 0.012, meilleur - second)) * (1.0 - fondu_lointain);

	vec3 teinte = mix(couleur_claire, couleur_sombre, pentagone);
	teinte = mix(teinte, teinte * 0.72, couture * 0.6);
	// Un ballon de match n'est jamais parfaitement propre.
	teinte *= 1.0 - usure * 0.06 * fract(sin(dot(d.xy, vec2(19.7, 43.1))) * 3571.0);

	ALBEDO = teinte;
	ROUGHNESS = mix(0.38, 0.52, pentagone) + usure * 0.15;
	SPECULAR = 0.5;
}
