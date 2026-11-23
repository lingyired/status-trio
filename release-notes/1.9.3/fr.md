# Version %VERSION% (Build %BUILD%)

### Réglages

- Interface des réglages entièrement revue : catégories plus claires et plus faciles à trouver ; les réglages liés aux icônes sont regroupés sous « Icône de l’app ».
- Nouvelle page « Luminosité » : choisissez par écran s’il apparaît dans le panneau d’état, et éventuellement BetterDisplay comme backend de luminosité (#241, #239).

### Panneau

- Le volume et la luminosité utilisent désormais un curseur capsule unifié : cliquez ou faites glisser pour régler ; le volume, la luminosité et l’entrée audio prennent aussi en charge la molette (#245, #213, #256).
- Correction d’un pic de CPU bref lors du réglage du volume (#263).
- Hauteur dynamique et barre de défilement du panneau plus stables (#283).
- Nouvelle option « Revenir à la page principale à chaque ouverture » (#262).
- Correction : le panneau d’état ne disparaissait pas lorsqu’on cliquait sur la fenêtre des réglages après avoir ouvert les réglages (#267).
- La ligne de luminosité dispose d’un bouton engrenage pour ouvrir directement les réglages système « Écrans » ; le réglage de la luminosité à la molette s’applique immédiatement.

### Barre des menus et icônes

- Nouvelle option « État de charge à l’intérieur de l’anneau » : l’anneau supérieur reste, et l’icône centrale passe à l’état de charge une fois branché (#253).
- Correction d’une traînée dégradée à gauche lorsque l’animation de charge traverse l’espace supérieur (#254).
- La plaque de base de l’icône du Dock est alignée sur la grille du système et ne paraît plus plus grande que celle des autres apps (#260).

### Batterie et alimentation

- Ajout du mode haute puissance, activable en un clic comme le mode basse consommation (#235).
- Ajout de l’activation automatique du mode basse consommation (#246).

### Wi-Fi et réseau

- La ligne récapitulative Wi-Fi dispose d’un interrupteur (affiché par défaut) ; la désactivation d’un réseau connecté demande confirmation (#252).
- Autorisation du nom Wi-Fi : la page de détails utilise désormais un bouton bien visible et la page Réseau comporte une section d’autorisation en haut ; sans autorisation de localisation, un message s’affiche et l’autorisation peut être accordée directement (#247, #276).
- Correction d’une consommation CPU élevée / d’un blocage après l’ouverture de la page de détails Wi-Fi (#259).

### Bluetooth, Apple Watch et AirPods

- Affichage de la batterie des AirPods amélioré et valeurs croisées corrigées (#248).
- Affichage de la batterie de l’Apple Watch et diagnostics de découverte améliorés (#249).
- Correction : la liste affichait encore des appareils en cache et des badges de connexion après la désactivation du Bluetooth (#265).
- Remarque : les corrections de batterie Bluetooth (AirPods, Apple Watch, etc.) sont toujours en cours et continueront d’être améliorées dans les prochaines versions.

### Installation

- L’installateur utilise par défaut la nouvelle page d’installation par glisser-déposer (instructions bilingues + flèche indicative) (#244).

### Corrections

- Correction d’un problème occasionnel de lecture des pipes à la fermeture d’un processus de surveillance (#268).
- L’interrupteur du mode d’écoute prend désormais aussi effet pour les écouteurs Huawei.
