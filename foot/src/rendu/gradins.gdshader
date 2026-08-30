shader_type spatial;
render_mode cull_back, diffuse_lambert;

// Sieges des gradins, dessines dans le pixel.
//
// Un stade de trente mille places represente trente mille sieges. En geometrie,
// meme reduits a une boite chacun, cela ferait plus de trois cent mille
// triangles et un temps de sommet qu'aucun telephone ne tient. On dessine donc
// la grille des places directement sur la pente des gradins : le cout ne depend
// plus du nombre de sieges mais du nombre de pixels a l'ecran, et une enceinte
// pleine coute exactement le meme prix qu'une enceinte vide.

uniform float rangees = 12.0;
uniform float places_par_rangee = 432.0;
uniform vec3 couleur_siege : source_color = vec3(0.16, 0.20, 0.34);
uniform vec3 couleur_siege_clair : source_color = vec3(0.62, 0.16, 0.18);
uniform vec3 couleur_beton : source_color = vec3(0.34, 0.34, 0.33);

varying vec2 coordonnee;

float hasard(vec2 graine) {
	return fract(sin(dot(graine, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	coordonnee = UV;
}

void fragment() {
	// Le mur de soutenement, marque par un v negatif, est du beton nu.
	if (coordonnee.y < -0.001) {
		float grain = hasard(floor(coordonnee * vec2(240.0, 40.0)));
		ALBEDO = couleur_beton * (0.88 + grain * 0.18);
		ROUGHNESS = 0.95;
	} else {
		vec2 grille = vec2(coordonnee.x * places_par_rangee, coordonnee.y * rangees);
		vec2 place = floor(grille);
		vec2 dans_la_place = fract(grille);

		// Un couloir d'acces toutes les vingt-quatre places : sans ces coupures,
		// la tribune ressemble a un tissu imprime plutot qu'a des travees.
		float couloir = step(0.94, fract(place.x / 24.0));

		// Le siege ne remplit pas toute sa case : l'ecart laisse voir le beton,
		// et c'est ce liset sombre qui donne le relief des rangees.
		vec2 bord = smoothstep(vec2(0.0), vec2(0.16), dans_la_place)
			* (1.0 - smoothstep(vec2(0.80), vec2(1.0), dans_la_place));
		float siege = bord.x * bord.y * (1.0 - couloir);

		// Deux couleurs par blocs, comme les mosaiques des tribunes. Les blocs
		// sont larges et peu contrastes : un damier serre donnerait un stade en
		// nappe de pique-nique.
		float bloc = step(0.5, fract(floor(place.x / 68.0) * 0.5 + floor(place.y / 7.0) * 0.5));
		vec3 teinte = mix(couleur_siege, mix(couleur_siege, couleur_siege_clair, 0.75), bloc);
		teinte *= 0.86 + hasard(place) * 0.24;

		// Le fond de tribune recoit moins de lumiere du ciel.
		float ombre = mix(0.62, 1.0, coordonnee.y);
		ALBEDO = mix(couleur_beton * 0.55, teinte, siege) * ombre;
		ROUGHNESS = mix(0.95, 0.72, siege);
	}
	SPECULAR = 0.12;
}
