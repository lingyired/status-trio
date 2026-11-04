# Version %VERSION% (Build %BUILD%)

### Barre des menus

- Actions rapides configurables par clic droit sur l'icône d'état : afficher le menu contextuel, basculer le mode économie d'énergie, charger à fond ou annuler, couper le son, activer/désactiver le Wi‑Fi, actualiser, ou ouvrir directement les réglages Wi‑Fi/Bluetooth/Batterie/Son (#209).

### Panneau

- Correction : le panneau s'ouvrait à la mauvaise position depuis l'icône du Dock (#229).
- Correction : le panneau débordait de l'écran (#237).
- Fond de panneau au choix : verre liquide, uni ou matériau classique (#233).
- Réduction des saccades à l'ouverture du panneau d'état (#232) :
  - les lignes Bluetooth affichent immédiatement les derniers appareils connus à la réouverture, les niveaux de batterie étant actualisés en arrière-plan ;
  - le sous-titre Bluetooth reste masqué jusqu'à la première lecture d'appareil, et les lignes restent stables jusqu'à l'arrivée des niveaux ;
  - la barre d'informations d'énergie est réservée par un squelette jusqu'à la première lecture, ce qui supprime le flash à l'ouverture, avec une apparition plus courte.
- Interface de la barre d'informations d'énergie retravaillée (#230, #238) : elle indique le sens de décharge, affiche « aucun adaptateur » sur batterie, colore la source de décharge en orange, et la carte d'entrée de charge adopte une surface argentée adaptative.
- Le remplissage en transparence réduite est résolu selon l'apparence effective (#234).
- Un simple clic sur l'icône d'état agit immédiatement lorsque le panneau est ouvert (#224).

### Batterie

- Le bouton « Charger à fond maintenant » n'affecte plus que le premier niveau du panneau d'état (#231).
- Correction de l'erreur lors de l'annulation après « Charger à fond maintenant » (#243).

### Écrans

- Compatibilité de la luminosité des écrans améliorée (#202) : les framebuffers sont reconnus par propriété avec un repli indépendant du nom, y compris ceux enregistrés en tant qu'AppleCLCD2.

### Corrections

- Contraste de la coche « Wi‑Fi connecté » amélioré (#242).
