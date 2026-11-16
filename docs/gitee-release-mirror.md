# Gitee 国内更新镜像（ZIP）

GitHub Release 仍是唯一正式构建和发布来源。Gitee 镜像同一个已签名、已公证并装订
票据的 app，但以 **ZIP** 形式上传；Gitee 会拒绝公证 DMG，ZIP 已验证可上传。

## 一次构建，两个安装包

1. 同一次冻结 SHA 构建出 `StatusTrio.app`，完成 Developer ID 签名和 Apple 公证。
2. 先给 app 执行 `stapler staple` 和 `validate`。
3. 从同一份已装订 app 生成：
   - GitHub 正式发布：`StatusTrio-X.Y.Z.dmg`，流程不变。
   - Gitee 镜像：`StatusTrio-X.Y.Z.zip`（ZIP 内是 `StatusTrio.app`，不是包着 DMG 的 ZIP）。
4. 两个文件分别计算长度、SHA-256，并分别用现有 Sparkle 私钥生成 EdDSA 签名。
   **DMG 和 ZIP 的签名不同，不能复用。** manifest 同时记录两者；ZIP 字段缺失的
   历史 manifest 仍可按原 DMG 流程恢复。

## 发布和恢复

JSON manifest 的新字段：

    "zip": {
      "filename": "StatusTrio-X.Y.Z.zip",
      "sha256": "...",
      "length": "...",
      "ed_signature": "..."
    }

- `package-release.sh` 在上传前从已验证 app 生成 ZIP、签 manifest。
- `publish-release.sh` 只使用冻结包内已有 ZIP，绝不重新打包；上传/公开回读同时
  校验 ZIP、ZIP `.sha256` 和 manifest。旧 DMG-only manifest 允许恢复。
- `verify-release-zip.rb` 会拒绝错误文件名、长度、SHA-256、缺失 sidecar、诊断包
  签名和非 Gitee 目标；不会影响历史 DMG 发布。

## Gitee 镜像

本地 AI Agent 执行（不依赖 GitHub 海外 Runner）：

    node scripts/gitee-mirror-agent.mjs check vX.Y.Z
    node scripts/gitee-mirror-agent.mjs auto vX.Y.Z
    node scripts/gitee-mirror-agent.mjs sync vX.Y.Z
    node scripts/gitee-mirror-agent.mjs verify vX.Y.Z

`sync` 下载并验证 GitHub ZIP，上传 ZIP、`.sha256`、manifest 到 Gitee，匿名回读
重新计算 SHA-256，然后从正式 appcast 派生 `appcast-gitee.xml`：只保留已镜像的
版本，enclosure URL 指向 Gitee ZIP，`length` 和 `sparkle:edSignature` 改为 ZIP
的值，绝不包含 GitHub 地址。Feed 完整验证后才写 Gitee 分支文件。
Gitee Feed 的中文说明顶部固定加 `更新源：Gitee`（繁体为 `更新來源：Gitee`）；
其他语言不添加来源行。

发布后默认运行 `auto`：先同步 ZIP 和 Feed，再立即回读 `verify`。

本地凭据从当前进程的 `GITEE_TOKEN` 或 macOS 钥匙串读取：
service `status-trio.gitee-token`，account `lingyired`。Token 不进入对话、日志、
命令行参数或提交。GitHub Actions 只跑离线检查并输出“待本地 Agent 同步”，不会
自动上传。发布后由本地 Agent 在同一个冻结 tag 上执行。

## 分页、幂等和未完成项

- 同 tag 同 SHA：复用附件；不同 SHA：立即失败，不覆盖。
- 部分上传/Feed 写失败：保留现场，修复后重试同一 tag。
- 上传顺序固定：ZIP → 校验公开字节 → 生成 Feed → 校验 Feed → 发布 Feed。
- 自动清理旧版本尚未实现；不要声称“最近五版”已生效。
- 真实 Gitee ZIP 下载、Sparkle 从 Gitee 实际安装和 macOS 13/当前系统运行时
  仍需在真实 tag 上验收。Mock 的耗时和结果不算真实验证。
