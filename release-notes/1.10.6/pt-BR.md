# Versão %VERSION% (Build %BUILD%)

## Correções

- Corrigido um erro falso de "não foi possível ler o estado de manter acordado com a tampa fechada" (código DS-R4) em Macs que nunca ativaram esse recurso. O macOS só mostra o ajuste após o primeiro uso, então agora o app o trata como desligado em vez de falha de leitura.
- O botão de manter acordado com a tampa fechada agora mostra o estado inicial correto e funciona no primeiro clique nesses Macs, sem executar `sudo pmset -a disablesleep` manualmente.
