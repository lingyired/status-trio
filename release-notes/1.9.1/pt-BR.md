# Versão %VERSION% (Compilação %BUILD%)

### Bateria

- A página de bateria mostra uma divisão do fluxo de energia (tela integrada, saída USB/acessórios e sistema) e uma barra opcional de energia ao vivo. A saída de acessórios é lida dos trilhos da porta SMC quando disponível.
- Novo ajuste «Restaurar limite após cancelar» para Carregar até a carga máxima, com estados mais claros quando o macOS inicia a substituição temporária.
- As cores do ícone da bateria podem seguir cores de estado personalizadas, com escolha separada do indicador de conexão (raio, plugue ou porcentagem).
- Modo «dividido» opcional para o anel da bateria: quando a lacuna superior mostra raio, plugue ou porcentagem, o arco esquerdo lê 0–50% e o direito 50–100%, então 40–60% deixa de ficar oculto. Desativado por padrão; vale para barra de menus e Dock.

### Energia

- O espaço central pode mostrar a energia total ao vivo em vez da fonte de conexão; Macs sem bateria integrada são totalmente suportados.

### Telas

- Controle de brilho: telas externas usam DDC direto e as integradas são controladas via DisplayServices.

### Ícone central

- A fonte do espaço central agora é um único seletor «Ícone central»: rede, dispositivo Bluetooth, fonte de entrada atual, porcentagem da bateria ou energia. Os dois interruptores de erro de rede foram unidos em um que vale para todas as fontes, o interruptor Bluetooth «substituir ícone de rede» que não funcionava foi removido e os valores salvos são migrados automaticamente.
- As fontes do ícone central agora são blocos de imagem que pré-visualizam o resultado real. Um único «Tamanho do ícone central» controla Wi‑Fi, Bluetooth, fonte de entrada e números, e as opções de estilo do ícone de rede foram movidas para essa página.
- A prévia mostra o estado de carga, o conteúdo central fica centralizado verticalmente no anel da bateria e o texto é um pouco menor que os símbolos.

### Guia

- Guia reformulado: a janela assume a altura da página mais alta e não muda mais de tamanho entre etapas; as prévias compartilham uma superfície, as legendas indicam arco superior, ícone central e pontos inferiores, foram adicionados exemplos do espaço central (porcentagem, energia, fonte de entrada) e o bloco de consentimento ficou mais compacto.

### Ajustes

- Todos os menus pop-up dos Ajustes usam uma largura comum e não mudam mais com as opções ou a lista de dispositivos, mantendo a aparência nativa.

### Áudio

- Dispositivos de entrada/saída podem ser reordenados, ocultados e limitados em quantidade.
- O retorno de volume pela rolagem é configurável separadamente; clicar de novo no modo de escuta selecionado o desativa.

### Painel

- O painel de status usa estilo sem cantos nem entalhe, adiciona um menu «mais» inferior e adapta melhor tamanho e layout no Liquid Glass.

### Correções

- As informações de Wi‑Fi continuam visíveis sem permissão de Localização.
