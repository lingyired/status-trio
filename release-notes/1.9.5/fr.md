# Version %VERSION% (build %BUILD%)

### Panneau et audio Bluetooth

- Les AirPods prennent désormais en charge « Spatialize Stereo » et « Conversation Awareness ».
- Ajout du changement de mode d'écoute pour les écouteurs Redmi / Xiaomi.
- Correction : les écouteurs affichaient encore « Connecté » pendant environ deux minutes après avoir été remis dans le boîtier.
- Correction : un simple clic sur l'icône d'état actualisait le panneau au lieu de le fermer — en mode normal, en mode barre de menus uniquement et lors d'un clic sur le bord de l'icône (#224).
- Volume à la molette plus fluide : mise à jour à chaque événement avec une courte animation sur le curseur, et chaque cran vaut 1/16 pour se rapprocher des touches de volume système.

### Batterie et alimentation

- Le temps d'autonomie restant s'affiche désormais dans le panneau d'état et les détails, qui indiquent aussi la température de la batterie (#298).
- « Capacité maximale » utilise désormais le pourcentage de santé système pour correspondre à macOS (#317), avec repli sur les infos système si l'état est illisible.
- La répartition d'énergie divise la sortie USB par port et nomme chaque accessoire ; correction de la perte de toute la sortie USB lorsque le port de charge atteint la limite de 300 W, et de l'absence de consommation de l'écran intégré sur certains modèles.
- Les Mac sans batterie affichent un anneau plein, l'indicateur supérieur bascule entre éclair et prise (#310) ; l'anneau plein ne s'applique qu'en charge (#318).
- « Charger à 100 % maintenant » correspond au comportement natif, l'interface « restaurer la limite » superflue est supprimée.
- L'échantillonnage d'énergie et le scan Bluetooth à proximité se mettent en pause quand l'écran dort et reprennent au réveil, pour économiser l'énergie (#300).
- Le contrôle segmenté du mode d'énergie utilise désormais un fond translucide adapté à Liquid Glass.

### Icônes et apparence

- Ajout d'une option pour utiliser des icônes noir et blanc pendant la charge et la connexion (#309).
- L'indicateur supérieur de batterie peut désormais être configuré séparément selon l'état d'utilisation (batterie / charge, etc.) (#315).
- Correction : l'élément d'anneau supérieur de la barre de menus était mal aligné et dérivait (#30).
- Correction : l'icône d'animation de charge du Dock rétrécissait de moitié sur les écrans 1x (#303).

### Écrans et luminosité

- Les réglages de luminosité permettent de choisir manuellement un écran BetterDisplay, et suggèrent un changement manuel quand la luminosité est indisponible (#313).
- Correction : la luminosité était indisponible lorsque l'identité d'un écran externe était ambiguë (repli désormais sur l'unique écran externe).

### Réseau et source d'entrée

- Ajout d'un réglage « Confirmer avant de désactiver le Wi-Fi » (#305).
- L'indicateur de source Pinyin distingue le pinyin simplifié et traditionnel ; le marqueur 简/繁 est désormais facultatif et peut afficher 中.

### Divers

- Correction : la liste des périphériques de sortie disparaissait lorsque la lecture du volume échouait (#296).
