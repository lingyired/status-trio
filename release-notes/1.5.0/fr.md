# Version %VERSION% (build %BUILD%)

### Améliorations

- Amélioration de la cohérence des mises à jour du panneau d’état, sans changer ses commandes, sa disposition ni sa navigation.
- Le panneau d’état s’affiche plus fiablement lors des changements d’appareil, de réseau ou d’audio.

### Confidentialité

- Ajout de statistiques d’utilisation facultatives. Sur une nouvelle installation, l’option est activée par défaut, mais aucun heartbeat n’est envoyé avant la fin du guide ou le choix de Personnaliser. Après une mise à niveau, la fonction reste désactivée jusqu’à son activation dans les réglages.
- Le heartbeat contient un identifiant d’installation aléatoire, les versions de l’app et de macOS, les langues du système et de l’app, ainsi que l’emplacement de l’icône. Consultez [confidentialité et analyses](https://github.com/lingyired/status-trio/blob/main/docs/privacy-telemetry.md).
- L’app n’inclut aucun SDK d’analyse tiers.
