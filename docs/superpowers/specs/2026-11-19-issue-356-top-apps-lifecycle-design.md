# #356 Top Apps 生命周期设计

1.10 开发构建在 M1 Pro / macOS 27.2 出现持续 500–700% CPU。基线 f1e915a3 已包含 8e295f5a 的 EOF 与结束 handler 清理。基线重点测试通过，其中 Swift Testing 46 项。代码复查发现，继承的写端能让退出后的读取在完成回调返回后继续占用线程和 FD。睡眠期间的异步 reset 也可能被迟到的累计采样覆盖。详见 [报告 #356](https://github.com/lingyired/status-trio/issues/356)。

## 约束

- macOS 13+，使用 Foundation、Dispatch、Darwin。保留 Process、同步和异步入口、环境变量与退出状态契约。
- 保留 Top Apps 的可见详情 Demand、sessionGeneration 和 inFlight。CPU/GPU/网络 2 秒，内存 6 秒。保持榜单口径、UI 和硬件监控周期。
- 沿用 250 ms kill grace、500 ms 错误收尾 grace。仅处理执行器启动且仍运行的直属进程。
- 以实测决定元信息、图标缓存和连续失败退避是否值得后续投入。

## 方案比较

1. 给现有 FileHandle 读路径加非阻塞。代码变动较小，仍需协调多队列的回调积压与 FD 关闭。
2. 选用两个独立 DispatchSourceRead，由原状态队列统一所有权。读端非阻塞，每个可读事件限制读取批次。多个事件可交错推进，超时和取消也能进入同一队列。Foundation Process 继续管理启动和退出。
3. 重写为 posix_spawn。可以直接控制 FD 继承与启动，但涉及更多既有调用契约。

## Runner

退出码为零、两路 EOF、监听和 FD 已清理后才能报告成功。直属进程退出后继续排空 stdout 和 stderr，直到两路 EOF 或原调用 deadline。继承写端在 deadline 前关闭时保留完整输出。超过 deadline 仍未关闭则返回 timedOut，已有失败原因优先。保留 #131 完整输出和 #268 双流回归。

读批次处理 EOF、EAGAIN/EWOULDBLOCK、EINTR 和致命读取错误。stdout 与 stderr 分别遵守现有 outputLimit。第一个明确终止原因固定，正常退出后的排空阶段仍接受取消。提前取消回调 cancelled，启动失败回调 failed。重复取消与迟到事件只会看到终止或完成状态。单路 EOF 立即取消该路读源。取消、超时、超限、读取错误和启动失败时停止相应读源并释放资源。使用原 FileHandle 监控时，由取消处理器调用 FileHandle.close()，不得对原 FD 同时调用 Darwin.close。读源取消处理器在同一状态队列登记清理完成。取消或弱捕获已无用的 deadline，避免短命令在到期前留存 Pipe。原 deadline 之后关闭的继承写端仍对应超时，500 ms grace 用于终止遗留直属进程。

## Top Apps

用受控采样验证睡眠时旧 GPU/网络读取挂起、唤醒后才返回，以及快速离开再返回同一指标。旧采样结束后重置累计基线，重置完成后新会话开始读。旧结果按会话标识丢弃，新会话第一个有效 GPU/网络样本只建基线。睡眠时没有在途采样也要重置。若已有 GPU 调用挂起，唤醒后等它返回再重置，沿用单个在途采样的约束。关闭面板、关闭 showsHardwareTopApps 开关和切页的 Demand 用现有 headless 集成测试验证。调度改动以可复现的缺陷为前提。

## 验收

分别记录自动回归、macOS 13 静态检查、开发机运行和报告机复测。真机 A/B 记录同场景、同持续时间的 CPU、子进程、线程、FD、失败采样以及关闭后的状态。保留 worktree 等待用户验收。
