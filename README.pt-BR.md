<p align="center">
  <img src="screenshots/status-trio-dock-state-strip-symmetric.png" width="1000" alt="Oito estados do ícone do Status Trio no Dock com fundos escuros e claros dispostos simetricamente, incluindo Wi-Fi, áudio Bluetooth, bateria, pontos e estados de arco">
</p>

<p align="center">
  <img src="Support/AppIcon.png" width="112" alt="Ícone do app Status Trio">
</p>

<h1 align="center">Status Trio</h1>

<p align="center">
  <a href="https://trendshift.io/repositories/234371?utm_source=trendshift-badge&utm_medium=badge&utm_campaign=badge-trendshift-234371" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/234371/daily?language=Swift" alt="lingyired/status-trio | Trendshift" width="250" height="55"/></a>
</p>

<p align="center"><strong>Três sinais do sistema. Um único ícone de status nativo do macOS — na sua barra de menus ou no Dock.</strong></p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-Universal%20%C2%B7%20macOS%2013%20target-000000?logo=apple&logoColor=white&style=for-the-badge" alt="Baixar para macOS — versão universal, macOS 13 como destino de implantação (validação do Ventura pendente)"></a>
</p>

<p align="center">
  Quer ver como funciona antes? Abra <a href="https://statustrio.lingai.net/">statustrio.lingai.net</a> para simular todos os estados do ícone no seu navegador.
</p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/github/v/release/lingyired/status-trio?label=release&color=blue" alt="Versão mais recente"></a>
  <a href="https://github.com/lingyired/status-trio/actions/workflows/release.yml"><img src="https://github.com/lingyired/status-trio/actions/workflows/release.yml/badge.svg" alt="Status do fluxo de trabalho Build and Release do macOS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lingyired/status-trio?label=license" alt="Licença: Apache-2.0"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%20target%20%28validation%20pending%29-blue?logo=apple&logoColor=white" alt="Compatível com macOS 13 como destino de implantação (validação do Ventura pendente)">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="Binário universal para Apple Silicon e Intel">
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <strong>Português (Brasil)</strong> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="screenshots/menu-bar-wifi.jpg" width="1000" alt="Ícone do Status Trio na barra de menus mostrando o glifo de Wi-Fi enquanto está conectado ao Wi-Fi, com o popover de status aberto">
</p>

O Status Trio é um app de status nativo do macOS que reúne Wi-Fi, bateria e volume em um único ícone compacto e configurável, exibido na barra de menus, no Dock ou em ambos. Seu popover vai além do ícone: um painel de Wi-Fi para redes próximas e detalhes do link, um painel de Bluetooth para dispositivos pareados, uma página de Detalhes da bateria e os dispositivos de áudio que estão reproduzindo. Ele é inspirado no ícone combinado da barra de status do iPhone Duo para Wi-Fi, Bateria e Dados Celulares, adaptado para o Mac com Volume no lugar dos Dados Celulares.

> O Status Trio é um projeto independente e não é afiliado à Apple.

## Destaques

- **Um ícone, três sinais** — bateria, Wi-Fi e volume compartilham um único ícone na barra de menus, no Dock ou em ambos, e um dispositivo Bluetooth que está reproduzindo pode ocupar o lugar central com seu próprio símbolo.
- **Bluetooth** — o indicador de volume fica azul durante a reprodução. O painel lista os dispositivos pareados que você pode tocar para conectar ou desconectar, mostra os níveis de bateria por padrão e permanece desativado até você ativá-lo.
- **Bateria** — porcentagem, carregando ou conectado à energia, tempo para carga total e uma cor quando fica fraca. Abra a linha para ver potência do adaptador, tensão, corrente, contagem de ciclos e Modo de baixo consumo.
- **Wi-Fi** — a rede em que você está e a intensidade do sinal. Abra para ver redes próximas, conferir os detalhes do link ou desativar o Wi-Fi. A troca entre redes acontece no painel de Wi-Fi dos Ajustes do Sistema.
- **Volume** — nível, mudo e o dispositivo de saída, desenhados como pontos ou arco. Role o painel inteiro ou apenas o controle e escolha qual direção aumenta o volume.
- **Do seu jeito** — tamanho do ícone, escala do símbolo, espessura do anel, cores de status e quais seções o popover exibe, na ordem que você quiser.
- **Barra de menus, Dock ou ambos** — e o ícone do Dock pode seguir o estilo do sistema ou permanecer escuro ou claro.
- **Nativo no macOS** — o clique com o botão esquerdo abre o popover, o clique com o botão direito abre o menu, e um guia de primeira execução explica cada parte do ícone. Ethernet, um ponto de acesso pessoal ou Compartilhamento de Internet podem manter o glifo de Wi-Fi, se você preferir.
- **Sempre atualizado** — o status vem de eventos do sistema, com uma sondagem lenta como alternativa, e o Sparkle atualiza o app por um feed assinado.
- **Também incluído** — doze idiomas e a opção de abrir ao iniciar sessão.

## Instalação

Instale pelo Cask oficial do Homebrew:

```bash
brew install --cask status-trio
```

Para atualizar uma instalação do Homebrew:

```bash
brew upgrade --cask status-trio
```

Ou baixe o `StatusTrio-*.dmg` mais recente em [GitHub Releases](https://github.com/lingyired/status-trio/releases/latest), abra e arraste `Status Trio.app` para `/Applications`.

A versão oficial é assinada com Developer ID e notarizada pela Apple. Abra normalmente após instalar; não é necessário remover atributos de quarentena. As atualizações no app usam Sparkle com verificação de assinatura EdDSA.

## Controles de entrada e áudio

- **Ícone de entrada**: mostre o método de entrada atual no centro do ícone da barra de menus e do Dock. Escolha em **Ajustes › Rede**; selecione uma fonte habilitada no painel para alternar para ela.
- **Atalho global**: configure em **Ajustes › Geral** para abrir ou fechar o painel a partir de outro app. Nenhum atalho é atribuído por padrão.
- **Controles Bluetooth**: ligue ou desligue o Bluetooth, conecte ou desconecte dispositivos e altere modos de escuta em AirPods e HUAWEI FreeBuds compatíveis. As linhas opcionais de bateria de dispositivos Apple são configuradas nos ajustes de Bluetooth; dependem do dispositivo e da conexão.
- **Entrada e saída de áudio**: selecione alto-falantes ou microfones e ajuste seus níveis. Controle alto-falantes de monitores externos compatíveis por DDC; o suporte depende do hardware e da conexão.
- **Carga e aparência**: efeitos de carga na barra de menus e no Dock. No macOS 26 ou posterior, o ícone no Finder e Launchpad também acompanha a aparência clara ou escura do sistema.

## Novidades em main (não publicadas)

Estas funções estão no código de `main`, mas não na versão pública atual do GitHub / Homebrew, **1.7.5**:

- **Fluxo de potência e impacto energético da CPU**: estimativas de entrada do carregador, carga da bateria e potência do sistema. Uma lista opcional ordena até cinco apps por energia de CPU, ou atividade de CPU quando faltam contadores. Não representa o consumo total nem a lista nativa do macOS. Ativá-la inicia amostragem periódica em segundo plano; desativá-la interrompe a coleta. [Detalhes](docs/battery-power-flow.md).
- **Carregar totalmente agora e cancelar**: opção desativada por padrão para Macs Apple Silicon compatíveis com macOS 26.4 ou posterior. Usa uma interface privada PowerUI para suspender o limite. **O limite pode permanecer em 100% após carregar ou reconectar a energia; não é restaurado automaticamente.** Cancele para solicitar a restauração ou confira e restaure o limite nos Ajustes do Sistema. O comportamento depende do macOS. [Comportamento e verificação](docs/charge-to-full-now-poc.md).

## Áudio Bluetooth

Enquanto o áudio é reproduzido por Bluetooth, dois interruptores em **Ajustes › Bluetooth** permitem que o glifo central se torne o símbolo do próprio dispositivo — AirPods, fones de ouvido, alto-falantes e outros dispositivos fornecem o seu — e que os pontos ou o arco de volume fiquem azuis. Ambos ficam desativados por padrão. **Priorizar erros de rede**, ativado por padrão, mantém o ícone de rede enquanto a própria conexão está com problemas:

<p align="center">
  <img src="screenshots/menu-bar-airpods.jpg" width="1000" alt="Ícone do Status Trio na barra de menus mostrando o glifo dos AirPods enquanto os AirPods estão conectados, com o popover de status aberto">
</p>

A linha Bluetooth do popover informa o estado ao vivo: os nomes dos dispositivos conectados e, no caso dos AirPods, a bateria do esquerdo, do direito e do estojo. O painel de Bluetooth lista os dispositivos pareados e o estado de conexão deles: toque em um dispositivo para conectar e em um conectado para desconectar — teclados, mouses, trackpads e gamepads pedem confirmação primeiro, na própria linha. Ele fica desativado por padrão, é ativado em **Ajustes › Painel de status** e solicita permissão de Bluetooth no primeiro uso. **Ajustes › Bluetooth** também controla se os níveis de bateria são lidos, lista os dispositivos pareados para você arrastá-los na ordem que você quiser e escolher quantos aparecem, e ajusta o tamanho do ícone de Bluetooth de 100% a 180%.

## Ícone do Dock

O mesmo ícone ao vivo pode ficar no Dock em vez da barra de menus, ou nos dois lugares ao mesmo tempo:

<p align="center">
  <img src="screenshots/status-trio-dock-dark-1440x810.jpg" width="880" alt="Ícone ao vivo do Status Trio no Dock com aparência escura">
  <br>
  <sub>Ícone do Dock com aparência escura</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-1440x810.jpg" width="880" alt="Ícone ao vivo do Status Trio no Dock com aparência clara">
  <br>
  <sub>Ícone do Dock com aparência clara</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-bt-1440x810.jpg" width="880" alt="Status Trio no Dock com o painel de Bluetooth exibido, aparência clara">
  <br>
  <sub>Prévia do painel de Bluetooth</sub>
</p>

O ícone do Dock desenha o mesmo ícone combinado da barra de menus, então, com a substituição pelo áudio Bluetooth ativada, o glifo do dispositivo também assume o centro ali. Seu fundo pode seguir o estilo de ícone do sistema ou ser fixado em um tom fixo:

<p align="center">
  <img src="screenshots/status-trio-dock-icons.png" width="880" alt="Ícone do Dock do Status Trio com fundos escuro, claro e transparente, em duas linhas: o estado de Wi-Fi e o áudio Bluetooth substituindo o ícone de Wi-Fi com pontos de volume azuis">
</p>

## Estados do ícone

Todos os estados que o ícone combinado pode exibir, desenhados pelo próprio renderizador do app — indicadores de bateria na parte superior, Wi-Fi (ou o dispositivo de áudio Bluetooth que pode substituí-lo, quando essa opção está ativada) no centro, e os pontos de volume ou o arco na parte inferior, ficando azuis enquanto um dispositivo Bluetooth está reproduzindo:

<p align="center">
  <img src="screenshots/status-trio-icon-states.png" width="880" alt="Estados do ícone do Status Trio: carregando, conectado à energia, porcentagem, bateria fraca e Modo de baixo consumo na parte superior; sinal de Wi-Fi, ponto de acesso pessoal, temporário, compartilhado e com fio no centro; áudio Bluetooth substituindo o ícone de Wi-Fi, Wi-Fi mantido durante um erro de rede e pontos e arco de volume azuis logo abaixo; estilos de pontos e arco de volume para todos os níveis na parte inferior">
</p>

Os mesmos estados renderizados para uma barra de menus escura:

<p align="center">
  <img src="screenshots/status-trio-icon-states-dark.png" width="880" alt="Os mesmos estados do ícone do Status Trio em aparência escura: glifos brancos sobre chips escuros, carregamento em verde, bateria fraca em vermelho e destaques em amarelo do Modo de baixo consumo, e o azul mais vibrante que o app usa para o áudio Bluetooth em uma barra de menus escura">
</p>

## Requisitos

- macOS 13 como destino de implantação (validação do Ventura pendente) para executar o app
- Toolchain do Swift 6 com o SDK do macOS 26 (Xcode 26 ou posterior) para compilá-lo. Compilar com um
  SDK mais antigo produz silenciosamente a aparência de popover anterior ao Tahoe, então `scripts/build-app.sh`
  falha quando o SDK for anterior ao 26.

## Executar a partir do código-fonte

```bash
git clone https://github.com/lingyired/status-trio.git
cd status-trio
swift run StatusTrio
```

## Compilar um app local

Compile um bundle de app assinado ad-hoc e inicie-o:

```bash
bash scripts/build-app.sh release
```

O bundle é criado em `dist/StatusTrio.app`. Para compilar sem encerrar ou iniciar uma instância existente, execute:

```bash
bash scripts/build-app.sh release no-open
```

O bundle assinado ad-hoc é destinado a uso pessoal local. O Gatekeeper pode rejeitá-lo se o bundle for transferido com metadados de quarentena.

## Uso

- **Clique com o botão esquerdo** no ícone da barra de menus ou no ícone do Dock para abrir o popover de status.
- **Clique com o botão direito** em qualquer um dos ícones para abrir o menu nativo, incluindo as ações de versão e de sair.
- Selecione a linha de Wi-Fi ou bateria no popover para abrir a página correspondente: redes próximas e detalhes do link, ou Detalhes da bateria. A linha Bluetooth lista os dispositivos pareados ali mesmo — toque em um para conectar ou desconectar — com um controle Expandir quando não couberem todos.
- Abra os **Ajustes** para escolher onde o ícone é exibido (barra de menus, Dock ou ambos) e para alterar seu tamanho, as cores, a espessura do anel, as seções do painel e a ordem delas, o comportamento de ajuste por rolagem, o idioma, a verificação de atualizações e a opção de abrir ao iniciar sessão.
- Reabra o guia **Conheça seu ícone** a qualquer momento em **Ajustes › Ícone do app › Abrir guia**.
- Ative o nome da rede Wi-Fi atual quando solicitado; o macOS pede acesso à localização para esse detalhe opcional.

## Limitações conhecidas

Dois limites que o macOS e este projeto traçam de propósito. Ambos são explicados em [Limitações conhecidas](docs/known-limitations.md).

- **A troca entre redes acontece nos Ajustes do Sistema.** Escolher uma rede no popover abre o painel de Wi-Fi; o Status Trio nunca lê nem armazena senhas de Wi-Fi, porque o macOS não oferece nenhuma API pública para conectar-se com uma senha salva, e todas as alternativas acabam com o app guardando essas senhas.
- **O controle do limite de carga depende da versão.** A versão 1.7.5 abre os Ajustes do Sistema. A opção de `main` usa uma interface privada e exige cancelamento explícito para solicitar a restauração. [Detalhes](docs/charge-to-full-now-poc.md). O Modo Pouca Energia usa um [helper privilegiado opcional](docs/privileged-helper.md) separado.

## Idiomas

O Status Trio segue o idioma preferido do macOS por padrão e inclui English, 简体中文, 繁體中文, 日本語, 한국어, Español, Français, Deutsch, Italiano, Português (Brasil), Русский e العربية.

## Privacidade

Status Trio lê o estado do sistema localmente. Estatísticas anônimas só são enviadas ao serviço próprio após você ativá-las; ficam desligadas em atualizações e são oferecidas na primeira instalação. Incluem ID aleatório, versões do app e macOS, idioma e posição do ícone, sem nomes, contas, detalhes de rede ou identificadores de hardware. Veja [telemetria e privacidade](docs/privacy-telemetry.md). O app não lê nem armazena senhas Wi-Fi e não pede acesso às Chaves. A localização é opcional para nome e detalhes de Wi-Fi; Bluetooth é solicitado ao ativar seu painel. Em `main`, o controle opcional de carga completa usa uma interface privada PowerUI apenas quando habilitado; os limites estão descritos antes.

## Desenvolvimento

Execute a suíte de testes:

```bash
bash scripts/verify-local.sh quick BatteryMonitorTests
bash scripts/verify-local.sh docs
bash scripts/verify-local.sh full
```

Execute um filtro XCTest específico pelo script auxiliar:

```bash
bash scripts/test.sh BatteryMonitorTests
```

Para compilar um app de worktree ao lado da instalação principal:

```bash
bash scripts/build-worktree.sh release
```

O script auxiliar deriva um identificador de bundle de desenvolvimento e um nome de exibição a partir da ramificação atual. Os dois valores podem ser substituídos:

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

O bloqueio de instância única é definido pelo identificador de bundle, então builds com identificadores diferentes podem ser executados ao mesmo tempo.

## Base técnica

- Swift 6
- SwiftUI + AppKit
- macOS 13 deployment target (Ventura runtime validation pending)
- `LSUIElement`: acessório da barra de menus que muda para uma política de ativação regular enquanto o ícone do Dock é exibido
- Sparkle para verificação de atualizações

## Documentação

- [Limitações conhecidas](docs/known-limitations.md)
- [Versões automatizadas do GitHub Actions](docs/github-actions-release.md)
- [Especificação de design do Status Trio](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [SVG do ícone da barra de menus](status-menubar.svg)
- [Demonstração do ícone orientada por dados](status-menubar-demo.html)

## Licença

Copyright 2026 lingyired.

Licenciado sob a Apache License, Version 2.0. Consulte [LICENSE](LICENSE) e [NOTICE](NOTICE).

## Autor

Criado e mantido por [lingyired](https://github.com/lingyired).<br>
Site: [https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
