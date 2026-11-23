# Version %VERSION% (build %BUILD%)

### Batterie et alimentation

- Les détails de la batterie incluent désormais la capacité maximale du système, l'état de la batterie, la durée de fonctionnement du système et l'état du mode haute puissance.
- Lorsque « Charge optimisée de la batterie » met la charge en pause à une limite de 100 %, « Charger à fond maintenant » est désormais disponible ; s'il ne l'est pas, les pages de détails et Réglages en expliquent la raison (#292, #280).

### Luminosité et écrans

- Les écrans externes bénéficient d'un backend de luminosité « Automatique » : utilise BetterDisplay tant qu'il tourne, sinon DDC direct.
- Les changements de luminosité de l'écran intégré via les touches, le Centre de contrôle ou les Réglages se reflètent désormais immédiatement dans le panneau (#286).
- Tant que le panneau est ouvert, les réglages de luminosité des écrans externes y sont aussi reflétés rapidement.
- Correction des saccades lors du glissement de la luminosité DDC et identification correcte des écrans externes (#284, #285).

### Wi-Fi et réseau

- La ligne résumé des services VPN système dispose désormais d'un interrupteur d'alimentation ; les connexions TUN de Clash Verge ne s'affichent plus comme « VPN » mais correctement comme « TUN » (avec le nom du client pour Clash Verge), et cette ligne reste en lecture seule sans interrupteur (#272).

### Source d'entrée

- L'indicateur de source d'entrée ABC affiche désormais a/A selon la casse (#279).

### Bluetooth

- Amélioration du problème des appareils fantômes Bluetooth (#248).
- Ajout d'une couleur personnalisée pour l'icône Bluetooth (#275).

### Panneau et réglages

- Meilleur alignement du survol et de la zone cliquable de la ligne des réglages de batterie (#281).
- Affinage de l'affichage des coins du diagramme de flux d'énergie (#282).
- L'intervalle d'actualisation de l'état se règle désormais séparément pour « Sur batterie / Branché sur secteur » (#255).

### Performances et stabilité

- Fréquence d'actualisation en arrière-plan et utilisation des ressources réduites, pour moins de consommation et plus de stabilité (#294).
- Correction de la liste des périphériques de sortie qui ne s'actualisait pas après un changement de périphérique audio (#293).
