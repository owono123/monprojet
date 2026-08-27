shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Pelouse et tracage du terrain.
//
// Les lignes ne sont pas une texture : elles sont calculees a partir de la
// distance du pixel a chaque trace. Trois avantages sur un fichier image —
// elles restent nettes quelle que soit la distance de la camera, elles ne
// coutent pas un octet de memoire video (une texture de terrain lisible
// occuperait plus de 10 Mo), et elles sont exactes au centimetre puisqu'elles
// viennent des dimensions reglementaires elles-memes.

uniform float demi_longueur = 52.5;
uniform float demi_largeur = 34.0;
uniform float largeur_trace = 0.12;
uniform float rayon_rond_central = 9.15;
uniform float surface_profondeur = 16.5;
uniform float surface_demi_largeur = 20.16;
uniform float but_profondeur = 5.5;
uniform float but_demi_largeur = 9.16;
uniform float point_penalty = 11.0;
uniform float rayon_corner = 1.0;

uniform vec3 couleur_gazon : source_color = vec3(0.106, 0.325, 0.129);
uniform vec3 couleur_trace : source_color = vec3(0.92, 0.93, 0.90);
uniform float contraste_bandes = 0.085;
uniform float largeur_bande = 8.75;   // 12 bandes sur la longueur du terrain
uniform float humidite : hint_range(0.0, 1.0) = 0.0;

varying vec2 sol;   // position au sol en metres, origine au point central

void vertex() {
	sol = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

// Distance au contour d'un rectangle centre sur l'origine.
float distance_contour_rectangle(vec2 p, vec2 demi) {
	vec2 d = abs(p) - demi;
	float dehors = length(max(d, vec2(0.0)));
	float dedans = min(max(d.x, d.y), 0.0);
	return abs(dehors + dedans);
}

float distance_cercle(vec2 p, vec2 centre, float rayon) {
	return abs(length(p - centre) - rayon);
}

float distance_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Convertit une distance en couverture de pixel, avec un lissage large d'un
// pixel exactement : c'est ce qui evite l'escalier sur les lignes vues de loin.
float trace(float distance_au_trait, float demi_epaisseur, float flou) {
	return 1.0 - smoothstep(demi_epaisseur - flou, demi_epaisseur + flou, distance_au_trait);
}

float bruit(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Bruit lisse, pour les variations de teinte du gazon.
float bruit_lisse(vec2 p) {
	vec2 entier = floor(p);
	vec2 reste = fract(p);
	reste = reste * reste * (3.0 - 2.0 * reste);
	float a = bruit(entier);
	float b = bruit(entier + vec2(1.0, 0.0));
	float c = bruit(entier + vec2(0.0, 1.0));
	float d = bruit(entier + vec2(1.0, 1.0));
	return mix(mix(a, b, reste.x), mix(c, d, reste.x), reste.y);
}

void fragment() {
	vec2 p = sol;
	vec2 q = abs(p);
	float demi = largeur_trace * 0.5;
	// Largeur d'un pixel projete au sol : sert de rayon de lissage.
	float flou = max(fwidth(p.x), fwidth(p.y)) * 0.75 + 0.002;

	float marque = 0.0;

	// Lignes de touche et de but.
	marque = max(marque, trace(
		distance_contour_rectangle(p, vec2(demi_longueur, demi_largeur)), demi, flou));

	// Ligne mediane et rond central.
	marque = max(marque, trace(
		distance_segment(p, vec2(0.0, -demi_largeur), vec2(0.0, demi_largeur)), demi, flou));
	marque = max(marque, trace(
		distance_cercle(p, vec2(0.0), rayon_rond_central), demi, flou));
	// Point central.
	marque = max(marque, trace(length(p), 0.11, flou));

	// Les deux moities du terrain sont symetriques : en repliant la coordonnee
	// en x on trace les deux surfaces d'un seul calcul.
	float x_replie = q.x;

	// Surface de reparation.
	float centre_surface = demi_longueur - surface_profondeur * 0.5;
	marque = max(marque, trace(distance_contour_rectangle(
		vec2(x_replie - centre_surface, p.y),
		vec2(surface_profondeur * 0.5, surface_demi_largeur)), demi, flou));

	// Surface de but.
	float centre_but = demi_longueur - but_profondeur * 0.5;
	marque = max(marque, trace(distance_contour_rectangle(
		vec2(x_replie - centre_but, p.y),
		vec2(but_profondeur * 0.5, but_demi_largeur)), demi, flou));

	// Point de penalty.
	vec2 vers_penalty = vec2(x_replie - (demi_longueur - point_penalty), p.y);
	marque = max(marque, trace(length(vers_penalty), 0.11, flou));

	// Arc de cercle devant la surface : seulement la portion situee en dehors.
	if (x_replie < demi_longueur - surface_profondeur) {
		marque = max(marque, trace(
			distance_cercle(vers_penalty, vec2(0.0), rayon_rond_central), demi, flou));
	}

	// Quarts de cercle de corner.
	if (q.x <= demi_longueur && q.y <= demi_largeur) {
		marque = max(marque, trace(
			distance_cercle(q, vec2(demi_longueur, demi_largeur), rayon_corner), demi, flou));
	}

	// Bandes de tonte : le rouleau passe dans un sens puis dans l'autre, ce qui
	// couche l'herbe et change la facon dont elle renvoie la lumiere.
	float phase = sin(p.x * (3.14159265 / largeur_bande));
	float bande = smoothstep(-0.35, 0.35, phase) * 2.0 - 1.0;

	vec3 gazon = couleur_gazon * (1.0 + bande * contraste_bandes);
	// Variation fine pour casser l'aspect plastique d'un aplat uniforme.
	gazon *= 0.94 + 0.12 * bruit_lisse(p * 1.7);
	gazon *= 1.0 - 0.10 * bruit_lisse(p * 11.0);
	// Une pelouse mouillee est plus sombre et plus brillante.
	gazon *= 1.0 - 0.22 * humidite;

	ALBEDO = mix(gazon, couleur_trace, marque);
	ROUGHNESS = mix(mix(0.86, 0.72, humidite) - bande * 0.05, 0.80, marque);
	SPECULAR = mix(0.18 + 0.35 * humidite, 0.25, marque);
}
