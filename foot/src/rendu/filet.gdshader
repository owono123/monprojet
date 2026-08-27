shader_type spatial;
render_mode cull_disabled, diffuse_lambert, depth_prepass_alpha;

// Filet de but : une grille dessinee dans le pixel, pas une texture.
//
// On utilise un seuil d'opacite (le pixel est garde ou jete) plutot qu'une vraie
// transparence : le tri des surfaces transparentes coute cher sur un telephone,
// et un filet n'a pas besoin de degrade.

uniform vec3 couleur : source_color = vec3(0.88, 0.89, 0.90);
uniform float maille = 0.12;      // cote d'une maille, en metres
uniform float epaisseur = 0.005;  // epaisseur du fil

varying vec2 coordonnee;

void vertex() {
	// L'UV porte deja des metres : la maille garde la meme taille sur tous les
	// pans du filet, quelle que soit leur dimension.
	coordonnee = UV;
}

void fragment() {
	vec2 cellule = abs(fract(coordonnee / maille) - 0.5) * maille;
	float distance_fil = min(cellule.x, cellule.y);
	float flou = fwidth(distance_fil) + 0.0005;
	float fil = 1.0 - smoothstep(epaisseur - flou, epaisseur + flou, distance_fil);

	// De loin, un pixel couvre plusieurs mailles. Garder le motif ferait
	// scintiller le filet a chaque mouvement de camera : selon que le centre du
	// pixel tombe sur un fil ou sur un trou, il passe du blanc au vide. On
	// bascule donc progressivement vers la couverture MOYENNE du filet, qui est
	// la reponse juste quand le motif n'est plus resolvable.
	float couverture_moyenne = 1.0 - pow(1.0 - 2.0 * epaisseur / maille, 2.0);
	float empreinte_pixel = fwidth(coordonnee.x) + fwidth(coordonnee.y);
	float fondu = smoothstep(epaisseur * 2.0, maille * 0.5, empreinte_pixel);

	ALPHA = mix(fil, couverture_moyenne, fondu);
	ALBEDO = couleur;
	ROUGHNESS = 0.75;
}
