# Version %VERSION% (Build %BUILD%)

### Batterie

- La page batterie affiche une répartition du flux d'énergie (écran intégré, sortie USB/accessoires et système) et une barre d'énergie en direct facultative. La sortie accessoires est lue depuis les rails du port SMC quand disponible.
- Nouveau réglage « Restaurer la limite après annulation » pour Charger à fond, avec des états plus clairs lorsque macOS lance lui-même la dérogation temporaire.
- Les couleurs de l'icône de batterie peuvent suivre des couleurs d'état personnalisées, avec un choix distinct pour l'indicateur de connexion (éclair, prise ou pourcentage).
- Mode « divisé » facultatif pour l'anneau de batterie : quand l'encoche affiche éclair, prise ou pourcentage, l'arc gauche lit 0–50 % et le droit 50–100 %, donc 40–60 % n'est plus masqué. Désactivé par défaut ; s'applique à la barre des menus et au Dock.

### Énergie

- L'emplacement central peut afficher la puissance totale en direct au lieu de la source de connexion.
- Les Mac sans batterie intégrée peuvent aussi afficher la puissance et ouvrir les détails de batterie.

### Écrans

- Réglage de la luminosité : les écrans externes utilisent le DDC direct, les écrans intégrés sont pilotés via DisplayServices.

### Icône centrale

- La source de l'emplacement central est désormais un sélecteur unique « Icône centrale » : réseau, appareil Bluetooth, source d'entrée actuelle, pourcentage de batterie ou puissance. Les deux interrupteurs d'erreur réseau sont fusionnés en un seul couvrant toutes les sources, l'interrupteur Bluetooth « remplacer l'icône réseau » inopérant disparaît et les anciennes valeurs sont migrées.
- Correction de l'icône centrale qui n'était pas centrée verticalement.

### Guide

- Guide d'introduction amélioré.

### Audio

- Les périphériques d'entrée/sortie peuvent être réordonnés, masqués et limités en nombre.
- Le retour de volume à la molette se règle séparément, et recliquer sur le mode d'écoute sélectionné le désactive.

### Panneau

- Le panneau de statut adopte un style sans coins ni encoche, assorti au panneau de la barre des menus de macOS. Un nouveau menu « … » en bas regroupe les actions courantes (Rechercher les mises à jour, À propos, Réglages de la barre des menus, Quitter) et la taille et la mise en page s'adaptent mieux sous Liquid Glass.

### Corrections

- Les infos Wi-Fi restent affichées sans autorisation de localisation.
