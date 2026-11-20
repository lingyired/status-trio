# Version %VERSION% (Build %BUILD%)

### Moniteur système

- Le panneau d'état surveille désormais le CPU, le GPU, la mémoire, le réseau, le disque et la vitesse du ventilateur ; cliquez pour ouvrir la page de détail correspondante.
- Couleurs personnalisées pour les indicateurs CPU, GPU, mémoire, réseau, disque et vitesse du ventilateur.
- Personnalisez l'intervalle de mise à jour et la durée de l'historique.
- Le moniteur système échantillonne à la demande : les valeurs ne sont lues que lorsqu'elles sont affichées, et l'historique en arrière-plan est désactivé par défaut, ce qui réduit la charge de fond.

### Icône de barre des menus et anneau

- Nouvelles sources de données du moniteur système pour l'anneau extérieur, avec disposition en anneau unique ou double anneau gauche/droite. Les arcs peuvent utiliser l'utilisation CPU, la température CPU, l'utilisation GPU, la température GPU, l'utilisation mémoire, la température de la batterie, le niveau de batterie, la vitesse du ventilateur, les débits descendant/montant, le volume et le signal Wi-Fi.
- L'arc du niveau de batterie suit les couleurs système de la batterie ; un nouveau rôle de couleur « Décharge (non branché) » permet de personnaliser séparément les couleurs charge, faible, haute puissance, critique et décharge (#357).
- Nouveau mode AirPods pour l'indicateur supérieur : les doubles anneaux peuvent afficher la batterie des écouteurs gauche et droit (un seul écouteur pris en charge) et basculent sur la batterie du Mac ou un anneau personnalisé en cas de déconnexion.
- L'indicateur inférieur prend en charge une source de données personnalisée : volume, signal Wi-Fi ou niveau de batterie (ou masqué).

### Panneau et interactions

- Survolez l'icône de la barre des menus pour afficher le panneau ; cliquez pour l'épingler (#355).
- Les détails s'ouvrent désormais dans un panneau latéral à côté du panneau d'état, avec une transition plus fluide.
- Ajout de la carte de moniteur matériel.
- Les curseurs numériques (volume, luminosité) ont été raffinés pour se rapprocher de macOS 26+ avec un mouvement plus fluide ; ils répondent au balayage horizontal du trackpad (#351).
- Les icônes Wi-Fi et Bluetooth sont teintées selon l'état de connexion (#352).
- Le bouton « Charger à fond maintenant » bénéficie d'un reflet liquid glass au survol.
- Suppression du gras dans le panneau d'état ; les valeurs et unités utilisent une police à chasse fixe.

### Maintien en éveil et veille

- Ajout de « Garder l'écran allumé » et « Pas de veille capot fermé », chacun avec une durée personnalisable (#295).

### Luminosité

- Nouveau réglage « Utiliser la luminosité combinée BetterDisplay » (#344).

### Batterie et audio

- Correction du texte et de la ligne de charge d'entretien à 100 %.
- Correction de la coupure du son à volume exactement nul et de la restauration de la sourdine automatique.
- Correction de l'estimation « temps avant charge complète » pour respecter la limite de charge de macOS (#349).

### Autres corrections

- L'historique des détails du moniteur est désormais isolé par type d'indicateur.
- Amélioration de l'échantillonnage en arrière-plan et de la stabilité des pipes de processus, moins de saccades et d'interférences.
- Correction du clignotement de hauteur de la ligne du mode d'écoute AirPods à l'ouverture du panneau (#354).
