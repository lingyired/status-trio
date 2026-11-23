# Versão %VERSION% (build %BUILD%)

### Painel e áudio Bluetooth

- Os AirPods agora oferecem suporte a "Spatialize Stereo" e "Conversation Awareness".
- Adicionada a troca de modo de audição para fones Redmi / Xiaomi.
- Corrigido: os fones continuavam mostrando "Conectado" por cerca de dois minutos após serem colocados de volta no estojo.
- Corrigido: um único clique no ícone de status atualizava o painel em vez de fechá-lo, no modo normal, somente barra de menus e ao clicar na borda do ícone (#224).
- Volume pela roda de rolagem mais fluido: atualiza a cada evento com uma breve suavização no controle, e cada passo é 1/16 para se aproximar das teclas de volume do sistema.

### Bateria e energia

- O tempo restante de uso agora aparece no painel de status e nos detalhes, que também mostram a temperatura da bateria (#298).
- "Capacidade máxima" agora usa a porcentagem de saúde do sistema para coincidir com o macOS (#317) e recorre às informações do sistema quando o estado não pode ser lido.
- O detalhamento de energia divide a saída USB por porta e nomeia cada acessório; corrigida a perda de toda a saída USB quando a porta de carregamento atinge o limite de 300W, e a ausência do consumo da tela integrada em alguns modelos.
- Macs sem bateria mostram um anel cheio, o indicador superior alterna entre raio e plugue (#310); o anel cheio só se aplica com energia conectada (#318).
- "Carregar até 100% agora" agora corresponde ao comportamento nativo, e a interface extra de "restaurar limite" foi removida.
- A amostragem de energia e a varredura de Bluetooth por perto pausam quando a tela dorme e retomam ao acordar, economizando energia (#300).
- O controle segmentado de modo de energia agora usa um fundo translúcido para combinar com o Liquid Glass.

### Ícones e aparência

- Adicionada uma opção para usar ícones em preto e branco durante o carregamento e a conexão (#309).
- O indicador superior da bateria agora pode ser configurado separadamente por estado de uso (bateria / carregando etc.) (#315).
- Corrigido: a peça do anel superior da barra de menus ficava desalinhada e se deslocava (#30).
- Corrigido: o ícone da animação de carregamento no Dock encolhia para metade em telas 1x (#303).

### Telas e brilho

- As configurações de brilho permitem escolher manualmente uma tela do BetterDisplay e sugerem a troca manual quando o brilho não está disponível (#313).
- Corrigido: o brilho ficava indisponível quando a identidade de uma tela externa era ambígua (agora recorre à única tela externa).

### Rede e fonte de entrada

- Adicionado um interruptor "Confirmar antes de desligar o Wi-Fi" (#305).
- O indicador da fonte Pinyin distingue pinyin simplificado e tradicional; o marcador 简/繁 agora é opcional e pode mostrar 中.

### Outros

- Corrigido: a lista de dispositivos de saída desaparecia quando a leitura do volume falhava (#296).
