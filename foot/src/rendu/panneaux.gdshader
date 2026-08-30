shader_type spatial;
render_mode cull_back, diffuse_lambert;

// Bandeau publicitaire du bord de touche.
//
// Les panneaux ne portent aucune marque : ce sont des aplats de couleur. Ce
// n'est pas une facilite, c'est la regle du projet — aucun sponsor reel n'entre
// dans le jeu. L'editeur de stade laissera regler la palette, et l'utilisateur
// mettra ce qu'il veut sur son propre appareil.
//
// La coordonnee horizontale porte des metres, si bien que la largeur d'un
// panneau reste la meme sur les cotes comme dans les virages.

uniform float largeur_panneau = 2.6;
uniform vec3 teinte_a : source_color = vec3(0.10, 0.22, 0.48);
uniform vec3 teinte_b : source_color = vec3(0.86, 0.86, 0.88);
uniform vec3 teinte_c : source_color = vec3(0.72, 0.14, 0.16);

varying vec2 coordonnee;

void vertex() {
	coordonnee = UV;
}

void fragment() {
	float index = floor(coordonnee.x / largeur_panneau);
	float dedans = fract(coordonnee.x / largeur_panneau);

	// Trois couleurs qui se suivent sans repetition trop evidente.
	float choix = fract(index * 0.37);
	vec3 fond = choix < 0.34 ? teinte_a : (choix < 0.67 ? teinte_b : teinte_c);

	// Joint sombre entre deux panneaux, et lisere en haut et en bas.
	float joint = smoothstep(0.0, 0.03, dedans) * (1.0 - smoothstep(0.97, 1.0, dedans));
	float lisere = smoothstep(0.0, 0.10, coordonnee.y) * (1.0 - smoothstep(0.88, 1.0, coordonnee.y));

	// Une bande claire au milieu du panneau, la ou se trouverait une inscription.
	float bande = smoothstep(0.30, 0.36, coordonnee.y) * (1.0 - smoothstep(0.62, 0.68, coordonnee.y));
	vec3 teinte = mix(fond, fond * 0.35 + vec3(0.35), bande * 0.55);

	ALBEDO = mix(vec3(0.06, 0.06, 0.07), teinte, joint * lisere);
	ROUGHNESS = 0.55;
	SPECULAR = 0.35;
}
