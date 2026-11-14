# Gitee 本地 Agent 镜像维护

GitHub Release 继续是唯一正式构建和发布来源。Gitee 只镜像已公开且验证通过的原始包。
正式发布后，GitHub Actions 的 Job Summary 会标记“Gitee mirror pending local Agent sync”，
不自动上传、不重跑 macOS 构建，也不因镜像故障回滚正式发布。

## 日常操作

给本地 AI Agent 一句话：“用 gitee-release-sync 把 v1.9.6 同步到 Gitee。”
Agent 从仓库根目录执行：

```bash
node scripts/gitee-mirror-agent.mjs check v1.9.6
node scripts/gitee-mirror-agent.mjs sync v1.9.6
node scripts/gitee-mirror-agent.mjs verify v1.9.6
```

`check` 和 `verify` 只读。首次未同步时报告缺失；`sync` 调用与之前相同的核心脚本，
不是第二套发布器。整个顺序为：读取 GitHub 正式版本 → 校验身份/公证/哈希 → 上传原包
→ 匿名下载校验 → 派生并校验 Feed → 提交 Feed → 匿名回读。

## 一次性凭据配置

本地入口只在 `sync` 时使用 `GITEE_TOKEN`；未设置时读取 macOS 钥匙串通用密码：
名称 `status-trio.gitee-token`，账户 `lingyired`，密码填 Gitee Token。请在“钥匙串访问”
或受控 Agent 环境中配置，不把 Token 发给 Agent，不放在 shell 命令行或提交文件里。
钥匙串若请求授权，由用户批准。之后 Agent 可直接运行，无需占用用户 Otty 终端。
GitHub Actions Secret 不能导出给本地 Agent；云端存着 Token 不等于本地已配置。

## 工作流边界

- 正式 `release.yml` 仅在成功后记录待同步提示，不 dispatch 上传流程；撤销额外的
  `actions: write` 权限，保留原正式发布和恢复逻辑。
- `gitee-sync.yml` 保留为手动离线脚本检查：Ubuntu、无 Token、无远程写入。
- 不自动创建定时任务。需要每次发布后同步时，显式调用本地 Skill。
- 同一时间只运行一个镜像命令，避免不同版本竞争 Feed。

## Feed 与客户端

Gitee Feed 独立使用 `appcast-gitee.xml`，由权威 GitHub appcast 派生，只包含已镜像
条目，仓库链接和发布说明链接都改成 Gitee，不含 GitHub URL。保留 Sparkle EdDSA
签名、文件长度、macOS 13.0 最低版本、XML 扩展字段和多语言内容。遇到 Signed Feed
或 DTD/实体直接失败，不能假设安装包签名等于 Feed 签名。

默认客户端顺序：GitHub → Gitee → gh-proxy.com → ghfast.top。手动 Gitee 入口
只对该周期使用 Gitee → GitHub → gh-proxy.com → ghfast.top；共享一个 Sparkle Updater。
取消、TLS/证书、签名、损坏、安装错误不自动换源。

## 故障恢复与尚未验收

重试相同 tag 时复用同哈希附件、补齐缺失内容；不同哈希立即失败且不覆盖。
Feed 更新失败时保留上传附件，不删除上一版；公开缓存尚未刷新时也报告未验证。
旧版自动清理和最近五版策略尚未实现，不能据此声称容量已受控。

2026-11-14 的证据：临时小 XML 和不含 GitHub 链接的完整 Feed 都公开返回 200；
本机上传 20 MB 零字节测试文件（含 .dmg 后缀）返回 201。但本机上传真实签名的
v1.9.6 DMG 返回 HTTP 403，响应为 "malicious file detected and rejected"；
把它复制成 .bin 再上传同样 403，证明是内容安全拦截，不是扩展名或网络问题。
海外 Runner 还在 300/900 秒上传超时后失败。

结论：当前 Gitee Release 附件不能托管真实 DMG，因此 Gitee DMG 镜像、公开
appcast-gitee.xml 发布、Sparkle 从 Gitee 安装和 macOS 13 运行时验收均未完成。
不要通过改后缀、压缩或分片绕过 Gitee 的安全检测。可行方向只有：向 Gitee 提交
附件误判申诉/申请白名单，或改用其他国内对象存储托管 DMG（Gitee 只放 Feed）。

## 官方 Skill 参考

[Gitee 官方社区版 Skills](https://gitee.com/oschina/gitee-agent-skills/blob/main/mcp-gitee-skills/README_CN.md)
中的 create-release 用于 Release 元数据、标签和 Changelog，并要求 Gitee MCP。
它未定义本项目签名、哈希与 Feed 的一致性规则。可结合它查询仓库，但镜像写入保持
调用本项目共用脚本，不复制二进制发布逻辑。无需为此新增或安装整个官方 Skill 合集。
