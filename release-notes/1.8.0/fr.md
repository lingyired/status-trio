# Version %VERSION% (Build %BUILD%)

### Batterie

- Le flux d’énergie de la batterie affiche désormais des estimations de l’entrée du chargeur, de l’énergie envoyée à la batterie et de l’énergie système. L’entrée du chargeur est désactivée par défaut ; les deux autres mesures sont activées.
- Une liste facultative de l’impact énergétique du processeur affiche jusqu’à cinq apps à partir d’échantillons récents. Si les compteurs d’énergie ne sont pas disponibles, elle utilise l’activité du processeur et accepte un intervalle d’échantillonnage de 10 à 60 secondes.
- Sur les Mac compatibles dotés d’une puce Apple et exécutant macOS 26.4 ou ultérieur, Charger jusqu’au maximum et Annuler la charge jusqu’au maximum sont disponibles et activés par défaut lorsque la fonctionnalité est prise en charge.

### Écrans externes

- Un mode de réglage du volume via BetterDisplay a été ajouté pour les écrans externes ou sorties audio dont macOS ne peut pas contrôler directement le volume. Il permet une association automatique ou manuelle de l’écran et indique les états de connexion et d’erreur.
- Le volume natif accessible en écriture reste prioritaire, le mode Standard/DDC peut être restauré à tout moment, et Status Trio ne lance pas BetterDisplay et ne modifie pas ses réglages lorsqu’il est indisponible.

### Stabilité et interface

- La gestion des événements Wi-Fi a été améliorée : les rappels CoreWLAN très fréquents sont regroupés et la fréquence de récupération est limitée dans les états anormaux, ce qui réduit le risque qu’une tempête d’événements amplifie la charge du processeur et de la mémoire.
- Le panneau d’état conserve désormais la page de détails en cours lors de sa réouverture au lieu de revenir à la page principale.
- La disposition des détails de la batterie, la navigation, la zone cliquable du engrenage et l’actualisation de la puissance en direct ont été améliorées.
- La composition de la couche colorée et de l’image modèle dans la barre des menus a été améliorée. Les écrans sans focus s’assombrissent désormais correctement tout en conservant la nouvelle teinte système lors du changement d’espace.

### Remarques importantes

- Charger jusqu’au maximum utilise une interface PowerUI privée et n’est disponible que sur les Mac à puce Apple exécutant macOS 26.4 ou ultérieur. Son comportement n’est pas garanti selon les versions de macOS.
- Une fois la charge terminée ou l’adaptateur secteur reconnecté, la limite de charge peut rester à 100 %. Status Trio ne la restaure pas automatiquement ; utilisez Annuler la charge jusqu’au maximum ou restaurez la limite dans Réglages Système.
- La liste de l’impact énergétique du processeur ne représente pas la consommation totale d’une app et n’est pas une copie de la liste macOS « Utilisation importante d’énergie ».
- Le réglage du volume via BetterDisplay nécessite que BetterDisplay soit en cours d’exécution. Le volume de l’écran et le comportement DDC dépendent toujours du matériel et de la connexion.
