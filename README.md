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

L'APK est compile par GitHub Actions, pas sur la machine de developpement.

1. Ouvrir l'onglet **Actions** du depot, choisir la derniere execution reussie.
2. Telecharger l'artefact `ia-locale-apk` (ou, sur une version taguee `v*`, prendre l'APK
   joint a la **Release** — c'est le plus simple depuis le navigateur du telephone).
3. Sur le telephone : Parametres > Securite > autoriser l'installation depuis cette source,
   puis ouvrir le fichier `.apk` telecharge.

L'APK est signe avec la cle de debogage : il s'installe directement, mais ne peut pas etre
publie sur le Play Store en l'etat.

## Compiler soi-meme

```sh
./gradlew assembleDebug
# app/build/outputs/apk/debug/app-debug.apk
```

Necessite le SDK Android et un JDK 17.

## Structure

```
app/src/main/
  java/com/monprojet/ia/
    MainActivity.kt        Activity hote : WebView + pont JavaScript
    bridge/                surface appelee depuis la page (envoi, arret, etat)
    engine/                moteur d'inference local
  assets/web/              interface de chat (HTML/CSS/JS, aucune ressource distante)
.github/workflows/         compilation de l'APK
```

L'interface est une page web embarquee dans les assets. Elle n'a aucun acces reseau ni
fichier : tout passe par le pont Kotlin, seul point de sortie de l'application.
