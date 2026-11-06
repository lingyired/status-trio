# Version %VERSION% (build %BUILD%)

### Batterie et alimentation

- Les détails de la batterie affichent désormais la capacité maximale du système, l'état de la batterie et la durée de fonctionnement du système.
- Le mode haute puissance apparaît maintenant toujours sur sa propre ligne claire dans les détails, en lisant son état depuis pmset ; les états de santé et de haute puissance inconnus sont affichés explicitement.
- Lorsque « Charge optimisée de la batterie » met la charge en pause à une limite de 100 %, « Charger à fond maintenant » fonctionne : la demande est envoyée comme le fait macOS, et une fois terminée, elle ne rétablit pas l'ancienne limite de charge (#292).
- Les pages de détails et Réglages expliquent désormais pourquoi « Charger à fond maintenant » est indisponible ou masqué (#280, #292).
- Les Réglages expliquent qu'une limite de 100 % peut tout de même mettre la charge en pause à cause de la charge optimisée (#292).

### Luminosité et écrans

- Les écrans externes bénéficient d'un backend de luminosité Automatique : utilise BetterDisplay tant qu'il tourne, sinon DDC direct ; un backend choisi explicitement est mémorisé et jamais écrasé.
- Les changements de luminosité de l'écran intégré via les touches, le Centre de contrôle ou les Réglages sont désormais reflétés immédiatement dans le panneau (#286).
- Tant que le panneau est visible, la luminosité des écrans externes est actualisée à un intervalle limité de 2 secondes afin que les changements au clavier parviennent rapidement au panneau.
- Correction des saccades lors du glissement de la luminosité DDC et identification correcte des écrans externes pour ne pas piloter l'écran intégré comme un écran externe (#284, #285).

### Wi-Fi et réseau

- Ajout d'un interrupteur d'alimentation Clash Verge TUN : le TUN est identifié via l'API en lecture seule de Mihomo, les tunnels bruts s'affichent en « TUN » au lieu de « VPN », et l'état de l'interrupteur reste synchronisé (#272).
- Amélioration de la visibilité de l'interrupteur d'alimentation de la ligne résumé Wi-Fi et de l'étendue de la confirmation avant de désactiver un réseau (#252).

### Source d'entrée

- Correction de la majuscule non conservée lorsque Verr. Maj et Maj sont activés en même temps ; l'indicateur affiche désormais correctement a/A (#279).

### Bluetooth

- Ajout d'une couleur personnalisée pour l'icône Bluetooth (#275).
- Les relevés de batterie obsolètes des appareils Bluetooth déconnectés expirent désormais au lieu de persister.

### Panneau et réglages

- Alignement de la décoration de survol de la ligne des réglages de batterie sur les limites du bouton cliquable et ajout d'espace (#281).
- Restauration des cartes arrondies du diagramme de flux d'énergie et masquage du débordement du ruban (#282).
- Restauration du composant curseur d'origine pour les intervalles d'actualisation dans les Réglages (#255).

### Performances et stabilité

- Resserrement de la durée de vie des threads de surveillance et de la cadence d'interrogation pour réduire le coût en arrière-plan et améliorer la stabilité (#294).
- Actualisation des périphériques de sortie en cache lorsque la topologie des périphériques audio change (#293).
- Correction de problèmes de performances et de stabilité sur les icônes, le panneau, les Réglages et la surveillance.
