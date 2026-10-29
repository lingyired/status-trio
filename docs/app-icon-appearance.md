# App 图标外观

Status Trio 有两个互不相同的图标表面。Issue #151 的“Finder/启动台里永远是深色”只涉及
第二个表面：应用包图标。Dock 里的实时图标由应用自己绘制，跟随应用内设置；Finder 和启动台
读取的是应用包内的系统图标资源，其外观由 macOS 和图标文档决定。

## 两个图标表面

| 表面 | 来源 | 跟随系统深浅色 |
| --- | --- | --- |
| Dock 实时图标 | `AppIconController` / `DockIconRenderer` 在运行时绘制，通过 `setApplicationIconImage` 交给 Dock | 跟随“Dock Icon Background”设置（Follow System / Dark / Light），与包图标无关 |
| 应用包图标 | `Contents/Resources/Assets.car` + `AppIcon.icns`，由 `CFBundleIconName` / `CFBundleIconFile` 指向 | macOS 26 起跟随系统外观和 Icon & Widget Style；macOS 13–15 没有外观分组，只显示默认（浅色）渲染 |

因此，设置里的 Dark/Light 只改变 Dock 里的实时图标，不会改变 Finder、启动台、聚焦或应用
切换器展示的包图标。反过来说，修改包图标素材也不会改变 Dock 实时图标的渲染结果。

## 构建方式

包图标的唯一来源是 Icon Composer 文档 `Support/AppIcon.icon`：

- `icon.json`：两个图层组，分别引用 `Assets/AppIcon-light.png` 与
  `Assets/AppIcon-dark.png`，并用 `hidden-specializations` 让浅色素材只在浅色外观显示、
  深色素材只在深色外观显示。
- `Assets/AppIcon-light.png`、`Assets/AppIcon-dark.png`：1024×1024、满幅方形 PNG，
  四角不透明；系统负责裁切为图标形状。

`scripts/build-app.sh` 用 `actool` 编译这个文档，而不是再用 `sips` + `iconutil` 拼
iconset：

```bash
xcrun actool "$ROOT/Support/AppIcon.icon" \
    --compile "$CONTENTS/Resources" \
    --platform macosx \
    --minimum-deployment-target "$LSMinimumSystemVersion" \
    --app-icon AppIcon \
    --output-partial-info-plist "$tmp/AppIcon.partial.plist"
```

其中 `LSMinimumSystemVersion` 从 `Support/Info.plist` 读取（当前为 13.0），不硬编码。
`actool` 直接把 `Assets.car` 与旧版 `AppIcon.icns` 写进 `Contents/Resources`，不会覆盖
同目录的本地化资源。构建脚本随后：

1. 断言 `Contents/Resources/Assets.car` 与 `Contents/Resources/AppIcon.icns` 都存在；
2. 用 `scripts/generate-app-icon-icns.sh` 从 `Assets/AppIcon-light.png` 重建完整的
   旧版 `AppIcon.icns`（`actool` 自带的回退只有 16/128 px 两档）；
3. 从 partial Info.plist 读取 `CFBundleIconName`、`CFBundleIconFile`，两者都必须是
   `AppIcon`，否则构建失败；
4. 把这两个键合并进 `Contents/Info.plist`，并在签名前再次断言最终值。

`Support/AppIcon.png` 保留为“已批准的预览图”，供 `AppIconPreviewTests` 对比，但不再是包
图标的构建输入。

## Assets.car 的外观栈

编译后的 `Assets.car` 内含同一个图标的多套外观渲染（`assetutil` 中表现为
`IconGroup` / `IconImageStack`）：

| 外观键 | 用途 |
| --- | --- |
| `NSAppearanceNameAqua` | 浅色外观 |
| `NSAppearanceNameDarkAqua` | 深色外观 |
| `ISAppearanceTintable` | Icon & Widget Style 的着色外观；当前回退到浅色素材（未单独制作着色层） |

macOS 26 及以上会按当前系统外观选择对应的渲染，因此 Finder、启动台等系统界面展示的包图标
能随系统深浅色切换；Dock 仍显示应用实时绘制的图标。

## 旧版 AppIcon.icns 是浅色回退

`macOS 13–15` 没有 `NSAppearanceNameDarkAqua` 这层图标选择逻辑，只会渲染目录里的默认
（Aqua/System）分组，也就是浅色素材。更老系统读取的 `AppIcon.icns` 因此也来自浅色外观。
`actool` 自带的 .icns 只有 16/128 px 两档，构建脚本会用
`scripts/generate-app-icon-icns.sh` 从浅色素材重建完整的 16–512 px（含 @2x）表示，避免
macOS 13–15 在 Finder 大图标和 Dock 里放大一张小图。所以这些系统上包图标固定显示浅色版本，
这是系统能力限制，不是构建遗漏；这些系统上也没有可用的系统级深色包图标 API。

同理，Icon & Widget Style 的着色（Tinted）与通透（Clear）外观目前也只会落到默认的浅色
素材，不会重新着色。本次范围只覆盖深色与浅色两种外观。

## 外观跟随的系统边界

- macOS 26+：应用包图标跟随系统深浅色，并支持 Icon & Widget Style 的着色。
- macOS 13–15：应用包图标没有外观感知能力，Finder/启动台显示 `AppIcon.icns` 的浅色
  回退。Issue #151 中“永远深色”的旧构建只用深色预览图 `Support/AppIcon.png` 生成
  `.icns`；现在外观素材由 `actool` 编进 `Assets.car`，旧版 `.icns` 再由构建脚本从
  浅色素材单独重建。
- Dock 实时图标不受此限制：它由应用绘制，在 macOS 13+ 上都能按设置切换 Dark/Light；
  “Follow System”会读取系统 Icon & Widget Style（macOS 15+）。

## 重新生成素材

素材由生产渲染器生成，不要手工改 `Assets.car` 或 `.icns`。修改图标渲染后，重写两张
1024 素材：

```bash
STATUS_TRIO_APP_ICON_ARTWORK_DIR=Support/AppIcon.icon/Assets \
    swift test --filter AppIconPreviewTests
```

该命令会写回 `AppIcon-light.png` 与 `AppIcon-dark.png`；`icon.json` 中的文件名保持不变。
如需更新旧的预览图 `Support/AppIcon.png`：

```bash
STATUS_TRIO_APP_ICON_PREVIEW=/tmp/status-trio-app-icon-preview.png \
    swift test --filter AppIconPreviewTests
```

## 验证

离线契约测试（不需要网络，`verify-local.sh full` 会运行它）：

```bash
bash scripts/test-app-icon-contract.sh
```

它检查 `icon.json` 与两张 1024 PNG 存在、`actool` 能按 `LSMinimumSystemVersion` 编译出
`Assets.car` 和 `AppIcon.icns`、partial plist 的两个键都是 `AppIcon`、`Assets.car` 同时
含有 Aqua 与 DarkAqua 图标组，以及重建的 `.icns` 能解出 16–512 px 的全部 1x/2x 表示。

构建后手工抽查：

```bash
bash scripts/build-app.sh release no-open
/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" dist/StatusTrio.app/Contents/Info.plist
ls dist/StatusTrio.app/Contents/Resources/{Assets.car,AppIcon.icns}
/usr/bin/assetutil --info dist/StatusTrio.app/Contents/Resources/Assets.car |
    grep -E 'NSAppearanceName(Aqua|DarkAqua)'
iconutil --convert iconset --output /tmp/StatusTrio.iconset \
    dist/StatusTrio.app/Contents/Resources/AppIcon.icns
```

注意：这些检查都是静态契约；真实 Finder/启动台外观需要分别在 macOS 26 与 macOS 13–15
上人工确认，并单独记录 PASS/FAIL/NOT RUN。
