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

### Icône centrale

- La source de l'emplacement central est désormais un sélecteur unique « Icône centrale » : réseau, appareil Bluetooth, source d'entrée actuelle, pourcentage de batterie ou puissance. Les deux interrupteurs d'erreur réseau sont fusionnés en un seul couvrant toutes les sources, l'interrupteur Bluetooth « remplacer l'icône réseau » inopérant disparaît et les anciennes valeurs sont migrées.
- Les sources de l'icône centrale sont maintenant des tuiles d'image qui prévisualisent le rendu réel. Une seule « Taille de l'icône centrale » pilote Wi‑Fi, Bluetooth, source d'entrée et nombres, et les options de style de l'icône réseau ont été déplacées sur cette page.
- L'aperçu affiche l'état de charge, le contenu central est désormais centré verticalement sur l'anneau de batterie et le texte est légèrement plus petit que les symboles.

### Guide

- Guide remanié : la fenêtre prend la hauteur de la page la plus grande et ne change plus de taille entre les étapes ; les aperçus partagent une surface, les légendes nomment l'arc supérieur, l'icône centrale et les points inférieurs, des exemples d'emplacement central (pourcentage, puissance, source d'entrée) sont ajoutés et le bloc de consentement est plus compact.

### Réglages

- Tous les menus contextuels des Réglages utilisent une largeur commune et ne changent plus avec leurs options ou la liste des appareils, tout en conservant l'apparence native.

### Audio

- Les périphériques d'entrée/sortie peuvent être réordonnés, masqués et limités en nombre.
- Le retour de volume à la molette se règle séparément, et recliquer sur le mode d'écoute sélectionné le désactive.

### Panneau

- Le panneau de statut adopte un style sans coins ni encoche, ajoute un menu « plus » en bas et adapte mieux taille et mise en page sous Liquid Glass.

### Corrections

- Les infos Wi-Fi restent affichées sans autorisation de localisation.
