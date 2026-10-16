# Versão %VERSION% (build %BUILD%)

### Novidades

- Agora é compatível com o macOS 13.
- Adicionamos estatísticas de uso opcionais. Ficam desativadas por padrão; você precisa ativá-las.
- Bateria de dispositivos Apple: permite ler a bateria de um Apple Watch pareado por meio de um iPhone conectado e mostra dispositivos Apple confiáveis como linhas unificadas na lista de Bluetooth. Também adiciona atualização de bateria em segundo plano com intervalo configurável. A bateria é lida apenas nos dispositivos selecionados visíveis no painel.
- Agora você pode personalizar o ícone de áudio do Bluetooth.

### Melhorias

- Otimizamos a lógica de atualização do ícone e do painel de status.

### Correções

- Renderização de ícones: corrigimos a fidelidade dos bitmaps em cache, o redimensionamento da animação estável, a coloração do raio de carregamento do heartbeat e o alinhamento da barra de menus e do Dock.
- A primeira atualização de Bluetooth não abre mais os Ajustes por engano.

### Privacidade

- Explica as estatísticas de uso opcionais, o que um heartbeat contém e que nenhum SDK de análise de terceiros está incluído. Consulte [privacidade e análises](https://github.com/lingyired/status-trio/blob/main/docs/privacy-telemetry.md) para ver todos os detalhes.
