# Version %VERSION% (Build %BUILD%)

### Nouveautés

- Contrôle du mode économie d'énergie : un interrupteur facultatif dans les détails de la batterie active ou désactive le mode économie d'énergie sans ouvrir Réglages Système. Une approbation unique est requise dans Réglages Système › Général › Ouverture à la connexion, sous « Autoriser en arrière-plan » ; l'assistant enregistré ne fait rien d'autre, ne s'exécute que pendant que l'app l'utilise et se termine de lui-même au repos. L'indication d'approbation reste sous le réglage, et toute la ligne ouvre les éléments d'ouverture.
- Niveau d'anneau plein : choisissez le niveau de charge auquel l'anneau de batterie est considéré comme plein (50%–100%, 100% par défaut). Utile sur un Mac dont la limite de charge maintient la batterie sous 100% ; « Utiliser la limite de charge » lit la valeur du système. La barre des menus et le Dock suivent ensemble.
- IP locale : un réglage facultatif de Réseau affiche l'adresse LAN privée de ce Mac sur la deuxième ligne de la ligne réseau, avant les détails Wi-Fi. Désactivé par défaut.
- Partage de connexion : les pages de détails Wi-Fi et filaire peuvent ouvrir directement le panneau « Partage », où le partage de connexion s'active. L'app ouvre le panneau ; elle n'active ni ne désactive le partage elle-même.

### Corrections

- Signal Wi-Fi : les lectures CoreWLAN invalides intermittentes sont contournées, l'icône connectée ne s'estompe plus et n'affiche plus 0 barre.
- Icônes des appareils Bluetooth : l'icône est désormais dessinée uniquement d'après la classe déclarée par l'appareil (device_minorType), donc connecter ou déconnecter ne la change plus. Si un fabricant déclare une mauvaise classe — un clavier qui s'annonce comme souris, par exemple — l'icône suit cette déclaration et l'app ne la corrige plus.
- Icône de la barre des menus : la partie monochrome se recolore en direct pendant le glissement d'un espace.
- Alignement des icônes : les SF Symbols sont centrés sur leur encre visible et non sur leur cadre de disposition, l'icône Wi-Fi ne décale plus dans l'anneau.
- Audio : la ligne en double du résumé de sortie audio a été supprimée.

### Remarques

- Pendant le glissement d'un changement d'espace, seule une icône entièrement monochrome suit l'espace cible ; les éléments portant une couleur d'état (batterie faible, mode économie d'énergie, secteur, Bluetooth) se mettent à jour une fois le changement validé.
