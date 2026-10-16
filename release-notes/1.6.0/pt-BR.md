# Versão %VERSION% (Compilação %BUILD%)

### Novidades

- Controle do modo de baixo consumo: um interruptor opcional nos detalhes da bateria ativa ou desativa o modo de baixo consumo sem abrir os Ajustes do Sistema. Requer uma aprovação única em Ajustes do Sistema › Geral › Itens de Login, em «Permitir em Segundo Plano»; o auxiliar registrado não faz mais nada, roda apenas enquanto o app o usa e encerra sozinho quando fica ocioso. A indicação de aprovação permanece abaixo do controle e a linha inteira abre os itens de login.
- Nível de anel cheio: escolha o nível de carga em que o anel da bateria conta como cheio (50%–100%, padrão 100%). Útil em um Mac cujo limite de carga mantém a bateria abaixo de 100%; «Usar o limite de carga» lê o valor do sistema. A barra de menus e o Dock acompanham juntos.
- IP local: um ajuste opcional de Rede que mostra o endereço privado de LAN deste Mac na segunda linha da linha de rede, antes dos detalhes de Wi-Fi. Desativado por padrão.
- Compartilhamento de Internet: as páginas de detalhes de Wi-Fi e com fio podem abrir diretamente o painel «Compartilhamento», onde o Compartilhamento de Internet é ativado. O app apenas abre o painel; não ativa nem desativa o compartilhamento por conta própria.

### Correções

- Sinal de Wi-Fi: leituras inválidas intermitentes do CoreWLAN agora são contornadas, então o ícone conectado não desbota nem mostra 0 barras.
- Ícones de dispositivos Bluetooth: o ícone agora é desenhado apenas a partir da classe declarada pelo próprio dispositivo (device_minorType), então conectar ou desconectar não o altera mais. Se o fabricante declarar a classe errada — um teclado que se anuncia como mouse, por exemplo — o ícone segue essa declaração e o app não a corrige mais.
- Ícone da barra de menus: a parte monocromática volta a se recolorir ao vivo enquanto um espaço é arrastado.
- Alinhamento dos ícones: os SF Symbols são centralizados pela tinta visível, e não pela caixa de layout, então o ícone de Wi-Fi não fica mais fora do centro do anel.
- Áudio: removida a linha duplicada de resumo da saída de áudio.

### Notas

- Enquanto uma troca de espaço é arrastada, apenas um ícone totalmente monocromático acompanha o espaço de destino; os elementos com cor de status (bateria fraca, modo de baixo consumo, energia conectada, Bluetooth) só se atualizam quando a troca é concluída.
