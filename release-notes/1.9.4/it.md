# Versione %VERSION% (build %BUILD%)

### Batteria e alimentazione

- I dettagli della batteria ora mostrano la capacità massima del sistema, le condizioni della batteria e il tempo di attività del sistema.
- La modalità ad alta potenza ora appare sempre come una riga chiara a sé nei dettagli, leggendo lo stato da pmset; gli stati di salute e alta potenza sconosciuti vengono mostrati esplicitamente.
- Quando «Ricarica ottimizzata della batteria» mette in pausa la ricarica con un limite del 100%, «Ricarica completamente ora» funziona: la richiesta viene inviata come fa macOS e, al completamento, non ripristina il limite di ricarica precedente (#292).
- Le pagine dei dettagli e Impostazioni ora spiegano perché «Ricarica completamente ora» non è disponibile o è nascosto (#280, #292).
- In Impostazioni è spiegato che un limite del 100% può comunque mettere in pausa la ricarica a causa della ricarica ottimizzata (#292).

### Luminosità e display

- I display esterni hanno un backend di luminosità Automatico: usa BetterDisplay mentre è in esecuzione, altrimenti DDC diretto; un backend scelto esplicitamente viene ricordato e mai sovrascritto.
- Le variazioni di luminosità del display integrato da tasti, Centro di controllo o Impostazioni ora si riflettono subito nel pannello (#286).
- Mentre il pannello è visibile, la luminosità dei display esterni si aggiorna a un intervallo limitato di 2 secondi, così le modifiche da tastiera arrivano subito al pannello.
- Corretti gli scatti durante il trascinamento della luminosità DDC e identificati correttamente i display esterni per non pilotare il display integrato come esterno (#284, #285).

### Wi-Fi e rete

- Aggiunto un interruttore di alimentazione per Clash Verge TUN: il TUN viene identificato tramite l'API di sola lettura di Mihomo, i tunnel semplici mostrano «TUN» invece di «VPN» e lo stato dell'interruttore resta sincronizzato (#272).
- Migliorata la visibilità dell'interruttore di alimentazione nella riga riepilogo Wi-Fi e l'ambito di conferma prima di disattivare una rete (#252).

### Sorgente di input

- Corretto il mancato mantenimento del maiuscolo quando Bloc Maiusc e Maiusc sono entrambi attivi; l'indicatore ora mostra correttamente a/A (#279).

### Bluetooth

- Aggiunto il colore personalizzato per l'icona Bluetooth (#275).
- Le letture della batteria obsolete dei dispositivi Bluetooth disconnessi ora scadono invece di rimanere.

### Pannello e impostazioni

- Allineata la decorazione al passaggio del mouse della riga delle impostazioni batteria ai limiti del pulsante cliccabile e aggiunto spazio (#281).
- Ripristinate le schede arrotondate nel diagramma del flusso di energia e mascherato lo sforamento del nastro (#282).
- Ripristinato il componente slider originale per gli intervalli di aggiornamento nelle Impostazioni (#255).

### Prestazioni e stabilità

- Ridotte le durate dei thread di monitoraggio e la cadenza di polling per diminuire il costo in background e migliorare la stabilità (#294).
- Aggiornati i dispositivi di output in cache quando cambia la topologia dei dispositivi audio (#293).
- Risolti problemi di prestazioni e stabilità su icone, pannello, Impostazioni e monitoraggio.
