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
| DM-RS 残差噪声方差 | `type1_decode_frame_grid_mex.c` 第 3 输出 | 是，按 slot |
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
| `type1_run_offline_baseline.m` | 不依赖板卡的 Phase-0：reference 到 BER 的完整 MATLAB 回归主干。 |

## 离线研究主干（Phase 0）

`type1_run_offline_baseline.m` 从共享 `nr4_type1_reference.mat` 的四层 TX
波形出发，经可配置 4×4 平坦信道、共同 CFO、AWGN、4 倍采样和
`type1_digital_switch` 的四相去交织，最后复用完整的
`type1_analyze`（PSS、PBCH、Type-1 DM-RS、RZF、QPSK/BER）。它不访问
YunSDR、无需 `sudo`，并保存 `captures/type1_offline_baseline_*/` 结果。

默认配置是确定性高 SNR 的相干理想锚点；`userCfoHz`、
`userTimingSamples`、`userPowerDb` 已作为每 layer 的受控注入接口预留，
但默认都为零。该模型是基于四路全数字采样的**可控开关仿真**，不应被表述为
物理单 RF 链 OTA 实现。

可选环境变量 `TYPE1_OFFLINE_OUTPUT_ROOT` 指定离线结果目录。若实时 sudo
测试使默认 `captures/` 对普通用户不可写，脚本会自动回退到 MATLAB 的用户临时目录。

### Phase 1 当前实现与模型边界

`type1_offline_multiuser_config.m` 为四个 TX layer 分别注入 CFO、带限分数
定时偏移、功率和独立 Wiener 相噪（参数单位为 rad/sample，尚未标定为某器件的
dBc/Hz mask）。在固定场景 `[-350,125,620,-900] Hz` 的用户 CFO 下，现有仅估计
共同 CFO 的接收机得到 BER `[0, 0.011, 0.272, 0.261]`；逐项消融表明差分 CFO 是
主要来源，而 CP 内定时偏移、功率失衡和当前相噪强度本身未造成 BER。

`type1_apply_switch_impairments.m` 以相干复泄漏矩阵表示隔离度，并以原始
122.88 MS/s 一阶因果响应表示 10--90% 建立时间。其代数测试确认：理想参数逐样点
等于原数字开关；0 dB 同相泄漏等于四路相干和；10 ns 时的 IIR 系数为 `0.832723`。

必须避免一个不合理结论：**固定且周期性的建立时间或静态隔离度，在四相去交织后
是频率选择性的多相 LTI MIMO 变换，不会天然产生 ICI。** 当前 Type-1 DM-RS 会估计
这一等效 H，RZF 因而可吸收大部分静态失真。32 dB SNR 下，25 dB/5 ns、15 dB/0 ns
和近乎无泄漏/10 ns 的受控测试均为零误码，仅 EVM/条件数改变。只有时变建立时间、
switch/ADC 时钟抖动、未知/失配的泄漏矩阵或不充分导频，才可合理地成为残余 ICI 或
BER 恶化来源；后续曲线必须明确区分“已知且被 DM-RS 校准”的静态损伤与这些残余项。

`type1_run_phase1_sweeps.m` 已实现六条单变量（隔离度、建立时间、差分 CFO、
独立相噪、过渡时钟抖动、功率失衡）和四张二维图（隔离度×建立时间、差分
CFO×隔离度、功率×隔离度、定时×隔离度的条件数）。`smoke` 配置以每点一帧
检查维度、复现性、失败标记和 PNG/MAT 输出；零误码点绘为 `1/Nbits` 上界，绝不
伪造对数坐标零点。首个 smoke 结果位于
`/home/bupt/type1_offline_captures/type1_phase1_smoke_20260714_000017/`：静态项和
100 ps 抖动均仅达 `BER < 1.57e-6`，而满尺度差分 CFO 的汇总 BER 为约 `0.133`。
这不是论文级统计；正式曲线必须使用 `TYPE1_SWEEP_PROFILE=pilot` 并提高
`TYPE1_SWEEP_FRAMES`，每个零误码点报告对应置信上界。

审议修正已开始落实：二维 heatmap 的 `smoke` 网格已提升为至少 `3×3`，`pilot`
网格为至少 `5×5`。新增 `type1_analyze_user_cfo.m`：以相邻 slot DM-RS 的信道
相位估计每 layer 残余 CFO，并把相位演化放进 RZF 的每 layer 信道列；它不是对
混合 RX 样本作不成立的“逐用户去旋”。固定独立用户场景下，Layer 3 BER 已由
约 `0.272` 降至 `9.3e-4`，Layer 4 由约 `0.261` 降至 0；这是后续损伤感知接收机
应比较的基础 CFO 补偿基线。

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
- frame-PHY 第 3 输出曾恒为零：现按实际 DM-RS RE 残差计算噪声方差；
- CFO 曾在每 0.5 ms slot 重置相位：现以 10 ms active frame 为连续相位基准；
  四个虚拟 RX 间 8.138 ns 的固定时偏作为每 RX 常相位保留在 DM-RS 估计的 H 中，
  避免无收益的逐 RE 旋转；
- 开关相位现由 `cfg.switchPhaseOffset` 明确校准（默认 0），`snapshotvirtual`、
  FIFO 与 direct consumer 共用同一 virtual-to-physical RX 映射，不随 PSS 重锁变化。

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
- `cmex-2026.07.13.2` -- 修复 frame-PHY 死噪声输出；CFO 改为帧内连续相位，虚拟 RX 固定时偏由 DM-RS H 吸收；新增固定可校准 switch-phase 映射，完成 OTA grid/H/EVM/bit 等价验证。
- `cmex-2026.07.13.3` -- 新增 `RUN_COMMANDS.md`，集中记录 sudo 板卡运行的可视化 `type1_rx_live` 与无图形 `type1_rx_direct` TX/RX 完整命令及所用空口波形。
- `cmex-2026.07.13.4` -- 新增硬件无关的 Phase-0 离线主干：reference→独立用户损伤接口→4×4 信道/AWGN→四相数字开关→完整 MATLAB PSS/DM-RS/RZF/BER；明确其为全数字受控开关仿真锚点。
- `cmex-2026.07.13.5` -- 增加独立用户 CFO/带限定时/功率/Wiener 相噪与相干泄漏/因果建立时间模型、模型代数验证和通用离线实验入口；记录静态周期性开关损伤可被 DM-RS 估计的边界，禁止将其直接归因为 ICI。
- `cmex-2026.07.14.1` -- 增加过渡时钟抖动与 Phase-1 六条单变量、四张双变量离线扫描器；零误码以统计上界绘图，静态可校准项与残余时变项分开报告，完成 smoke 级 MATLAB/PNG/MAT 验证。
- `cmex-2026.07.14.2` -- 新增 `EXPERT_REVIEW.md`，集中说明远程/离线/OTA 运行命令、输出结构、已验证数据、统计限制、模型边界与核心代码职责，供专家审议；未提交。
- `cmex-2026.07.14.3` -- 按专家审议将 smoke/pilot 二维网格提升至 3×3/5×5；新增基于跨 slot DM-RS 的逐用户残余 CFO 估计与时变 RZF 列相位补偿，建立可分离多用户 BER 基线；未提交。
- `cmex-2026.07.14.4` -- 新增 3GPP TDL-A+Tx/Rx 指数相关离线信道与自由振荡 Wiener 相噪 dBc/Hz 锚定；OTA 25 dB/5 ns 交叉验证暴露现有 startup raw IQ 基线失效，已明确标记为未通过并要求重采有效 IQ；未提交。
- `cmex-2026.07.14.5` -- 新增同一段 raw122 OTA IQ 的 ideal/25 dB+5 ns 成对注入桥接器：两支均经过 `type1_apply_switch_impairments` 和完整接收链，保存/打印 PSS、PBCH、BER、EVM、cond(H) 与配对差值；基线不合格时禁止将 OTA/离线增量称为交叉验证；未提交。

### `cmex-2026.07.13.2` 详细变更与验证

本版本相对 `6fcdf2a` 的修改如下。

1. **修复 frame-PHY 的噪声诊断输出。**
   `type1_decode_frame_grid_mex.c` 原先声明但未累计 `ne/nc`，因而第 3 个
   输出 `noise` 恒为零。现在对每个 slot 的实际 Type-1 DM-RS RE 计算
   `y - H·r` 残差功率并除以参与统计的 RE 数。此变更不改变 RZF、硬判决或
   BER 路径，但使噪声诊断与 `type1_dmrs_type1_mex` 的语义一致。

2. **将 direct consumer 的 CFO 从“每 slot 相位复位”改为帧内连续。**
   `direct_make_grid`、`type1_decode_frame_batch` 以及 grid/H/EVM 对照脚本
   都以 active 10 ms frame 的连续 virtual-sample 序号计算 CFO 旋转，不再在
   每个 0.5 ms slot 用 `%15360` 归零。这样 slot 边界不再人为产生 CFO 相位
   不连续。为保持实时性，C MEX 在 `directstart` 和每次低频
   `directsetcfo` 时预计算 168,960 点 CFO 复旋表；逐帧热路径只查表相乘，
   不在 154×4×1024 个样点内重复调用 `sinf/cosf`。

3. **固定并显式配置 virtual-to-physical RX 映射。**
   新增 `cfg.switchPhaseOffset`（默认 0）和 MEX 命令
   `type1_yunsdr_rx_mex('switchphase',offset)`。virtual 链 `q` 始终读取物理
   RX `(q + offset) mod 4`，且 `snapshotvirtual`、FIFO、native direct grid
   使用同一映射；映射不再随 PSS 锁定点、DMA block 或重新锁定而漂移。旧的
   reference MAT 不含该运行时字段时，`type1_load_package` 自动补入默认值，
   不需要重新生成 TX 波形。

4. **固定时偏的处理选择。**
   四个切换 virtual RX 相差一个 122.88 MS/s 采样周期（8.138 ns）。本版本
   不在热路径增加逐 RE 的补偿旋转：它在窄带 OFDM 中表现为每个 RX 的固定
   公共相位，已由 Type-1 DM-RS 的每 RX 信道估计 `H` 吸收。此选择保持当前
   4×4 RZF 数值等价；若后续采用需要绝对物理天线相位的 M>N/BABF 校准，须以
   `switchPhaseOffset` 为固定基准，并在校准链中显式处理该相位。

5. **更新验证路径。**
   `type1_validate_native_ring_grid.m` 和 `type1_compare_direct_stages.m`
   使用相同的连续 CFO 基准和 switch-phase 配置，避免 MATLAB 对照本身带有
   slot-reset 假差异。已验证 native-grid 相对 MATLAB CP-end grid 的 NMSE
   约 `-115 dB`、H NMSE 约 `-115 dB`、EVM 差约 `9e-6%`，逐帧 raw bit errors
   一致；这确认上述实现修正没有引入可测的 C/MATLAB 栅格或判决偏差。

6. **本版本 60 s OTA 观察（结果目录
   `captures/type1_direct_20260713_194952/`）。**
   TX 持续 70 s，四路 underflow 为 0；RX 硬件 overflow/count/timeout 增量全为
   0，`dropNew=0`，共解码 5,989 帧。5–58 s 的稳态 pending 中位数为 9 ms、
   P95 不高于约 19 ms，C 平均时延为 extract `1.71 ms`、FFT `5.11 ms`、PHY
   `2.00 ms`、总计约 `8.99 ms`。约 58.7 s 前的汇总 BER 约 `6.3e-8`。
   第 59 s MATLAB PSS 健康检查两次超出 ±512 sample 跟踪窗口；该控制面调用
   暂停了 `directpoll`，pending 在结束时升至 206 ms，且失锁帧被继续硬判决，
   使包含异常尾段的全程 BER 变为约 `7.1e-3`。因此该测试证明 C 数据面未发生
   持续时延退化，但也暴露出 PSS 控制面失锁会阻塞消费者；全程 BER 不能作为
   稳态 BER 指标，必须将该事件单独诊断。
