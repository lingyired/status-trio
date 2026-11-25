# Versione %VERSION% (Build %BUILD%)

## Correzioni

- Corretto un falso errore «impossibile leggere lo stato di mantieni attivo a coperchio chiuso» (codice DS-R4) sui Mac in cui questa funzione non era mai stata attivata. macOS mostra l'impostazione solo dopo il primo utilizzo, quindi ora l'app la considera disattivata invece di un errore di lettura.
- L'interruttore mantieni attivo a coperchio chiuso ora mostra lo stato iniziale corretto e funziona al primo clic su questi Mac, senza eseguire manualmente `sudo pmset -a disablesleep`.
