# Versione %VERSION% (Build %BUILD%)

## Novità

- L’indicatore inferiore ora include l’opzione «Pressione memoria», per vedere a colpo d’occhio l’uso attuale della memoria.
- I dettagli del disco ora elencano tutti i volumi montati (interni ed esterni) con la velocità di lettura/scrittura di ciascuno; la percentuale superiore può includere facoltativamente gli SSD esterni.
- I quattro anelli del monitor hardware possono ora dividere l’avanzamento su entrambi i lati, così la percentuale superiore non copre più l’anello.
- La pagina dei dettagli hardware include un pulsante «Apri Monitoraggio Attività» per vedere rapidamente cosa occupa le risorse.
- L’elenco di utilizzo/consumo elevato ora consente di bloccare una riga e forzarne la chiusura (inclusi i processi figli); le schede mostrano un conto alla rovescia di aggiornamento e la voce scompare subito dopo la chiusura.

## Correzioni

- Risolta la temperatura GPU del M3 Air non leggibile ed evitato il doppio conteggio della stessa zona.
- Ottimizzato il calcolo della temperatura CPU per M5 / M6.
- Aggiunto il riconoscimento dell’A18 Pro; i chip non riconosciuti ora mostrano «non disponibile» invece di una temperatura errata.
- Risolto un caso in cui alcuni modelli mostravano ancora 0,00 W di consumo dello schermo senza una lettura reale.
- Il consumo dello schermo ora viene nascosto quando non c’è una lettura reale, invece di mostrare una stima; non restano più valori vecchi con schermo spento o coperchio chiuso.
- Il consumo di 0 W di schermo e USB non viene più mostrato come consumo reale.
- Risolto il fallimento della prima lettura dell’impostazione del coperchio all’avvio a freddo; ora viene ritentata automaticamente.
- Risolto un falso timeout in cui l’app si arrendeva prima del servizio in background; i messaggi di errore ora includono un codice per la diagnosi.
- In assenza di dispositivi audio il cursore del volume viene nascosto e al suo posto compare «Nessun dispositivo disponibile».
- Migliorati alcuni testi inglesi e le righe lunghe per evitare troncamenti.
