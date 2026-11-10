# Versão %VERSION% (Compilação %BUILD%)

### Bateria

- O fluxo de energia da bateria agora mostra estimativas da entrada do carregador, da energia enviada à bateria e da energia do sistema. A entrada do carregador fica desativada por padrão; as outras duas leituras ficam ativadas.
- Uma lista opcional do impacto energético da CPU mostra até cinco apps com base em amostras recentes. Quando os contadores de energia não estão disponíveis, ela usa a atividade da CPU e aceita um intervalo de amostragem de 10–60 segundos.
- Em Macs compatíveis com chip Apple e macOS 26.4 ou posterior, Carregar até o máximo e Cancelar carga até o máximo ficam disponíveis e são ativados por padrão quando há suporte.

### Monitores externos

- Foi adicionado um método de controle de volume via BetterDisplay para monitores externos ou saídas de áudio cujo volume o macOS não consegue controlar diretamente. Ele permite associar o monitor de forma automática ou manual e mostra estados de conexão e erro.
- O volume nativo gravável continua tendo prioridade, o modo Standard/DDC pode ser restaurado a qualquer momento, e o Status Trio não inicia nem altera as configurações do BetterDisplay quando ele não está disponível.

### Estabilidade e interface

- O tratamento de eventos de Wi-Fi foi aprimorado com a agregação de callbacks CoreWLAN de alta frequência e a limitação da frequência de recuperação em estados anormais, reduzindo o risco de uma tempestade de eventos ampliar a pressão sobre CPU e memória.
- O painel de status agora mantém a página de detalhes atual ao ser reaberto, em vez de voltar à página inicial.
- Foram aprimorados o layout dos detalhes da bateria, a navegação, a área clicável da engrenagem e a atualização da potência em tempo real.
- Foi aprimorada a composição da camada colorida e da imagem de modelo na barra de menus. Monitores sem foco agora escurecem corretamente, mantendo a recoloração do sistema ao trocar de Space.

### Observações importantes

- Carregar até o máximo usa uma interface privada do PowerUI e está disponível apenas em Macs com chip Apple e macOS 26.4 ou posterior. Não há garantia de comportamento entre versões do macOS.
- Após a conclusão da carga ou a reconexão do adaptador de energia, o limite de carga pode permanecer em 100%. O Status Trio não o restaura automaticamente; use Cancelar carga até o máximo ou restaure o limite nos Ajustes do Sistema.
- A lista de impacto energético da CPU não representa o consumo total de energia de um app e não é uma cópia da lista “Uso significativo de energia” do macOS.
- O controle de volume via BetterDisplay exige que o BetterDisplay esteja em execução. O volume do monitor e o comportamento DDC ainda dependem do hardware e da conexão.
