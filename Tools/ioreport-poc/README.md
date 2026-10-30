# ioreport-poc — SoC 功耗只读可行性 POC

Phase 2（PR B 可行性）的独立实验工具。**不是产品代码**：不在 `Package.swift` 里、不属于任何 target、不进入 app 产物、不需要 sudo/entitlement/daemon/LaunchAgent。

结论与数据见 `docs/io-report-power-poc.md`（结论：**NO-GO**，macOS 27.2 / M3 Max 上 Energy Model 的 CPU/ANE/DRAM/DISP 计数器冻结，仅 `GPU Energy` 推进）。

## 文件

| 文件 | 用途 |
|---|---|
| `ioreport-poc.swift` | 主程序：dlopen `/usr/lib/libIOReport.dylib` 动态解析私有符号，枚举通道、区间能量差 → W、SMC/电池交叉验证、自身开销、基线门控自测 |
| `run.sh` | 编译到 `/tmp/ioreport-poc/` 并执行；`run.sh experiments` 跑受控对照批次 |
| `run-experiments.sh` | 空闲 / 8 线程 CPU 满载 / Metal GPU 负载 三组对照，写 `/tmp/ioreport-poc/experiments.jsonl` |
| `gpu-load.swift` | 合成 GPU 负载（Metal compute），仅用于对照 |

## 常用命令

```bash
bash run.sh groups                        # 210 group / 11292 channel 全景
bash run.sh list --group "Energy Model"   # 325 通道 + 单位
bash run.sh sample --window 5            # 区间功率 + PSTR/电池交叉验证
bash run.sh sample --window 5 --json     # 机器可读
bash run.sh bench --window 6             # setup/采样耗时、CPU%、RSS、ri_energy_nj
bash run.sh selftest                     # 基线/计数器回卷/停更 门控用例
bash run.sh experiments                  # 受控对照批次
```

日志与产物统一放 `/tmp/ioreport-poc/`，不写入仓库。

## 硬约束

- 不运行 `powermetrics`（需要 root），不申请任何权限；
- 只读：SMC 只用命令 9（读 key info）与 5（读 bytes），从不发送写命令 6；
- 失败/无数据/计数器停更一律返回 nil，不输出 0 W、不造数。
