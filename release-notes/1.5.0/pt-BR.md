# Versão %VERSION% (build %BUILD%)

### Melhorias

- Melhoramos a consistência das atualizações do painel de status, preservando controles, layout e navegação.
- A exibição do painel de status ficou mais confiável diante de mudanças no dispositivo, na rede e no áudio.

### Privacidade

- Adicionamos estatísticas de uso opcionais. Em novas instalações, a opção fica ativada por padrão, mas nenhum heartbeat é enviado antes de concluir o guia ou escolher Personalizar. Em atualizações, o recurso permanece desativado até ser habilitado nos Ajustes.
- O heartbeat contém um ID de instalação aleatório, versões do app e do macOS, idiomas do sistema e do app e posição do ícone. Consulte [privacidade e análises](https://github.com/lingyired/status-trio/blob/main/docs/privacy-telemetry.md).
- O app não inclui nenhum SDK de análise de terceiros.
