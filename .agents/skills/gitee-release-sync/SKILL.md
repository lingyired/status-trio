---
name: gitee-release-sync
description: Use when asked to check, mirror, resume, or verify an already published Status Trio GitHub release on Gitee. Run locally through the shared verification script; never rebuild or create another authoritative release.
---

# 本地 Agent 同步 Gitee 镜像

GitHub 是唯一正式发布来源。本 Skill 在本地网络执行，不通过 GitHub Actions 上传。
用户说“把 vX.Y.Z 同步到 Gitee”或“恢复 Gitee 同步”时，直接执行下列入口并处理结果，
不要让用户反复在终端运行命令，不操作用户的 Otty，不把 Token 读入对话。

## 入口

从仓库根目录执行：

```bash
node scripts/gitee-mirror-agent.mjs check v1.9.6
node scripts/gitee-mirror-agent.mjs sync v1.9.6
node scripts/gitee-mirror-agent.mjs verify v1.9.6
```

- `check` / `verify`：只读，不加载 Gitee 写入凭据。
- `sync`：只同步指定的已公开正式版本；成功后继续执行 `verify`。
- 核心实现统一在 `scripts/sync-gitee-release.mjs`，不要在 Skill 或 MCP 中复制发布逻辑。

## 凭据：一次配置，之后 Agent 直接运行

入口先使用当前子进程的 `GITEE_TOKEN`，没有时从 macOS 钥匙串读取：

- 通用密码名称（service）：`status-trio.gitee-token`
- 账户（account）：`lingyired`

令牌只留在执行进程内，不输出、不写代码、不传在命令行参数中。首次没有凭据时，
提示用户在“钥匙串访问”中新建上述密码条目，或在 Agent 的受控进程环境配置
`GITEE_TOKEN`；不得索要 Token 文本，不从用户 shell、历史或进程列表提取 Token。
钥匙串授权弹窗由用户操作。GitHub Secret 不可读，不试图导出它。

## 必须保留的验证

1. 读取公开稳定 GitHub Release，拒绝 Draft、预发布和诊断包。
2. 验证 manifest 的 repo/tag/source SHA、Developer ID、公证状态、DMG 长度和 SHA-256。
3. 上传原始字节，不重编译、不重新签名。
4. 通过公开 Gitee URL 下载并重新计算 SHA-256。
5. 仅保留已镜像的条目，派生完全不含 GitHub URL 的 `appcast-gitee.xml`；保留多语言、
   CDATA、最低系统版本、长度、EdDSA 签名和扩展字段。未知 Feed 签名直接失败。
6. 全部通过后才提交 Feed，然后匿名回读校验。不得先更新 Feed 后上传包。

## 恢复与结果

- 同 tag 同字节：安全复用；不同哈希：立即停止，不覆盖或删除已有附件。
- 部分上传/Feed 写入/缓存验证失败：保留现场，解决具体原因后重试相同 tag。
- 网络错误不是权限或内容审核的证据；不要仅根据 403 或超时猜测根因。
- 结果报告 tag、SHA-256、GitHub/Gitee URL、Feed 和耗时。Mock 耗时不冒充真实同步耗时。
- 自动清理旧版暂未实现，禁止把“最近五版”说成已生效。并行本地同步禁止：一次只运行一个。
- 不改变 GitHub Release，不自动触发正式构建，不替换生产客户端。

## 与 Gitee 官方 MCP Skill 的关系

参考 [官方说明](https://gitee.com/oschina/gitee-agent-skills/blob/main/mcp-gitee-skills/README_CN.md)
和 [create-release](https://gitee.com/oschina/gitee-agent-skills/blob/main/mcp-gitee-skills/skills/create-release/SKILL.md)。
官方 Skill 要求连接 Gitee MCP，主要覆盖 Release 元数据、标签和 Changelog，未定义上述
原始 DMG、SHA-256、EdDSA 和 Feed 一致性闭环，因此不直接用通用 create-release 替代本入口。
若已连接 Gitee MCP，可用于只读仓库/Release 查询；二进制上传及 Feed 发布仍由共用脚本负责。
当前会话没有 Gitee MCP 不妨碍本 Skill 通过 HTTPS API 执行。
