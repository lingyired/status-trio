# Versione %VERSION% (build %BUILD%)

### Pannello e audio Bluetooth

- AirPods ora supportano «Spatialize Stereo» e «Conversation Awareness».
- Aggiunto il cambio della modalità di ascolto per gli auricolari Redmi / Xiaomi.
- Corretto: gli auricolari continuavano a mostrare «Connesso» per circa due minuti dopo essere stati riposti nella custodia.
- Corretto: un singolo clic sull'icona di stato aggiornava il pannello invece di chiuderlo, in modalità normale, solo barra dei menu e cliccando sul bordo dell'icona (#224).
- Volume con la rotellina più fluido: si aggiorna a ogni evento con una breve animazione sul cursore, e ogni scatto è 1/16 per avvicinarsi ai tasti volume di sistema.

### Batteria e alimentazione

- Il tempo di utilizzo rimanente ora compare nel pannello di stato e nei dettagli, che mostrano anche la temperatura della batteria (#298).
- «Capacità massima» ora usa la percentuale di salute del sistema per coincidere con macOS (#317) e ripiega sulle informazioni di sistema se lo stato non è leggibile.
- Il dettaglio energetico suddivide l'uscita USB per porta e nomina ogni accessorio; corretto: perdita dell'intera uscita USB quando la porta di ricarica raggiunge il limite di 300 W e consumo del display integrato mancante su alcuni modelli.
- I Mac senza batteria mostrano un anello pieno, l'indicatore superiore alterna fulmine e spina (#310); l'anello pieno vale solo con alimentazione collegata (#318).
- «Ricarica a 100% ora» ora corrisponde al comportamento nativo e l'interfaccia extra «ripristina limite» è stata rimossa.
- Il campionamento energetico e la scansione Bluetooth nelle vicinanze si sospendono quando il display dorme e riprendono al risveglio, risparmiando energia (#300).
- Il controllo segmentato della modalità energia usa ora uno sfondo traslucido adatto a Liquid Glass.

### Icone e aspetto

- Aggiunta un'opzione per usare icone in bianco e nero durante ricarica e connessione (#309).
- L'indicatore superiore della batteria ora può essere configurato separatamente per stato d'uso (batteria / ricarica, ecc.) (#315).
- Corretto: l'elemento ad anello superiore della barra dei menu era disallineato e andava alla deriva (#30).
- Corretto: l'icona dell'animazione di ricarica nel Dock si riduceva a metà sulle schermate 1x (#303).

### Display e luminosità

- Le impostazioni della luminosità consentono di scegliere manualmente un display BetterDisplay e suggeriscono di cambiarlo a mano quando la luminosità non è disponibile (#313).
- Corretto: la luminosità non era disponibile quando l'identità di un display esterno era ambigua (ora ripiega sull'unico display esterno).

### Rete e sorgente di input

- Aggiunto un interruttore «Conferma prima di disattivare il Wi-Fi» (#305).
- L'indicatore della sorgente Pinyin distingue il pinyin semplificato e tradizionale; il marcatore 简/繁 ora è facoltativo e può mostrare 中.

### Altro

- Corretto: l'elenco dei dispositivi di uscita scompariva quando la lettura del volume falliva (#296).
