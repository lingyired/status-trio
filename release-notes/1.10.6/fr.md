# Version %VERSION% (Build %BUILD%)

## Corrections

- Correction d'un faux message « impossible de lire l'état du maintien en éveil capot fermé » (code DS-R4) sur les Mac où cette fonction n'a jamais été activée. macOS n'affiche ce réglage qu'après une première utilisation ; l'app le considère désormais comme désactivé au lieu d'une erreur de lecture.
- Le bouton de maintien en éveil capot fermé affiche maintenant le bon état initial et fonctionne dès le premier clic sur ces Mac, sans exécuter `sudo pmset -a disablesleep` manuellement.
