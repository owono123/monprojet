shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Habillage d'un joueur, sans la moindre texture.
//
// Le maillage transporte dans UV2.x un identifiant de zone — peau, maillot,
// short, chaussettes, chaussures, oeil, iris, cheveux, levres, sourcils — et le
// shader choisit la couleur en consequence. Les couleurs arrivent par des
// parametres propres a l'instance : tous les joueurs partagent donc le meme
// materiau en memoire tout en portant des tenues, des teints et des cheveux
// differents. C'est ce qui permet d'afficher vingt-deux joueurs sans
// vingt-deux materiaux.
//
// Les motifs de maillot sont calcules a partir des coordonnees UV du torse, ou
// u fait le tour du buste et v monte du bas vers les epaules. Aucune image
// n'est chargee : changer de motif dans l'editeur ne coutera pas un octet.

instance uniform vec4 couleur_peau : source_color = vec4(0.72, 0.55, 0.42, 1.0);
instance uniform vec4 couleur_maillot : source_color = vec4(0.85, 0.16, 0.18, 1.0);
instance uniform vec4 couleur_maillot_secondaire : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec4 couleur_short : source_color = vec4(0.12, 0.12, 0.14, 1.0);
instance uniform vec4 couleur_chaussettes : source_color = vec4(0.85, 0.16, 0.18, 1.0);
instance uniform vec4 couleur_chaussures : source_color = vec4(0.08, 0.08, 0.09, 1.0);
instance uniform vec4 couleur_cheveux : source_color = vec4(0.12, 0.09, 0.07, 1.0);
instance uniform vec4 couleur_iris : source_color = vec4(0.28, 0.19, 0.12, 1.0);

// 0 uni · 1 rayures verticales · 2 cercles horizontaux · 3 moities
// 4 diagonale · 5 damier · 6 epaules contrastees
instance uniform float motif = 0.0;

varying vec2 coordonnee;
varying float zone;

void vertex() {
	coordonnee = UV;
	// L'identifiant a ete divise par seize a la construction pour rester dans une
	// plage confortable ; on le retablit ici.
	zone = UV2.x * 16.0;
}

// Bascule nette entre deux couleurs, mais lissee sur la largeur d'un pixel.
//
// Un simple step() suffirait a l'oeil de pres ; a quinze metres, les rayures
// d'un maillot deviennent plus fines qu'un pixel et se mettent a moirer des que
// le joueur bouge. On lisse donc la transition sur l'empreinte reelle du pixel.
float bascule(float valeur, float empreinte) {
	float flou = max(empreinte, 0.0005);
	return smoothstep(0.5 - flou, 0.5 + flou, valeur);
}

float part_secondaire(vec2 uv, float lequel) {
	if (lequel < 0.5) {
		return 0.0;                                                // uni
	} else if (lequel < 1.5) {
		return bascule(fract(uv.x * 8.0), fwidth(uv.x) * 8.0);      // rayures verticales
	} else if (lequel < 2.5) {
		return bascule(fract(uv.y * 5.0), fwidth(uv.y) * 5.0);      // cercles horizontaux
	} else if (lequel < 3.5) {
		return bascule(fract(uv.x + 0.25), fwidth(uv.x));           // moities
	} else if (lequel < 4.5) {
		float d = uv.x * 3.0 + uv.y * 2.0;                          // diagonale
		return bascule(fract(d), fwidth(d));
	} else if (lequel < 5.5) {
		float damier = fract(floor(uv.x * 8.0) * 0.5) + fract(floor(uv.y * 5.0) * 0.5);
		return step(0.75, damier) + step(1.4, damier) * -1.0;
	}
	return smoothstep(0.66, 0.74, uv.y);                            // epaules contrastees
}

void fragment() {
	vec3 teinte;
	float rugosite = 0.85;
	float brillance = 0.16;
	float peau = 0.0;

	if (zone < 0.5) {
		teinte = couleur_peau.rgb;
		rugosite = 0.52;
		brillance = 0.35;
		peau = 1.0;
	} else if (zone < 1.5) {
		teinte = mix(couleur_maillot.rgb, couleur_maillot_secondaire.rgb,
			part_secondaire(coordonnee, motif));
		rugosite = 0.88;
	} else if (zone < 2.5) {
		teinte = couleur_short.rgb;
		rugosite = 0.90;
		brillance = 0.14;
	} else if (zone < 3.5) {
		teinte = couleur_chaussettes.rgb;
		rugosite = 0.92;
		brillance = 0.12;
	} else if (zone < 4.5) {
		teinte = couleur_chaussures.rgb;
		rugosite = 0.34;
		brillance = 0.55;
	} else if (zone < 5.5) {
		// Le blanc de l'oeil n'est jamais pur : il tire vers le gris rose, sans
		// quoi le regard devient celui d'une poupee.
		teinte = vec3(0.86, 0.84, 0.82);
		rugosite = 0.18;
		brillance = 0.70;
	} else if (zone < 6.5) {
		teinte = couleur_iris.rgb;
		rugosite = 0.12;
		brillance = 0.85;
	} else if (zone < 7.5) {
		teinte = couleur_cheveux.rgb;
		rugosite = 0.62;
		brillance = 0.30;
	} else if (zone < 8.5) {
		// Les levres sont de la peau plus sombre et plus rouge, pas une couleur
		// posee dessus.
		teinte = couleur_peau.rgb * vec3(0.82, 0.56, 0.54);
		rugosite = 0.40;
		brillance = 0.45;
		peau = 1.0;
	} else {
		teinte = couleur_cheveux.rgb * 0.85;   // sourcils
		rugosite = 0.70;
	}

	ALBEDO = teinte;
	ROUGHNESS = rugosite;
	SPECULAR = brillance;

	// Sur la peau, la lumiere ne s'arrete pas net au bord : elle traverse les
	// premiers millimetres et ressort en rougeoyant. Un vrai calcul de diffusion
	// sous-cutanee est hors de portee du moteur de rendu compatible ; le terme de
	// bordure en donne l'essentiel pour presque rien, et c'est ce qui empeche un
	// visage de ressembler a du plastique.
	RIM = peau * 0.55;
	RIM_TINT = 0.35;
}
