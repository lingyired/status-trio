# GitHub Actions 正式发布

`.github/workflows/release.yml` 只有 `workflow_dispatch` 入口，不再由
`v*` Tag push、PR 或 `main` push 自动触发。正式发布分三步：

1. `verify` 与 `native`：分别检出冻结的 `candidate_sha`，并行运行完整
   Swift 测试，以及 Native 契约测试和离线发布回归；两者都不接收签名或
   公证 secrets。
2. `package`：等待上述两个 Job 均成功后，在 `xcode-27` 上对同一 SHA
   做一次 Universal 构建，完成
   Helper/MobileBattery 验证、签名、可选公证、DMG、Sparkle EdDSA 签名和
   manifest。
3. `publish`：只下载上一步的 Actions artifact，校验 SHA-256、manifest、
   Tag、appcast 和公开 URL，然后发布；不得再次编译、打包、签名或公证。

正式工具链是 `xcode-27` runner、Xcode 27 及其 SDK。历史文档中的
`macos-26` / Xcode 26.6 结果是该工具链的历史证据，不代表当前发布环境。
开发前请先阅读 [Swift 工具链 CI 兼容性规则](swift-ci-compatibility.md)。

## 日常开发与正式发布

`AGENTS.md` 的 Local-First 流程优先：普通 commit、PR 和合并使用
`bash scripts/verify-local.sh quick <filter>`、`docs` 或 `full`。本机结果不会
创建 Tag、Release、DMG 或 appcast 变更。`full` 生成的是非 Universal 的
本地开发 bundle；Universal 打包仍属于正式发布。

正式发布必须满足：

- 候选 commit SHA 已冻结并记录。
- 完整 Release CI 在该 SHA 上通过。
- package 阶段的 DMG、manifest 与 SHA-256 被 publish 阶段原样复用。
- 人工批准 `distribution` Environment 后才创建并发布公开产物。

`merged`、`built` 和 `released` 不是同义词；只有公开 Release 与 appcast 都
核验完成，才可称为 `released`。

## 触发方式

### Formal release dispatch

从 GitHub Actions 页面选择 **Build and Release macOS**，或在已认证的
本机显式派发。`candidate_sha` 必须是小写 40 位 commit SHA，并已包含在
`origin/main` 中：

```bash
CANDIDATE_SHA="$(git rev-parse origin/main)"
gh workflow run release.yml \
  --repo lingyired/status-trio \
  --ref main \
  -f candidate_sha="$CANDIDATE_SHA" \
  -f version=1.2.0 \
  -f build=99 \
  -f publish=true \
  -f notarize=false
```

输入语义：

- `candidate_sha`：必填；workflow checkout、manifest、验证和 Tag 都绑定到此 SHA。
- `version`：例如 `1.2.0`；留空时读取 `Support/Info.plist`。
- `build`：显式数字构建号，必须大于当前公开 appcast 的最大构建号。
- `publish=true`：完整验证和打包后创建/恢复 Draft Release、写入 appcast，
  最后才转为公开 Release。
- `publish=false`：只验证、打包并上传 Actions artifact；没有未来版本的
  Release Notes 时应成功跳过文案校验。这是维护者显式发起的诊断入口，
  不是日常 PR 门槛，也不能被自动发布。
- `notarize=true`：强制 Developer ID 签名和公证；可用于 `publish=false`
  的集成验证，也可与 `publish=true` 一起使用。缺少任一凭据时直接失败，
  不回退 Ad-hoc。

Developer ID 凭据存在时，`publish=true` 必须成功完成公证；若 Developer ID
未配置，则只允许如实生成 Ad-hoc fallback。`notarize=true` 必须配置
`DEVELOPER_ID_CERTIFICATE_P12`、`DEVELOPER_ID_CERTIFICATE_PASSWORD`、
`APPSTORE_CONNECT_API_KEY_ID`、`APPSTORE_CONNECT_API_ISSUER_ID` 和
`APPSTORE_CONNECT_API_PRIVATE_KEY`。

### 审批边界与 Environment

`package` 根据发布模式和当前触发者选择 Environment：

- `publish=true`：始终使用有 reviewer 的 `distribution`。
- `publish=false` 且触发者是仓库所有者 `lingyired`：使用无 reviewer 的
  `distribution-owner-signing`。
- `publish=false` 但触发者是其他人，或由其他人重新运行：使用有 reviewer 的
  `distribution`。

选择条件使用 `github.triggering_actor`，不是最初的 `github.actor`，因此他人
不能通过重新运行所有者的 workflow 绕过审批。`publish` Job 始终使用
`distribution`。`verify` 和 `native` 不访问 Environment，也不接收签名或公证
secrets。Environment 审批不能替代 SHA 冻结和 artifact 校验。

两个 signing Environment 都只允许 `main`。`distribution` 必须保留 reviewer；
`distribution-owner-signing` 不配置 reviewer，但必须保持同一 `main` 分支限制。
创建 owner Environment 的命令：

```bash
gh api --method PUT \
  repos/lingyired/status-trio/environments/distribution-owner-signing \
  --input - <<'JSON'
{"deployment_branch_policy":{"custom_branch_policies":true,"protected_branches":false}}
JSON

gh api --method POST \
  repos/lingyired/status-trio/environments/distribution-owner-signing/deployment-branch-policies \
  --input - <<'JSON'
{"name":"main","type":"branch"}
JSON
```

五个签名和公证 secrets 必须同时存在于 `distribution` 和
`distribution-owner-signing`。GitHub 不支持 Environment secret 继承，也不能
通过 API 读取旧值；轮换时必须同时更新两个 Environment。以下命令通过标准输入
设置，不要把值写进命令或仓库：

```bash
for environment in distribution distribution-owner-signing; do
  base64 -i DeveloperIDApplication.p12 |
    gh secret set DEVELOPER_ID_CERTIFICATE_P12 --env "$environment" --repo lingyired/status-trio
  gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD --env "$environment" --repo lingyired/status-trio
  gh secret set APPSTORE_CONNECT_API_KEY_ID --env "$environment" --repo lingyired/status-trio
  gh secret set APPSTORE_CONNECT_API_ISSUER_ID --env "$environment" --repo lingyired/status-trio
  gh secret set APPSTORE_CONNECT_API_PRIVATE_KEY --env "$environment" --repo lingyired/status-trio < AuthKey_XXXXXXXXXX.p8
done
```

无 reviewer 的 Environment 只适用于所有者信任自己触发的 `main` workflow。
如果以后授予其他人写权限，必须同时要求 `.github/workflows/` 的改动经过所有者
审查；否则有写权限的人可以修改 actor 条件并选择 owner Environment。

在最后一条命令中，`AuthKey_XXXXXXXXXX.p8` 是本机私钥文件路径，不是 secret 值。不要读取或打印私钥来验证配置。GitHub Environment 审批控制 job 何时获得 Environment secrets，不会让它们在 runner 中保持加密：获批后，工作流及同一 job 中执行的 action/code 可以使用它们，日志脱敏也不能防止所有泄漏。只允许可信的 `main` 工作流使用该 Environment，并审查会改动这些工作流的变更。

文案不再通过输入传入，改为读取仓库内的 `release-notes/<version>/`。正式发布
dispatch 会运行 `scripts/validate-appcast-notes.sh`，打印语言覆盖表，并把
生成的 appcast 条目干跑到临时文件后断言 XML 合法、变体齐全、`en` 排第一、
无未替换占位符。`publish=true` 要求 12 种语言齐全；`publish=false` 在没有
未来版本目录时明确跳过，不再错误验证最新旧版本。

正式发布统一使用手动 workflow。workflow 必须将 checkout、构建 artifact、manifest 和 Release Tag 绑定到同一个冻结 SHA；Tag 已存在但 SHA 不同必须失败。

## CI 预检、诊断与原生依赖缓存

`verify` 在 Swift 测试之前逐文件检查 shell 语法、禁止模式、工作流策略和
Release Notes。Swift 测试仍只通过 `scripts/test.sh` 执行一次，并同时启动
独立的 `native` Job 运行 Native 和离线发布回归；`package` 必须等待两者都
成功。该拆分不缩短单项检查，只移除两个互不依赖阶段的串行等待。失败时各自
的 Job Summary 记录阶段、观测到的失败类别、首个断言或编译位置、原始退出码
和耗时。未知原因标为 `unknown`，不会把慢 runner 推断为根因。原始日志分别
存入 `verify-diagnostics` 和 `native-diagnostics` artifact；只有资源加载类
失败才附加 Bundle 路径诊断。

恢复旧 package 时，新诊断脚本来自已有的 `release-tools` 可信 checkout，
测试仍在原始 candidate checkout 执行。原产物、SHA、digest 和发布恢复校验
保持原有边界，不重建 package。

`package` 只在可信 `main` 手动流程中恢复/保存 `actions/cache@v4` 的两份
独立依赖缓存。每份只含一个架构的 `prefix` 与 `.dependencies-cache.json`；
不缓存 Helper、app、DMG、签名凭据或整个 `.build`。key 包含 schema、
OS/架构、Xcode/Swift/Clang/SDK、构建工具版本、最低系统版本、依赖清单、已审核
许可证文件集及内容摘要、构建脚本与配置。安装的 `.pc` / `.la` 和 dylib 引用
绝对路径，因此 key 也绑定
canonical prefix 路径；不同 checkout 路径会安全 miss，不尝试未经验证的迁移。
没有宽泛的 `restore-keys`。

恢复成功后，构建脚本仍验证完整文件 inventory/SHA-256、Header、metadata、
symlink、Mach-O 架构、deployment target 和动态依赖。缓存 key 和 marker 已绑定
依赖清单、许可证摘要、构建脚本及 canonical prefix；只有真正重建时才 checkout pinned
sources 并再次验证 source pins。日志区分 `restored`、`validated` 和
`build skipped`。缺失/损坏的缓存会从 pinned sources 重建，检查工具失败则直接
失败。

已审核的第三方 license 文本提交在
`Support/MobileBatteryHelper/ThirdPartyNotices/`。精确缓存命中且不重建依赖时，
构建不 checkout 完整源码树，直接使用这些文本；修改许可证内容或文件集会使缓存
失效。发生冷构建时，在封存缓存前逐文件比较上游 license 与已审核副本，比较会
归一化换行与行尾空白，内容不一致即失败。失败的许可证验证不得留下可复用的新
marker。Helper 每次重新编译，最终 Universal
bundle、签名、公证及产物身份契约仍全部执行。

GitHub cache 的同 key 内容不可覆盖。若精确命中的条目损坏，当前运行会安全重建；
维护者应删除该条目或递增 `scripts/mobile-battery-cache.py` 的 schema，使后续
运行保存新条目。缓存保存发生在正式 package artifact 上传之后，恢复发布仍可
使用已经上传的原产物。

`package-build-timings` artifact 和 package Job Summary 记录 TSV 阶段耗时。
父阶段含子阶段，不能把全部行相加；公证包含 Apple/network 等待。cache restore
与 save 的区间包含 Action 调度开销，压缩大小和传输信息见对应 Action 日志，
解压后的 prefix 大小由 `du -sk` 记录。Artifact upload 的步骤耗时见 Actions
元数据。净收益需同 candidate/工具链的一次冷、一次热远程运行才能计算；
本次本地验证不替代该测量，也未启用 SwiftPM 编译产物缓存。

基线、故障分类和实际验证记录见
[CI stability baseline](ci/ci-stability-baseline.md)、
[CI performance report](ci/ci-performance-report.md)。

## 发布恢复

`package_run_id` 仍要求显式 `publish=true`、`notarize=true` 和版本、
构建号、Tag。非发布诊断不会进入线上恢复发布路径；恢复校验的正反例通过
离线 fixture 验证，不应为测试关闭这些入口保护。

源 workflow 可以是历史的 `verify/package/publish` 三 Job 结构，或当前的
`verify/native/package/publish` 四 Job 结构。源 run 的 Job 集合和依赖必须与
冻结候选中的 workflow 相符；四 Job 结构还必须有成功的 `native`，缺失、
失败或跳过都不能退回按旧结构接受。Artifact、manifest、SHA 和 digest 的
原有绑定继续执行。

所有重试必须复用同一次 `package` 产生的 artifact：

- Draft 已存在但上传失败：重新上传 DMG、`.sha256` 和
  `release-manifest.json`，校验 digest/size 后再继续。
- Appcast 写入失败：保留 Draft，重新运行同一 artifact；已有正确 appcast
  item 时只核验，不重复写入。
- Release 已公开：只核验 Release assets、公开 DMG SHA-256 和 raw appcast，
  不得重新上传、编辑公开 metadata 或改写 feed。
- Tag 已存在但指向其他 SHA、manifest 与 artifact 不一致、公开下载或 appcast
  不匹配：立即失败并保留现场，不得用新构建覆盖。

发布脚本只做有限次公开传播核验；失败时报告尝试次数和最终错误，不使用
无限重试。

## 文案目录

每个版本一个目录，每种语言一个文件，语言名与 `Sources/StatusTrioCore/Resources/*.lproj` 逐字一致（大小写敏感）：

```
release-notes/1.2.0/
  en.md  zh-Hans.md  zh-Hant.md  ja.md  ko.md
  de.md  fr.md       es.md       it.md  pt-BR.md  ru.md  ar.md
```

- 每份文件第一行是 `# <标题>`，必须同时含 `%VERSION%` 与 `%BUILD%` 占位符，由脚本注入实际数字（这样标题里的版本号不可能手写错）。
- 其余行为 `- 条目` 或 `## 小节`；空行忽略；不要写 `**加粗**` 之类的 Markdown 内联语法，它们会被 XML 转义成字面量。
- `en.md` 与 `zh-Hans.md` 一份两用：既进 appcast，也拼成 GitHub Release 正文的英文段与中文段。
- 术语必须取自该语言已有的 `.lproj` 字符串，而不是字面转换。例如繁体用「圖示 / 捲動 / 音訊 / 設定」，简体用「电池详情」而不是「电量详情」。
- 只有 `zh-Hans` 包含针对中国大陆网络的镜像回退说明，其余语言不含。

## Release notes 规则

GitHub Release 正文必须包含英文和中文，英文在上、中文在下，并使用版本号标题：

```markdown
# Version 1.2.0 （English + 中文， 中文在下方）

## English

- English change one.
- English change two.

## 中文

- 中文变更一。
- 中文变更二。
```

工作流会根据 `version` 自动生成标题，并把 `release-notes/<version>/en.md` 与 `zh-Hans.md` 合并为上述格式，同时剥掉每份文件的 `# ` 标题行（正文自己有一级标题）。

Sparkle `appcast.xml` 使用分语言说明：每个新条目为文案目录中每种语言写入一组带显式 `xml:lang` 的 `<title>` 与 `<description>`，`en` 必须排第一——Sparkle 的 `-bestNodeInNodes:name:` 在用户偏好语言都匹配不到时取**文档顺序第一个节点**作为兜底。把两种语言堆进同一个 `<description>` 会让所有用户都看到双语。`publish=true` 要求 12 种语言齐全，`publish=false` 只警告不阻断。GitHub Release 正文始终是英文 + 简体双语。

GitHub Release 正文只包含双语说明。配置了 Developer ID 与公证之后，正文不再追加首次启动的 `xattr -dr com.apple.quarantine` / `open` 提示——公证过的构建不需要这一步。只有退回 Ad-hoc 签名的版本才需要该提示，而 Sparkle appcast 永远不包含它。

## 预检产物与更新验证

`publish=false` 的预检产物使用的是**下一个正式版的构建号**（准备发布 1.2.0 / build 9 时，预检也用 build 9）。Sparkle 只按 `sparkle:version`（即 `CFBundleVersion`）判断新旧，因此有两条硬性注意事项：

- **不要把预检产物安装到 `/Applications`。** 本机一旦存在构建号相同的应用，正式版发布后 Sparkle 会判定「已是最新」，这台机器就再也收不到该版本的更新。需要在本机试用预检构建时，改用 `scripts/build-worktree.sh` 产出的构建——它的 bundle id 带 `.dev.<branch>` 后缀，不会覆盖正式安装。
- **验证「旧版本 → 新版本」的更新链路时，必须先安装上一个正式发布的构建号。** 例如验证 1.2.0 时先装 1.1.0（build 8），`9 > 8` 才成立；装预检构建无法测出更新。

Sparkle 的磁盘缓存还会掩盖网络结果：`~/Library/Caches/com.lingsmbp.StatusTrio/` 里缓存过比较新的 feed 时，即使这次网络请求失败，也可能照常显示「有更新」。要验证真实网络路径（包括镜像回退是否生效），先清掉缓存再检查：

```bash
osascript -e 'quit app "Status Trio"' 2>/dev/null
rm -rf ~/Library/Caches/com.lingsmbp.StatusTrio
```

查看这次检查实际请求了哪个源：

```bash
sqlite3 ~/Library/Caches/com.lingsmbp.StatusTrio/Cache.db \
  "select request_key, time_stamp from cfurl_cache_response;"
```

出现 `raw.githubusercontent.com` 之外、带 `gh-proxy.com/` 或 `ghfast.top/` 前缀的记录，说明镜像回退已经接管。

## 第一次配置

### 1. 配置 Sparkle EdDSA 私钥

私钥必须与 `Support/Info.plist` 中的 `SUPublicEDKey` 配对。导出当前 Sparkle 私钥：

```bash
KEY_DIR="$(mktemp -d)"
KEY_FILE="$KEY_DIR/sparkle-private-key"
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x "$KEY_FILE"
gh secret set SPARKLE_PRIVATE_KEY < "$KEY_FILE"
rm -f "$KEY_FILE"
rmdir "$KEY_DIR"
```

不要把导出的私钥提交到 Git，也不要在 issue 或日志中粘贴私钥。

### 2. 让上传内容可匿名下载

Sparkle 无法从私有 GitHub Release 更新。二选一：

#### 方案 A：源码仓库公开

将 `lingyired/status-trio` 改为 public。当前 `SUFeedURL` 已经指向：

```text
https://raw.githubusercontent.com/lingyired/status-trio/main/appcast.xml
```

#### 方案 B：使用独立的公开更新仓库

保留源码仓库为 private，新建公开仓库，例如 `lingyired/status-trio-updates`，并在其中放置 `appcast.xml`。将本项目的 `release.json` 和 `Support/Info.plist` 指向该更新仓库：

```json
"github_repo": "lingyired/status-trio-updates"
```

```text
SUFeedURL=https://raw.githubusercontent.com/lingyired/status-trio-updates/main/appcast.xml
```

也可以不修改文件，而是在 GitHub 设置仓库变量覆盖：

```bash
gh variable set RELEASE_REPO --body "lingyired/status-trio-updates"
gh variable set RELEASE_BRANCH --body "main"
```

跨仓库写入需要 PAT，设置 `RELEASE_TOKEN` secret。PAT 至少需要目标更新仓库的 `Contents: Read and write` 权限：

```bash
gh secret set RELEASE_TOKEN
```

如果更新仓库与源码仓库相同且仓库为 public，可以省略 `RELEASE_TOKEN`，工作流会使用内置 `GITHUB_TOKEN`。

### 3. 可选：Developer ID 签名和 Apple 公证

未配置证书时，工作流使用 Ad-hoc 签名。用户可以安装和更新，但第一次手动安装可能需要移除 quarantine：

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
```

配置 Developer ID 后无需这一步。签名和公证 secrets 只能放在
`distribution` 和 `distribution-owner-signing` 两个 Environment 中，不要配置
到 repository secrets。`distribution` 保留 reviewer；
`distribution-owner-signing` 仅允许所有者诊断时无 reviewer 使用。两者的
`main` 分支限制和安全前提见上文。Environment secrets 名称为：

| Secret | 内容 |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | Developer ID Application `.p12` 文件的 Base64 |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | `.p12` 密码 |
| `APPSTORE_CONNECT_API_KEY_ID` | App Store Connect API Key ID |
| `APPSTORE_CONNECT_API_ISSUER_ID` | App Store Connect Issuer ID |
| `APPSTORE_CONNECT_API_PRIVATE_KEY` | `AuthKey_*.p8` 文件内容 |

生成证书 secret 的准确命令：

使用上文“审批边界与 Environment”中的循环命令，将五个值分别写入两个
Environment。这些 Apple credentials 不属于 repository secrets。不要在本地
通过读取 keychain、打印 secret 或检查私钥内容来确认它们。

`SPARKLE_PRIVATE_KEY` 只传入 `package` Job 的 `Build, sign, notarize, and package once` 步骤；`publish` Job 不接收它。`publish=true` 没有该 secret 会失败，`publish=false` 且未提供时只生成带诊断标记、不可发布的 package。Environment 对 Apple secrets 的隔离不改变 repository secret 的作用域，审查仓库 workflow 变更及其权限仍然必要。

## 本地验证

只构建诊断 package，不连接 GitHub。要求工作树干净：

```bash
PUBLISH=false bash scripts/release.sh
```

兼容入口始终产出 Universal package；不接受降低为单架构的诊断构建。
入口默认 `PUBLISH=false`；手工 fallback 必须显式设置 `PUBLISH=true`。

正式发布不要从本机执行 `PUBLISH=true bash scripts/release.sh`；请使用上面的
workflow dispatch，确保同一 SHA 的验证、Universal package、签名/公证和发布
记录都在 Actions 中完成。只有在 workflow 不可用且维护者明确要求手动 fallback
时，才允许使用本地兼容入口。
