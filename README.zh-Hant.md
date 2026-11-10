<p align="center">
  <img src="screenshots/status-trio-dock-state-strip-symmetric.png" width="1000" alt="Status Trio 八種 Dock 圖示狀態，深色與淺色背景對稱排列，包含 Wi-Fi、藍牙音訊、電池、圓點和圓弧狀態">
</p>

<p align="center">
  <img src="Support/AppIcon.png" width="112" alt="Status Trio 應用程式圖示">
</p>

<h1 align="center">Status Trio</h1>

<p align="center">
  <a href="https://trendshift.io/repositories/234371?utm_source=trendshift-badge&utm_medium=badge&utm_campaign=badge-trendshift-234371" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/234371/daily?language=Swift" alt="lingyired/status-trio | Trendshift" width="250" height="55"/></a>
</p>

<p align="center"><strong>三種系統訊號，一個原生 macOS 狀態圖示 —— 就在你的選單列或 Dock。</strong></p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-Universal%20%C2%B7%20macOS%2013%20target-000000?logo=apple&logoColor=white&style=for-the-badge" alt="下載 macOS 版 —— 通用二進位檔，需 macOS 13 部署目標（Ventura 執行驗證待完成）"></a>
</p>

<p align="center">
  想先看看實際效果？打開 <a href="https://statustrio.lingai.net/">statustrio.lingai.net</a>，就能在瀏覽器裡模擬每一種圖示狀態。
</p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/github/v/release/lingyired/status-trio?label=release&color=blue" alt="最新發行版本"></a>
  <a href="https://github.com/lingyired/status-trio/actions/workflows/release.yml"><img src="https://github.com/lingyired/status-trio/actions/workflows/release.yml/badge.svg" alt="Build and Release macOS 工作流程狀態"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lingyired/status-trio?label=license" alt="授權條款：Apache-2.0"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%20target%20%28validation%20pending%29-blue?logo=apple&logoColor=white" alt="支援 macOS 13 部署目標（Ventura 執行驗證待完成）">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="通用二進位檔，支援 Apple Silicon 與 Intel">
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-Hans.md">简体中文</a> ·
  <strong>繁體中文</strong> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português (Brasil)</a> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="screenshots/menu-bar-wifi.jpg" width="1000" alt="Status Trio 選單列圖示：連接 Wi-Fi 時顯示 Wi-Fi 符號，並展開狀態彈出式視窗">
</p>

Status Trio 是一款原生 macOS 狀態應用程式，把 Wi-Fi、電池和音量整合成一個精巧、可自訂的圖示，顯示在選單列、Dock，或兩處同時顯示。它的彈出式視窗比圖示本身更深入：可用 Wi-Fi 面板查看附近網路與連線詳情、用藍牙面板查看已配對的裝置、還有「電池詳細資訊」頁面，以及正在播放的音訊裝置。靈感來自 iPhone Duo 把 Wi-Fi、電池和行動網路合併顯示的狀態列圖示，並在 Mac 上以音量取代行動網路。

> Status Trio 是獨立專案，與 Apple 沒有任何隸屬關係。

## 主要特色

- **一個圖示，三種訊號** —— 電池、Wi-Fi 和音量在選單列、Dock 或兩處共用同一個圖示，而正在播放的藍牙裝置還能以自己的符號佔據中間的位置。
- **藍牙** —— 播放時音量指示會變成藍色。面板會列出已配對裝置，點一下即可連接或斷開，電量預設顯示，並且在你啟用之前保持關閉。
- **電池** —— 顯示電量百分比、充電中或已連接電源、預計充滿時間，電量偏低時還會變色。打開該列可查看電源轉接器額定功率、電壓、電流、循環使用次數和低耗電模式。
- **Wi-Fi** —— 顯示你目前所在的網路與訊號強弱。打開後可查看附近的網路、鏈路詳細資訊，或直接關閉 Wi-Fi。切換網路請在系統設定的 Wi-Fi 面板中操作。
- **音量** —— 音量大小、靜音狀態和輸出裝置，以圓點或圓弧呈現。可捲動整個面板或只捲動控制項，並選擇哪個方向是調高音量。
- **打造自己的風格** —— 圖示顯示尺寸、符號縮放比例、外環線條粗細、狀態顏色，以及彈出式視窗要顯示哪些區塊、以什麼順序排列。
- **選單列、Dock，或兩處同時顯示** —— 而 Dock 圖示可以跟隨系統樣式，或固定為深色或淺色。
- **原生 macOS 體驗** —— 按左鍵打開彈出式視窗，按右鍵打開選單，首次啟動時還有導覽逐一解說圖示的每個部分。如果你比較喜歡，乙太網路、個人熱點或網際網路共享也可以保留 Wi-Fi 符號。
- **保持最新** —— 狀態來自系統事件，並以低頻輪詢作為備援；Sparkle 會透過已簽署的更新來源更新應用程式。
- **還包括** —— 十二種語言，以及可選的開機時啟動。

## 安裝

透過 Homebrew 官方 Cask 安裝：

```bash
brew install --cask status-trio
```

更新已透過 Homebrew 安裝的版本：

```bash
brew upgrade --cask status-trio
```

也可以從 [GitHub Releases](https://github.com/lingyired/status-trio/releases/latest) 下載最新的 `StatusTrio-*.dmg`，開啟後將 `Status Trio.app` 拖入 `/Applications`。

官方發行版已使用 Developer ID 簽署並通過 Apple 公證。安裝後正常開啟即可，無需執行移除隔離屬性的指令。應用程式內更新由 Sparkle 提供，並驗證 EdDSA 簽章。

## 輸入法、音訊與日常控制

- **輸入法圖示**：選單列和 Dock 的中央圖示可顯示目前輸入法，在**設定 › 網路**中選擇；也可在面板選擇已啟用的輸入法並切換。
- **全域快捷鍵**：在**設定 › 一般**中設定快捷鍵，即可從其他應用程式開啟或關閉狀態面板，預設未指派。
- **藍牙控制**：直接開關藍牙、連接或中斷已配對裝置，並切換支援的 AirPods 和 HUAWEI FreeBuds 聆聽模式。可選的 Apple 裝置電量列在**設定 › 藍牙**中設定，讀取能力取決於裝置與連線方式。
- **音訊輸入與輸出**：選擇揚聲器或麥克風、調整輸出與輸入音量，並透過 DDC 控制相容的外接顯示器揚聲器；支援程度取決於硬體與連線。
- **充電與外觀**：選單列和 Dock 均可啟用充電特效；macOS 26 及更新版本的 Finder 和啟動台圖示也會跟隨系統深淺色外觀。

## main 分支新功能（尚未發行）

以下功能已合入 `main` 原始碼，尚未包含在目前 GitHub / Homebrew 公開版 **1.7.5** 中：

- **電池功率流向與 CPU 能耗影響**：顯示充電器輸入、電池充電與系統供電的估算功率。選用清單依 CPU 能耗列出最多五個應用程式，計數不可用時改用 CPU 活躍度；並非完整應用程式能耗或 macOS 原生高耗能清單。啟用清單後會定期背景取樣，關閉即停止。詳見[功率與能耗說明](docs/battery-power-flow.md)。
- **立即完全充電與取消**：支援的 Apple 晶片 Mac、macOS 26.4 及更新版本可選擇啟用按鈕，解除原生充電上限。功能使用私有 PowerUI 介面，預設關閉。**充滿或拔插電源後，上限可能仍為 100%，不會自動恢復。** 請使用取消操作要求恢復，或在系統設定中檢查並恢復上限。可用性與行為取決於 macOS，詳見[行為與驗證](docs/charge-to-full-now-poc.md)。

## 藍牙音訊

當音訊透過藍牙播放時，**設定 › 藍牙**中的兩個開關會讓中間的符號變成該裝置自己的符號 —— AirPods、耳機、揚聲器與其他裝置會各自提供 —— 並讓音量圓點或圓弧變成藍色。兩者預設都是關閉。預設開啟的**網路異常優先於藍牙圖示**會在連線本身出問題時保留網路圖示：

<p align="center">
  <img src="screenshots/menu-bar-airpods.jpg" width="1000" alt="Status Trio 選單列圖示：連接 AirPods 時顯示 AirPods 符號，並展開狀態彈出式視窗">
</p>

彈出式視窗中的藍牙列會顯示即時狀態：已連接裝置的名稱，以及 AirPods 的左耳、右耳和充電盒電量。藍牙面板會列出已配對裝置及其連接狀態：點一下裝置即可連接，再點一下已連接的裝置即可斷開，鍵盤、滑鼠、觸控板和遊戲手把會先在行內確認。它預設為關閉，需在**設定 › 狀態面板**中啟用，並在首次使用時要求藍牙權限。**設定 › 藍牙**也會控制是否讀取電量（預設開啟）、列出已配對裝置供你拖曳排序並設定最多顯示裝置數，並將藍牙圖示從 100% 縮放到 180%。

## Dock 圖示

同一個即時圖示也可以改放在 Dock，而不是選單列，或兩處同時顯示：

<p align="center">
  <img src="screenshots/status-trio-dock-dark-1440x810.jpg" width="880" alt="Dock 中的 Status Trio 即時圖示（深色外觀）">
  <br>
  <sub>Dock 圖示（深色外觀）</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-1440x810.jpg" width="880" alt="Dock 中的 Status Trio 即時圖示（淺色外觀）">
  <br>
  <sub>Dock 圖示（淺色外觀）</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-bt-1440x810.jpg" width="880" alt="Dock 中的 Status Trio 與藍牙面板（淺色外觀）">
  <br>
  <sub>藍牙面板預覽</sub>
</p>

Dock 圖示繪製的是與選單列相同的組合圖示，因此開啟藍牙音訊取代功能後，裝置符號同樣會佔據那裡的中間位置。它的背景可以跟隨系統圖示樣式，或固定為特定深淺：

<p align="center">
  <img src="screenshots/status-trio-dock-icons.png" width="880" alt="Status Trio Dock 圖示的深色、淺色與透明背景，分兩列呈現：Wi-Fi 狀態，以及藍牙音訊以藍色音量圓點取代 Wi-Fi 圖示">
</p>

## 圖示狀態

組合圖示能顯示的每一個狀態，全由應用程式自己的渲染器繪製 —— 頂部是電池指示，中間是 Wi-Fi（開啟該選項時，也可能是取代它的藍牙音訊裝置），底部是音量圓點或圓弧，並在藍牙裝置播放時轉為藍色：

<p align="center">
  <img src="screenshots/status-trio-icon-states.png" width="880" alt="Status Trio 圖示狀態：頂部為充電中、已連接電源、電量百分比、低電量與低耗電模式；中間為 Wi-Fi 訊號、個人熱點、臨時連線、共享與有線狀態；其下為藍牙音訊取代 Wi-Fi 圖示、網路異常時保留 Wi-Fi，以及藍色音量圓點與圓弧；底部為各級音量的圓點與圓弧樣式">
</p>

同一批狀態在深色選單列下的呈現：

<p align="center">
  <img src="screenshots/status-trio-icon-states-dark.png" width="880" alt="相同的 Status Trio 圖示狀態在深色外觀下：深色底塊上的白色符號、綠色充電、紅色低電量與黃色低耗電模式強調色，以及應用程式在深色選單列上為藍牙音訊使用的更亮藍色">
</p>

## 系統需求

- 執行應用程式需要 macOS 13 部署目標（Ventura 執行驗證待完成）
- 建置則需要搭配 macOS 26 SDK 的 Swift 6 工具鏈（Xcode 26 或以上版本）。使用較舊的 SDK
  建置會悄悄產生 Tahoe 之前的彈出式視窗外觀，因此當 SDK 低於 26 時，
  `scripts/build-app.sh` 會直接失敗。

## 從原始碼執行

```bash
git clone https://github.com/lingyired/status-trio.git
cd status-trio
swift run StatusTrio
```

## 建置本機應用程式

建置 ad-hoc 簽名的應用程式套件並啟動：

```bash
bash scripts/build-app.sh release
```

套件會建立在 `dist/StatusTrio.app`。若要只建置、不結束或啟動現有執行個體，請執行：

```bash
bash scripts/build-app.sh release no-open
```

ad-hoc 簽名的套件適合本機個人使用。如果套件連同隔離標記一起轉移，Gatekeeper 可能會拒絕它。

## 使用方式

- **按左鍵**點擊選單列圖示或 Dock 圖示，即可打開狀態彈出式視窗。
- **按右鍵**點擊任一個圖示，會顯示原生選單，其中包含版本與結束等操作。
- 在彈出式視窗中選擇 Wi-Fi 或電池列，即可打開對應頁面：Wi-Fi 詳細資訊與附近網路、電池詳細資訊。藍牙列則直接在行下列出已配對裝置 —— 點一下即可連接或斷開 —— 放不下時用「展開」查看。
- 打開**設定**可選擇圖示顯示的位置（選單列、Dock 或兩處），並變更其尺寸、顏色、外環線條粗細、面板區塊與其順序、捲動調節音量行為、語言、更新檢查，以及開機時啟動。
- 隨時可以從 **設定 › 應用程式圖示 › 打開指引** 重新開啟 **認識你的圖示** 導覽。
- 需要時請依提示允許顯示目前的 Wi-Fi 網路名稱；macOS 會為這項選用細節要求定位權限。

## 已知限制

有兩條界線，是 macOS 與本專案各自刻意劃下的。兩者的詳細說明見[已知限制](docs/known-limitations.md)。

- **切換網路在系統設定裡完成。** 在彈出式視窗中選擇網路會打開 Wi-Fi 面板；Status Trio 從不讀取也不儲存 Wi-Fi 密碼——macOS 沒有用已儲存密碼連線的公開 API，而其他做法最後都會讓 app 持有你的密碼。
- **充電上限控制取決於版本。** 公開版 1.7.5 透過系統設定操作；`main` 的選用按鈕使用私有介面，需主動取消以要求恢復上限，詳見[行為與限制](docs/charge-to-full-now-poc.md)。低耗電模式由獨立的[選用特權輔助程式](docs/privileged-helper.md)處理。

## 支援的語言

Status Trio 預設跟隨 macOS 的偏好語言，內建 English、简体中文、繁體中文、日本語、한국어、Español、Français、Deutsch、Italiano、Português (Brasil)、Русский 和 العربية。

## 隱私權

Status Trio 在本機讀取系統狀態。匿名使用統計為選用功能，僅在主動啟用後向第一方服務傳送心跳；升級使用者預設關閉，新安裝會在導覽中詢問。內容包括隨機安裝 ID、應用程式和 macOS 版本、語言及圖示位置，不包含姓名、帳戶、網路詳情或硬體識別碼。詳見[遙測與隱私](docs/privacy-telemetry.md)。不讀取或儲存 Wi-Fi 密碼，也不要求鑰匙圈存取。定位權限用於選用的 Wi-Fi 名稱與詳情；啟用藍牙面板時才要求藍牙權限。`main` 中的選用完全充電控制僅在啟用後使用私有 PowerUI 介面，限制見前文。

## 開發

執行測試套件：

```bash
bash scripts/verify-local.sh quick BatteryMonitorTests
bash scripts/verify-local.sh docs
bash scripts/verify-local.sh full
```

透過輔助指令碼執行指定範圍的 XCTest 篩選：

```bash
bash scripts/test.sh BatteryMonitorTests
```

若要在主要安裝之外另外建置 worktree 應用程式：

```bash
bash scripts/build-worktree.sh release
```

輔助指令碼會依據目前分支產生開發版套件識別碼與顯示名稱。這兩個值都可以覆寫：

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

單一執行個體鎖定會以套件識別碼區分，因此識別碼不同的版本可以同時執行。

## 技術基準

- Swift 6
- SwiftUI + AppKit
- macOS 13 deployment target (Ventura runtime validation pending)
- `LSUIElement` 選單列輔助應用程式，在顯示 Dock 圖示時切換為一般啟用策略
- 使用 Sparkle 檢查更新

## 文件

- [已知限制](docs/known-limitations.md)
- [自動化 GitHub Actions 發行](docs/github-actions-release.md)
- [Status Trio 設計規格](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [選單列圖示 SVG](status-menubar.svg)
- [資料驅動圖示示範](status-menubar-demo.html)

## 授權條款

Copyright 2026 lingyired.

依 Apache License, Version 2.0 授權。請參閱 [LICENSE](LICENSE) 與 [NOTICE](NOTICE)。

## 作者

由 [lingyired](https://github.com/lingyired) 建立並維護。<br>
網站：[https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
