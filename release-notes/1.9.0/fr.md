# Version %VERSION% (Build %BUILD%)

### Batterie

- Mode « divisé » facultatif pour l'anneau de batterie : quand l'encoche affiche éclair, prise ou pourcentage, l'arc gauche lit 0–50 % et le droit 50–100 %, donc 40–60 % n'est plus masqué. Désactivé par défaut ; s'applique à la barre des menus et au Dock.
- Les couleurs de l'icône de batterie peuvent suivre des couleurs d'état personnalisées, avec un choix distinct pour l'indicateur de connexion (éclair, prise ou pourcentage). Barre des menus et Dock partagent une même scène.
- La page batterie affiche une répartition du flux d'énergie (écran intégré, sortie USB/accessoires et système) et une barre d'énergie en direct facultative. La sortie accessoires est lue depuis les rails du port SMC quand disponible.
- Nouveau réglage « Restaurer la limite après annulation » pour Charger à fond, avec des états plus clairs lorsque macOS lance lui-même la dérogation temporaire.

### Énergie

- L'emplacement central peut afficher la puissance totale en direct au lieu de la source de connexion ; les Mac sans batterie intégrée sont pris en charge.

### Écrans

- Réglage de la luminosité : les écrans externes utilisent le DDC direct, les écrans intégrés sont pilotés via DisplayServices, donc BetterDisplay n'est plus nécessaire pour l'écran interne.
- Dans le diagramme de flux, la hauteur de chaque carte suit sa part, quel que soit le nombre de branches.

### Audio

- Les périphériques d'entrée/sortie peuvent être réordonnés, masqués et limités en nombre. Un seul appareil compatible mode d'écoute conserve ses boutons de réduction de bruit même si d'autres sorties sont masquées.
- Le retour de volume à la molette se règle séparément, et recliquer sur le mode d'écoute sélectionné le désactive.

### Panneau

- Le panneau de statut adopte un style sans coins ni encoche, ajoute un menu « plus » en bas et adapte mieux taille et mise en page sous Liquid Glass. Dans l'ordre par défaut, « Luminosité de l'écran » est sous « Entrée audio ».

### Corrections

- Redémarrer pendant Charger à fond conserve la limite de restauration calculée au départ au lieu de revenir à 100 %.
- Fermer le panneau libère l'échantillonnage de la barre d'énergie ; l'icône n'échantillonne toutes les 2 s que lorsqu'elle affiche l'énergie.
- Basculer la barre d'énergie panneau ouvert utilise immédiatement la nouvelle valeur.
- Une répartition d'énergie batterie vérifiée n'est plus perdue au débranchement.
- Le branchement à chaud d'un écran actualise la liste de luminosité et abandonne la connexion DDC obsolète.
- Une écriture DDC non confirmée affiche « indisponible » au lieu de perdre le curseur et l'explication.
- Les infos Wi-Fi restent affichées sans autorisation de localisation.
