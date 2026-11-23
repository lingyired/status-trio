# Versão %VERSION% (build %BUILD%)

### Monitor do sistema

- O painel de status agora monitora CPU, GPU, memória, rede, disco e velocidade da ventoinha; clique para abrir a página de detalhes correspondente.
- Cores personalizadas para as métricas de CPU, GPU, memória, rede, disco e velocidade da ventoinha.
- Personalize o intervalo de atualização e o período do histórico.
- O monitor do sistema coleta sob demanda: lê as métricas apenas enquanto estão sendo exibidas, e o histórico em segundo plano fica desativado por padrão, reduzindo a carga.

### Ícone da barra de menus e anel

- Novas fontes de dados do monitor do sistema para o anel externo, com layout de anel único e anel duplo esquerdo/direito. Os arcos podem usar uso de CPU, temperatura da CPU, uso de GPU, temperatura da GPU, uso de memória, temperatura da bateria, nível da bateria, velocidade da ventoinha, velocidade de download/upload, volume e sinal Wi-Fi.
- O arco do nível da bateria segue as cores do sistema; uma nova função de cor «Descarregando (sem energia)» permite personalizar separadamente as cores de carregamento, baixa, alto desempenho, crítica e descarga (#357).
- Novo modo AirPods para o indicador superior: os anéis duplos podem mostrar a bateria dos fones esquerdo e direito (também um só) e, ao desconectar, voltam para a bateria do Mac ou um anel personalizado.
- O indicador inferior aceita uma fonte de dados personalizada: volume, sinal Wi-Fi ou nível da bateria (ou oculto).

### Painel e interação

- Passe o cursor sobre o ícone da barra de menus para abrir o painel; clique para fixá-lo (#355).
- Os detalhes agora abrem em um painel lateral ao lado do painel de status, com transição mais suave.
- Novo cartão de monitor de hardware.
- Refinados os controles deslizantes numéricos (volume e brilho) com visual mais próximo do macOS 26+ e movimento mais suave; aceitam deslize horizontal no trackpad (#351).
- Os ícones de Wi-Fi e Bluetooth são tingidos conforme o estado de conexão (#352).
- O botão «Carregar até 100% agora» ganhou um brilho liquid glass ao passar o cursor.
- Removido o negrito do painel de status; valores e unidades usam fonte monoespaçada.

### Manter ativo e suspensão

- Adicionados «Manter tela ligada» e «Sem suspensão com tampa fechada», cada um com duração personalizável (#295).

### Brilho

- Novo botão «Usar brilho combinado do BetterDisplay» (#344).

### Bateria e áudio

- Corrigidos o texto e a linha de carga de manutenção em 100%.
- Corrigido o silenciamento com volume exatamente zero e a restauração apenas do silenciamento automático.
- Corrigida a estimativa de «tempo até carga total» para respeitar o limite de carga do macOS (#349).

### Outras correções

- O histórico de detalhes do monitor agora é isolado por tipo de métrica.
- Melhorada a coleta em segundo plano e a estabilidade dos pipes de processo, com menos travamentos e interferência.
- Corrigida a oscilação de altura da linha do modo de escuta do AirPods ao abrir o painel (#354).
