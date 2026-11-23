# Version %VERSION% (build %BUILD%)

## Capteurs et températures

- La température GPU du M3 Air (Mac15,12) refonctionne : les capteurs Tf illisibles sont remplacés par les capteurs Tg vérifiés, regroupés en six paires pour ne pas compter deux fois une même zone physique.
- Sur M5 et M6, les sondes d'un même cœur CPU sont regroupées ; plusieurs sondes n'augmentent plus le nombre de cœurs ni la moyenne.
- Identification de l'A18 Pro ajoutée. Les puces inconnues n'empruntent plus les clés de température d'une autre génération ; elles affichent une absence de mesure plutôt qu'un chiffre plausible mais faux.

## Consommation de l'écran

- Issue #374 corrigée : un M3 Air sans PDBR et avec PBLR bloqué à 0 n'affiche plus une branche écran à 0,00 W.
- Sans voie de rétroéclairage mesurée exploitable, la consommation de l'écran peut utiliser une estimation AppleARMBacklight. Les 6 V sont une hypothèse, pas une mesure ; la valeur est marquée ≈ et le résidu système comme estimé.
- Les branches écran et USB à 0 W sont masquées.

## Surveillance et performances

- Les capacités des capteurs sont sondées une fois puis mises en cache ; les clés absentes sont réessayées avec un délai croissant.
- Aucun nouveau minuteur, helper ni accès privilégié. La collecte de température et de rétroéclairage s'arrête toujours à la fermeture du panneau.
