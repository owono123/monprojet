# IA Locale

Assistant informatique pour Android, dont le modele de langage tourne **entierement sur le
telephone**. Aucune conversation n'est envoyee a un serveur, aucune cle API n'est requise,
et l'application fonctionne en mode avion une fois le modele installe.

Cible : Android 9 (API 28) et superieur.

## Ce que c'est, et ce que ce n'est pas

Un modele qui tient dans la memoire d'un telephone fait 1 a 3 milliards de parametres. Il
tient une conversation, explique des notions, ecrit du code simple et relit une
configuration, a environ 2 a 6 mots par seconde sur un appareil ancien. Il n'a pas le
niveau d'un modele de datacenter : il ne remplace pas un audit de securite mene par un
humain et il n'entraine pas d'autres modeles. L'application est concue pour tirer le
maximum de cette taille — mode reflexion multi-passes, profils specialises, contexte web
optionnel — pas pour faire croire le contraire.

Le profil « auditeur » est **defensif** : revue de code, durcissement de configuration,
OWASP, lecture de logs, bonnes pratiques cryptographiques.

## Reseau

L'inference est locale. Deux fonctions seulement touchent Internet :

- le telechargement du modele au premier lancement (une fois) ;
- la recherche web, **desactivee par defaut**, activable dans les reglages.

## Installer l'APK sur le telephone

L'APK est compile par GitHub Actions, pas sur la machine de developpement. Chaque push
met a jour une pre-release `dev`, dont l'adresse ne change pas :

**https://github.com/owono123/monprojet/releases/download/dev/ia-locale.apk**

1. Ouvrir ce lien depuis le navigateur du telephone.
2. Parametres > Securite : autoriser l'installation depuis cette source.
3. Ouvrir le fichier `.apk` telecharge.

Les executions de l'onglet **Actions** conservent aussi l'APK en artefact, si besoin
d'une version precise.

L'APK est signe avec la cle de debogage : il s'installe directement, mais ne peut pas etre
publie sur le Play Store en l'etat.

## Compiler soi-meme

```sh
./gradlew assembleDebug
# app/build/outputs/apk/debug/app-debug.apk
```

Necessite le SDK Android et un JDK 17.

## Fonctionnement

Au premier lancement, l'application mesure la memoire de l'appareil et conseille un
modele. Le telechargement reprend la ou il s'etait arrete en cas de coupure ; un fichier
`.task` recupere par un autre moyen peut aussi etre importe depuis le stockage du
telephone.

Les reglages permettent de changer de modele, de reecrire entierement le prompt systeme,
de choisir un profil (expert, auditeur defensif, developpeur), de regler la temperature,
et d'activer le **mode reflexion** : le modele redige un plan, un brouillon, se relit puis
se corrige. Chaque passe est une generation complete, donc trois passes prennent environ
cinq fois plus de temps qu'une reponse directe — le reglage descend a zero.

Le profil developpeur ecrit chaque fichier dans un bloc annote de son chemin ; le bouton
« Exporter en ZIP » reconstruit alors l'arborescence en archive partageable. Compiler un
APK depuis le telephone n'est pas possible : il n'existe pas de chaine de compilation
Android executable sous Android 9. L'archive est faite pour etre poussee sur un depot, ou
une integration continue produit l'APK — exactement comme ce projet.

## Structure

```
app/src/main/
  java/com/monprojet/ia/
    MainActivity.kt        Activity hote : WebView + pont JavaScript
    bridge/                surface appelee depuis la page (envoi, arret, etat)
    engine/                inference locale (MediaPipe) et reflexion multi-passes
    model/                 catalogue, telechargement et stockage des modeles
    search/                recherche web facultative
    export/                reconstruction et archivage d'un projet
    data/                  reglages, profils, historique des conversations
  assets/web/              interface de chat (HTML/CSS/JS, aucune ressource distante)
.github/workflows/         compilation de l'APK
```

L'interface est une page web embarquee dans les assets. Elle n'a aucun acces reseau ni
fichier : tout passe par le pont Kotlin, seul point de sortie de l'application.
