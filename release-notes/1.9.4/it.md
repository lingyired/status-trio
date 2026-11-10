# Versione %VERSION% (build %BUILD%)

### Batteria e alimentazione

- I dettagli della batteria ora includono la capacità massima del sistema, le condizioni della batteria, il tempo di attività del sistema e lo stato della modalità ad alta potenza.
- Quando «Ricarica ottimizzata della batteria» mette in pausa la ricarica con un limite del 100%, ora è disponibile «Ricarica completamente ora»; se non è disponibile, le pagine dei dettagli e Impostazioni ne spiegano il motivo (#292, #280).

### Luminosità e display

- I display esterni hanno un backend di luminosità «Automatico»: usa BetterDisplay mentre è in esecuzione, altrimenti DDC diretto.
- Le variazioni di luminosità del display integrato da tasti, Centro di controllo o Impostazioni ora si riflettono subito nel pannello (#286).
- Mentre il pannello è aperto, anche le regolazioni di luminosità dei display esterni si riflettono prontamente nel pannello.
- Corretti gli scatti durante il trascinamento della luminosità DDC e identificati correttamente i display esterni (#284, #285).

### Wi-Fi e rete

- La riga riepilogo dei servizi VPN di sistema ora ha un interruttore di alimentazione; le connessioni TUN di Clash Verge non vengono più mostrate come «VPN» ma correttamente come «TUN» (con il nome del client per Clash Verge), e quella riga resta di sola lettura senza interruttore (#272).

### Sorgente di input

- L'indicatore della sorgente di input ABC ora mostra a/A in base a maiuscole e minuscole (#279).

### Bluetooth

- Migliorato il problema dei dispositivi fantasma Bluetooth (#248).
- Aggiunto il colore personalizzato per l'icona Bluetooth (#275).

### Pannello e impostazioni

- Migliorato l'allineamento tra hover e area cliccabile della riga delle impostazioni batteria (#281).
- Rifinita la resa degli angoli del diagramma del flusso di energia (#282).
- L'intervallo di aggiornamento dello stato ora si imposta separatamente per «A batteria / Collegato alla corrente» (#255).

### Prestazioni e stabilità

- Ridotte la frequenza di aggiornamento in background e l'uso delle risorse, per consumare meno e migliorare la stabilità (#294).
- Corretto il mancato aggiornamento dell'elenco dei dispositivi di output dopo il cambio di dispositivo audio (#293).
