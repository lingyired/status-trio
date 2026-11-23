# Versione %VERSION% (Build %BUILD%)

### Barra dei menu

- Azioni rapide configurabili con il tasto destro sull'elemento di stato: mostra il menu contestuale, attiva/disattiva il risparmio energetico, ricarica al massimo o annulla, disattiva l'audio, attiva/disattiva il Wi‑Fi, aggiorna, oppure apri direttamente le impostazioni Wi‑Fi/Bluetooth/Batteria/Suono (#209).

### Pannello

- Corretta l'apertura del pannello nella posizione sbagliata dall'icona del Dock (#229).
- Corretto il pannello che usciva dallo schermo (#237).
- Sfondo del pannello selezionabile: vetro liquido, tinta unita o materiale classico (#233).
- Ridotte le esitazioni all'apertura del pannello di stato (#232):
  - le righe Bluetooth mostrano subito i dispositivi noti alla riapertura, mentre i livelli della batteria si aggiornano in background;
  - il sottotitolo Bluetooth resta nascosto fino alla prima lettura del dispositivo e le righe restano stabili finché non arrivano i livelli;
  - la barra delle informazioni sull'energia è riservata con uno scheletro fino alla prima lettura, eliminando il lampeggio all'apertura, con una comparsa più breve.
- Interfaccia della barra delle informazioni sull'energia rifinita (#230, #238): mostra la direzione di scarica, indica «nessun adattatore» a batteria, colora di arancione la sorgente di scarica e la scheda di ingresso ricarica usa una superficie argentata adattiva.
- Il riempimento con trasparenza ridotta viene risolto rispetto all'aspetto effettivo (#234).
- Un singolo clic sull'elemento di stato ha effetto immediato quando il pannello è aperto (#224).

### Batteria

- Il pulsante «Ricarica al massimo ora» ora influisce solo sul primo livello del pannello di stato (#231).
- Corretto l'errore durante l'annullamento dopo «Ricarica al massimo ora» (#243).

### Display

- Migliorata la compatibilità della luminosità dei display (#202): i framebuffer vengono riconosciuti tramite proprietà con un fallback indipendente dal nome, inclusi quelli registrati come AppleCLCD2.

### Correzioni

- Migliorato il contrasto del segno di spunta «Wi‑Fi connesso» (#242).
