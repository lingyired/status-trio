---
name: gitee-release-sync
description: Use when asked to check, mirror, resume, or verify an already published Status Trio GitHub release on Gitee using its notarized app ZIP. Run locally through the shared verification script; never rebuild or create another authoritative release.
---

# Gitee ZIP 镜像（本地 Agent）

GitHub 是唯一正式发布来源。Gitee 只镜像已公开、已公证的 app；正式 GitHub 包仍是
DMG，Gitee 使用同一 app 生成的 ZIP。不要重建、重签 app，也不要把 DMG 再套一层 ZIP。

## 命令

    node scripts/gitee-mirror-agent.mjs check vX.Y.Z
    node scripts/gitee-mirror-agent.mjs auto vX.Y.Z
    node scripts/gitee-mirror-agent.mjs sync vX.Y.Z
    node scripts/gitee-mirror-agent.mjs verify vX.Y.Z

`check` / `verify` 只读；`sync` 使用同一核心脚本同步 ZIP；`auto` 会自动执行
`sync` 后紧接着 `verify`，这是发布后由本地 Agent 执行的默认流程。发布工作流
本身只记录待同步 tag，不直接上传 Gitee。

## 凭据

Agent 进程优先读 `GITEE_TOKEN`，否则读 macOS 钥匙串通用密码：
service `status-trio.gitee-token`，account `lingyired`。一次性配置后无需用户终端；
Token 不进入聊天、日志、命令行或仓库。GitHub Secret 不可读出；不要把 Token 文本
贴到对话里。

## 中文更新日志来源标记

Gitee 派生 Feed 的中文说明顶部必须加来源提示：`zh-Hans` 写
`更新源：Gitee`，`zh-Hant` 写 `更新來源：Gitee`。目前只写中文，其他语言保持
原文，不添加来源行；该行不能改变原更新日志正文。

## 必须保留的验证

1. GitHub Release 必须已发布、稳定、非 Draft、非诊断包。
2. manifest 的 repo/tag/source SHA、Developer ID、公证状态、DMG 和 ZIP 的长度、
   SHA-256 和独立 EdDSA 签名全部匹配；ZIP 签名不能是诊断占位。
3. 上传原始 ZIP 字节；不得解压重打包或重签名 app。
4. 从公开 Gitee 下载 ZIP 并重新计算 SHA-256。
5. 从正式 appcast 派生 Gitee Feed：只保留已镜像项目，enclosure 指向 Gitee ZIP，
   长度和 `sparkle:edSignature` 使用 ZIP 的值，文件中不能有 `github.com`。
6. Feed 全部校验通过后才提交；未知 Feed 签名、DTD 和实体 fail closed。

## 失败恢复

- 同 tag 同字节：复用；不同哈希：立即停止，不覆盖、不删除已有附件。
- HTTP 403、超时或缓存未刷新：先判断是权限、内容审核还是网络，不要猜。
- 部分上传/Feed 写入失败：保留已上传附件和上一版 Feed，修复原因后重试同一 tag。
- 一次只运行一个同步，避免并发 Feed 覆盖；自动旧版清理尚未实现。
- 不改变 GitHub Release，不自动触发构建，不替换生产客户端。

## 与官方 Gitee Skill

参考 [Gitee 官方 Skills](https://gitee.com/oschina/gitee-agent-skills/blob/main/mcp-gitee-skills/README_CN.md)。
官方 create-release 负责 Release 元数据、标签和 Changelog，要求 Gitee MCP；它不包含
本项目的原包完整性、公证、哈希和 Sparkle Feed 规则。若已连接 MCP，可只读查询
仓库/Release，二进制 ZIP 上传和 Feed 发布仍调用本项目共用脚本，不复制发布逻辑。
