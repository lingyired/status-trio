# Version %VERSION% (Build %BUILD%)

## Nouveautés

- L’indicateur inférieur propose désormais l’option « Pression mémoire », pour voir d’un coup d’œil l’utilisation actuelle de la mémoire.
- Les détails du disque listent maintenant tous les volumes montés (internes et externes) avec leur débit de lecture/écriture propre ; le pourcentage supérieur peut inclure les SSD externes en option.
- Les quatre anneaux du moniteur matériel peuvent désormais répartir la progression des deux côtés, le pourcentage supérieur ne masquant plus l’anneau.
- La page de détails du matériel ajoute un bouton « Ouvrir le Moniteur d’activité » pour identifier rapidement ce qui consomme des ressources.
- La liste à forte utilisation / forte consommation permet désormais de verrouiller une ligne puis de la forcer à quitter (processus enfants inclus) ; les cartes affichent un compte à rebours d’actualisation et l’élément disparaît dès sa fermeture.

## Corrections

- Correction de la température GPU du M3 Air illisible et de la même zone comptée deux fois.
- Optimisation du calcul de la température CPU pour M5 / M6.
- Ajout de l’identification de l’A18 Pro ; les puces non reconnues affichent « indisponible » au lieu d’une température erronée.
- Correction d’un cas où certains modèles affichaient encore 0,00 W de consommation d’écran sans mesure réelle.
- La consommation d’écran est désormais masquée lorsqu’aucune mesure réelle n’est disponible, au lieu d’afficher une estimation ; plus de valeurs obsolètes écran éteint ou capot fermé.
- La consommation de 0 W de l’écran et de l’USB n’est plus affichée comme une consommation réelle.
- Correction de l’échec de la première lecture du réglage du capot au démarrage à froid ; elle est maintenant réessayée automatiquement.
- Correction d’un faux délai d’attente où l’app abandonnait avant le service en arrière-plan ; les messages d’erreur incluent désormais un code pour le diagnostic.
- En l’absence de périphérique audio, le curseur de volume est masqué et un message « Aucun appareil disponible » s’affiche.
- Amélioration de certains textes anglais et des lignes longues pour éviter les coupures.
