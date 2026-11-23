# 受控负载实验原始数据清单

- 时区 Asia/Shanghai (+08:00)；绝对时间见各文件名的时间戳与 _orchestration/boundaries.log。
- Mac15,9 / M3 Max / 12P+4E / 128GB / macOS 27.2 (26B123)。
- AC接电，开始时80%且未充电；内建屏在线，亮度不改变。
- 后台应用维持现状；Stats.app、macpow未停止。
- 唯一仓库写入范围为本目录；实验工具与分析在 /tmp/soc-power-research/lab/。
- 无sudo、无SMC写入、未安装软件、未改系统设置、未提交git。
- **原始逐秒 JSONL（约 11 MB）不随仓库提交**：保留在本机该目录，`.gitignore` 已排除 `*.jsonl`；表内 SHA256 供本机校验，`evidence/harness-evidence.tar.gz` 另含探测阶段的采样与逐通道矩阵。

## 采样器版本与命令

- schema: soc-power-research/1，默认17通道（原生Energy Model 14 + CLPC 3）。
- 二进制 SHA256: `d48e2ad65d013be37c8b749f28b72e706f7b29851eb8745ee4c78bebefeefc00`
- 源码 SHA256: `16671caf5c67f512059fbcea131b3d48a36b0ad811b29faf241ccaccfc2a2258`
- 命令：`power-sampler --hz 1 --seconds <phase-duration+5> --out <scenario>-20261030T230326.jsonl --label <scenario>`
- 单调时钟：CLOCK_MONOTONIC，加载器/编排labprobe/采样器共享同一系统基准。
- CPU: cpuload 2线程45s、6线程60s；GPU: Metal运行期源码编译，grid65536×inner4096，55s。
- 内存: memload 4线程×256MiB，总1GiB，40s；向量读写，校验约186.7GB/s。
- 混合: cpuload 4线程 + gpuload，55s。
- 阶段间10秒缓冲，负载结束后同场景继续采样5秒；所有原始样本均保留。

## 阶段边界（mono 秒）

下表PHASE_START包含快照/热检查准备时间；精确LOAD_START/STOP来自生成器日志。完整边界见 _orchestration/boundaries.log。

| 场景 | phase_start | load_start | load_stop | phase_end | 样本数 | ts_mono首/末 |
|---|---:|---:|---:|---:|---:|---|
| 01-idle-baseline | 199994.082548 | — | — | 200030.188497 | 35 | 199994.322618/200028.327636 |
| 02-cpu-light | 200040.352836 | 200040.522000 | 200085.532000 | 200090.968196 | 50 | 200040.609266/200089.612838 |
| 03-cpu-medium | 200101.127645 | 200101.272000 | 200161.313000 | 200167.425333 | 65 | 200101.353330/200165.353739 |
| 03b-memory-bandwidth | 200177.588526 | 200177.730008 | 200217.740841 | 200223.855252 | 45 | 200177.818749/200221.821169 |
| 04-recovery-idle | 200234.012060 | — | — | 200290.089311 | 55 | 200234.232590/200288.233247 |
| 05-gpu-compute | 200300.247544 | 200300.438000 | 200355.439000 | 200361.418051 | 60 | 200300.473856/200359.478738 |
| 06-cpu-gpu-mixed | 200371.574456 | 200371.717000 | 200426.763000 | 200432.577263 | 60 | 200371.796793/200430.798799 |
| 07-recovery-idle-2 | 200442.728945 | — | — | 200499.006878 | 55 | 200442.919538/200496.921468 |

## 后台与热状态快照

- 每阶段开始/中段/结束的ps：`_orchestration/ps-snapshots/`。
- 热状态变化：`_orchestration/thermal.jsonl`；每秒看门狗，中止阈值serious/critical。
- M3温度实际值位于各JSONL的smc数组：Te05 ECPU1、Tf04 PCPU1、Tf14 GPU1（Stats M3映射；传感器能力报告见 /tmp/soc-power-research/harness/capabilities.md）。
- 每秒GPU Device Utilization：`_orchestration/gpu-util.tsv`。
- 两GPU通道逐秒差分对照：`gpu-crosscheck.csv`。

### 开始时背景（完整初始ps快照另存）

```
# ps snapshot: 00-run-start  wall=2026-10-30T23:03:26+0800 mono=199993.975538
# --- top 25 by cpu ---
  PID  PPID  %CPU %MEM COMM
 1328     1 105.5  0.3 /System/Applications/Siri AI.app/Contents/MacOS/Siri AI
48440     1  85.8  0.0 /System/Applications/System Settings.app/Contents/Resources/systemsettingsagent
81860     1  67.3  6.9 /Applications/BlueStacks.app/Contents/MacOS/BlueStacks
  619     1  58.8  0.9 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
 1045     1  56.9  0.3 /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Support/corespotlightd
63065     1  35.7  0.7 /Applications/magpie.app/Contents/MacOS/magpie
59354 59341  33.8  0.4 /Applications/DeepSeek Harness.app/Contents/Frameworks/DeepSeek Harness Helper (Renderer).app/Contents/MacOS/DeepSeek Harness Helper (Renderer)
59342 59341  27.7  0.1 /Applications/DeepSeek Harness.app/Contents/Frameworks/DeepSeek Harness Helper.app/Contents/MacOS/DeepSeek Harness Helper
 1077     1  21.8  0.0 /usr/libexec/siriknowledged
  879     1  20.2  0.6 /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/Metadata.framework/Versions/A/Support/mds_stores
 1200     1  14.1  0.0 /usr/libexec/swcd
18255 17803  11.0  0.0 /Users/lingsmbp/Downloads/macpow
  808     1   8.6  0.1 /usr/sbin/coreaudiod
 1309     1   8.2  0.1 /System/Applications/Utilities/Activity Monitor.app/Contents/MacOS/Activity Monitor
  613     1   6.4  0.0 /usr/sbin/notifyd
17763     1   6.4  0.1 /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
 5090     1   6.1  0.0 /usr/libexec/diagnosticd
84549 84507   4.9  0.0 /usr/bin/log
 1005     1   4.6  0.0 /System/Library/PrivateFrameworks/BiomeStreams.framework/Support/BiomeAgent
49245  9296   4.3  0.0 ps
 3951  1409   3.7  0.2 /Applications/Doubao.app/Contents/Helpers/Doubao Browser.app/Contents/Frameworks/Doubao Browser Framework.framework/Versions/147.0.7727.149/Helpers/Doubao Browser Helper (Renderer).app/Contents/MacOS/Doubao Browser Helper (Renderer)
49315 49313   3.4  0.0 /bin/bash
59797 59341   3.1  0.7 /Applications/DeepSeek Harness.app/Contents/MacOS/DeepSeek Harness
49296  9342   2.9  0.0 /usr/sbin/lsof
48740     1   2.9  0.0 /System/Library/PrivateFrameworks/CascadeSets.framework/Versions/A/XPCServices/SetStoreUpdateService.xpc/Contents/MacOS/SetStoreUpdateService
# --- our loaders / sampler ---
(none)

```

## 异常 / NOT TESTED

- brightness: NOT TESTED。用户禁止系统设置变更；公开API只读探测返回NO_DISPLAY_SERVICE，未尝试调亮度；无法验证PDBR/PHPC的亮度串扰。
- 无干净空闲；后台GPU基线已高且不同阶段发生变化，只把阶段均值作为本次环境观察。
- ANE未安排隔离负载；计数偶尔增长不能确定来源，更不能确认PHPC是否覆盖ANE。
- USB PowerOutDetails在所有样本缺失；残差采用USB=0的条件估算，不作为完整边界的严格验证。
- 充电为IsCharging=false，未读取SMC B0AC/B0AV；充电功率使用AppleSmartBattery代理。
- PPbb不可用；原生EM CPU/ANE/DRAM/DISP等13/14通道冻结，不补为0W。
- 风扇声音/真人感知卡顿无自动传感器证据，不声称已测；thermal看门狗与温度保留。
- PDBR随背景内容/实际背光变化，不能当作受控亮度常量。

## 边界日志

完整逐行记录（含 PHASE_START/LOAD_START/LOAD_STOP/MID_SNAPSHOT/BUFFER）：`_orchestration/boundaries.log`。

## 数据SHA256

| 文件 | 字节数 | SHA256 |
|---|---:|---|
| 01-idle-baseline-20261030T230326.jsonl | 713971 | d3feb5896e5f99e42df1877a1dfab7454cbb77a03adf974139e42941ed412131 |
| 02-cpu-light-20261030T230326.jsonl | 1021193 | 52cfca925c5ed2be864b5d9db4405373968a822a2a81ea5c0c8f6b283f55324e |
| 03-cpu-medium-20261030T230326.jsonl | 1328770 | 9c95edc471ec7d7f353449109f1c00189fa47a423fe421b9e599a6d867acc2cc |
| 03b-memory-bandwidth-20261030T230326.jsonl | 919590 | 6dee4562d4d4bde8d4af3c4088db87e00028b431866418a5fc9d6543d30c0c99 |
| 04-recovery-idle-20261030T230326.jsonl | 1123655 | 31696625e924bbad81b11914c6a0c67b5707c2747acdd29e688aadc2074c4bbc |
| 05-gpu-compute-20261030T230326.jsonl | 1226090 | f9064aa65d46c767e9f667b29b893bc00c621fae23be151d6751b9cd89b8a14f |
| 06-cpu-gpu-mixed-20261030T230326.jsonl | 1226152 | 3a736026ac9b775f9c07d88b2ae1b92f55d9db4f1258b80ea76b64ec40e0e62b |
| 07-recovery-idle-2-20261030T230326.jsonl | 1123848 | ab4e39265c9add611299fe1f371ad57b79701cf4ebc375ac4f7110490716efe4 |
