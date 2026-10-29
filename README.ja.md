<p align="center">
  <img src="screenshots/status-trio-dock-state-strip-symmetric.png" width="1000" alt="ダークとライトの背景を左右対称に並べた 8 種類の Status Trio Dock アイコン状態。Wi-Fi、Bluetooth オーディオ、バッテリー、ドット、円弧の各状態を含みます">
</p>

<p align="center">
  <img src="Support/AppIcon.png" width="112" alt="Status Trio のアプリアイコン">
</p>

<h1 align="center">Status Trio</h1>

<p align="center">
  <a href="https://trendshift.io/repositories/234371?utm_source=trendshift-badge&utm_medium=badge&utm_campaign=badge-trendshift-234371" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/234371/daily?language=Swift" alt="lingyired/status-trio | Trendshift" width="250" height="55"/></a>
</p>

<p align="center"><strong>3 つのシステムシグナル。1 つのネイティブ macOS ステータスアイコン — メニューバーでも Dock でも。</strong></p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-Universal%20%C2%B7%20macOS%2013%20target-000000?logo=apple&logoColor=white&style=for-the-badge" alt="macOS 版をダウンロード — ユニバーサルビルド、macOS 13 を展開対象として対応（Ventura の実行検証は保留中）"></a>
</p>

<p align="center">
  まず動きを見てみたいですか？<a href="https://statustrio.lingai.net/">statustrio.lingai.net</a> を開くと、ブラウザで全アイコン状態をシミュレートできます。
</p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/github/v/release/lingyired/status-trio?label=release&color=blue" alt="最新リリース"></a>
  <a href="https://github.com/lingyired/status-trio/actions/workflows/release.yml"><img src="https://github.com/lingyired/status-trio/actions/workflows/release.yml/badge.svg" alt="Build and Release macOS ワークフローのステータス"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lingyired/status-trio?label=license" alt="ライセンス: Apache-2.0"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%20target%20%28validation%20pending%29-blue?logo=apple&logoColor=white" alt="macOS 13 を展開対象として対応（Ventura の実行検証は保留中）に対応">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="Apple Silicon と Intel 向けのユニバーサルバイナリ">
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <strong>日本語</strong> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português (Brasil)</a> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="screenshots/menu-bar-wifi.jpg" width="1000" alt="Wi-Fi に接続中で Wi-Fi グリフを表示する Status Trio のメニューバーアイコン。ステータスポップオーバーを開いた状態">
</p>

Status Trio は、Wi-Fi、バッテリー、音量を 1 つのコンパクトでカスタマイズ可能なアイコンにまとめ、メニューバー、Dock、またはその両方に表示するネイティブ macOS ステータスアプリです。ポップオーバーはアイコンよりさらに踏み込み、近くのネットワークとリンク詳細を表示する Wi-Fi パネル、ペアリング済みデバイスを表示する Bluetooth パネル、バッテリーの詳細ページ、再生中のオーディオデバイスを備えています。iPhone Duo が Wi-Fi、バッテリー、モバイル通信を 1 つのステータスバーアイコンにまとめていることに着想を得て、Mac 向けにモバイル通信の代わりに音量を使う形に合わせています。

> Status Trio は独立したプロジェクトであり、Apple とは提携していません。

## ハイライト

- **1 つのアイコン、3 つのシグナル** — バッテリー、Wi-Fi、音量がメニューバー、Dock、またはその両方で 1 つのアイコンを共有し、再生中の Bluetooth デバイスは独自のシンボルで中央の位置を引き継ぐことができます。
- **Bluetooth** — 再生中は音量インジケータが青色になります。パネルには、タップで接続や切断できるペアリング済みのデバイスが一覧表示され、バッテリー残量は初期状態で表示され、有効にするまではオフのままです。
- **バッテリー** — パーセント表示、充電中または電源接続、満充電までの時間、残量が少なくなったときの色分け。行を開くと、アダプタの定格出力、電圧、電流、充放電回数、低電力モードを確認できます。
- **Wi-Fi** — 接続中のネットワークと電波の強さ。開くと、近くのネットワークの表示、リンク詳細の確認、Wi-Fi のオフができます。ネットワーク間の切り替えは、システム設定の Wi-Fi パネルで行います。
- **音量** — レベル、ミュート、出力デバイスを、ドットまたは円弧で表示します。パネル全体またはコントロールのみをスクロールでき、音量を上げる方向も選べます。
- **自分好みにカスタマイズ** — アイコンの表示サイズ、シンボルサイズ、外枠リングの太さ、ステータスカラー、ポップオーバーに表示する項目とその順序を自由に設定できます。
- **メニューバー、Dock、または両方** — Dock アイコンの背景はシステム設定に従わせるか、ダークまたはライトに固定できます。
- **macOS ネイティブ** — 左クリックでポップオーバー、右クリックでメニューが開き、初回起動時のガイドがアイコンの各部分を説明します。Ethernet、ホットスポット、インターネット共有でも、設定次第で Wi-Fi グリフを表示し続けられます。
- **常に最新の状態** — ステータスはシステムイベントから取得し、補助として低頻度のポーリングも行います。アプリの更新は Sparkle が署名済みフィードを通じて行います。
- **その他** — 12 言語に対応し、ログイン時の起動も任意で設定できます。

## インストール

Homebrew の公式 Cask からインストール：

```bash
brew install --cask status-trio
```

Homebrew でインストール済みの場合の更新：

```bash
brew upgrade --cask status-trio
```

または [GitHub Releases](https://github.com/lingyired/status-trio/releases/latest) から最新の `StatusTrio-*.dmg` をダウンロードして開き、`Status Trio.app` を `/Applications` にドラッグします。

公式リリースは Developer ID で署名され、Apple の公証を受けています。インストール後は通常どおり開けます。隔離属性を削除するコマンドは不要です。アプリ内更新には Sparkle と EdDSA 署名検証を使用します。

## 入力ソースとオーディオの操作

- **入力ソースアイコン**：メニューバーと Dock の中央に現在の入力ソースを表示できます。**設定 › ネットワーク**で選択し、パネルから有効な入力ソースを選んで切り替えられます。
- **グローバルショートカット**：**設定 › 一般**で割り当てると、他のアプリからパネルを開閉できます。既定では未割り当てです。
- **Bluetooth 操作**：パネルで Bluetooth のオン／オフ、接続／切断、対応する AirPods と HUAWEI FreeBuds のリスニングモード変更ができます。Apple デバイスの任意のバッテリー表示は Bluetooth 設定で有効にします。利用可否はデバイスと接続によります。
- **音声の入力と出力**：スピーカーやマイクを選び、入力・出力音量を調整できます。対応する外部ディスプレイのスピーカーは DDC で操作します。対応状況はハードウェアと接続によります。
- **充電と外観**：メニューバーと Dock の充電エフェクトに対応。macOS 26 以降では Finder と Launchpad のアプリアイコンもシステムの明暗に追従します。

## main の新機能（未リリース）

次の機能は `main` のソースに含まれますが、現在の GitHub / Homebrew 公開版 **1.7.5** には含まれません：

- **電力フローと CPU エネルギー影響**：充電器入力、バッテリー充電、システム電力の推定値を表示します。任意の一覧は CPU エネルギーで最大 5 アプリを順位付けし、取得できない場合は CPU 活動量を使います。総消費電力や macOS 純正の高エネルギー一覧ではありません。有効時は定期的にバックグラウンド計測し、無効にすると停止します。[詳細](docs/battery-power-flow.md)。
- **今すぐフル充電とキャンセル**：対応する Apple シリコン Mac、macOS 26.4 以降で有効化できる、既定でオフの機能です。非公開 PowerUI API で充電上限を解除します。**満充電や電源の抜き差し後も上限が 100% のまま残る場合があり、自動復元しません。** キャンセル操作で復元を要求するか、システム設定で上限を確認・復元してください。動作は macOS に依存します。[動作と検証](docs/charge-to-full-now-poc.md)。

## Bluetooth オーディオ

Bluetooth でオーディオを再生している間、**設定 › Bluetooth** の 2 つのスイッチで、中央のグリフをそのデバイス固有のシンボル（AirPods、ヘッドホン、スピーカーなどのデバイスがそれぞれのシンボルを提供します）に切り替えたり、音量のドットまたは円弧を青色にしたりできます。どちらも初期状態はオフです。初期状態でオンの**ネットワークエラーを優先**は、接続自体に問題がある間はネットワークアイコンを表示し続けます：

<p align="center">
  <img src="screenshots/menu-bar-airpods.jpg" width="1000" alt="AirPods 接続中に AirPods グリフを表示する Status Trio のメニューバーアイコン。ステータスポップオーバーを開いた状態">
</p>

ポップオーバーの Bluetooth 項目はライブ状態を表示します。接続中のデバイス名と、AirPods の場合は左右およびケースのバッテリー残量です。Bluetooth パネルはペアリング済みデバイスとその接続状態を一覧表示します。デバイスをタップすると接続し、接続中のデバイスをタップすると切断します。キーボード、マウス、トラックパッド、ゲームパッドでは、先にその行内で確認を求めます。初期状態はオフで、**設定 › ステータスパネル**で有効にでき、初回使用時に Bluetooth の権限を求めます。**設定 › Bluetooth** では、バッテリー残量を読み取るかどうかを制御し（初期状態でオン）、ペアリング済みデバイスを一覧表示し、ドラッグで並べ替えや表示するデバイス数を設定でき、Bluetooth アイコンを 100% 〜 180% で拡大縮小します。

## Dock アイコン

同じライブアイコンは、メニューバーの代わりに Dock に表示することも、両方に同時に表示することもできます：

<p align="center">
  <img src="screenshots/status-trio-dock-dark-1440x810.jpg" width="880" alt="ダーク表示の Dock にある Status Trio のライブアイコン">
  <br>
  <sub>ダーク表示の Dock アイコン</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-1440x810.jpg" width="880" alt="ライト表示の Dock にある Status Trio のライブアイコン">
  <br>
  <sub>ライト表示の Dock アイコン</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-bt-1440x810.jpg" width="880" alt="Bluetooth パネルを表示したライト表示の Dock の Status Trio">
  <br>
  <sub>Bluetooth パネルのプレビュー</sub>
</p>

Dock アイコンはメニューバーと同じ組み合わせアイコンを描画するため、Bluetooth オーディオの置き換えを有効にすると、そこでもデバイスのグリフが中央を引き継ぎます。背景はシステムのアイコンスタイルに従わせるか、固定の明暗に設定できます：

<p align="center">
  <img src="screenshots/status-trio-dock-icons.png" width="880" alt="ダーク、ライト、クリア背景の Status Trio Dock アイコンを 2 行で表示。Wi-Fi の状態と、Wi-Fi アイコンを置き換えて青い音量ドットを伴う Bluetooth オーディオ">
</p>

## アイコンの状態

組み合わせアイコンが表示できるすべての状態を、アプリ自身のレンダラーで描画したものです。上部がバッテリー表示、中央が Wi-Fi（そのオプションがオンのときは、それを置き換え得る Bluetooth オーディオデバイス）、下部が音量のドットまたは円弧で、Bluetooth デバイスの再生中は青色になります：

<p align="center">
  <img src="screenshots/status-trio-icon-states.png" width="880" alt="Status Trio のアイコン状態：上部が充電中、電源接続、パーセント表示、低バッテリー、低電力モード。中央が Wi-Fi シグナル、ホットスポット、一時接続、共有、有線の各状態。その下が Wi-Fi アイコンを置き換える Bluetooth オーディオ、ネットワークエラー時に Wi-Fi を維持する状態、青い音量ドットと円弧。下部がすべてのレベルに対応する音量ドットと円弧のスタイル">
</p>

同じ状態をダークなメニューバー向けに描画したもの：

<p align="center">
  <img src="screenshots/status-trio-icon-states-dark.png" width="880" alt="ダーク表示の同じ Status Trio アイコン状態：ダークなチップ上の白いグリフ、緑の充電、赤の低バッテリーと黄の低電力モードのアクセント、そしてダークなメニューバーでアプリが Bluetooth オーディオに使うより明るい青">
</p>

## 動作環境

- アプリの実行には macOS 13 を展開対象として対応（Ventura の実行検証は保留中）
- ビルドには macOS 26 SDK を備えた Swift 6 ツールチェーン（Xcode 26 以降）が必要です。古い SDK でビルドすると、Tahoe 以前のポップオーバー外観が警告なく生成されるため、`scripts/build-app.sh` は SDK が 26 より古い場合に失敗します。

## ソースから実行

```bash
git clone https://github.com/lingyired/status-trio.git
cd status-trio
swift run StatusTrio
```

## ローカルアプリをビルド

ad-hoc 署名済みのアプリバンドルをビルドして起動します：

```bash
bash scripts/build-app.sh release
```

バンドルは `dist/StatusTrio.app` に作成されます。既存のインスタンスを終了したり起動したりせずにビルドするには、次を実行します：

```bash
bash scripts/build-app.sh release no-open
```

ad-hoc 署名済みのバンドルはローカルでの個人利用を目的としています。隔離属性を付けたままバンドルを移動すると、Gatekeeper が拒否する場合があります。

## 使い方

- メニューバーアイコンまたは Dock アイコンを**左クリック**すると、ステータスポップオーバーが開きます。
- どちらのアイコンも**右クリック**すると、バージョンや終了などのネイティブメニューが開きます。
- ポップオーバーで Wi-Fi またはバッテリーの行を選択すると、そのページが開きます：近くのネットワークとリンク詳細、またはバッテリーの詳細です。Bluetooth 行はペアリング済みデバイスをその場で一覧表示します — タップで接続や切断 — デバイスがすべて入りきらないときは「展開」コントロールが表示されます。
- **設定**を開くと、アイコンの表示場所（メニューバー、Dock、または両方）を選び、サイズ、色、外枠リングの太さ、パネルの項目とその順序、スクロールで音量を調整する動作、言語、アップデートの確認、ログイン時に起動を変更できます。
- **アイコンの見方**ガイドは、**設定 › アプリアイコン › ガイドを開く** からいつでも再度開けます。
- 求められたら現在の Wi-Fi ネットワーク名を有効にしてください。この任意の項目のために、macOS が位置情報へのアクセスを要求します。

## 既知の制限

macOS とこのプロジェクトが意図的に引いている 2 つの境界があります。どちらも[既知の制限](docs/known-limitations.md)で説明しています。

- **ネットワークの切り替えはシステム設定で行います。** ポップオーバーでネットワークを選択すると Wi-Fi パネルが開きます。macOS は保存済みのパスワードで接続するための公開 API を提供しておらず、ほかのどの方法も最終的にはアプリがパスワードを保持することになるため、Status Trio は Wi-Fi のパスワードを読み取ることも保存することもありません。
- **充電上限の操作はバージョンによります。** 公開版 1.7.5 はシステム設定で操作します。`main` の任意機能は非公開 API を使い、復元には明示的なキャンセルが必要です。[詳細](docs/charge-to-full-now-poc.md)。低電力モードには別の[任意の特権ヘルパー](docs/privileged-helper.md)を使います。

## 言語

Status Trio は既定で macOS の優先言語に従い、English、简体中文、繁體中文、日本語、한국어、Español、Français、Deutsch、Italiano、Português (Brasil)、Русский、العربية に対応しています。

## プライバシー

Status Trio はシステム状態をローカルで読み取ります。匿名の使用統計は明示的に有効にした場合のみ第一者サービスに送信します。アップグレード時はオフ、新規インストール時は案内で選択します。送信内容はランダムなインストール ID、アプリと macOS のバージョン、言語、アイコン配置で、名前、アカウント、ネットワーク詳細、ハードウェア識別子は含みません。[プライバシー](docs/privacy-telemetry.md)。Wi-Fi パスワードの読み取りや保存、キーチェーンへのアクセスは行いません。位置情報は任意の Wi-Fi 名称と詳細に、Bluetooth 権限は Bluetooth パネルを有効にしたときに要求します。`main` のフル充電操作は有効時のみ非公開 PowerUI API を使います。制限は前述のとおりです。

## 開発

テストスイートを実行します：

```bash
bash scripts/verify-local.sh quick BatteryMonitorTests
bash scripts/verify-local.sh docs
bash scripts/verify-local.sh full
```

ヘルパーを使って特定の XCTest フィルタを実行します：

```bash
bash scripts/test.sh BatteryMonitorTests
```

メインのインストールと並行して worktree アプリをビルドするには：

```bash
bash scripts/build-worktree.sh release
```

ヘルパーは現在のブランチから開発用のバンドル識別子と表示名を生成します。どちらの値も上書きできます：

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

単一インスタンスのロックはバンドル識別子単位で適用されるため、識別子が異なるビルドは同時に実行できます。

## 技術的な前提

- Swift 6
- SwiftUI + AppKit
- macOS 13 deployment target (Ventura runtime validation pending)
- `LSUIElement` のメニューバーアクセサリ。Dock アイコンの表示中は通常のアクティベーションポリシーに切り替わります
- アップデートの確認に Sparkle

## ドキュメント

- [既知の制限](docs/known-limitations.md)
- [GitHub Actions による自動リリース](docs/github-actions-release.md)
- [Status Trio 設計仕様](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [メニューバーアイコン SVG](status-menubar.svg)
- [データ駆動のアイコンデモ](status-menubar-demo.html)

## ライセンス

Copyright 2026 lingyired.

Apache License, Version 2.0 に基づいてライセンスされています。[LICENSE](LICENSE) と [NOTICE](NOTICE) をご覧ください。

## 作者

作成・メンテナンス: [lingyired](https://github.com/lingyired)。<br>
ウェブサイト: [https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
