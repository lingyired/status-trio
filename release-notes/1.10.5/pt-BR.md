# Versão %VERSION% (Build %BUILD%)

## Novidades

- O indicador inferior agora tem a opção «Pressão de memória», para ver rapidamente o uso atual de memória.
- Os detalhes do disco agora listam todos os volumes montados (internos e externos) com a velocidade de leitura/gravação de cada um; o percentual superior pode incluir SSDs externos opcionalmente.
- Os quatro anéis do monitor de hardware agora podem dividir o progresso para os dois lados, então o percentual superior não cobre mais o anel.
- A página de detalhes de hardware ganhou o botão «Abrir Monitor de Atividade» para ver rapidamente o que está consumindo recursos.
- A lista de alto uso / alto consumo agora permite fixar uma linha e forçar o encerramento (incluindo os processos filhos); os cartões mostram uma contagem regressiva de atualização e o item sai da lista assim que é encerrado.

## Correções

- Corrigida a temperatura de GPU do M3 Air que não podia ser lida e evitado contar a mesma zona duas vezes.
- Otimizado o cálculo da temperatura de CPU para M5 / M6.
- Adicionado o reconhecimento do A18 Pro; chips não reconhecidos agora mostram «indisponível» em vez de uma temperatura errada.
- Corrigido um caso em que alguns modelos ainda mostravam 0,00 W de consumo da tela sem leitura real.
- O consumo da tela agora é ocultado quando não há leitura real, em vez de mostrar estimativa; não ficam mais valores antigos com a tela desligada ou a tampa fechada.
- O consumo de 0 W da tela e da USB não é mais exibido como consumo real.
- Corrigida a falha da primeira leitura do ajuste da tampa na inicialização a frio; agora ela é repetida automaticamente.
- Corrigido um falso timeout em que o app desistia antes do serviço em segundo plano; as mensagens de falha agora incluem um código de erro para diagnóstico.
- Quando não há dispositivo de áudio disponível, o controle de volume é ocultado e aparece o aviso «Nenhum dispositivo disponível».
- Ajustados alguns textos em inglês e linhas longas para não serem cortados.
