# 低版本（macOS 13–15）充电上限 — 交接与跟进说明

最后更新：2026-11-26

## 1. 代码位置

| 项 | 值 |
| --- | --- |
| 分支 | `fix/207-charge-limit-compat` |
| 工作区（worktree） | `/Users/lingsmbp/Documents/aiwork/status-trio/.agents/worktrees/fix/207-charge-limit-compat` |
| 远端分支 | `origin/fix/207-charge-limit-compat`（已推送） |
| 当前 HEAD | `4b1a2063`（`settings: regenerate the settings skill artifacts…`） |
| 与 main | 落后 `origin/main` 0 个提交；**未合入 main** |
| 计划文档 | `docs/superpowers/plans/2026-11-26-legacy-charge-limit-lifetime-and-selfheal.md` |
| 设计/决策记录 | `docs/legacy-charge-limit.md`（§10 生命周期策略、§10.1 优化电池充电提示） |
| 内部台账 | `.superpowers/sdd/status-trio-legacy-charge-limit-plan/ledger.md`（Round 1–13） |

进入工作区：

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio/.agents/worktrees/fix/207-charge-limit-compat
```

## 2. 已构建的公证测试包（推荐用它测）

| 项 | 值 |
| --- | --- |
| 版本 / 构建号 | 1.10.6 / 76（Helper 授权 + 状态刷新修复版） |
| 源 SHA | `2796ff8c` |
| GitHub Actions run | `45765965524`（build-candidate.yml，`fast`，`publishable=false`） |
| 本机目录 | `~/Downloads/StatusTrio-candidate-1.10.6-b76/` |
| 安装包 | `StatusTrio-1.10.6-充电上限.dmg`（用户已改名；同目录另有 `StatusTrio-1.10.6.zip`、sha256、`release-manifest.json`） |
| 签名/公证 | Developer ID + `accepted_and_stapled`，Universal `arm64 + x86_64` |

这是**非公开测试候选**，只能安装测试，不能直接发布。安装到 macOS 15 机器后，首次启动需批准后台 Helper（系统设置 → 通用 → 登录项与扩展，或按 App 提示）。

## 3. 功能范围（务必知晓）

- 「充电上限限制」组**只在 macOS 13–15 显示**；macOS 16–25 不显示；macOS 26+ 显示系统原生「充电」组。
- 运行模型：**仅 App 运行时限制生效**。退出/崩溃恢复原值；想重启后仍生效，请打开 App 现有的「开机自启动」，App 启动会自动重设上次上限。
- 上限滑杆 80–100%，**100% = 不限制（等于关闭）**。
- 「在面板中显示『立即充满电』按钮」开关默认关；打开后**仅在连接电源时**电池面板下方出现按钮；点按临时解除上限（24h 后自动恢复，或再次点按立即恢复）。
- 「睡眠时」二选一：暂停充电 / 充到上限前不睡眠（合盖屏幕仍会关）。
- 「当前电池优化状态」显示真实状态（已托管/正在充满/失败/外部改动等）。
- 固定提示：建议关闭系统「优化电池充电」，可点击打开电池设置页（不做检测）。
- 自愈：启动、唤醒、插电、打开设置页时校验并重写被系统重置的上限；第三方占用时报「外部改动」，不抢。
- 迟滞 4%；高于上限只停充，不主动放电。

## 4. macOS 15 实测清单（请在双系统机器上逐项打勾）

基础可见性
- [ ] 设置 → 电池 只出现「充电上限限制」组，不出现原生「充电」组。
- [ ] 管理充电上限开关可开/关；状态行显示「当前电池优化状态」。

上限行为（Apple Silicon / Intel 分别记录）
- [ ] 设 85%，插电，电量到 85% 附近停止充电；低于上限（≤81%）恢复充电。
- [ ] 滑杆拖到 100% → 限充关闭、恢复原值；再设 80% 可重新限制。
- [ ] 状态在「已托管 / 正在检查 / 失败 / 外部改动」之间合理变化。

立即充满
- [ ] 打开「在面板中显示『立即充满电』按钮」，电池面板（连接电源时）出现按钮；用电池时不出现。
- [ ] 点按后状态「正在临时充满电」，按钮变「取消充满」；再点立即恢复。
- [ ] 24 小时到期自动恢复（可临时把系统时间前移验证，或记录时间点观察）。

睡眠
- [ ] 选「暂停充电」：合盖时停在当前电量，唤醒后继续充到上限。
- [ ] 选「充到上限前不睡眠」：低电量合盖时屏幕关但继续充电到上限，然后正常睡眠。

退出 / 重启 / 唤醒 / 插电
- [ ] 退出 App：上限恢复原值（不再限制）。
- [ ] 开启「开机自启动」，重启后打开 App：上次上限自动恢复（不再是「未验证」）。
- [ ] 系统改动上限后：唤醒或插电，App 自动补回。
- [ ] 用别的工具改上限：显示「外部改动」，不被覆盖。

提示与帮助
- [ ] 「优化电池充电」提示可见，点击能打开系统电池设置页。

日志/取证（失败时）
- Helper 日志：Console.app 搜索 `StatusTrioPowerHelper`。
- 恢复记录目录：`/Library/Application Support/StatusTrio/`（只读检查，不要手动删）。
- App 状态：设置组内的「当前电池优化状态」。

## 5. 验收之后如何发布（不重新构建）

候选已签名+公证；验收通过后用同一个候选发布，保证「测过的包 == 公开的包」：

```bash
# 用 GitHub UI 或 gh 触发 publish-candidate.yml，输入：
#   candidate_run_id = 45734163807
```

不要重新跑 build-candidate，也不要在本机打包/签名/公证。

## 6. 若测试发现问题，如何继续改

1. 在本 worktree 直接改（分支 `fix/207-charge-limit-compat` 已包含全部近期工作）。
2. 开发期跑聚焦测试，交付前跑风险档：
   ```bash
   bash scripts/test.sh 'LegacyChargeLimit|LocalizationParityTests|SettingsViewTests'
   bash scripts/verify-local.sh full
   ```
3. 改了设置项（新增/改默认）时：更新 `SettingsSemanticCatalog`，并重新生成 skill 生成物（`references/settings-schema.json`、`modules/*.md`）与 `docs/settings/settings-inventory.md` 计数，否则 `SettingsSchemaArtifactConsistencyTests` 会失败。
4. 提交并推送分支；需要新测试包时重新触发 `build-candidate.yml`（见 §7）。
5. **验收前不要合并到 main**；验收通过再合。

## 7. 打新的测试候选包（分支 SHA）

分支候选必须从 **main 的 workflow 定义**派发（环境按 workflow ref 判定），并人工批准 `distribution` 环境：

```bash
cd /Users/lingsmbp/Documents/aiwork/status-trio/.agents/worktrees/fix/207-charge-limit-compat
git push origin fix/207-charge-limit-compat
SHA=$(git rev-parse HEAD)
gh workflow run build-candidate.yml --ref main \
  -f candidate_sha="$SHA" -f release_mode=fast \
  -f version=1.10.6 -f build=<比已发布 build 大的数字>
# 运行进入 waiting 后，人工批准 distribution 部署，再等待 package 完成
gh run list --workflow=build-candidate.yml --limit=1
```

- build 号必须**大于已发布 build**（当前已发布 1.10.5/build 73，故用 74 或更大）。
- 直接 `--ref <分支>` 会被 Environment 分支策略拦住。

## 8. 收尾清理（都完成后）

- 分支已在 main 合并并推送、无未提交改动、无残留进程后，可删除分支与 worktree。
- 在删除 worktree 前确认：`git status` 干净、没有本 worktree 的 `StatusTrio.app` 进程在跑。

## 9. 仍未验证（NOT RUN，必须在真机确认）

- 任何真实 SMC 写入/读回、Intel `BCLM` 与 Apple Silicon `CH0B/CH0C/CHTE` 的真实行为。
- 到点停充/恢复、高于上限时的表现。
- 睡眠策略两种模式的实际效果、唤醒/插电自愈。
- 退出还原、启动重设、开机自启后的自动恢复。
- 与系统「优化电池充电」的实际冲突与提示效果。
- 真实 Helper 安装/批准、XPC 握手、Developer ID 包在 13–15 的安装。

## 10. 已知修复：Helper 授权按钮“没反应”（2026-11-26）

旧候选（build 74）里，低版本组的授权按钮只请求注册，不会打开批准入口，看起来没反应。修复后（build 75 起）点击会：
请求注册 Helper，并**直接打开「系统设置 → 通用 → 登录项与扩展」**，在列表里允许 Status Trio 的后台项即可。
若按钮仍无反应，请确认 App 已从 DMG 拷到「应用程序」再运行（不要在 DMG 里直接跑），并在系统设置里检查该后台项是否被允许。

> build 76 追加：在登录项里批准 Helper 后，App 会自动重新探测，状态不再需要重启才更新。
