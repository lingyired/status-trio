# 只读功耗采样器（Mac15,9 / macOS 27.2）

研究用工具。除 `--out` 指定的 JSONL 外不写任何位置；不写 SMC、不枚举 SMC 键表、不提权、不安装、不常驻。完整能力与限制见 [capabilities.md](capabilities.md)。

## 构建

```sh
cd /tmp/soc-power-research/harness
make
```

等价命令：

```sh
/usr/bin/clang -O2 -fobjc-arc -Wall -Wextra \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  power-sampler.m -o power-sampler \
  -framework Foundation -framework IOKit -lIOReport
```

`-lIOReport` 链接 SDK 内的 `usr/lib/libIOReport.tbd`（install-name `/usr/lib/libIOReport.dylib`）。

## 运行

```sh
./power-sampler --hz 1 --seconds 60 --out /path/file.jsonl --label name
```

固定接口：

```text
power-sampler --hz <1..100> --seconds <N> --out <file.jsonl> [--label <name>] [--all-channels] [--inventory <channels.json>]
```

- 默认订阅 17 个通道：14 个关键原生 `Energy Model` 通道 + 3 个显式 AppleCLPC 通道。
- `--all-channels`：订阅全部原生 `Energy Model` 通道（325 个）与 CLPC 3 个，用于能力探测/冻结判断，文件很大。
- `--inventory <file>`：额外导出一次全量原生通道枚举与当前原始值（只用于探测）。
- 正常结束或 `Ctrl-C`/`SIGINT`/`SIGTERM` 都会刷盘、释放订阅并返回 0。

## JSONL

每行一个 JSON 对象，`schema = "soc-power-research/1"`。顶层字段：

| 字段 | 含义 |
| --- | --- |
| `ts_mono` | `clock_gettime(CLOCK_MONOTONIC)` 秒，double |
| `ts_wall` | UTC ISO8601（毫秒） |
| `label` | `--label` |
| `index` | 从 0 开始的样本序号 |
| `smc` | 12 个固定键的数组：`key/type/size/raw_hex/value/unit_inferred/status` 及原始 SMC 返回码 |
| `ioreport` | `status`、`native_channel_count` 不在此行（见 inventory）；`channels` 为订阅通道数组 |
| `ioreport.channels[]` | `group/subgroup/channel/unit/format/channel_id_hex/id`、`raw_count`、`raw_count_decimal`、`delta_count`、`delta_count_decimal`、`power_w_estimate` |
| `clpc` | `channels[]`（同上）、`iokit_open`、`properties`（`~pkg-power-split-*` 等原始属性） |
| `thermal_state` | `nominal` / `fair` / `serious` / `critical` |
| `pmset_batt` | IOKit `AppleSmartBattery` 属性：`PowerTelemetryData`、`AdapterDetails`、`ChargerData`、`Voltage`、`InstantAmperage` 等，原样整数 |
| `sampling` | `target_hz`、`scheduled_mono`、`lateness_s`、`interval_s`、`interval_error_s` |
| `sample_read_duration_s` | 本次读取耗时 |
| `pid` | 采样器 PID |

要点：

- 所有 64 位计数器同时给出 JSON 整数与十进制字符串（`*_decimal`）。JavaScript/JSON 双精度会丢失 >2^53 的整数精度，分析请用字符串或 Python。
- 只有“计数增加且单位可换算”时才给 `power_w_estimate`。计数不变时为 `null` 并写 `power_status: "count unchanged; zero W not inferred"`，绝不当作 0 W。
- CLPC 的 `channel/unit/name` 是采样器按 macmon 反推结果**声明**的 descriptor，不是原生枚举。字段 `descriptor_origin`、`unit_origin`、`name_origin` 标明这一点。
- `pmset_batt` 的 `PowerTelemetryData` 可能长时间不刷新；`ts_wall` 是读取时间，不是测量时间。

## 字段示意（数值为占位，非实测行；真实数据见 `sample-idle.jsonl`）

```json
{"schema":"soc-power-research/1","ts_mono":123456.789,"ts_wall":"2026-10-30T14:57:00.123Z","label":"idle-no-induced-load","index":0,"smc":[{"key":"PDTR","type":"flt ","size":4,"raw_hex":"e0474142","value":48.32,"unit_inferred":"W","status":"ok"}],"ioreport":{"status":"ok","channels":[{"group":"CLPC","channel":"GPU Energy","unit":"nJ","raw_count":372907437344396,"raw_count_decimal":"372907437344396","delta_count":12345,"power_w_estimate":4.1}],"interval_s":1.0},"clpc":{"channels":[]},"thermal_state":"nominal","pmset_batt":{"PowerTelemetryData":{"SystemPowerIn":40905}},"sampling":{"target_hz":1,"lateness_s":0.005}}
```

## 辅助文件

- `analyze.py`：离线汇总 `*.jsonl`，生成 `analysis-summary.json` 与 `channel-freeze-matrix.csv`；只读输入、只写同目录。
- `inventory.json`：一次全量枚举（11,282 原生 descriptor，11,120 个有当前样本）及当前原始值。
- `channel-freeze-matrix.csv`：60 秒全通道冻结矩阵。
- `sample-idle.jsonl`：30 秒默认 17 通道样例（未主动施加负载）。
- `freeze-1hz-60s.jsonl`：60 秒全通道冻结观察。
- `smc-tick-10hz.jsonl` / `temperature-tick-10hz.jsonl`：10 Hz 25 秒更新节奏观察。
- `clpc-ioreg.txt`、`background-load.txt`、`pmset-batt.txt`：环境证据。
