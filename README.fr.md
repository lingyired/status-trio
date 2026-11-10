<p align="center">
  <img src="screenshots/status-trio-dock-state-strip-symmetric.png" width="1000" alt="Huit états de l’icône du Dock de Status Trio avec des fonds sombres et clairs disposés symétriquement, incluant les états Wi-Fi, audio Bluetooth, batterie, points et arc">
</p>

<p align="center">
  <img src="Support/AppIcon.png" width="112" alt="Icône de l’app Status Trio">
</p>

<h1 align="center">Status Trio</h1>

<p align="center">
  <a href="https://trendshift.io/repositories/234371?utm_source=trendshift-badge&utm_medium=badge&utm_campaign=badge-trendshift-234371" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/234371/daily?language=Swift" alt="lingyired/status-trio | Trendshift" width="250" height="55"/></a>
</p>

<p align="center"><strong>Trois signaux système. Une seule icône d’état native macOS — dans votre barre des menus ou dans le Dock.</strong></p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-Universal%20%C2%B7%20macOS%2013%20target-000000?logo=apple&logoColor=white&style=for-the-badge" alt="Télécharger pour macOS — version universelle, macOS 13 comme cible de déploiement (validation Ventura en attente)"></a>
</p>

<p align="center">
  Vous voulez d’abord le voir en action ? Ouvrez <a href="https://statustrio.lingai.net/">statustrio.lingai.net</a> pour simuler chaque état de l’icône dans votre navigateur.
</p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/github/v/release/lingyired/status-trio?label=release&color=blue" alt="Dernière version"></a>
  <a href="https://github.com/lingyired/status-trio/actions/workflows/release.yml"><img src="https://github.com/lingyired/status-trio/actions/workflows/release.yml/badge.svg" alt="État du workflow Build and Release macOS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lingyired/status-trio?label=license" alt="Licence : Apache-2.0"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%20target%20%28validation%20pending%29-blue?logo=apple&logoColor=white" alt="macOS 13 comme cible de déploiement (validation Ventura en attente) pris en charge">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="Binaire universel pour Apple Silicon et Intel">
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a> ·
  <strong>Français</strong> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português (Brasil)</a> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="screenshots/menu-bar-wifi.jpg" width="1000" alt="Icône de Status Trio dans la barre des menus affichant le glyphe Wi-Fi pendant une connexion Wi-Fi, avec son panneau d’état ouvert">
</p>

Status Trio est une app d’état native macOS qui réunit le Wi-Fi, la batterie et le volume dans une seule icône compacte et configurable, affichée dans la barre des menus, dans le Dock, ou dans les deux. Son panneau d’état va plus loin que l’icône : un panneau Wi-Fi pour les réseaux à proximité et les détails de la liaison, un panneau Bluetooth pour les appareils jumelés, une page Détails de la batterie, et les appareils audio en cours de lecture. Elle s’inspire de l’icône combinée de la barre d’état de l’iPhone Duo pour le Wi-Fi, la batterie et les données cellulaires, adaptée au Mac avec le volume à la place des données cellulaires.

> Status Trio est un projet indépendant et n’est pas affilié à Apple.

## Points forts

- **Une icône, trois signaux** — la batterie, le Wi-Fi et le volume partagent une seule icône dans la barre des menus, dans le Dock ou dans les deux, et un appareil Bluetooth en cours de lecture peut occuper la place centrale avec son propre symbole.
- **Bluetooth** — l’indicateur de volume devient bleu pendant la lecture. Le panneau répertorie les appareils jumelés sur lesquels vous cliquez pour les connecter ou les déconnecter, affiche les niveaux de batterie par défaut, et reste désactivé tant que vous ne l’activez pas.
- **Batterie** — pourcentage, en charge ou sur secteur, temps avant charge complète, et une couleur lorsque la batterie devient faible. Ouvrez la ligne pour la puissance de l’adaptateur, la tension, le courant, le nombre de cycles et le mode économie d’énergie.
- **Wi-Fi** — le réseau sur lequel vous êtes et la force du signal. Ouvrez-le pour voir les réseaux à proximité, consulter les détails de la liaison, ou désactiver le Wi-Fi. Le changement de réseau se fait dans le panneau Wi-Fi des Réglages Système.
- **Volume** — niveau, sourdine et périphérique de sortie, dessinés sous forme de points ou d’un arc. Faites défiler tout le panneau ou seulement le réglage du volume, et choisissez le sens qui augmente le volume.
- **Personnalisez-le** — taille de l’icône, échelle des symboles, épaisseur de l’anneau, couleurs d’état et éléments affichés dans le panneau d’état, dans l’ordre de votre choix.
- **Barre des menus, Dock, ou les deux** — et l’icône du Dock peut suivre le style du système ou rester sombre ou claire.
- **Natif sur macOS** — un clic gauche ouvre le panneau d’état, un clic droit ouvre le menu, et un guide du premier lancement explique chaque partie de l’icône. Ethernet, un partage de connexion ou le partage Internet peuvent conserver le glyphe Wi-Fi si vous préférez.
- **Toujours à jour** — l’état provient des événements système avec une interrogation lente en secours, et Sparkle met à jour l’app via un flux signé.
- **Également inclus** — douze langues et un lancement à l’ouverture de session facultatif.

## Installation

Installez le Cask officiel Homebrew :

```bash
brew install --cask status-trio
```

Pour mettre à jour une installation Homebrew :

```bash
brew upgrade --cask status-trio
```

Ou téléchargez le dernier `StatusTrio-*.dmg` depuis [GitHub Releases](https://github.com/lingyired/status-trio/releases/latest), ouvrez-le et glissez `Status Trio.app` dans `/Applications`.

La version officielle est signée avec Developer ID et notarisée par Apple. Ouvrez-la normalement après installation, sans supprimer les attributs de quarantaine. Les mises à jour intégrées utilisent Sparkle et la vérification des signatures EdDSA.

## Commandes de saisie et audio

- **Icône de saisie** : affichez la source de saisie actuelle au centre de l’icône dans la barre des menus et le Dock. Sélectionnez-la dans **Réglages › Réseau** ; sélectionnez une source activée dans le panneau pour l’utiliser.
- **Raccourci global** : attribuez un raccourci dans **Réglages › Général** pour ouvrir ou fermer le panneau depuis une autre app. Aucun n’est attribué par défaut.
- **Commandes Bluetooth** : activez ou désactivez Bluetooth, connectez ou déconnectez les appareils et changez le mode d’écoute des AirPods et HUAWEI FreeBuds compatibles. Les lignes facultatives de batterie Apple se configurent dans les réglages Bluetooth ; leur disponibilité dépend de l’appareil et de la connexion.
- **Entrée et sortie audio** : choisissez les haut-parleurs ou microphones et réglez leurs niveaux. Les haut-parleurs d’écrans externes compatibles sont contrôlés par DDC, selon le matériel et la connexion.
- **Charge et apparence** : effets de charge dans la barre des menus et le Dock. Sous macOS 26 ou ultérieur, l’icône dans Finder et Launchpad suit aussi l’apparence claire ou sombre du système.

## Nouveautés sur main (non publiées)

Ces fonctions sont dans le code de `main`, mais pas dans la version publique actuelle GitHub / Homebrew, **1.7.5** :

- **Flux de puissance et impact énergétique CPU** : estimations de l’entrée du chargeur, de la charge de la batterie et de la puissance système. Une liste facultative classe jusqu’à cinq apps selon leur énergie CPU, ou leur activité CPU si les compteurs manquent. Ce n’est ni la consommation totale ni la liste native de macOS. L’activer lance un échantillonnage périodique en arrière-plan ; la désactiver l’arrête. [Détails](docs/battery-power-flow.md).
- **Charger complètement et annuler** : option désactivée par défaut sur les Mac Apple Silicon compatibles sous macOS 26.4 ou ultérieur. Elle utilise une interface privée PowerUI pour lever la limite. **La limite peut rester à 100 % après la charge ou le rebranchement ; elle n’est pas restaurée automatiquement.** Annulez pour demander sa restauration, ou vérifiez-la et rétablissez-la dans Réglages Système. Le comportement dépend de macOS. [Comportement et vérification](docs/charge-to-full-now-poc.md).

## Audio Bluetooth

Pendant la lecture audio en Bluetooth, deux options sous **Réglages › Bluetooth** permettent au glyphe central de devenir le symbole propre à cet appareil — les AirPods, les casques, les haut-parleurs et d’autres appareils fournissent le leur — et aux points de volume ou à l’arc de devenir bleus. Les deux sont désactivées par défaut. **Donner la priorité aux erreurs réseau**, activée par défaut, conserve l’icône réseau lorsque la connexion elle-même rencontre un problème :

<p align="center">
  <img src="screenshots/menu-bar-airpods.jpg" width="1000" alt="Icône de Status Trio dans la barre des menus affichant le glyphe AirPods pendant que des AirPods sont connectés, avec son panneau d’état ouvert">
</p>

La ligne Bluetooth du panneau d’état indique l’état en direct : les noms des appareils connectés et, pour les AirPods, la batterie gauche, droite et du boîtier. Le panneau Bluetooth répertorie les appareils jumelés et leur état de connexion : cliquez sur un appareil pour le connecter, sur un appareil connecté pour le déconnecter — les claviers, les souris, les trackpads et les manettes de jeu demandent d’abord une confirmation dans la ligne. Le panneau est désactivé par défaut, s’active sous **Réglages › Panneau d’état**, et demande l’autorisation Bluetooth à la première utilisation. **Réglages › Bluetooth** contrôle aussi la lecture des niveaux de batterie, répertorie les appareils jumelés pour que vous puissiez les faire glisser afin de modifier leur ordre et fixer combien s’affichent, et ajuste l’échelle de l’icône Bluetooth de 100 % à 180 %.

## Icône du Dock

La même icône dynamique peut résider dans le Dock au lieu de la barre des menus, ou dans les deux à la fois :

<p align="center">
  <img src="screenshots/status-trio-dock-dark-1440x810.jpg" width="880" alt="Icône dynamique de Status Trio dans le Dock en apparence sombre">
  <br>
  <sub>Icône du Dock en apparence sombre</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-1440x810.jpg" width="880" alt="Icône dynamique de Status Trio dans le Dock en apparence claire">
  <br>
  <sub>Icône du Dock en apparence claire</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-bt-1440x810.jpg" width="880" alt="Status Trio dans le Dock avec le panneau Bluetooth affiché, apparence claire">
  <br>
  <sub>Aperçu du panneau Bluetooth</sub>
</p>

L’icône du Dock dessine la même icône combinée que la barre des menus ; ainsi, lorsque le remplacement par l’audio Bluetooth est activé, le glyphe de l’appareil y occupe lui aussi la place centrale. Son fond peut suivre le style d’icône du système ou être fixé à une teinte déterminée :

<p align="center">
  <img src="screenshots/status-trio-dock-icons.png" width="880" alt="Icône du Dock de Status Trio sur fonds sombre, clair et transparent, en deux rangées : l’état Wi-Fi et l’audio Bluetooth remplaçant l’icône Wi-Fi avec des points de volume bleus">
</p>

## États de l’icône

Tous les états que l’icône combinée peut afficher, dessinés par le moteur de rendu de l’app — les indicateurs de batterie en haut, le Wi-Fi (ou l’appareil audio Bluetooth qui peut le remplacer, lorsque cette option est activée) au centre, et les points de volume ou l’arc en bas, qui deviennent bleus pendant la lecture d’un appareil Bluetooth :

<p align="center">
  <img src="screenshots/status-trio-icon-states.png" width="880" alt="États de l’icône Status Trio : charge, sur secteur, pourcentage, batterie faible et mode économie d’énergie en haut ; signal Wi-Fi, partage de connexion, temporaire, partagé et filaire au centre ; audio Bluetooth remplaçant l’icône Wi-Fi, conservation du Wi-Fi pendant une erreur réseau, et points de volume bleus et arc juste en dessous ; styles de points et d’arc de volume pour chaque niveau en bas">
</p>

Les mêmes états rendus pour une barre des menus sombre :

<p align="center">
  <img src="screenshots/status-trio-icon-states-dark.png" width="880" alt="Les mêmes états de l’icône Status Trio en apparence sombre : glyphes blancs sur pastilles sombres, charge en vert, batterie faible en rouge et accents jaunes du mode économie d’énergie, et le bleu plus vif que l’app utilise pour l’audio Bluetooth sur une barre des menus sombre">
</p>

## Configuration requise

- macOS 13 comme cible de déploiement (validation Ventura en attente) pour exécuter l’app
- Une chaîne d’outils Swift 6 avec le SDK macOS 26 (Xcode 26 ou version ultérieure) pour la compiler. Compiler avec un
  SDK plus ancien produit silencieusement l’apparence de popover antérieure à Tahoe, c’est pourquoi `scripts/build-app.sh` échoue
  lorsque le SDK est antérieur à 26.

## Exécuter depuis les sources

```bash
git clone https://github.com/lingyired/status-trio.git
cd status-trio
swift run StatusTrio
```

## Compiler une app locale

Compilez un paquet d’app signé ad hoc et lancez-le :

```bash
bash scripts/build-app.sh release
```

Le paquet est créé dans `dist/StatusTrio.app`. Pour compiler sans quitter une instance existante ni en lancer une, exécutez :

```bash
bash scripts/build-app.sh release no-open
```

Le paquet signé ad hoc est destiné à un usage personnel local. Gatekeeper peut le rejeter si le paquet est transféré avec des métadonnées de quarantaine.

## Utilisation

- **Clic gauche** sur l’icône de la barre des menus ou sur l’icône du Dock pour ouvrir le panneau d’état.
- **Clic droit** sur l’une ou l’autre icône pour le menu natif, avec la version et l’action Quitter.
- Sélectionnez la ligne Wi-Fi ou la ligne de batterie dans le panneau d’état pour ouvrir sa page : les réseaux à proximité et les détails de la liaison, ou les Détails de la batterie. La ligne Bluetooth répertorie ses appareils jumelés sur place — cliquez sur l’un d’eux pour le connecter ou le déconnecter — avec un contrôle Développer lorsqu’ils ne tiennent pas tous.
- Ouvrez les **Réglages** pour choisir où l’icône s’affiche (barre des menus, Dock, ou les deux) et pour modifier sa taille, ses couleurs, l’épaisseur de l’anneau, les éléments du panneau d’état et leur ordre, le réglage du volume en défilant, la langue, la recherche de mises à jour et le lancement à l’ouverture de session.
- Rouvrez le guide **Découvrez votre icône** à tout moment depuis **Réglages › Icône de l’app › Ouvrir le guide**.
- Autorisez l’affichage du nom du réseau Wi-Fi actuel lorsque vous y êtes invité ; macOS demande l’accès à la localisation pour ce détail facultatif.

## Limitations connues

Deux limites que macOS et ce projet tracent délibérément. Les deux sont expliquées dans [Limitations connues](docs/known-limitations.md).

- **Le changement de réseau se fait dans les Réglages Système.** Choisir un réseau dans le panneau d’état ouvre le panneau Wi-Fi ; Status Trio ne lit ni ne stocke jamais les mots de passe Wi-Fi, car macOS n’offre aucune API publique pour se connecter avec un mot de passe enregistré et toutes les alternatives finissent par obliger l’app à les conserver.
- **Le contrôle de la limite de charge dépend de la version.** La version 1.7.5 renvoie aux Réglages Système. L’option de `main` utilise une interface privée et exige une annulation explicite pour demander la restauration. [Détails](docs/charge-to-full-now-poc.md). Le mode économie d’énergie utilise un [helper privilégié facultatif](docs/privileged-helper.md) distinct.

## Langues

Status Trio suit par défaut la langue préférée de macOS et inclut English, 简体中文, 繁體中文, 日本語, 한국어, Español, Français, Deutsch, Italiano, Português (Brasil), Русский et العربية.

## Confidentialité

Status Trio lit l’état système localement. Les statistiques anonymes ne sont envoyées au service propriétaire que si vous les activez ; elles sont désactivées lors d’une mise à niveau et proposées à la première installation. Elles contiennent un ID aléatoire, les versions de l’app et de macOS, la langue et l’emplacement de l’icône, sans noms, comptes, détails réseau ni identifiants matériels. Voir [télémétrie et confidentialité](docs/privacy-telemetry.md). L’app ne lit ni ne stocke les mots de passe Wi-Fi et ne demande pas le Trousseau. La localisation est facultative pour le nom et les détails Wi-Fi ; Bluetooth est demandé à l’activation de son panneau. Sur `main`, la commande facultative de charge complète utilise une interface privée PowerUI uniquement lorsqu’elle est activée ; ses limites sont précisées plus haut.

## Développement

Exécutez la suite de tests :

```bash
bash scripts/verify-local.sh quick BatteryMonitorTests
bash scripts/verify-local.sh docs
bash scripts/verify-local.sh full
```

Exécutez un filtre XCTest ciblé via le script auxiliaire :

```bash
bash scripts/test.sh BatteryMonitorTests
```

Pour compiler une app de worktree à côté de l’installation principale :

```bash
bash scripts/build-worktree.sh release
```

Le script dérive un identifiant de paquet de développement et un nom d’affichage à partir de la branche actuelle. Les deux valeurs peuvent être remplacées :

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

Le verrou d’instance unique est propre à l’identifiant de paquet, de sorte que des compilations dotées d’identifiants différents peuvent s’exécuter en même temps.

## Base technique

- Swift 6
- SwiftUI + AppKit
- macOS 13 deployment target (Ventura runtime validation pending)
- `LSUIElement`, accessoire de la barre des menus qui bascule vers une politique d’activation standard pendant que l’icône du Dock est affichée
- Sparkle pour la recherche de mises à jour

## Documentation

- [Limitations connues](docs/known-limitations.md)
- [Publications automatisées avec GitHub Actions](docs/github-actions-release.md)
- [Spécification de conception de Status Trio](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [SVG de l’icône de la barre des menus](status-menubar.svg)
- [Démonstration d’icône pilotée par les données](status-menubar-demo.html)

## Licence

Copyright 2026 lingyired.

Sous licence Apache License, Version 2.0. Voir [LICENSE](LICENSE) et [NOTICE](NOTICE).

## Auteur

Créé et maintenu par [lingyired](https://github.com/lingyired).<br>
Site web : [https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
