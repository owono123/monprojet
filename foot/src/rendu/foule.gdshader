shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

// Un spectateur : un simple quadrilatere, tete claire au-dessus, maillot en
// dessous, la couleur venant de l'instance.
//
// Plusieurs milliers d'entre eux tiennent dans un seul MultiMesh, donc un seul
// appel de rendu. Le mouvement est calcule ici plutot que par la simulation :
// une foule qui respire ne change rien au match, mais une foule parfaitement
// immobile trahit immediatement le decor en carton.

uniform vec3 couleur_peau : source_color = vec3(0.74, 0.58, 0.46);
uniform float amplitude_du_mouvement = 0.055;

varying vec3 maillot;
varying float teint;

void vertex() {
	maillot = COLOR.rgb;
	// Chaque spectateur bouge a son propre rythme : sans ce decalage, toute la
	// tribune ondulerait ensemble comme un seul organisme.
	float decalage = fract(float(INSTANCE_ID) * 0.6180339887) * 6.2831853;
	float souffle = sin(TIME * 1.7 + decalage) + sin(TIME * 0.63 + decalage * 2.1) * 0.5;
	VERTEX.y += souffle * amplitude_du_mouvement;
	// Le teint varie d'un spectateur a l'autre, tire du meme decalage.
	teint = 0.72 + fract(float(INSTANCE_ID) * 0.7548776662) * 0.52;
}

void fragment() {
	// Le haut du quadrilatere est la tete, le reste le buste. La bascule est
	// franche : a cette distance, un degrade ne se verrait pas.
	float est_la_tete = step(UV.y, 0.30);
	// Les epaules sont arrondies plutot que carrees, ce qui suffit a lire une
	// silhouette humaine dans une tache de quelques pixels.
	float largeur = mix(0.5, 0.30, smoothstep(0.30, 0.10, UV.y));
	if (abs(UV.x - 0.5) > largeur) {
		discard;
	}
	ALBEDO = mix(maillot, couleur_peau * teint, est_la_tete);
	ROUGHNESS = 0.92;
	SPECULAR = 0.08;
}
