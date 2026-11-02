# Versão %VERSION% (Compilação %BUILD%)

### Bateria

- Modo «dividido» opcional para o anel da bateria: quando a lacuna superior mostra raio, plugue ou porcentagem, o arco esquerdo lê 0–50% e o direito 50–100%, então 40–60% deixa de ficar oculto. Desativado por padrão; vale para barra de menus e Dock.
- As cores do ícone da bateria podem seguir cores de estado personalizadas, com escolha separada do indicador de conexão (raio, plugue ou porcentagem). Barra de menus e Dock compartilham a mesma cena.
- A página de bateria mostra uma divisão do fluxo de energia (tela integrada, saída USB/acessórios e sistema) e uma barra opcional de energia ao vivo. A saída de acessórios é lida dos trilhos da porta SMC quando disponível.
- Novo ajuste «Restaurar limite após cancelar» para Carregar até a carga máxima, com estados mais claros quando o macOS inicia a substituição temporária.

### Energia

- O espaço central pode mostrar a energia total ao vivo em vez da fonte de conexão; Macs sem bateria integrada são totalmente suportados.

### Telas

- Controle de brilho: telas externas usam DDC direto e as integradas são controladas via DisplayServices, então o BetterDisplay não é mais necessário para a tela integrada.
- No diagrama de fluxo, a altura de cada cartão segue sua proporção, com qualquer número de ramos.

### Áudio

- Dispositivos de entrada/saída podem ser reordenados, ocultados e limitados em quantidade. Um único dispositivo com modo de escuta mantém os botões de controle de ruído mesmo ocultando outras saídas.
- O retorno de volume pela rolagem é configurável separadamente; clicar de novo no modo de escuta selecionado o desativa.

### Painel

- O painel de status usa estilo sem cantos nem entalhe, adiciona um menu «mais» inferior e adapta melhor tamanho e layout no Liquid Glass. Na ordem padrão, «Brilho da tela» fica abaixo de «Entrada de áudio».

### Correções

- Reiniciar durante Carregar até a carga máxima mantém o limite de restauração calculado inicialmente em vez de voltar a 100%.
- Fechar o painel libera a amostragem da barra de energia; o ícone amostra a cada 2 s apenas enquanto mostra energia.
- Alternar a barra de energia com o painel aberto usa o novo valor imediatamente.
- Uma divisão de energia da bateria verificada não é mais descartada ao desconectar.
- Conectar uma tela a quente atualiza a lista de brilho e descarta a conexão DDC obsoleta.
- Uma gravação DDC não confirmada mostra «indisponível» em vez de perder o controle e a explicação.
- As informações de Wi‑Fi continuam visíveis sem permissão de Localização.
