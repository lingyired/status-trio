# Version %VERSION% (Build %BUILD%)

### Batterie

- La page batterie affiche une répartition du flux d'énergie (écran intégré, sortie USB/accessoires et système) et une barre d'énergie en direct facultative. La sortie accessoires est lue depuis les rails du port SMC quand disponible.
- Nouveau réglage « Restaurer la limite après annulation » pour Charger à fond, avec des états plus clairs lorsque macOS lance lui-même la dérogation temporaire.
- Les couleurs de l'icône de batterie peuvent suivre des couleurs d'état personnalisées, avec un choix distinct pour l'indicateur de connexion (éclair, prise ou pourcentage).
- Mode « divisé » facultatif pour l'anneau de batterie : quand l'encoche affiche éclair, prise ou pourcentage, l'arc gauche lit 0–50 % et le droit 50–100 %, donc 40–60 % n'est plus masqué. Désactivé par défaut ; s'applique à la barre des menus et au Dock.

### Énergie

- L'emplacement central peut afficher la puissance totale en direct au lieu de la source de connexion ; les Mac sans batterie intégrée sont pris en charge.

### Écrans

- Réglage de la luminosité : les écrans externes utilisent le DDC direct, les écrans intégrés sont pilotés via DisplayServices.

### Audio

- Les périphériques d'entrée/sortie peuvent être réordonnés, masqués et limités en nombre.
- Le retour de volume à la molette se règle séparément, et recliquer sur le mode d'écoute sélectionné le désactive.

### Panneau

- Le panneau de statut adopte un style sans coins ni encoche, ajoute un menu « plus » en bas et adapte mieux taille et mise en page sous Liquid Glass.

### Corrections

- Les infos Wi-Fi restent affichées sans autorisation de localisation.
