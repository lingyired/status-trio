# Versão %VERSION% (build %BUILD%)

### Bateria e energia

- Os detalhes da bateria agora incluem a capacidade máxima do sistema, a condição da bateria, o tempo de atividade do sistema e o estado do modo de alto consumo.
- Quando o "Carregamento Otimizado da Bateria" pausa o carregamento com limite de 100%, agora é possível usar "Carregar até 100% agora"; quando indisponível, as páginas de detalhes e Ajustes explicam o motivo (#292, #280).

### Brilho e monitores

- Monitores externos ganham um backend de brilho "Automático": usa o BetterDisplay enquanto estiver em execução, caso contrário DDC direto.
- Mudanças de brilho da tela integrada por teclas, Central de Controle ou Ajustes agora refletem imediatamente no painel (#286).
- Enquanto o painel estiver aberto, os ajustes de brilho dos monitores externos também são refletidos prontamente no painel.
- Corrigida a engasgada ao arrastar o brilho DDC e a identificação correta de monitores externos (#284, #285).

### Wi-Fi e rede

- A linha de resumo dos serviços VPN do sistema agora tem um botão de energia; conexões TUN do Clash Verge não aparecem mais como "VPN", mas corretamente como "TUN" (com o nome do cliente quando for Clash Verge), e essa linha permanece somente leitura sem botão (#272).

### Fonte de entrada

- O indicador da fonte de entrada ABC agora mostra a/A conforme maiúsculas e minúsculas (#279).

### Bluetooth

- Melhorado o problema de dispositivos fantasmas de Bluetooth (#248).
- Adicionada cor personalizada para o ícone de Bluetooth (#275).

### Painel e ajustes

- Melhorado o alinhamento entre o foco e a área clicável da linha de ajustes da bateria (#281).
- Refinada a aparência dos cantos do diagrama de fluxo de energia (#282).
- O intervalo de atualização de status agora é definido separadamente para "Na bateria / Ligado à tomada" (#255).

### Desempenho e estabilidade

- Reduzidas a frequência de atualização em segundo plano e o uso de recursos, diminuindo o consumo e melhorando a estabilidade (#294).
- Corrigido o fato de a lista de dispositivos de saída não ser atualizada após trocar de dispositivo de áudio (#293).
