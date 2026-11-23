# Versão %VERSION% (build %BUILD%)

## Sensores e temperaturas

- A temperatura da GPU do M3 Air (Mac15,12) voltou a funcionar: os sensores Tf ilegíveis são substituídos pelos Tg verificados, agrupados em seis pares para não contar a mesma zona física duas vezes.
- No M5 e M6, sondas do mesmo núcleo de CPU são agrupadas; várias sondas não aumentam mais a contagem de núcleos nem a média.
- Adicionada a identificação do A18 Pro. Chips desconhecidos não usam mais as chaves de temperatura de outra geração; mostram leitura indisponível em vez de um número plausível, mas errado.

## Consumo do display

- Corrigido o Issue #374: um M3 Air sem PDBR e com PBLR fixo em 0 não mostra mais uma ramificação de display de 0,00 W.
- Sem uma via de retroiluminação medida utilizável, a ramificação de display fica oculta; nenhum valor estimado é publicado.
- Ramificações de display e USB com 0 W ficam ocultas.

## Monitoramento e desempenho

- As capacidades dos sensores são sondadas uma vez e armazenadas; chaves inexistentes são tentadas novamente com backoff.
- Nenhum novo timer, helper ou acesso privilegiado. A coleta de temperatura e retroiluminação continua parando ao fechar o painel.
