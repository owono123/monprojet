# Foot 2026

Jeu de football pour Android, en Godot 4. Hors-ligne, sans publicite, sans
micro-transaction, sans compte, sans connexion requise — jamais.

Cible : Samsung Galaxy Note 8 (Android 9, Exynos 8895 / Snapdragon 835) a
60 images par seconde, en paysage.

## Installer sur le telephone

L'APK est compile par GitHub Actions, pas sur une machine de developpement.
Chaque envoi met a jour une pre-release dont l'adresse ne change pas :

**https://github.com/owono123/monprojet/releases/download/dev-foot/foot2026.apk**

1. Ouvrir ce lien depuis le navigateur du telephone.
2. Parametres > Securite : autoriser l'installation depuis cette source.
3. Ouvrir le fichier `.apk` telecharge.

## Ou en est le jeu

**Phase 0 — la chaine de compilation.** Terrain aux dimensions reglementaires
(105 x 68 m), ballon avec physique complete, un joueur pilotable au joystick
tactile, camera de retransmission, compteur d'images par seconde. C'est peu de
jeu, mais cela prouve que tout le reste est possible : un APK part d'ici et
tourne sur le telephone.

Les phases suivantes ajoutent le match a onze contre onze, les regles, l'image
(corps et visages fabriques par le code), l'editeur, les competitions, le
deux joueurs en reseau local, les replays et le son.

## Contenu

Le jeu ne contient aucun nom, blason, maillot sponsorise, logo de competition
ni visage de joueur reel, et aucun fichier extrait d'un autre jeu. Ce n'est pas
un oubli a combler plus tard : distribuer ce contenu serait de la contrefacon.

A la place, le jeu embarque un editeur complet et un import de fichier JSON ou
CSV. Les effectifs sont engendres par le code pour qu'aucune equipe ne soit
vide, et tout — noms, couleurs, maillots, visages, stades — se modifie dans le
jeu. Ce que l'utilisateur met ensuite dans son propre fichier, sur son propre
appareil, ne regarde que lui.

## Architecture

La contrainte la plus structurante n'est pas graphique : c'est le **deux joueurs
en reseau local**. Elle impose, des la premiere ligne, une simulation
deterministe a pas fixe separee du rendu. La poser apres coup obligerait a tout
reecrire ; posee d'emblee, elle donne gratuitement les replays.

```
src/
  noyau/        simulation pure — ignore l'affichage, pas fixe de 1/60 s,
                aucun appel a randf(), commandes serialisables en 4 octets
  rendu/        terrain, buts, filets, ballon : tout est fabrique par le code,
                aucun modele ni texture importes
  interface/    joystick virtuel, boutons, compteur d'images par seconde
tests/          determinisme, physique, serialisation, captures d'image
```

Trois regles tenues sans exception dans `noyau/` :

1. pas de temps **fixe** — jamais de delta variable, sinon deux appareils qui
   n'affichent pas au meme rythme divergent ;
2. **aucun** `randf()` — tout tirage passe par un generateur a graine explicite ;
3. aucune reference a un `Node`, une texture ou une camera.

## Developper

Godot n'a pas besoin d'etre ouvert : les scenes (`.tscn`), les ressources et les
scripts sont des fichiers texte. Le projet s'ecrit donc entierement au clavier
et se compile par integration continue.

```sh
GODOT=/chemin/vers/Godot_v4.7.2-stable_linux.x86_64

# Enregistrer les classes globales (une fois, et apres tout nouveau fichier)
$GODOT --headless --path foot --import

# Tests du noyau : determinisme, ballon, commandes
$GODOT --headless --path foot --script res://tests/test_noyau.gd

# Captures de controle, en rendu logiciel — sans carte graphique ni telephone
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a $GODOT --path foot \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --resolution 1280x720 res://tests/capture.tscn -- foot/captures
```

## Moteur de rendu

Le projet demande le rendu `mobile` (Vulkan) avec repli automatique sur
`gl_compatibility` (OpenGL ES 3.0). Le compteur affiche en haut de l'ecran
lequel des deux tourne reellement, ainsi que le minimum d'images par seconde sur
la derniere minute — un telephone donne toujours de beaux chiffres a froid et
ralentit apres dix minutes de jeu, et c'est ce minimum-la qui compte.
