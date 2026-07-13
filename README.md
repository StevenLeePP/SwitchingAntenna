# Type-A 4T4R：MEX 持久消费者实时接收系统

本目录是 `demo` 工程的 C/MEX 实时化分支（`cmex`）。目标不是改变
NR Type-A 4T4R 空口格式，而是把连续接收时最耗时、最容易造成 MATLAB
队列堆积的工作下放到持久 MEX 消费者，同时保留 MATLAB 作为低频同步和
诊断控制面。

当前默认参考为半帧载荷：slot 0 用于 PSS/SSB，slot 1--10 为四层 QPSK
数据，后续 slot 静默。TX 与 RX 必须使用同一个
`nr4_type1_reference.mat`。

## 当前架构

```text
YunSDR RX 4 路 122.88 MS/s
        |
        v
type1_yunsdr_rx_mex.c 后台 pthread
  - DMA 读取、硬件事件计数、原始 IQ 环形缓冲
  - producer / consumer sequence 与 drop-new 保护
        |
        +--> MATLAB 控制面（低频）
        |      PSS 锁定、窄窗 PSS 健康检查、CP-CFO 与帧时间基准
        |
        v
direct consumer（MEX 持久数据面）
  - 四相数字开关：122.88 -> 30.72 MS/s
  - CFO 补偿、1024 点固定 radix-2 C FFT、612 子载波抽取
  - 持久 DM-RS / data RE / QPSK / bit-reference maps
  - 帧 timestamp、FIFO、BER 和分段时延累积
  - 调用已验证的 C frame-PHY MEX：Type-1 DM-RS、4x4 RZF、QPSK 硬判决
        |
        v
结果 MAT：BER、EVM、H、队列、时延、硬件事件、timestamp/sequence 审计
```

MATLAB 不再在每帧导出整段 IQ、重建 reference maps 或执行逐帧 FFT。
它只在启动时 PSS 锁定 timestamp，并以 0.5 s 周期执行小窗口健康检查，
把 CFO 与帧时间校正发送给 MEX。

当前启动使用两阶段切换：先用 MATLAB 完成粗 PSS，再显式丢弃已进入软件
ring 的冷启动数据；完成 maps 与窄窗 PSS 跟踪后，等待可完整解码的 PSS 对齐帧并
再次 `directflush`，最后才启动 direct consumer。`startupDiscardBlocks`、
`startupTimestampAudit` 会保存两次丢弃量、PSS/raw timestamp、ring sequence 和
x=0 的 pending，便于区分软件 ring 历史与驱动 DMA 尚未入环的积压。

> 当前 DM-RS/RZF/判决内核是 `type1_decode_frame_grid_mex`；它是 C MEX，
> 由 direct consumer 以 MEX API 调用。换言之，重计算的 PHY 算法已是 C，
> 但栅格仍以内部 MEX `mxArray` 传给该内核，并非完全手写的单一 C 函数。

## 已下放到 MEX 的功能

| 功能 | 位置 | 是否在逐帧热路径 |
|---|---|---|
| YunSDR 四通道 DMA 接收、原始环形缓冲、事件计数 | `type1_yunsdr_rx_mex.c` | 是 |
| FIFO producer/consumer、drop-new、高水位 | `type1_yunsdr_rx_mex.c` | 是 |
| 4 相开关/解交织 | `direct_make_grid` | 是 |
| CFO 复旋、固定 1024 点 FFT、子载波抽取 | `direct_make_grid` | 是 |
| DM-RS/data/QPSK/bit maps 的持久副本 | `directphysetup` | 启动一次 |
| Type-1 DM-RS、4x4 RZF、硬判决、raw BER 累积 | `type1_decode_frame_grid_mex.c` + `directpoll` | 是 |
| PSS 获取、窄窗 PSS 复检、CFO/时间基准控制 | `type1_analyze_fast.m` | 否，0.5 s 控制周期 |
| PBCH/MIB、全帧 MATLAB 对照、图形显示 | MATLAB 离线/诊断路径 | 否 |

## 关键脚本与命令

| 文件/命令 | 用途 |
|---|---|
| `type1_tx.m` | 周期发送共享参考中的一个 10 ms 波形；退出时关闭 cyclic TX。 |
| `type1_rx_direct.m` | MEX 持久消费者的无图形实时 RX；保存 `type1_direct_results.mat`。 |
| `type1_yunsdr_rx_mex.c` | YunSDR、FIFO、native-ring FFT、时间控制与审计 MEX。 |
| `type1_decode_frame_grid_mex.c` | C 实现的 Type-1 DM-RS、4x4 RZF、QPSK 判决和 BER。 |
| `type1_validate_direct_phy_maps.m` | 持久 reference maps 与直接 frame-PHY MEX 的严格等价检查。 |
| `type1_validate_native_ring_grid.m` | 同一 PSS timestamp 下 native-ring C grid 与 MATLAB grid/H/EVM/raw errors 对照。 |
| `type1_compare_direct_stages.m` | MATLAB 标准路径、MATLAB+C PHY、native-ring+C PHY 的阶段消融对照。 |
| `type1_plot_pending_compare.m` | 读取两个 `pendingTrace` 结果，离线绘制单阶段与两阶段启动队列曲线。 |
| `type1_build_rx_mex.m` | 编译 YunSDR 接收 MEX。 |

在 RX 服务器上编译并运行直接消费者：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
/home/bupt/tools/matlab/bin/matlab -batch "type1_build_rx_mex"

# 板卡设备节点仅 root 可访问；按服务器既有权限策略启动。
env TYPE1_DIRECT_DURATION_SEC=60 TYPE1_FIFO_RING_BLOCKS=2048 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_rx_direct"
```

TX 应比 RX 多运行至少启动和收尾余量。`type1_tx.m` 的正确结束日志必须包含：

```text
Type-A TX cleanup: cyclic disable ret=0; YunSDR device closed.
```

## 队列与实时性指标说明

MEX 以 **1 ms 原始 DMA block** 为队列单位；在本配置中每 block 为
122,880 个 122.88 MS/s 样本。所有 `pending`/`highWater` 数值均可近似
读作毫秒。

| 指标 | 含义 | 合格判据 |
|---|---|---|
| `frames` | 已完成的 10 ms 直接解码帧数 | 60 s 应约 6000 帧 |
| `pending` | producer 已写入、consumer 尚未释放的 1 ms block 数 | 稳定或下降；最终值小于环形容量 |
| `highWater` | 本轮 `pending` 的最大值 | 用于评估启动突发和容量裕量，不等同丢包 |
| `dropNew` | FIFO 满时未写入环形缓冲的新 block 数 | 必须为 0；非零则 BER 无效 |
| `extractMs` | 四相取样、IQ 标定、CFO 复旋的平均帧时延 | 与 FFT/PHY 合计小于 10 ms 且有裕量 |
| `fftMs` | 154 个 OFDM 符号、4 路 1024 点 C FFT 的平均帧时延 | 同上 |
| `phyMs` | C DM-RS、RZF、判决与 BER 的平均帧时延 | 同上 |
| `totalMs` | 上述 direct consumer 一帧总平均时延 | 小于 10 ms 才能长期追上 100 frame/s |
| `eventDelta` | 四 RX 口的 overflow/count/timeout 增量 | overflow、timeout 必须为 0 |

例如 `pending=10，峰值 517` 的意思是：试验结束时只剩 10 个 1 ms block
（约 10 ms）等待处理；启动/同步阶段曾积压到 517 个 block（约 517 ms），
但没有满队列、没有丢弃新 block，之后已消化到 10。它不是“处理时延 517 ms”。

### 两阶段启动与初始数据丢弃

当前两阶段策略的目标是让 PSS、reference-map 建立和 MATLAB 控制面工作不进入
direct consumer 的待处理历史。`directflush` 只作用于**已经进入 MEX 软件 ring**
的块；它不能清空 YunSDR/驱动内部尚未由后台 pthread 读出的 DMA 描述符。因此，
`pending` 的 x=0 仍可能大于完整一帧所需的约 6--8 ms。这不是 `dropNew`，也不是
软件 ring 未执行 flush；应通过 `startupTimestampAudit` 中“timestamp 对齐但
producer sequence 提前”的证据识别该驱动侧积压。

最新 10 s OTA 启动对比（`captures/type1_direct_20260713_171338`）为：

| 项目 | 单阶段历史对比 | 当前两阶段 |
|---|---:|---:|
| x=0 pending | 约 482 block | 84 block |
| 峰值 pending | 约 558 block | 约 103 block |
| 稳态 pending | 未在 10 s 内追平，结束约 214 block | 约 20 block，最终 15 block |
| `dropNew` | 0 | 0 |

两阶段显著减少了 PSS 冷启动造成的软件历史；但该 10 s 结果是启动/队列验证，
不是对下文 60 s BER 基线的替代。若验收要求 x=0 接近零，需要 vendor DMA 提供
显式 flush，或把“PSS 锁定--驱动清队列--arm 新帧”的状态机放入 native 路径。

## 实时星座图

`type1_rx_live.m` 的星座图以低频率刷新固定数量的均衡后 data RE（默认最多
500 点/层），并固定坐标轴为 `[-2, 2]`。即使虚拟 IQ 的信号存在性门限判为无信号，
也不会清空或显示 `NO SIGNAL` 覆盖层：均衡后的噪声/切换过渡散点会照常绘制，
QPSK 理想点始终显示。门限仅保留给 BER 与有效载荷覆盖率统计，相关快照的
`outcome` 为 `no-signal-fast-gate`，不计作有效 `decoded` 样本。

## 最新 OTA 测试结果

以下为最新已保存且带 timestamp/sequence 审计的 RX 60 s 结果：

`captures/type1_direct_20260713_155645/type1_direct_results.mat`

| 项目 | 实测值 | 说明 |
|---|---:|---|
| 持续时间 | 60.095 s | TX 连续运行且四路 underflow=0 |
| 已解码帧数 | 6041 | 约 100.5 frame/s |
| `dropNew` | 0 | 没有软件 FIFO 丢帧 |
| 最终/峰值 pending | 10 / 517 block | 约 10 ms / 517 ms |
| 硬件事件增量 | 全 0 | 四路 overflow/count/timeout 均无异常增量 |
| `extractMs` | 2.142 ms | 平均每 10 ms 帧 |
| `fftMs` | 5.141 ms | 平均每 10 ms 帧 |
| `phyMs` | 1.943 ms | 平均每 10 ms 帧 |
| `totalMs` | 9.380 ms | 小于 10 ms；约 0.62 ms 平均预算裕量 |
| 各层 bit errors | `[16, 29, 1, 19]` | 每层分母为 `6041 × 159120` bits |
| 各层 BER | `[1.66e-8, 3.02e-8, 1.04e-9, 1.98e-8]` | 极低但**不是严格零误码** |
| 时间审计 | 116 条、overflow=0、invariant=1 | 每条均满足 frame timestamp 位于对应 DMA block 内 |

本轮证明队列、时延和 timestamp/sequence 一致性均正常；但是严格“60 秒零误码”
尚未达到，不能把上述 BER 当作零误码验收。继续优化应以同一参考帧的 MATLAB
基线为准，而不能仅降低时延。

## 精度与 BER 对照结论

`type1_compare_direct_stages.m` 在同一 PSS 锁定 OTA 帧上得到：

| 对照 | raw bit errors | 平均 EVM |
|---|---:|---:|
| 标准 MATLAB `type1_analyze` | 0 | 1.925% |
| MATLAB 默认 OFDM + C PHY | 0 | 2.111% |
| MATLAB CP-end OFDM + C PHY | 0 | 2.377% |
| native-ring C FFT + C PHY | 0 | 2.377% |

native-ring C grid 相对 MATLAB CP-end grid 的 NMSE 为 `-115.63 dB`，C/MATLAB
CP-end H NMSE 为 `-115.91 dB`，raw bit errors 完全一致。这说明固定 C FFT、
single 精度和 C PHY 并未在正确对齐的单帧上引入可观察误码。

MATLAB 默认 `nrOFDMDemodulate` 窗口与当前 C 的 CP-end 窗口不同；二者 grid/H
NMSE 约 `-46 dB`，最大 EVM 差约 `0.708%`。尝试用“简单 CP 中点”模拟 MATLAB
默认窗口会产生约 `+3.07 dB` grid NMSE 且 bit errors 不一致，因此不可直接替换。

已定位并修复过的实时错误包括：

- 以绝对 timestamp `% 4` 选切换天线：已改为相对 DMA block 起点的四相位；
- 仅每 5 s 校正 PSS timestamp：已改为 0.5 s 窄窗 PSS/CFO/时间健康检查；
- 时间校正跨 DMA block 后的无符号 timestamp 下溢：已加入跨块归一化与审计。

## 结果文件与验收建议

`type1_rx_direct.m` 每轮保存：

```text
captures/type1_direct_YYYYMMDD_HHMMSS/type1_direct_results.mat
```

其中 `summary` 包含 `status`、`eventDelta`、`timingAudit` 和
`timingAuditInvariant`。连续 BER 只有在以下条件同时满足时才有效：

1. `dropNew == 0`；
2. 硬件 overflow/timeout 增量为 0；
3. `timingAuditInvariant == true` 且 `timingAudit.overflow == 0`；
4. pending 不呈持续正斜率；
5. TX 清理日志确认 cyclic TX 已关闭。

严格零误码验收还应要求四层 `status(6:9)` 全为 0；当前最新 60 s 测试不满足
这一额外条件。

## 提交变更记录

后续每次代码修改与提交都必须在本节追加一行，格式为“版本 -- 主要变更”。

- `cmex-2026.07.13.1` -- 新增两阶段启动的软件 ring 丢弃、startup timestamp/sequence 审计与 pending 离线对比；实时星座图改为始终绘制均衡结果并移除 `NO SIGNAL` 覆盖；更新启动队列实测说明。
