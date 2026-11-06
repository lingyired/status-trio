# Versão %VERSION% (build %BUILD%)

### Bateria e energia

- Os detalhes da bateria agora mostram a capacidade máxima do sistema, a condição da bateria e o tempo de atividade do sistema.
- O modo de alto consumo agora sempre aparece como uma linha clara própria nos detalhes, lendo o estado do pmset; estados de saúde e alto consumo desconhecidos são exibidos explicitamente.
- Quando o "Carregamento Otimizado da Bateria" pausa o carregamento com limite de 100%, o "Carregar até 100% agora" funciona: a solicitação é enviada como o macOS faz e, ao concluir, não restaura o limite de carga anterior (#292).
- As páginas de detalhes e Ajustes agora explicam por que "Carregar até 100% agora" está indisponível ou oculto (#280, #292).
- Os Ajustes explicam que um limite de 100% ainda pode pausar o carregamento por causa do Carregamento Otimizado (#292).

### Brilho e monitores

- Monitores externos ganham um backend de brilho Automático: usa o BetterDisplay enquanto estiver em execução, caso contrário DDC direto; um backend escolhido explicitamente é lembrado e nunca sobrescrito.
- Mudanças de brilho da tela integrada por teclas, Central de Controle ou Ajustes agora refletem imediatamente no painel (#286).
- Enquanto o painel estiver visível, o brilho dos monitores externos é atualizado em um intervalo limitado de 2 segundos, para que mudanças pelo teclado cheguem logo ao painel.
- Corrigida a engasgada ao arrastar o brilho DDC e a identificação correta de monitores externos, para não controlar a tela integrada como externa (#284, #285).

### Wi-Fi e rede

- Adicionado um botão de energia do Clash Verge TUN: o TUN é identificado pela API somente leitura do Mihomo, túneis simples aparecem como "TUN" em vez de "VPN", e o estado do botão permanece sincronizado (#272).
- Aprimorada a visibilidade do botão de energia na linha de resumo do Wi-Fi e o escopo da confirmação antes de desativar uma rede (#252).

### Fonte de entrada

- Corrigido o não mantimento de maiúsculas quando Caps Lock e Shift estão ambos ativos; o indicador agora mostra corretamente a/A (#279).

### Bluetooth

- Adicionada cor personalizada para o ícone de Bluetooth (#275).
- Leituras de bateria antigas de dispositivos Bluetooth desconectados agora expiram em vez de permanecer.

### Painel e ajustes

- Alinhada a decoração de foco da linha de ajustes da bateria aos limites do botão clicável e adicionado espaço (#281).
- Restaurados os cartões arredondados no diagrama de fluxo de energia e mascarada a sobra da fita (#282).
- Restaurado o componente deslizante original para os intervalos de atualização nos Ajustes (#255).

### Desempenho e estabilidade

- Ajustados os tempos de vida das threads de monitoramento e a cadência de polling para reduzir o custo em segundo plano e melhorar a estabilidade (#294).
- Atualizados os dispositivos de saída em cache quando a topologia dos dispositivos de áudio muda (#293).
- Corrigidos problemas de desempenho e estabilidade em ícones, painel, Ajustes e monitoramento.
