# 专家审议说明：4T4R Type-A 与单链开关仿真研究主干

更新时间：2026-07-16（Asia/Shanghai）
工程：`/root/lap/SwitchingAntenna/c_demo`，分支：`cmex`

## 1. 结论先行与审议边界

本工程已有两条互补路径：

1. **OTA 实时路径**：YunSDR 4 TX/4 RX 板卡、真实 NR Type-A 帧、C/MEX 持久
   consumer。它验证实时性、队列、时延和空口 BER。
2. **纯 MATLAB 离线路径**：以同一 reference 波形为输入，在四路全数字 RX
   采样上受控模拟开关、独立用户与非理想性，再复用完整 PSS/DM-RS/RZF/BER
   接收机。它用于可重复的模型、算法和参数扫描。

严格的非主张是：当前 OTA 平台有四路全速采集链，因此它是**全数字开关仿真和
理想 OTA 锚点**，不是已经完成的物理单 RF 链原型。论文中不能将现有 OTA BER
直接作为真实 RF 开关器件 BER。

## 2. 信号、帧结构与数据流

TX 循环发送共享 `nr4_type1_reference.mat` 中的一帧 10 ms 波形：

| 帧部分 | 内容 |
|---|---|
| slot 0 | 仅 TX1 的 PSS/SSS/PBCH/DM-RS，用于同步与 MIB 验证 |
| slot 1--10 | 四个空间 layer 的 QPSK 数据；Type-1、单符号、l=2 DM-RS；端口 1000--1003 |
| slot 11--19 | 当前 half 模式下静默 |
| 采样率 | TX/virtual RX 30.72 MS/s；物理 RX 122.88 MS/s |

```text
共享 reference 四层波形
  -> [离线：独立用户 CFO/定时/功率/相噪 + 4×4 信道 + AWGN]
  -> 四路全数字物理 RX（或 YunSDR 四路 RX）
  -> 四相选择/单条 stitched 122.88-MS/s 流
  -> 去交织为四个 30.72-MS/s virtual RX
  -> PSS/CFO、OFDM、Type-1 DM-RS、4×4 RZF、QPSK 硬判决、BER/EVM
```

## 3. 运行方式

远端 MATLAB 工程均为 `/home/bupt/tools/matlab_test/nr4x4_type1`，MATLAB 为
`/home/bupt/tools/matlab/bin/matlab`。TX 主机是 `bupt@10.156.64.30`；RX 主机
`bupt@10.156.64.41` 通过 TX 跳板连接：

```bash
# TX
ssh -tt bupt@10.156.64.30

# RX
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
```

### 3.1 纯离线验证（不访问板卡、不需要 sudo）

先在本地工程目录将新增离线脚本同步至 RX 服务器：

```bash
cd /root/lap/SwitchingAntenna/c_demo
scp -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' \
  type1_offline_*.m type1_run_offline_*.m type1_apply_switch_impairments.m \
  type1_validate_switch_impairments.m type1_run_phase1_sweeps.m \
  bupt@10.156.64.41:/home/bupt/tools/matlab_test/nr4x4_type1/
```

然后在 RX 上执行：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1

# 代数回归：理想开关、0 dB 泄漏和有限建立时间 IIR
/home/bupt/tools/matlab/bin/matlab -batch "type1_validate_switch_impairments"

# Phase 0：reference -> 4x4 channel/AWGN -> switch -> full receiver -> BER
TYPE1_OFFLINE_FRAMES=3 \
TYPE1_OFFLINE_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_offline_baseline"

# Phase 1：固定独立用户 CFO/定时/功率/相噪压力场景
TYPE1_OFFLINE_FRAMES=3 \
TYPE1_OFFLINE_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_offline_multiuser"

# 六条单变量 + 四张二维图；smoke 仅检查流程，pilot 才加密网格
TYPE1_SWEEP_PROFILE=smoke TYPE1_SWEEP_FRAMES=1 \
TYPE1_OFFLINE_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase1_sweeps"
```

`TYPE1_SWEEP_PROFILE=pilot` 使用更密网格。正式论文统计应显式提高
`TYPE1_SWEEP_FRAMES`；所有零误码点只能报告有限样本上界，不能报告为“BER=0”。

### 3.2 OTA 无图形实时测试

TX 与 RX 各使用一个终端，TX 先启动。板卡节点需要 `sudo`，仅此类操作使用
root 权限。

```bash
# TX server
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_TX_DURATION_SEC=75 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_tx"

# RX server
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_DIRECT_DURATION_SEC=60 TYPE1_FIFO_RING_BLOCKS=2048 \
  TYPE1_DIRECT_STARTUP_MODE=two_stage \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_rx_direct"
```

异常停止 TX：

```bash
sudo /home/bupt/tools/matlab/bin/matlab -batch "type1_tx_stop"
```

## 4. 输出文件与指标解释

| 路径 | 主要内容 |
|---|---|
| `captures/type1_direct_*/type1_direct_results.mat` | OTA 的 `summary`：BER、分段时延、pending trace、dropNew、硬件事件、timestamp/sequence 审计。 |
| `type1_offline_baseline_*/type1_offline_baseline_results.mat` | `report`：Phase 0 每 layer BER/EVM、CFO、PSS、PBCH 和条件数。 |
| `type1_offline_multiuser_*/type1_offline_multiuser_results.mat` | 独立用户固定压力场景的同类指标及注入参数。 |
| `type1_phase1_*/phase1_sweeps.mat` | 六条曲线和四张热图的原始数值、点失败标记、每点帧数。 |
| `type1_phase1_*/phase1_single_variable.png` / `phase1_heatmaps.png` | 对应扫描图；仅为 MAT 原始数据的可视化。 |

OTA `pending` 的单位是 1 ms 原始 DMA block。例如 `pending=10，peak=517` 表示
结束时积压约 10 ms、历史最高约 517 ms；它**不是**单帧解码时延。真正的每帧
处理时延由 `extractMs + fftMs + phyMs = totalMs` 给出。`dropNew>0` 时 FIFO 已
丢弃新数据，该轮 BER 不具备连续链路意义。

## 5. 已验证数据与严谨解释

### OTA / C-MEX 数值一致性

- native-ring C grid 与 MATLAB CP-end grid：grid NMSE 约 `-115 dB`，H NMSE
  约 `-115 dB`，单帧 raw bit errors 一致。
- 近期短时 OTA 典型总时延约 `9 ms/frame`，`dropNew=0`；这证明 C 数据面可接近
  100 frame/s，但不等价于“同步控制面永不失锁”。
- 一次 60 s 测试在约 59 s 出现 PSS 跟踪失败；`pending` 由约 20 ms 升至 206 ms，
  全程 BER 因末尾失锁帧变为约 `7.1e-3`。因此该轮的全程 BER 不可作为稳态 BER，
  只能使用失锁前约 58.7 s 的稳态数据（汇总约 `6.3e-8`）并单独报告失锁事件。

### Phase 0 离线锚点

在 32 dB SNR、确定性满秩 4×4 信道、850 Hz 共同 CFO、理想四相开关下，3 帧
完整 PSS/PBCH/DM-RS/RZF 链路四层 BER 均为 0，平均 EVM 为
`[2.718, 2.775, 2.714, 2.738]%`。共同 CFO 的估计约为 `861--864 Hz`；四相
重采样/去交织有限窗导致约 14 Hz 偏差，回归阈值设为 25 Hz，不能误解为 CFO
模型错误。

### 独立用户与开关非理想性

- 固定多用户场景使用 user CFO `[-350, 125, 620, -900] Hz`、CP 内分数定时、
  `[-3,0,3,-1.5] dB` 功率及独立 Wiener 相噪。现有“仅共同 CFO”接收机得到
  四层 BER `[0, 0.0136500754148, 0.273066448802, 0.258689458689]`
  （3 帧、seed `20260713`）；逐项消融显示差分 CFO 是该设置的主导因素。这是
  未加入逐用户 CFO 补偿前的基线，不是最终算法结果。
- 静态 25 dB 隔离度 + 5 ns 建立时间、15 dB 静态隔离度、以及 10 ns 固定建立
  时间，在 32 dB SNR 的单帧受控测试中均未产生误码，仅改变 EVM/估计条件数
  `cond(Hhat)`。
- 这一现象是合理的：固定、周期性的泄漏/建立过程在去交织后是频率选择性的
  多相 LTI MIMO 变换，Type-1 DM-RS 可估计等效 H，RZF 可吸收大部分静态影响。
  因此不能声称“固定建立时间天然产生 ICI”。剩余 BER/ICI 研究应针对时变建立
  时间、过渡时钟抖动、未知泄漏矩阵、估计失配或导频不足。

### 统计限制

当前 Phase-1 图是 smoke 回归：每点 1 帧、全四层总 bit 数为
`4 × 10 × 15912 = 636480`，无错点仅表示经验 BER 小于约 `1.57e-6`，并不证明
BER 为零。论文级点需要预先指定置信度、最少错误数或最大仿真 bit 数；若仍零错，
应报告 binomial 上置信界（而非零）。

## 6. 核心代码概述

| 文件 | 作用与审议重点 |
|---|---|
| `type1_build_package.m` | 生成共享 NR reference、DM-RS/data/QPSK/bit 真值和 10 ms 四层波形。 |
| `type1_analyze.m` | MATLAB 完整基线接收机：PSS、共同 CFO、PBCH、DM-RS、RZF、BER/EVM。 |
| `type1_yunsdr_rx_mex.c` | OTA 原始 ring、四相抽取、持续 C FFT、时间戳审计和 direct consumer。 |
| `type1_decode_frame_grid_mex.c` | C Type-1 DM-RS、4×4 RZF、硬判决、BER、DM-RS 残差噪声。 |
| `type1_offline_link.m` | 离线波形级链路；带限分数延迟避免线性插值造成的高频幅度伪损伤。 |
| `type1_apply_switch_impairments.m` | 相干泄漏矩阵、建立时间一阶响应、可重复过渡抖动；静态与时变项明确分离。 |
| `type1_validate_switch_impairments.m` | 三个代数不变量测试，防止损伤模型本身出错。 |
| `type1_run_phase1_sweeps.m` | 6×1D + 4×2D 扫描器；保存原始 MAT、PNG 和失败点。 |

## 7. 建议专家重点审议的问题

1. 独立用户相噪目前采用 Wiener 增量（rad/sample），尚未映射到实测 PLL 的
   dBc/Hz mask；是否应先确定目标器件/掩码再做论文级相噪曲线？
2. 静态泄漏和建立时间被 DM-RS 校准后，论文是否应将创新重点转向“时变/失配
   残余协方差下的白化 RZF”，而不是声称静态器件参数本身必然造成 BER cliff？
3. 正式扫描应采用多少 bit/点、哪种置信区间和哪种停止规则，才能支撑器件规格
   包络结论？
4. 端口选择矩阵应如何加入真实的码序列、占空比与因果性约束，避免将物理开关
   夸张成任意二值矩阵？

## 8. 当前版本状态

Phase-1 离线损伤基础设施已提交为 `9ea0f7c`。后稳定 OTA 采集器、有效 OTA 配对
结果及本节勘误目前为**未提交工作区修改**，便于专家审议后再由项目方决定是否提交。

## 9. 审议修正进展（2026-07-14）

已完成的修正：

- 二维图网格：`smoke` 已为至少 3×3，`pilot` 已为至少 5×5。
- 逐用户 CFO：新增跨 slot DM-RS 残余 CFO 估计和时变 RZF 列相位补偿。在固定的
  3 帧、seed `20260713` 压力场景中，未补偿 BER 为
  `[0,0.0136501,0.2730664,0.2586895]`；补偿后为
  `[0,5.86559e-5,9.48969e-4,0]`。
- 信道多样性：新增不依赖额外 Toolbox 的 3GPP TDL-A PDP、100 ns delay spread、
  Tx/Rx Kronecker 指数相关模型。验证路径 PBCH/MIB 正常，TDL-A 样例估计条件数
  `cond(Hhat)` P95
  为 40.326，四层 BER 为 `[6.28e-6,5.72e-4,3.39e-4,2.70e-4]`。
- 相噪锚定：当前 Wiener 增量 `sigma` 对自由振荡器小偏移近似满足
  `L(f)=sigma^2*Fs/(4*pi^2*f^2)`。因此 `sigma=1.5e-4 rad/sample`、
  `Fs=30.72 MS/s` 对应 `L(10 kHz)=-97.57 dBc/Hz`。该映射只适用于自由振荡器；
  已锁定 PLL 的有界相噪仍应在 Phase 2 前/中改用单极或双极 PLL PSD。

历史 startup raw122 不可作为 OTA 锚点：其中两段在理想开关下的平均 EVM 已约
807%，且 PSS/PBCH 不成立。它们保留为“启动期反例”，不得用于模型结论。该问题
已通过后稳定期采集路径修正，具体有效验证见下节；但单点结果不替代后续多 SNR、
多信道实现的统计校准。

为消除 OTA 路径与离线注入路径之间的“桥断”问题，现增加
`type1_analyze_raw122_switch_pair.m`：它只读取一次 raw122，分别以 ideal 和
25 dB/5 ns 模型调用 `type1_apply_switch_impairments`，之后均进入同一
`type1_analyze` 接收链。报告强制保留两支的 PSS NID2、PBCH CRC/MIB、BER、EVM
和估计条件数 `cond(Hhat)`，打印 impaired−ideal 配对差值，并保存 MAT 审计文件。仅当 ideal 支
PSS/PBCH 有效且平均 EVM 不高于预设 20% 质量门限时，外层
`type1_validate_ota_switch_model` 才允许把 OTA 与离线的增量并列为交叉验证；否则
仅报告诊断结果，不宣称模型得到 OTA 证实。

## 10. OTA 后稳定期配对注入验证（2026-07-14）

本节完成专家审议所要求的“同一段 OTA 原始 IQ、ideal/非理想两支配对”的最小
有效验证。为避免将 RX 冷启动数据误当作空口数据，新增
`type1_capture_ota_valid_raw122.m`：它在既有 TX 运行且 RX 采样稳定 5 s 后，循环
读取 20 ms 的四路 122.88 MS/s raw122；每个候选先经 ideal 数字开关和完整
`type1_analyze`。只有 `bestNID2==expectedNID2`、PBCH CRC/MIB 均成功且平均 ideal
EVM 不高于 20% 时，才写入磁盘。该准入标准与配对桥接器的质量 gate 一致。

有效样本为 RX 端
`data/type1_valid_ota_iq_20260714_004458_seq2230_raw122_csingle_iq4.bin`，长度 20 ms。
采集时 TX 的四路 underflow 均为 0。准入分析得到 PSS `0/0`、PBCH/MIB 成功、
ideal EVM `2.178%`、raw BER `0`。随后对**该同一个文件**完成以下两支：

| 指标 | ideal（Inf dB、0 ns） | 25 dB、5 ns | impaired − ideal |
|---|---:|---:|---:|
| PSS / PBCH | `0/0`，成功 | `0/0`，成功 | — |
| raw BER / bit errors | `0 / 0` | `0 / 0` | `0 / 0` |
| 平均 EVM | `2.1778%` | `2.2569%` | `+0.0791` percentage point |
| `cond(Hhat)` P95 | `4.4739` | `5.6021` | `+1.1282`（`+25.2%`） |

同种 25 dB/5 ns 注入在当前离线锚点给出 EVM `2.8011%→3.2084%`
（`+0.4074` percentage point）和 `cond(Hhat)` P95 `1.4879→1.9119`
（`+0.4241`，`+28.5%`）。两条链路的 BER 均不变，EVM 与条件数的变化方向一致，
且条件数的相对变化相差约 3.3 percentage points；这证明同参数的损伤注入已可在
真实 OTA 原始 IQ 上稳定执行，且不会破坏同步/解码。

严谨边界：这是**单点的功能和趋势交叉验证通过**，不是“离线模型已按绝对 EVM
幅度校准”的结论。OTA EVM 增量为 `0.0791` percentage point，而当前固定离线
信道为 `0.4074` percentage point；差异应归因于两者的 SNR、真实空间信道和噪声
协方差并未拟合一致，不能被掩盖。论文级量化一致性仍应在多个 SNR/TDL 实现上比较
归一化增量及置信区间。配对报告和外层交叉验证 MAT 已保存于 RX 端 data 目录。

## 11. 审议勘误与接收机量纲边界（2026-07-14）

1. **Wiener 相噪锚定已修正 3 dB。** 对每采样相位增量方差 `sigma^2`，离散
   Wiener 在小偏移的双边相位 PSD 为 `sigma^2*Fs/(4*pi^2*f^2)`；IEEE SSB
   `L(f)` 等于该双边值（等价于单边 PSD 的一半），此前的 `8*pi^2` 分母错误地
   少算 3.01 dB。`type1_phase_noise_anchor(1.5e-4,1e4,30.72e6)` 现在应给出
   `-97.57 dBc/Hz`。这不改变直接以 `sigma` 注入的既有仿真，但会修正今后由
   器件 mask 反推 `sigma` 的数值；例如目标 `-100.58 dBc/Hz` 对应约
   `1.06e-4 rad/sample`，而非 `1.5e-4`。

2. **跨 slot 残余 CFO 的范围已经显式限制。** 相邻 slot DM-RS 相距 0.5 ms，
   主值相位差的无模糊范围是 `±1 kHz`。`type1_analyze_user_cfo` 在
   `|fhat|>=750 Hz` 发出 `type1:UserCFOAmbiguity` 告警，并把范围/门限随结果
   保存；`type1_run_offline_multiuser` 拒绝已知差分 CFO 超过 `±800 Hz` 的场景。
   这不是对精确整数倍混叠的“检测器”——后者在已包裹相位中信息论不可辨，必须
   用相位展开、不同导频间隔或更宽范围的估计器；因此不得用此基线声称支持 ±2 kHz。

3. **所有 Phase-1 条件数均重命名为 `cond(Hhat)`。** `type1_analyze` 的 DM-RS
   插值后信道估计是 `Hhat`；`conditionStats` 保留为兼容别名，新增
   `estimatedConditionStats` 作为明确接口。定时偏移在每个子载波上主要是各用户
   列的酉相位，物理复合 `cond(H)` 不必改变；热图中随定时出现的变化因此只能解释
   为导频/插值下的**估计条件数**，而不是未经 oracle 验证的物理信道恶化。

4. **多用户引用已经逐位可复现。** 上文使用的所有 BER 数字均由
   `TYPE1_OFFLINE_FRAMES=3`、seed `20260713`、SNR 32 dB、共同 CFO 850 Hz 与
   `[-350,125,620,-900] Hz` 用户 CFO 得到；重跑的未补偿/补偿 BER 分别为
   `[0,0.0136500754148,0.273066448802,0.258689458689]` 和
   `[0,5.86559410089e-5,9.48969331322e-4,0]`。

## 12. Phase 2 A1/A2：时变开关损伤的模型纪律（进行中）

`type1_apply_switch_impairments` 新增两类分离的时变项。A1 使用
`tau[n]=tau0*(1+a_slow*sin(2*pi*f_slow*t)+a_fast*w[n])`，并将每样点
`beta[n]=1-exp(-dt[n]/tau[n])` 写入同一个因果 IIR。`a_slow` 是秒级温漂的
帧间/慢时变控制项；它不应被预设为 ICI 来源。`a_fast` 才是 DM-RS 到数据 RE
之间不能由静态 H 吸收的候选残余。A2 的 `samplingBoundaryJitterStdPs` 在切换前
对四路 raw122 做公共的亚样点边界位移，采用 9-tap 窗函数 sinc；其零抖动路径与
原数字开关逐样点恒等，因此 `rise=0` 时抖动不再是空操作。高斯尾部超过 0.49
raw-sample 时会截断并计数，避免模型悄然变成未建模的整数采样滑移。

`type1_validate_switch_impairments` 已新增不变量：零损伤严格等于
`type1_digital_switch`；边界抖动在 rise=0 时可复现且非零；`tau(t)` 产生有限的
非恒定 beta。正式 smoke 结果由 `type1_run_phase2_timevarying_switch` 生成：20 dB、
1 帧、20 ns 基础建立时间、基础 seed `20260713`，各点的实际 seed 保存在 MAT。
静态控制（seed `20260714`）四层 BER 为零；快抖标准差 0.6（seed `20260816`）时
四层 BER 为 `[1.72197084e-3,9.42684766e-4,8.54700855e-4,9.17546506e-4]`，1.0
（seed `20260817`）时为 `[9.83534439e-3,7.64831574e-3,7.56661639e-3,7.60432378e-3]`。
这仅证明已找到进入 BER 敏感区的模型点；不是论文级曲线。1 ns 边界抖动单独
（seed `20260917`）仍 BER=0，EVM 仅从其独立 0 ps 对照的 `8.127286%` 增至
`8.577664%`，并有 109 个截断尾样点；因此当前证据不支持把边界抖动称为主导 BER
来源。正式入口
`type1_run_phase2_timevarying_switch` 会分开扫描静态/慢漂/快抖/边界抖动；随后才以
其残余结构决定是否存在可恢复的实现级 ICI；不预设协方差白化必然有效。

## 13. Phase 2 B1/B2：DM-RS 残差白化 RZF 的首个负基线

已实现 `type1_analyze_whitened_rzf`。它用每个 slot 的 DM-RS 向量残差
`e=y-Hhat*x_DMRS` 构造 `Rhat_ee=E^H*E/N`，加 5% 显式对角加载后执行
`(H^H*Rhat_ee^-1*H+lambda*I)^-1*H^H*Rhat_ee^-1*y`；这与先乘
`Rhat_ee^-1/2` 再做标准 RZF 代数等价。`type1_validate_whitened_rzf` 已验证理想
链路的标准/白化 BER 均为零且每 slot `Rhat_ee` 正定。

在第 12 节的正式快抖 0.6 点（seed `20260816`）上，标准 RZF BER 为
`[1.72197084e-3,9.42684766e-4,8.54700855e-4,9.17546506e-4]`；当前 DM-RS
残差白化版本为 `[1.72825540e-3,9.36400201e-4,8.73554550e-4,9.17546506e-4]`。
这不是可宣称的恢复增益。残差协方差并非简单白噪声（10 个 slot 的非对角 Frobenius
占比约 `0.45--0.51`，特征值展宽约 `3.65--4.20`），但时变开关的主要残余还含有
跨 OFDM 符号/子载波的 ICI；仅以同 RE 的 4×4 空间协方差白化不足以消除它。对于
集平均相关，带状频域 MMSE 的预期增益仅约 0.002 dB，已降级为可选负对照；本项目
不将该首版称为 Phase-2 算法增益。

## 14. Phase 2 路线勘误：快抖相关时间、genie 上界与协方差估计边界

专家的真值辅助 data-RE 频域残差诊断改变了原 B2 路线。对 i.i.d. 快抖 0.6，
新增 ICI 的 lag-1/lag-5 归一化相关仅约 `0.9%`，接近噪声底；因此把当前模型直接
扩展成时频 `R_ee` 后再白化没有可利用的带状结构，原先“下一步构建时频协方差”的
表述已撤回。物理上这也正确：122.88 MS/s 的逐样点白噪声驱动会均匀扩散 ICI，而
真实开关驱动/电源噪声通常受带宽限制。

模型现在以 `settlingFastJitterCorrelationSec` 指定平稳 AR(1)/OU 快抖相关时间，
`tau_c=0` 保持原 i.i.d. 路径；`tau_c>0` 用
`a=exp(-Ts/tau_c)` 和 `sqrt(1-a^2)` 的创新项保持同一稳态快抖标准差。`meta` 已
记录 fast-fraction lag-1、`tauFloorHitCount/Fraction`，并可在 `recordTimeSeries=true`
时记录 beta 序列。此前注释称会记录 tau 下限却未实现的问题已修复：在 fast 0.6 的
本轮点下下限触发约 `4.92%`；fast 1.0 的约 `16.1%` 必须在后续扫描中单独标识，
因为 beta 趋于 1 的截断点不是对称高斯扰动。

`type1_run_phase2_tau_correlation` 以相同 20 ns、fast 0.6、20 dB、seed `20260816`
扫描 `tau_c={0,8 ns,100 ns,1 us}`，保存每点 seed、BER、beta lag-1、data-RE 真值
残差频域 lag 和 genie BER。当前远端结果为：

| tau_c | beta lag-1 | data-RE lag-1 / lag-5 | 标准 RZF BER（四层约） | beta-genie BER |
|---:|---:|---:|---:|---:|
| 0 | -0.0013 | 0.00407 / 0.00141 | 0.00085--0.00172 | 0 |
| 8 ns | 0.3600 | 0.00493 / 0.00184 | 0.00116--0.00205 | 0 |
| 100 ns | 0.9214 | 0.00243 / 0.00988 | 0.00510--0.00705 | 0 |
| 1 us | 0.9918 | 0.01396 / 0.01093 | 0.00820--0.01121 | 0 |

其中频域诊断与 genie 都是**真值/已知 beta 辅助的离线研究工具，不是可部署接收机**。
但 zero-BER genie 仅说明 beta 已知时该 IIR 可代数求逆，并非实际估计器的统计界。
10-slot 诊断噪声底约 0.0018、静态基线约 0.004；100 ns 的 lag-1=0.00243 低于
基线且 lag-1<lag-5，不能视为带状结构。仅 1 us 的 lag-1=0.01396（约基线 3.4 倍）
成立，但幅度仍弱；它的机会在逐符号实现级 ICI 核，而非跨符号平均协方差白化。

DM-RS 残差空间白化的负结果也已有解释。专家诊断显示同批 DM-RS 拟合残差功率约
`0.521`，而 data-RE 真值残差约 `1.615`，存在约 3.1 倍（5 dB）的 in-sample 低估；
它不能再作为后续 `R_ee` 的无偏估计。并且主要干扰沿信号相同的 H 列进入，单 RE
空间线性变换原则上不能分离这种信号子空间自干扰，故 B1 的无增益是可预期结果，
不是未解释的异常。后续协方差必须采用交叉验证 DM-RS 残差或数据辅助/判决反馈残差，
并只在有测得相关结构的 `tau_c` 区间评估。

## 15. R3 主线：逐符号 ICI 核的交叉拟合判决反馈（首个正结果）

按 R3，`type1_analyze_ici_decision_feedback` 先运行标准 RZF 并硬判决，构造每个
data RE 的 `v=Hhat*xhat` 与 `e=y-v`。在每个数据 OFDM symbol 内，以
`e[k]≈sum_{|u|<=6}m[u]v[k-u]` 拟合共享于 4 个 virtual RX 的 13-tap 标量核；这是一
个可检验的“共同物理开关核”约束，而非任意 4×4 ICI 矩阵。为避免同 RE 拟合噪声后又
在原 RE 报告收益，偶/奇子载波各用对方 parity 的 LS 核纠正：每个 13 系数核由
`4×300=1200` 个复方程估计，故实现实际使用两个交叉拟合核/符号（而非把同一 13 个
系数 in-sample 套回全部 RE）。边缘 `±6` bin 不参与消除。

在 R3 的 `tau_c=1 us`、20 ns、fast 0.6、20 dB、seed `20260816` 单帧受控点，三方
比较为：标准 RZF BER `[0.0112053795877,0.0099987430870,0.0082013574661,0.0091440422323]`；
交叉拟合 ICI-DF 为
`[0.0068124685772,0.0064479638009,0.0049648064354,0.0056875314228]`；已知 beta 的
genie 为 `[0,0,0,0]`。四层均获约 35--40% 的 BER 降低，但离 genie 天花板仍远，
且仅有一帧，不能报告为论文级统计。`type1_validate_ici_decision_feedback` 已确认
理想链路 BER=0，排除算法在无损伤时自身制造误码；运行器保存标准/DF/genie 的 MAT
及完整 seed/config。2026-07-14 在 RX 主机以受限 `sudo` MATLAB 离线复跑该命令，
控制台数值与上述逐位一致，且已核验输出
`/tmp/type1_phase2/type1_phase2_ici_df_20260714_174339/phase2_ici_decision_feedback.mat`
存在（18 MB、root 所有）；本次没有启动板卡或 TX。

结论边界：这是“时变开关损伤可被结构化接收机部分恢复”的第一个正向**基线**，尚未
证明通用最优性。下步应在固定 tau_c=1 us 对 Q、迭代次数、SNR 和至少 100 错误或
1e7 bits 的停止规则扫描；100 ns 与带状 MMSE 仅保留为预期无显著增益的对照。

## 16. R4 论文级成对 Q/迭代/SNR 扫描（2026-07-14）

R4 审议被采纳为可检验实验，而非只保留单帧示例。`type1_analyze_ici_decision_feedback`
新增 `iterations` 参数；第 2/3 次均以**原始** data-RE `y` 重新构造
`y-M(Hhat*xhat)`，不对已消除的 `y` 二次相减。理想链路的 3 次迭代仍为 BER=0，且
每次、每个有效 symbol 的偶/奇交叉拟合训练行数均非零。新运行器
`type1_run_phase2_ici_df_statistics` 以相同 seed 生成每个标准 RZF/DF 成对窗口，记录
每层/聚合错误、bits、停止原因、`C(Q)`、相对 BER 降低与
`eta=(1-BER_DF/BER_std)/C(Q)`；接收或 PSS 失败不会静默丢失，而会记录为
`acquisitionFailure`。

本轮 RX 主机离线 paper 档结果目录为
`/tmp/type1_phase2/type1_phase2_ici_df_statistics_20260714_190530/`。它不访问板卡或
TX；20 dB、20 ns、fast 0.6、`tau_c=1 us`、基准 seed `20260816`。paper 档预先设定
“每个接收机至少 10,000 个聚合错误或 1e7 聚合 bits”，比 Phase-2 的最小
100-error/1e7-bit 规则严格；Q/迭代及 12 dB 以上 SNR 点实际为 2--4 个独立 seed 的
10 ms 窗口、`1.27e6--2.55e6` 聚合 bits，低 SNR 点因单帧已远超 10,000 错而只需一帧；
所有可解码点由错误数而非 bits 上限停止。

运行审计：自动执行工具曾在 paper MATLAB 仍运行时提前返回，随后误启动一个仅用于
诊断输出的重复进程。发现后以 root 只向后启动副本发送 `TERM`，保留先启动的正式扫描；
本节仅采用其完成后的 `...190530` MAT/PNG，未启动硬件、TX 或删除任何工程数据。

对 R4 的 OU/Lorentzian 预测，使用
`C(Q)=2/pi*atan((Q+1/2)/(T_sym*f_c))`，其中
`T_sym=10 ms/280`、`f_c=1/(2*pi*tau_c)`；故 `C(0/6/12/24)` 分别为
`0.0559/0.5426/0.7283/0.8549`。成对 Q 扫描如下（BER 为四层聚合）：

| Q | 标准 RZF BER | ICI-DF BER | 降低 | eta | bits / 标准-DF 错误 |
|---:|---:|---:|---:|---:|---:|
| 0 | 1.0506e-2 | 1.0618e-2 | -1.06% | -0.190 | 1.273e6 / 13374-13516 |
| 6 | 1.0854e-2 | 6.8444e-3 | 36.94% | 0.681 | 1.909e6 / 20725-13069 |
| 12 | 1.0854e-2 | 5.6535e-3 | 47.91% | 0.658 | 1.909e6 / 20725-10795 |
| 24 | 1.0590e-2 | 4.9621e-3 | 53.15% | 0.622 | 2.546e6 / 26962-12633 |

这复现了捕获律的单调、递减收益：Q=0 的核估计噪声略有反噬，Q=6--24 有稳定正收益；
Q=24 的 eta 回落说明仅扩大核宽度还会受判决污染、Hhat 误差和 IIR 一阶近似限制，不能
把 `C(Q)` 本身误读为可达到 genie 的恢复比例。

固定 Q=12 的迭代扫描给出：1/2/3 次的 DF BER 分别为
`5.6535e-3/5.0713e-3/4.4565e-3`，对应相对降低
`47.91%/52.11%/57.92%` 与 `eta=0.658/0.716/0.795`。这支持 R4 的“提高 eta 而非
无限加 Q”判断；但仅验证到 3 次，尚不能外推更多迭代的收敛性或复杂度收益。

SNR 扫描固定 Q=12、2 次迭代。`-8,-4,0,4,8,12,16,20,24 dB` 的标准/DF BER 为
`31.92/31.75, 20.97/20.60, 10.88/10.15, 4.960/4.104, 2.627/1.828,
1.586/0.924, 1.239/0.624, 1.059/0.507, 1.003/0.471 %`；相应 eta 从
`0.007,0.024,0.091,0.237,0.417,0.573,0.681,0.716,0.729` 单调恢复。对同一 seed，
`-10` 与 `-12 dB` 的 PSS 没有留下完整帧，记录为 `type1:IncompleteFrame`，DF 未运行。
因此在此模型/seed 下，DF 在**可同步**的最低 `-8 dB` 点没有观察到负收益，但几乎无效；
端到端先遇到的门限是约 `(-10,-8] dB` 的 PSS 获取边界，而非已证明的 DF 错误传播反噬
门限。该括号不能泛化为 OTA 或所有随机 seed 的 SNR 阈值。

结论：R4 要求的 Q、迭代、SNR 三类成对曲线已完成，且数据支持“时变开关 ICI 可被
结构化 DF 部分恢复”的主张。后续 R5 应扩展 PSS 成功率到多 seed 的 SNR 曲线，并在
每个可同步 SNR 下检查更多独立 seed；只有实际出现 DF BER 高于标准 RZF 时，才能报告
判决反馈的反噬门限。

## 17. R5 修正：软/硬反馈消融与器件规格包络（2026-07-14）

R5 的 F-R5-1 经代码核查属实，已修正术语和接口：首轮一律使用硬 QPSK 判决；第 2/3
轮的 `feedbackMode='soft'`（默认）使用上一轮 RZF 软输出，`'hard'` 则重新硬判决并
QPSK 重调制。两种模式均通过三轮理想链路 BER=0 回归。固定 Q=12、3 次迭代、20 dB、
20 ns、fast=0.6、tau_c=1 us，在同一四个 seed、2.546e6 聚合 bits 下，标准/hard/soft
BER 为 `1.0590e-2/4.871e-3/4.457e-3`（错误数 `26962/12402/11346`）。soft 比 hard
再降低约 8.5%，故后续结果明确称为 **soft-DF**，不再笼统称“硬判决 DF”。

R5 优先级 1 的规格包络已完成，远端输出为
`/tmp/type1_phase2/type1_phase2_device_envelope_20260714_193307/`。固定 20 dB、20 ns、
Q=12、3 次 soft-DF，扫描 `fastFraction={0,0.2,0.4,0.6,0.8}` 与
`tau_c={0,8 ns,100 ns,1 us}`；标准/soft-DF/genie 始终使用同一 seed 波形。标准和
soft-DF 均达到 10,000 错才停止，或到 1e7 bits；genie 不参与停止判据，因为其可合法
保持零错。误码按共享时变核成簇，故这里不把 iid binomial 置信区间当作严格方差估计。

规格结论只按离散网格给出**括号**，不虚构连续阈值。R6 指出此前把通过格点比
`0.6/0.4=1.5` 错称为保证下界；该区间算术不成立，已撤回。独立的加密扫描
`fast={0.5,0.7,0.75}`（同 seed 协议，结果目录
`/tmp/type1_phase2/type1_phase2_device_envelope_20260714_194749/`）给出标准/soft-DF BER
`5.601e-3/1.782e-3`、`1.608e-2/7.469e-3`、`1.934e-2/9.330e-3`。故在 tau_c=1 us、
BER<=1e-2 下，标准容限为 `[0.5,0.6)`，soft-DF 为 `[0.75,0.8)`；保证倍率严格为
`rho > 0.75/0.6 = 1.25x`，对数 BER 插值的点估计约 `0.77/0.59=1.3x`，而非 1.5x。

该放宽是 tau_c 依赖的：tau_c=100 ns 时标准与 soft-DF 同为 `[0.6,0.8)`，没有离散
放宽；tau_c=0/8 ns 时至 fast=0.8 均低于 1e-2，故无可识别的规格倍率。后两类的
fast=0.8 又有约 10.8% tau-floor 截断，不能外推为无截断高斯器件规格。对 fast<=0.2
的 1.018368e7 bits 零错格点，报告的是 95% BER 上界 `-log(0.05)/N=2.94e-7`，不是
“BER=0”。genie 的全网格零错同样仅表示已知 beta 的代数上界，其相应零错上界随实际
bits 保存于 `zeroErrorUpper95`。

F-R5-2 同样成立：上述曲线是确定性 flat-channel 回归锚点上的噪声/抖动平均，不能称为
TDL-A 信道平均。下一优先级是将 soft-DF 接入已有逐用户 CFO 补偿路径，并在 TDL-A、
25 dB 泄漏、相噪、建立和抖动共同存在时做成对集成测试；P_acq(SNR) 则按 R5 所定义的
真值 timing 容差与假峰率另行实现，不能由 `IncompleteFrame` 次数替代。

## 18. R7 全损伤栈预注册（实验运行前冻结）

组合接收机不得串联两个 analyzer。逐用户 CFO 由相邻 slot DM-RS 相位估计，数据 RE
信道列和 ICI 回归量统一使用
`Hhat_p*exp(j*2*pi*deltaHat_p*DeltaT/fs)`；750 Hz 告警与 +/-1 kHz 无模糊范围沿用
R1-F2。第一遍是逐用户 CFO-RZF，后续为 Q=12、3 次 soft-DF。

固定 20 dB，使用 8 个预注册 TDL-A 信道 seed `20261001:20261008`。共同损伤为独立用户
CFO/timing/power/Wiener phase noise、TDL-A 100 ns delay spread、Tx/Rx 指数相关 0.5、
25 dB leakage、20 ns static rise、20 ps transition jitter 与 100 ps boundary jitter。
L0 无 fast tau jitter；L1 增加 fast=0.6、tau_c=1 us；L2 在 L1 上启用 CFO-aware
soft-DF；L3 用已知 beta 将 L1 的动态 settling 替换为 L0 的静态 settling，再运行逐用户
CFO 接收机。这样 genie 只免除新增快抖，仍保留 CFO、相噪、TDL、泄漏和估计误差。

主指标预注册为每 seed
`gapClosure=(BER_L1-BER_L2)/(BER_L1-BER_L3)`，不再用相对 L1 的普通降低百分比冒充
全栈恢复比例。统计单位是 TDL seed，不是 iid bit：对 8 个 seed 的 BER 中位数做固定
bootstrap seed `20261099`、2000 次配对重采样，报告 95% percentile CI、极差和中位数。
自检要求每 seed 的 L3/L0 虚拟 IQ 相对误差 `<1e-5` 且 bit-error 结果完全一致；未通过
立即停止。pilot go/no-go 在 L1/L2 聚合错误均至少 100 后判定：L2 中位数<L1、两者
bootstrap 95% CI 不重叠且 gap-closure 中位数>=30%。任一失败不得升级 paper，并按
核能量/CFO 混淆、信道估计残差、深衰子载波误码的顺序诊断。

## 19. R7 全损伤栈 pilot 结果：no-go（2026-07-14）

组合接收机已实现为单一接收路径，而非 analyzer 串联：跨 slot DM-RS 估计逐用户残余
CFO，数据 H 列和 ICI 回归量 v 均携带相同的逐 symbol 相位斜坡；独立回归以
`[-350,125,620,-900] Hz` 激活并验证了 750 Hz 告警和 +/-1 kHz 边界。初始 full-stack
smoke 使用该 CFO 幅度时出现第 4 层 `+963 Hz` 包络折返，L0 BER=0.356，属于预注册的
CFO 混叠诊断。正式 pilot 前将 CFO 幅度冻结为一半
`[-175,62.5,310,-450] Hz`，保持多用户独立 CFO 且位于实测无模糊范围内；此调整发生在
8-seed pilot 之前，未依据 pilot BER 选点。

L3 不是“全损伤清零 genie”：`type1_genie_replace_settling` 先用 L1 已知 beta 逆出目标，
再施加 L0 的静态 beta，因此只移除新增 fast tau jitter。所有可解码 seed 的 L3/L0
误码矩阵完全一致，虚拟 IQ 相对误差为 `5.98e-8--6.15e-8`，严格通过 L3≈L0 的算法
不变量；CFO、相噪、TDL、泄漏、定时、功率和信道估计误差仍作为非零栈地板保留。

pilot 使用预注册 TDL-A seeds `20261001:20261008`。其中 20261002/004/006/007 发生
`type1:IncompleteFrame`，不被静默删除，因此只有 4 个可解码实现。其 L0/L1/L2/L3
BER 和 gap closure 为：

| seed | L0 | L1 | L2 | L3 | gap closure |
|---:|---:|---:|---:|---:|---:|
| 20261001 | 0.25734 | 0.29958 | 0.30261 | 0.25734 | -0.0717 |
| 20261003 | 0.19214 | 0.25663 | 0.25829 | 0.19214 | -0.0259 |
| 20261005 | 0.25355 | 0.30084 | 0.30105 | 0.25355 | -0.0045 |
| 20261008 | 0.49960 | 0.50033 | 0.50042 | 0.49960 | -0.1154 |

有效 seed 中位数 L0/L1/L2/L3 为 `0.25544/0.30021/0.30183/0.25544`，极差分别为
`[0.1921,0.4996]/[0.2566,0.5003]/[0.2583,0.5004]/[0.1921,0.4996]`。L2 在每个有效
seed 均未优于 L1，gap-closure 中位数 `-0.0488`、范围 `[-0.1154,-0.0045]`；bootstrap
CI 不分离且 4 个 seed 采集失败，所以 go/no-go 明确为 **no-go**，没有运行 paper。

失败诊断保留坏 seed 20261001：其 L0 `cond(Hhat)` 中位/P95/峰值为
`106/362/1143`；去掉独立用户 timing 后四层 BER 降为
`[0.055,0.0245,0.0021,0.00414]`，而只去 CFO、phase noise 或开关损伤均不能恢复。
TDL-anchor 仍有 `[0.0334,0.0333,0.0382,0.00451]` BER 和峰值 cond 1353，说明当前
全栈点首先受频选深衰、空间病态和 per-user timing 下的估计/插值误差支配，首过 BER
远高于预期 1e-3--1e-2；公共 ICI 核在该区域没有可靠判决回归量。该负结果不能宣称
soft-DF 全栈有效，也不能通过筛除坏 seed 或事后放宽判据改成正结果。

## 20. R8 两段式定时补偿、获取中断审计与修复后阶梯（2026-07-14）

### 20.1 对 R8 裁决及复现失败记录的回应

R8 的双因子判断合理：逐用户定时只给真实信道列施加酉相位，理论上不改变
`cond(H_true)`；此前 `cond(Hhat)` 的额外膨胀应归入 DM-RS OCC/插值估计伪影。同时，
R8 给出的 `cond(H_true)` 本身仍很大，说明仅修估计器也不可能让原 0.5/0.5 相关压力
场景变成低 BER 链路。因此按 R8-A/B/C/D 全部实现，没有回改或删除 R7 的 no-go 数据。

专家记录的 seed `20261008` 在洁净孪生链路上 PSS 复现失败，不是工具或命令失败。
R8 重跑把离线 suffix 加长到完整 10 ms 后，接收机不再抛 `IncompleteFrame`，但选择的
PSS timing 相对已知前缀错 `145743` 个 30.72-MS/s 样点、NID2 错误、PBCH CRC 失败且
L0 BER=`0.4993`。因此它仍被归为 `falsePssPeak` 中断，而不是有效 BER 点；“异常形式由
IncompleteFrame 变为可返回的假峰解码”与专家的物理中断结论一致，并非复现矛盾。

### 20.2 R8-A：两段式逐用户定时估计

新增 `type1_estimate_user_channels.m`，先用原 DM-RS 得到初始 `Hhat`，再以每用户、每
接收支路的相邻子载波复乘积做幅度加权圆周相位斜率估计，得到 `tauHat_p`；随后把已知
DM-RS reference 按该斜率去旋并重新调用 `nrChannelEstimate`。数据 RE 的信道列同时
恢复相应 timing 斜坡，并继续携带逐用户 CFO 的 symbol-time 相位。该公共 helper 已被
`type1_analyze_user_cfo` 和组合 ICI-DF 共用，避免两条接收路径的估计定义漂移。

首次远端验收因标量 timing 与 DM-RS 数组的隐式维度扩展不一致而终止，没有产生 BER
数据；将 timing 显式整形为列向量后，固定 seed `20261001` 的压力场景结果保存在
`/tmp/type1_phase2/type1_phase2_timing_precomp_20260714_223126/`：

| 指标 | 旧估计 | 两段式估计 |
|---|---:|---:|
| `cond(Hhat)` 中位/P95/max | 106.40 / 361.95 / 1143.10 | 58.97 / 246.68 / 2599.28 |
| 四层 BER | 0.2806 / 0.2460 / 0.3542 / 0.1486 | 0.07265 / 0.04057 / 0.005329 / 0.009747 |
| 四层平均 BER | 25.74% | 3.21% |

中位条件数从 `106.4` 回到 `58.97`，接近 decider 的真实中位 `56.8`；平均 BER 逼近
去 timing 消融约 2.14% 的量级，故 R8-A 验收通过。P95 同向改善，但 max 变为
2599，说明个别深衰子载波仍可能产生极端估计值，不能声称全分位一致恢复。配置 timing
为 `[-12.5,3.25,8.5,-6.75]` 样点，而估计为
`[0.883,15.260,16.103,6.605]`；两者不能直接逐元素相等，因为估计斜率还包含每用户
TDL 群时延和共同 timing 基准。本验收依据是去斜后的条件数与 BER，不把绝对值误称为
纯硬件 timing 真值。

### 20.3 R8-B/D：主/压力场景和中断协议

主场景冻结为 SNR 20 dB、TDL-A 100 ns、Tx/Rx 指数相关 `0.3/0.3`、逐用户 timing
残差限幅至 `+/-4` 样点、25 dB 隔离、20 ns 静态建立、`tau_c=1 us`。原 0.5/0.5 相关、
原 timing 和 fast=0.6 保留为 `stress`，不用于替代主结果。主场景 fast 幅度先后仅做了
单 seed smoke 校准：0.6 得 L1=12.52%，0.4 得 8.740%，均偏离 R8 引用的可恢复 BER
区间；依据 R6 在 pilot 前冻结为 0.2，压力点仍为 0.6，不再根据 8-seed 结果调参。

中断预注册为“接收异常，或 L0 BER>10%”。只有非中断 seed 参与 gap/CI；所有 seed
仍进入中断率。prefix 延长为 0.5 ms、suffix 延长为完整 10 ms。报告新增已知 prefix
相对 timing、三种 PSS peak/metric、NID2、PBCH CRC 和失败类别。以最大 CP 长度 88
个样点为 timing 真值容差：正常 seed 的误差为 `-2` 或 `-3`；20261004/006/008 的误差
为 `145741--145743`，且均 NID2 错、PBCH CRC 失败，故三者均为 `falsePssPeak`，不是
窗口裁剪。

### 20.4 组合接收机缺陷修复及正式 R8 pilot

在 R8 smoke 诊断中发现组合路径仍有一处违反 R7 架构约束：核回归的 `h` 已包含两段式
timing/CFO 补偿，但首轮 `xHat` 仍取自旧 `type1_analyze.postCompData`。现已改为直接用
同一 `y,h` 做首轮 RZF，再硬判决构造回归量；`type1_validate_ici_user_cfo` 复测通过，
并正常触发 750 Hz CFO guard 告警。修复前 fast=0.2 smoke 的 gap 为 `-4.82%`，修复后
为 `+0.55%`，说明路径混用确为 bug，但不是剩余性能差距的主因。

正式输出为
`/tmp/type1_phase2/type1_phase2_full_stack_pilot_20260714_224914/`，固定 seeds
`20261001:20261008`，每个有效 seed 为 636480 bits：

| seed | 状态 | L0 | L1 | L2 | L3 | gap closure |
|---:|---|---:|---:|---:|---:|---:|
| 20261001 | ok | 0.01291 | 0.03032 | 0.03022 | 0.01291 | 0.0055 |
| 20261002 | ok | 0.000413 | 0.006338 | 0.005863 | 0.000413 | 0.0801 |
| 20261003 | ok | 0.003681 | 0.01521 | 0.01480 | 0.003681 | 0.0354 |
| 20261004 | false-PSS 中断 | 0.5003 | 0.4994 | 0.4996 | 0.5003 | 不参与 |
| 20261005 | ok | 0.005164 | 0.01845 | 0.01777 | 0.005164 | 0.0513 |
| 20261006 | false-PSS 中断 | 0.4999 | 0.5001 | 0.5004 | 0.4999 | 不参与 |
| 20261007 | ok | 0.009076 | 0.03586 | 0.03503 | 0.009076 | 0.0308 |
| 20261008 | false-PSS 中断 | 0.4993 | 0.4997 | 0.4997 | 0.4993 | 不参与 |

5 个非中断 seed 的中位 L0/L1/L2/L3 为
`0.005164/0.01845/0.01777/0.005164`，极差分别为
`[0.000413,0.01291]/[0.006338,0.03586]/[0.005863,0.03503]/[0.000413,0.01291]`。
L2 在 5 个有效 seed 上均小于 L1，但 gap closure 中位仅 `0.0354`，范围及固定 seed
bootstrap 95% CI 均为 `[0.0055,0.0801]`；L1/L2 BER CI 不分离。三种假峰使总中断率
为 `3/8=37.5%`。所有能返回的 seed 均满足 L3/L0 bit-error 完全相同，IQ 相对误差
`6.01e-8--6.41e-8`，所以 genie 语义和自检仍成立。

最终 `goNoGo=false`：R8 已把基线从 R7 的约 25.5% 修到有效 seed 中位 0.516%，并把
DF 从全负增益修到全正增益，但只关闭约 3.5% 的 settling gap，远低于预注册 30%，且
获取中断率仍高。没有启动 paper 档。下一轮应把“获取假峰”和“全栈下公共核只能获得
小增益”拆成两个问题：前者做独立 P_acq/假峰统计，后者用真值 ICI 核/真值判决分解
核估计误差、信道估计误差和判决污染；在完成该分解前不继续调 fast/Q/迭代来追求通过。

## 21. R9 验收注记与 R10 四支分解预注册（实验运行前冻结）

R9 对 R8 的复现和 no-go 裁决成立，并以独立 EVM 分解改写了失效主嫌：seeds
20261001/003 的新增 ICI 分别占 L1 残差功率 51%/63%，而 L2 EVM 为 45.3%/35.98%，
说明不能再把“信道估计误差稀释核 LS”当作单一解释。后续主假设改为跨开关相位的核
模型缺项 H1 与强/弱子载波拟合错位 H2。

R8-A 的 timing 输出统一称为**聚合斜率**：配置 timing、每用户 TDL 群时延和公共 PSS
量化共同进入该值。配置与估计值相差约 7.6--13.4 样点是预期的基准/群延迟项；只比较
去斜后的 `cond(Hhat)` 和 BER，不把 `tauHat` 逐元素解释为硬件配置偏移。条件数头条仅报
中位/P95；精化后 max 从 1143 恶化到 2599，作为局部深衰重估失败的尾部证据保留。

R10 固定 seeds `20261001/20261003`、main 场景、fast=0.2、`tau_c=1 us`、Q=12、3 次
soft 迭代；不扫描或调整 fast/Q/迭代。所有支路共享每 seed 的信号、TDL、噪声和开关
随机实现。

1. **模型上限支（H1）**：用 SNR=200 dB 的配对 L0/L1 得到真值增量残差
   `eTrue=Y_L1-Y_L0`，用记录的稳态开关 target 构造当前相位 `V_q` 及严格按 raw 顺序
   对齐的前一相位 `V_{q-1}`。在每 OFDM symbol 内做偶/奇子载波交叉拟合，比较单 bank
   `V_q` 与双 bank `[V_q,V_{q-1}]` 的 out-of-sample 捕获分数
   `1-P_residual/P_eTrue`。若两个 seed 的双 bank 均比单 bank 高至少 0.15，且双 bank
   捕获均不低于 0.30，则 H1 成立并允许升级双 bank；若两者捕获均低于 0.20，则判卷积
   核模型在该频选点失效；其余结果判为证据不足，不升级模型。
2. **genie 判决支**：保持两段式 `Hhat`，只把核回归反馈替换为真实 QPSK `xTrue`；与
   当前首遍判决支比较捕获分数、EVM、BER。两个 seed 均获得至少 0.15 的 gap-closure
   绝对增量，才称判决污染是主导项；否则只量化为次要贡献。
3. **genie 信道支**：从同一 TDL 抽取、用户损伤和开关 realization 重放每个 layer，
   以无快抖 L0 的无噪声分量构造逐 RE `HTrue`；保持标准首遍判决，只替换回归/均衡
   信道。判据同上：两个 seed 的 gap closure 均绝对增加至少 0.15 才称信道估计误差
   主导。另报 `HTrue+xTrue` 联合 genie 作为实现自检，不拿它代替单因素归因。
4. **误差定位支（H2）**：按每 data RE 的 `sigma_min(Hhat)` 排序，统计最低十分位中
   承载的 L1 bit errors。均匀基准为 10%；若两个 seed 均至少 30%（三倍富集），确认
   H2。仅在确认后试固定权重
   `w=1/max(P_v,0.1*median(P_v))` 的反功率 LS；只有两个 seed BER 都下降且聚合相对
   降低至少 5%，才保留为候选，否则作为负结果撤下，不另调权重。

PSS 并行项先做代码事实核验：当前 `type1_analyze` 已将四列
`nrTimingEstimate` correlation magnitude 用 `sum(abs(.)^2,2)` 非相干合并，并非单链。
因此只比较当前四链合并与四条固定单链的 timing/NID2 成功数；成功定义为已知 prefix
相对 timing 在最大 CP（88 样点）内且 NID2 正确。该对照用于判断已有分集是否有效，
不把现成功能包装成新增算法。

若且仅若 H1 门禁通过，允许把双 bank 接入同一 CFO/timing-aware DF；默认单 bank 接口
保持不变以保护既有回归。双 bank 候选只有在两个 seed 的 BER 都低于单 bank，且各自
gap closure 至少增加 0.15 时，才称为有意义升级；否则结论为“真值模型缺项成立，但
估计双 bank 尚不能把结构上限转化为接收增益”，不继续调核宽或正则化。

## 22. R10 四支分解、双 bank 决策与 PSS 分集核验（2026-07-14）

### 22.1 真值重放与回归卫生

`type1_apply_switch_impairments` 在 `recordTimeSeries=true` 时新增保存稳态 target、
`beta[n]` 和采样边界位移；`type1_replay_switch_trace` 可把任一线性 layer 通过完全相同
的 leakage/boundary/beta realization 重放。`type1_replay_tdl_components` 用保存的 TDL-A
gains 重建每个 layer 的无噪声物理 RX 分量。两条代数不变量均通过：TDL 分层相加恢复
原输出的相对误差 `2.5e-16`，开关轨迹重放逐样点相对误差为 `0`。这些接口只用于
genie/真值诊断，不进入实时或普通离线接收机。

四支结果保存在
`/tmp/type1_phase2/type1_phase2_r10_decompose_20260714_231115/`。固定 fast=0.2、
`tau_c=1 us`、Q=12、3 次 soft-DF 和 seeds 20261001/003：

| seed | 单 bank 真值捕获 | 双 bank 真值捕获 | L0 BER | L1 BER | 当前 DF | xTrue DF | HTrue DF | HTrue+xTrue |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 20261001 | 0.2617 | 0.4746 | 0.01291 | 0.03032 | 0.03022 | 0.02999 | 0.02206 | 0.02190 |
| 20261003 | 0.3527 | 0.5134 | 0.003681 | 0.01521 | 0.01480 | 0.01461 | 0.009084 | 0.009114 |

对应 current/xTrue/HTrue/joint gap closure 分别为
`[0.0055,0.0188,0.4744,0.4833]` 和
`[0.0354,0.0523,0.5315,0.5289]`；EVM 分别为：

| seed | L0 | L1 | 当前 DF | xTrue DF | HTrue DF | joint |
|---:|---:|---:|---:|---:|---:|---:|
| 20261001 | 31.04% | 44.36% | 45.30% | 43.90% | 40.38% | 39.03% |
| 20261003 | 22.15% | 36.43% | 35.98% | 35.53% | 31.02% | 30.74% |

### 22.2 四支裁决

1. **H1 通过**：双 bank 相对单 bank 的 out-of-sample 捕获增加 0.213/0.161，且双 bank
   均超过 0.30。跨相位状态差确实是单 bank 的结构缺项；卷积核模型类没有失效。
2. **判决污染非主导**：换 `xTrue` 后 gap 只增加 0.013/0.017，未达到 0.15。
3. **对角信道模型/估计支是最大贡献**：HTrue 支相对当前 gap 增加 0.469/0.496，两个
   seed 均过 0.15。但该 `HTrue` 是用逐 layer 洁净孪生和真实 data symbol 构造的
   **data-aided 对角等效信道**，会把部分逐用户 CFO/相噪自 ICI 吸收到对角系数中；
   因此只能称“对角模型+估计联合 genie 上界”，不能把全部 47--53% 归因于 DM-RS
   插值误差。joint 仍非 L0/零误码也说明动态跨子载波项和噪声未被对角 genie 消除。
4. **H2 未通过**：最低 `sigma_min(Hhat)` 十分位承载的 L1 bit-error 比例为
   26.4%/40.6%，只有一个 seed 达到 30%。因此 `h2Confirmed=false`，反功率 LS 阶段由
   代码门禁拒绝，未运行、未调权重；最终回归确认返回 `type1:R10H2Gate`。

### 22.3 双 bank 实际接收机：结构正确但候选失败

H1 通过后，组合接收机增加显式 `kernelBanks='single'|'double'`，默认保持 single。
double 使用自链和 raw 顺序的前一开关相位链，共 50 个复系数/符号；phase 1 的前驱
phase 4 包含一个 virtual-sample OFDM 延迟。single/double 理想链路三轮均为零误码。

门控结果保存在
`/tmp/type1_phase2/type1_phase2_r10_double_bank_20260714_231436/`：

| seed | single BER / gap | double BER / gap | double EVM |
|---:|---:|---:|---:|
| 20261001 | 0.03022 / +0.006 | 0.03405 / -0.215 | 46.55% |
| 20261003 | 0.01480 / +0.035 | 0.01714 / -0.167 | 36.93% |

两个 seed 均恶化，故 `retainDoubleBank=false`。结论不是推翻 H1，而是：真值前相位
target 提供的结构上限存在，但用 `Hhat*xhat` 构造的前相位 bank 加倍自由度后受对角
模型误差/共线性污染，未能兑现上限。按预注册纪律不调 Q、正则化或 fast 来挽救该点，
double 接口仅保留为研究负基线，不能替代默认 single。

### 22.4 PSS 非相干合并核验

代码审计确认正式 `type1_analyze` 已对四列相关 magnitude 做平方和，因此四虚拟链
非相干合并早已存在。首次对照脚本漏掉正式路径的逐链 RMS 归一化，导致 seed 20261002
不能复现 R8；该轮被判为测试脚本错误，不作为数据。补齐归一化并加入 R8 逐 seed 断言
后，结果保存在
`/tmp/type1_phase2/type1_phase2_r10_pss_diversity_20260714_231713/`：四链合并与固定
chain1--4 的成功数为 `5/8, 4/8, 3/8, 5/8, 5/8`。四链合并救回单链 1--3 均失败的
20261002，但 20261004/006 在至少一条固定链成功、合并却假峰；20261008 所有方法均
失败。

因此“现有四链非相干合并提供免费分集”只得到部分支持：它优于固定 chain1/2，但未
超过最佳固定 chain3/4，且简单能量和会被错误链相关峰拖偏。后续可预注册 trimmed/
选择式鲁棒合并并在更多独立信道上评价；当前不能把既有合并包装成新增算法，也不能用
8 个 seed 宣称 PSS 获取率普适提升。

## 23. R10 验收与 R11 任务预注册（实验运行前冻结）

R10 经专家逐位复现后无保留通过。新增解释成立：`jointGenie` 与 `genieChannel` 几乎
相同，只修判决没有额外恢复；而单 bank 真值捕获仅 26--35%，所以对角信道修复与核
结构升级缺一不可。PSS 的 20261004 又证明固定 chain3/4 可成功而简单四链和失败，支持
峰位一致性投票，而不是继续增加相关能量。

R11 继续冻结 main 场景、seeds 20261001/003、fast=0.2、`tau_c=1 us`、Q=12 和 3 次
迭代，不按结果调参。

1. **DDCE**：每次 DF 迭代先把当前输出硬判决为 QPSK；在去除已估 timing/CFO 斜坡的
   基准域内，对每 slot、每子载波和每 RX，用最多 13 个 data symbols 建立
   `Y_l=sum_p H_p exp(j phi_lp) xHat_lp` 的复 LS，重估四列 H，再把 timing/CFO 相位回加
   到每个 data RE。DDCE 只有在两个 seed BER 都下降，且相对当前 single-bank DF 的
   gap closure 均增加至少 0.15 时通过；否则不进入默认接收机。
2. **约束核的自由度修正**：专家给出的“52 real -> 13 real”对应 Q=6；当前冻结 Q=12，
   无约束双 bank 实为 `2*(2Q+1)` 个复系数，即 100 real DOF。实值 `deltaBeta` 只推出
   `B(-u)=conj(B(u))`，因此约束后为 `1+2Q=25` real DOF；13 real 还需要 B 为实偶函数，
   该条件没有物理依据，故不采用，也不把 Q 偷换为 6。由一阶递推
   `e_n=(1-beta0)e_{n-1}+deltaBeta_n*(t_n-y0_{n-1})`，构造已知驱动
   `D=t-y0_prev`，只拟合共轭对称 B。真值交叉拟合捕获相对同一 target/state 无约束
   双 bank 下降小于 0.05 才通过；否则报告每频移无约束系数比值的跨 seed 稳定性，不进
   接收机。
3. **组合**：仅在约束核真值门禁通过后，将 DDCE H 与 constrained B 同时用于 DF。
   两 seed BER 均低于 DDCE-only，且 gap 再提升至少 0.10 才称组合有增益；最终是否达到
   30% 仍按原 full-stack gate 判断。
4. **PSS 投票**：每条固定链独立给出 NID2/peak；若至少两链在 88-sample 容差内且 NID2
   相同，则选择该一致簇中总 metric 最大的峰，否则回退现有四链非相干和。固定 8 seed
   上至少成功 6/8 才称该候选通过；这仍是 smoke 证据，后续必须扩 seed。

## 24. R11：DDCE、物理约束核、组合与 PSS 投票结果（2026-07-14）

### 24.1 任务 1：DDCE 温和正增益，但未过门槛

`type1_analyze_ici_decision_feedback` 新增可选 `channelTracking='fixed'|'ddce'`，默认
`fixed`。DDCE 初轮用原始 data observation，后续用上一轮 ICI 校正 observation；每轮
将当前输出硬判为 QPSK，对每 slot/subcarrier/RX 用 data symbols 复 LS 重估四层基准域
H，再回加两段式估计器的 timing/CFO 相位。理想链路零误码，两个研究 seed 的所有
子载波均满秩，秩亏计数为 0。

结果目录为 `/tmp/type1_phase2/type1_phase2_r11_ddce_20260714_233607/`：

| seed | L0 | L1 | fixed DF | DDCE | fixed/DDCE gap | fixed/DDCE EVM |
|---:|---:|---:|---:|---:|---:|---:|
| 20261001 | 0.01291 | 0.03032 | 0.03022 | 0.02995 | 0.0055 / 0.0211 | 45.30% / 39.89% |
| 20261003 | 0.003681 | 0.01521 | 0.01480 | 0.01429 | 0.0354 / 0.0805 | 35.98% / 29.68% |

DDCE 在两 seed 均降低 BER，EVM 改善也很明显，但 gap 只增加 0.0156/0.0451，未达到
0.15，故 `ddcePassed=false`。这说明 data-aided H 更新能恢复幅度误差，却仍无法显著
改变承载 bit error 的局部 RE；不能以 EVM 好转替代 BER gate，也不把 DDCE 设为默认。

### 24.2 任务 2：约束 B(u) 真值门禁通过

用严格的一阶驱动 `D=t-y0_prev`，在相同 target/state 回归量上比较 100-real-DOF
无约束双 bank 与 25-real-DOF 共轭对称 B。结果目录为
`/tmp/type1_phase2/type1_phase2_r11_constrained_model_20260714_233748/`：

| seed | 无约束捕获 | constrained B 捕获 | 捕获下降 |
|---:|---:|---:|---:|
| 20261001 | 0.6359 | 0.6372 | -0.0013 |
| 20261003 | 0.6501 | 0.6452 | +0.0049 |

两点下降均小于 0.05，`constrainedModelPassed=true`。该结果确认实值 `deltaBeta` 和
状态差递推可把 Q=12 双 bank 从 100 压到 25 real DOF，几乎不损失真值捕获；也验证
此前拒绝“52→13”计数是必要的，13 real DOF 只对应 Q=6 或额外实偶约束。

### 24.3 任务 3：真值结构无法由当前状态代理兑现，组合失败

接收机新增可选 `kernelConstraint='free'|'physical'`；physical 仅允许 double 概念 bank，
实际拟合 `V_current-V_previous` 上的 25-real-DOF 共轭对称 B。默认仍为 free/single。
single/double/DDCE/physical/combined 理想链路全部零误码。

门控组合结果在 `/tmp/type1_phase2/type1_phase2_r11_combined_20260714_234122/`：

| seed | fixed gap | DDCE gap | physical-B gap | DDCE+physical gap |
|---:|---:|---:|---:|---:|
| 20261001 | +0.0055 | +0.0211 | -0.5615 | -0.7301 |
| 20261003 | +0.0354 | +0.0805 | -0.6364 | -0.5262 |

对应 physical/combined BER 为 `0.04009/0.04303` 与 `0.02255/0.02128`，均高于 L1；
`combinationPassed=false`，30% gate 也失败。真值 constrained B 的 64% 捕获与接收机
反噬并不矛盾：真值驱动使用真实 analog target 和 L0 前一状态；接收机只能用受
对角 H/判决误差污染的 `Hhat*xhat` 近似当前/前一状态。物理约束减少了自由度，却不能
修复错误的状态代理。DDCE 对该代理的净化不足，因此不调 Q、正则化或 fast 挽救。

### 24.4 任务 4：PSS 峰位投票通过 smoke

在原四链非相干检测外增加候选投票：至少两条固定链的 NID2 相同、峰位在 88 samples
内，选择该簇最强峰；否则回退原合并。诊断结果目录为
`/tmp/type1_phase2/type1_phase2_r10_pss_diversity_20260714_234237/`，成功数从原合并
`5/8` 提升为 `6/8`：投票修复 20261004；20261002/007 无一致簇时回退合并并成功；
20261006/008 仍失败。`votePassedSmokeGate=true`。

投票已作为 `type1_analyze(rx,package,"vote")` 的可选模式接入，默认仍为 `"combined"`。
集成回归确认 seed 20261002 正确回退、20261004 由两链一致峰救回。该 6/8 仅满足预
注册 smoke 门槛，尚不能替换默认 OTA/论文获取器；下一步需增加独立 TDL seeds、SNR
分层和假峰/漏检置信区间。

R11 四任务最终状态：DDCE 实现但门禁失败；约束核真值门禁通过；实际 constrained/
组合接收机门禁失败；PSS 投票 smoke 通过。所有负门禁均按预注册执行，没有将 EVM
改善、真值捕获或 8-seed PSS 结果冒充 full-stack BER 成功。

最终兼容性回归同时通过开关代数、`2.5e-16/0` 真值重放、single/double/DDCE/physical
理想零误码、CFO 750-Hz guard 和 PSS vote 集成；默认 R8 smoke 逐位保持
L0/L1/L2/L3=`0.01291/0.03032/0.03022/0.01291`，结果目录
`/tmp/type1_phase2/type1_phase2_full_stack_smoke_20260714_234640/`。因此新增研究接口没有
改变历史默认 single/fixed/free/combined 基线。

## 25. R12 前置收束：received-drive 与 PSS 扩样预注册（实验运行前冻结）

本节判据写于实验结果产生之前。它服从 `PHASE2_MIDTERM_REPORT.md` 的最终目标：B 线的
目的不是无限调参把 full-stack BER “救成正结果”，而是确定“信道估计质量 × 模拟状态
可观测性”的集成边界。received-drive 是 B 线最后一次有界尝试，无论通过与否，本次
之后冻结 fast=0.2、`tau_c=1 us`、Q=12、3 次 soft 迭代与 seeds
20261001/20261003，并结束 B 线。

1. **received-drive 定义与信息边界**：用单链 ADC 实际可见的 stitched stream 构造
   `dHat[n]=(y[n]-y[n-1])/beta0`。`beta0=1-exp(-1/(Fs*tau0))` 只由配置的 20 ns
   10--90% rise time 和 122.88 MS/s 得到；不得读取动态 beta、target 或 L0 state。
   `dHat` 按四相 reshape、沿与接收信号相同的 PSS/CFO 基准解 OFDM，然后作为 25-real-
   DOF 共轭对称 B 的唯一 drive。第一门在 full-stack 20 dB、同 realization L1-L0
   真值残差上做偶/奇交叉拟合；两个 seed 的 capture 都不低于 0.50 才进入接收机。
   200 dB 只作为“模型上限/观测噪声”诊断，不参与放行。
2. **接收机门**：只在第一门通过时比较 DDCE-only 与 DDCE+received-drive；沿用
   `combinationPassed`，即两个 seed 均严格降低 BER，且相对 DDCE 的 gap closure 均增加
   至少 0.10。没有通过时不调 Q、正则或 fast。
3. **PSS 投票扩样**：固定 seeds 20261101--20261130、SNR={14,20,26} dB，同一 realization
   配对比较现有四链非相干合并与 R11 峰位投票。逐 SNR 记录 vote rescue
   `n01=(combined fail,vote pass)`、vote loss `n10=(combined pass,vote fail)`，并报告精确
   双侧 McNemar p 值。只有每个 SNR 都满足 `n01>=n10`，且至少一个 SNR 满足
   `n01>n10,p<0.05`，才把 vote 升为默认；否则保持显式可选模式。该判据不在看数后修改。

## 26. Phase 2 集成边界定论与 R11 收束结果（2026-07-15）

### 26.1 received-drive：真值可观测，但接收机门差 1.22 pp

实现新增 `type1_received_drive` 和 `kernelConstraint='received'`。前者只从 stitched ADC
及名义建立时间构造 `dHat`；后者把该 drive 沿接收信号相同的 timing/CFO 基准解调，
再做 Q=12、25-real-DOF、偶/奇交叉拟合。没有读取动态 beta、target 或 L0 state。
结果位于 `/tmp/type1_phase2/type1_phase2_received_drive_20260715_000817/`。

| seed | 20 dB exact capture | 20 dB received capture | 200 dB received capture |
|---:|---:|---:|---:|
| 20261001 | 0.6372 | 0.6365 | 0.6365 |
| 20261003 | 0.6453 | 0.6435 | 0.6434 |

第一门两点均远高于 0.50，且 20/200 dB 几乎重合：在当前 paired residual 定义下，
ADC 差分确实保留精确一阶 drive 的主要结构，20 dB 回归量噪声不是 capture 损失主因。
但这不等于接收机通过：真值门只回答“结构可观测”，不能替代 BER 门。

| seed | BER L1 | BER DDCE | BER DDCE+received | gap DDCE | gap received | gap 增量 |
|---:|---:|---:|---:|---:|---:|---:|
| 20261001 | 0.030318 | 0.029951 | 0.028422 | 0.0211 | 0.1089 | **0.0878** |
| 20261003 | 0.015213 | 0.014285 | 0.010525 | 0.0805 | 0.4065 | 0.3260 |

两 seed BER 都下降，EVM 分别由 DDCE 的 39.89%/29.68% 降至 39.55%/26.07%；但
20261001 的 gap 增量只有 8.78 pp，比预注册 10 pp 少 1.22 pp。因此
`truthGatePassed=true`、`receiverGatePassed=false`。不得因“很接近”重写门槛，也不把
单个 seed 的 40.65% gap 包装为 full-stack 成功。新增 received 模式的理想链路回归
BER=0，未破坏既有模式。

### 26.2 集成边界最终解释（论文 Integration/Limitations 章素材）

Phase 2 B 线现已冻结。隔离场景的 ICI-DF 可以降低 BER 38--58%，但迁移到 TDL-A、
多用户 CFO/定时和开关损伤的 full stack 时，同时受以下两门限制：

1. **信道估计质量**：R10 的 data-aided HTrue 支给出 47--53% gap，DDCE 实际只兑现
   1.6/4.5 pp；深衰和逐符号等效信道误差仍污染判决与回归量。
2. **模拟状态可观测性**：精确 `t-y0_prev` 与 received-drive 都有约 64% 真值 capture，
   证明一阶机制正确且 ADC 差分可见；但实际 DDCE+received 的收益跨信道 realization
   离散很大（gap 10.89% vs 40.65%），未通过统一门槛。

所以结论不是“ICI 不可恢复”，也不是“组合接收机已经成功”，而是：**算法的隔离场景
增益有明确的迁移条件；在现有信道估计器与 20 dB full stack 上，状态结构可观测但不能
稳定兑现为跨 realization 的 BER 恢复。** 三次预注册失败、64% 真值天花板和最后一次
received-drive 的正趋势/门禁失败共同构成停止证据；不再调 Q、fast、迭代或门槛。

### 26.3 PSS 投票 30 seeds × 3 SNR 配对结论

结果位于 `/tmp/type1_phase2/type1_phase2_pss_vote_statistics_20260715_001401/`：

| SNR | combined 成功 | vote 成功 | rescue/loss | 精确双侧 McNemar p |
|---:|---:|---:|---:|---:|
| 14 dB | 17/30 | 18/30 | 1/0 | 1.0 |
| 20 dB | 17/30 | 19/30 | 2/0 | 0.5 |
| 26 dB | 17/30 | 19/30 | 2/0 | 0.5 |

投票在三点均无反向丢失，满足计数意义的“不劣”，但没有任何一点达到 p<0.05，故
`upgradeVoteToDefault=false`，`type1_analyze` 默认保持 `combined`，vote 继续为显式可选。
三个 SNR 的 combined 成功数完全相同，且多数失败是相同 TDL realization 上的远端假峰，
说明 14--26 dB 区间主要暴露信道/峰选择瓶颈而非 acquisition waterfall；它只能作为
R13 的数据与脚本地基。R13 必须扩至至少 100 seeds，并把 SNR 网格下探到成功率随 SNR
变化的区域，预先定义假峰/漏检和 timing 容差，不能把本表称为正式 P_acq(SNR) 曲线。

## 27. R12 RX-LO 拓扑实验预注册（实验运行前冻结）

R11b 已由独立审议 fresh 全量重跑，capture/BER/gapGain 三项逐位一致，B 线冻结维持。
R12 是独立的 RX-LO 拓扑实验，不复用 received-drive 调参，也不重开 B 线。TX 侧已有
逐用户 Wiener 相噪保持不变；新增模型一律标为 **RX PLL/LO 相噪**。

### 27.1 模型与注入点

有界单极 PLL 近似采用稳态 OU/AR(1)：
`phi[n]=alpha*phi[n-1]+sqrt(1-alpha^2)*sigmaPhi*w[n]`，
`alpha=exp(-2*pi*Bpll/F_rate)`。`sigmaPhi` 是稳态 RMS 相位，`Bpll` 是单极拐点；
连续极限的低频 SSB 平台为 `L(0)=sigmaPhi^2/(pi*Bpll)`，并在一次 Welch 数值验证中
以 10 kHz/100 kHz 点允许绝对误差不超过 1 dB。

- common：在 122.88 MS/s stitched 单链流上乘同一 `exp(j*phi[n])`，位于开关合成后；
- independent：在 30.72 MS/s 四支路窗口上分别乘 `exp(j*phi_r[n])`，位于开关前；
- LO 使用配置 seed 创建独立 `RandStream`，不得消耗既有信号、信道、噪声或开关流；
  `mode=off` 或 `sigmaPhi=0` 必须逐位恒等。

### 27.2 假设及适用边界

H-LO1：同 `(sigmaPhi,Bpll)` 下 common BER 不高于 independent BER。物理原因是共同 LO
只有一个共享时变核，而四独立 LO 产生四个接收支路核并使 DM-RS 后等效 H 的行相位
分别漂移。主判据是 5×3 网格每一点的聚合 common/independent error count；不因单点
结果修改参数。

H-LO2：在隔离打样点 `(2 deg,100 kHz)`，common 加每 OFDM symbol 一个判决引导 CPE
参数后近似无 RX-LO 基线。预先把“近似”定义为 BER 不高于
`max(BERoff,3/Nbits)` 且聚合 EVM 相对 off 增量不超过 1 percentage point。
但 `W(exp(j theta)y)=exp(j theta)Wy` 只在符号内近似常相位时严格成立；100 kHz/1 MHz
会产生公共 ICI，故高速网格中 CPE 未回到基线是物理偏离，不据此判实现错误。

H-LO3：independent 上同一标量 CPE 只能去公共分量；小相位区间
`sigmaPhi={0.5,1,2,4} deg` 的 CPE 后**增量 EVM 功率**应近似正比于 `sigmaPhi^2`。
逐 Bpll 记录过原点拟合斜率和 R2；这是比零误码区 BER 更有辨识力的机理指标。

### 27.3 顺序、统计停止与规格口径

先运行四项验证（零 sigma 恒等、common 四列同相、Welch PSD、LO-off 完整链逐位兼容），
再运行 flat/相干用户/理想开关/20 dB 的 `(2 deg,100 kHz)` 单点。验证或同步失败即停止，
不得铺网格。

正式网格固定 `sigmaPhi={0.5,1,2,4,8} deg`、`Bpll={10 kHz,100 kHz,1 MHz}`。
每点 common/common+CPE/independent/independent+CPE 使用相同信号 seed 序列；每个接收机
至少累计 100 errors，或共同达到不少于 1e7 bits（当前每帧 636480 bits，最多 16 个
10 ms realization）。零错按 `-log(0.05)/Nbits` 报 95% 上界，不写 BER=0。

规格目标预注册为 BER<=1e-3。只有网格同时夹住 independent 与 common+CPE 的通过/
失败边界，才计算放宽倍率 `A=sigma_commonCPE/sigma_independent`；若任一边界超出 8 deg，
只报单侧下界或“网格内不可识别”，不外插。最后在 R11 main 温和栈、seed 20261001、
fast=0 上做 `(2 deg,100 kHz)` off/common/independent 单点，只确认 RX-LO 增量，不改变任何
B 线结论或门禁。

## 28. R12 公共单 LO vs 独立 4-LO：假设检验与规格边界（2026-07-15）

### 28.1 实现、验证与打样

`type1_apply_rx_lo_phase_noise` 实现有界 OU/AR(1) RX-PLL，使用配置 seed 的独立
`RandStream`。independent 在 30.72 MS/s 四支路、开关前注入；common 在 stitched
122.88 MS/s 单链、开关后注入。`mode=off` 和 `sigmaPhi=0` 都直接返回原数组，不执行
乘法或随机数生成。历史 sim 不含 `rxLo` 字段时补成 off，完整 `raw122/stitched/
virtual` 与显式 off 逐位相等。

四项验证全部通过：零 sigma/off 恒等；common helper 对同一物理时刻的四列施加完全
相同相位；OU 理论 `alpha=0.97975467`、实测 lag-1 `0.97953897`；2 deg/100 kHz 在
10.1 kHz 的 Welch SSB 为 -85.14 dBc/Hz，理论 -84.16 dBc/Hz，误差 -0.98 dB，在
预注册 1 dB 内。LO-off 标准/CPE 均零误码。须注意实际开关虚拟向量的四个分量相差
8.138 ns，不是物理同时采样；“共同标量”在 `Bpll` 越高时只是四相周期内近似。

隔离打样 `/tmp/type1_phase2/type1_phase2_rx_lo_pilot_20260715_140622/` 固定 seed
20261201、2 deg/100 kHz、20 dB，off/common/common+CPE/independent/independent+CPE
均 0/636480 errors，EVM 为 7.963/9.955/8.963/9.669/9.177%。H-LO1 在该零错点只能称
未违反，不能称显著优势；H-LO2 按预注册门失败，因为 common+CPE 相对 off 的 EVM
增加约 1.0001 pp，略高于 1 pp，不能按显示三位小数改判。

### 28.2 CPE 实现勘误与保留审计

首版 `type1_apply_symbol_cpe` 逐符号直接使用
`angle(sum(conj(xHat).*xEq))`，但没有对 QPSK 的 pi/2 象限模糊作连续跟踪。首次网格
目录 `...rx_lo_statistics_20260715_140156/` 被保留为实现审计，不作为最终曲线。在
10 kHz/8 deg 的 seed 20261215 上，memoryless CPE 有 25498 errors；genie-only
逐符号 reference 诊断发现只有 11/130 个符号的估计与 oracle 相差超过 pi/4，却承载
25487/25498=99.96% 的错误，而 oracle CPE 为 0 errors。这证明首版失败是象限获取/
周跳，不是公共 LO 信息被破坏。

正式 CPE 仍保持每符号一个实参数，只用 DM-RS 已把等效 H 锚定为零相位这一事实，从
DM-RS 向前/向后选择与上一符号最近的 pi/2 分支；没有增加导频、参数或真值。该修正把
上述 seed 降至 8364 errors，但相邻符号变化超过 pi/4 时仍不可唯一获取。继续加入更强
PLL/Bayesian tracker 会成为新的算法，不在看数后加入。最终 fresh 网格为
`/tmp/type1_phase2/type1_phase2_rx_lo_statistics_20260715_141225/`。

### 28.3 paper-stop 网格结果

每个零错/低错点累计 16 个 realization、10183680 bits；10 kHz/8 deg 因四接收机均
超过 100 errors 在 15 个 realization、9547200 bits 停止。没有 PSS/acquisition 异常。
下表给 8 deg 端点，顺序为 common / common+CPE / independent / independent+CPE：

| Bpll | errors | BER |
|---:|---:|---:|
| 10 kHz | 29997 / 8364 / 492 / 138 | 3.142e-3 / 8.761e-4 / 5.153e-5 / 1.445e-5 |
| 100 kHz | 50717 / 35065 / 149 / 2 | 4.980e-3 / 3.443e-3 / 1.463e-5 / 1.964e-7 |
| 1 MHz | 0 / 0 / 1 / 0 | <2.94e-7 / <2.94e-7 / 9.820e-8 / <2.94e-7 |

0.5/1/2 deg 的所有拓扑均零错；4 deg 只有 10/100 kHz common 各 2 errors，其余零错。
零错均按 95% 上界报告，不能写 BER=0。生成的三面板拓扑图位于结果目录
`phase2_rx_lo_topology.png`。

H-LO1 的“每点 common errors<=independent errors”门为 **false**。反例不是微小统计
涨落：10/100 kHz、8 deg 的 common raw BER 比 independent 高约 61/340 倍。机理应
改写为：公共 LO 把损伤集中成一个可跟踪公共核，但在没有可靠相位获取时也把慢相位
偏转同时施加到全部层；独立支路在当前 well-conditioned 4x4 flat 信道和逐 slot DM-RS
下可由空间合成部分平均。线性可交换性描述“已知相位时容易校正”，不保证 blind/
decision-directed 端到端 BER 更低。

H-LO3 得到支持：independent+CPE 在 sigma<=4 deg 的增量 EVM 功率对 sigma^2 过原点
拟合，10/100/1000 kHz 的 R2 为 0.9913/0.9915/0.9901，斜率为
1.493/1.531/1.351。该结果比零错 BER 更直接验证四独立 LO 的残余二阶缩放。

### 28.4 规格结论与 full-stack 限定

BER<=1e-3 下，independent 三个带宽均到 8 deg 仍通过，因此阈值只知 `>=8 deg`。
common+CPE 在 10 kHz 为 `>=8 deg`，100 kHz 夹在 `[4,8) deg`，1 MHz 为
`>=8 deg`。网格没有同时夹住两个拓扑阈值，故 `relaxationIdentifiable=false`，不能
报告专家预期的放宽倍率 A；100 kHz 甚至给出相反排序。不得用 EVM 或 oracle CPE
替换预注册 BER 后再声称正倍率。

温和 full-stack 单点目录为
`/tmp/type1_phase2/type1_phase2_rx_lo_full_stack_20260715_141253/`。seed 20261001、
2 deg/100 kHz 的 off/common/common+CPE/independent/independent+CPE BER 为
0.012908/0.014107/0.014085/0.016827/0.016832，EVM 为
32.02/33.50/33.45/35.27/35.26%。该单点中 common 的 RX-LO 增量小于 independent，
与 flat 网格反例共同说明拓扑排序依赖信道、DM-RS 跟踪和 phase acquisition。它只完成
预注册的 LO 增量确认，`doesNotReopenBLine=true`；不能用一个 full-stack seed 推翻
paper flat 网格，也不能泛化为公共 LO 已有规格优势。

R12 的可发表结论因此从“单链必然放宽 RX-LO 规格”改为：**公共单 LO 把四支路随机
相位失配压缩成一个理论上可校正的共享状态（oracle 在灾难 seed 为零错），但是否优于
独立 4-LO 由相位获取/周跳与信道空间平均共同决定；简单一参数判决 CPE 不足以保证
跨 realization 的拓扑优势。** 这是一个明确的设计边界，不是预期正结果。

最终兼容性回归通过开关代数、RX-LO PSD/off、五种 ICI-DF 理想零误码、CFO guard 和
PSS vote；R8 默认 smoke 逐位保持 L0/L1/L2/L3=
`0.0129085/0.0303183/0.0302225/0.0129085`、gap=0.0055、L3/L0 IQ 相对误差
`6.01e-8`，目录 `/tmp/type1_phase2/type1_phase2_full_stack_smoke_20260715_141751/`。
因此新增 RX-LO off 默认与 CPE 研究接口没有改变历史接收路径。

### 28.5 文献锚点与论文口径修正

R12 的 flat-channel 反例不是孤立的实现现象。Björnson、Matthaiou、Debbah 的
[TWC 论文](https://doi.org/10.1109/TWC.2015.2420095)以及 Björnson、Matthaiou、
Pitarokoilis、Larsson 的
[EUSIPCO 论文](https://doi.org/10.1109/EUSIPCO.2015.7362822)均区分共同振荡器与
分布式振荡器：独立支路相噪可在空间合并中部分平均，公共相噪则保留为共模状态。
因此论文不再声称“公共单 LO 必然更优”或报告不可识别的规格倍率，而写成**带条件的
架构代价**：开关式单 RF 链强制公共 RX-LO，放弃独立 4-LO 的相噪空间平均收益；一个
DM-RS 锚定、每符号 1 实参 CPE 可部分缓解共模旋转，但会有可审计的象限周跳。在病态
信道中，权重偏斜和独立行相位造成的跨层泄漏又可使排序反转。最终产物应是
`(sigmaPhi,Bpll,cond(Hhat))` 的条件拓扑图，而不是单一 `xA` 数字。

## 29. R13 P_acq(SNR) 与多帧非相干累积预注册（实验运行前冻结）

### 29.1 场景、配对和检测臂

正式统计固定 100 个 TDL-A realization（seeds 20262001--20262100），SNR 网格固定为
`{-20,-16,-12,-8,-6,-4,0,8,14,20,26}` dB。信道为 R11 main 的 TDL-A 100 ns、
Tx/Rx 指数相关 0.3、多用户半幅 CFO、截断到 +/-4 samples 的定时偏移，以及
25 dB 隔离、20 ns 建立、20 ps transition jitter、100 ps boundary jitter；fast settling
jitter 为零，RX-LO 为 off。不得在看见 waterfall 后移动 SNR 点或更换 realization。

每个 seed 只生成一次固定五帧物理信号和一次独立复高斯噪声序列。所有 SNR 由同一
`signal + a(SNR)*noise` 基底构造；开关 on/off 也共用物理信号与噪声。开关 on 的信号
和噪声分别经过**同一随机开关轨迹**，在复相关域线性合成后才取绝对值。正式运行前
必须通过两道等价门：自写复相关与 `nrTimingEstimate` 幅度相对误差不超过 `1e-5`，以及
`S(x+a*n)` 与 `S(x)+a*S(n)` 相对误差不超过 `1e-5`。这样多帧累积不会重复同一噪声，
也不会把两次独立采集误当成配对。

四个 on-switch 检测臂为：`combined1`（现有四链单帧非相干合并）、`vote1`（R11 的
至少两链峰位/NID2 一致，否则回退 combined）、`accum2` 和 `accum4`（分别把同一候选
frame phase 上 2/4 个连续帧的 PSS 相关功率非相干相加）。仅执行 PSS 获取，不运行
PBCH、信道估计、RZF 或 BER 解码。在 20 dB 另做 `combined1` 的 switch on/off 成对
对照，量化“经开关同步”的 acquisition 代价；该对照不改变主曲线场景。

### 29.2 成功、失败三分类和统计量

成功定义在运行前固定为：`NID2==mod(PCI,3)` 且循环 timing error 的绝对值不超过最大
CP（当前 88 个 30.72-MS/s samples）。对失败按以下互斥顺序分类：

1. `windowClip`：正确 PSS 的完整相关窗口不在已采集样本内；
2. `miss`：窗口完整，但正确 NID2、真值 timing +/-88 samples 内的 peak-to-background-
   median 小于既有 Track 门限 8 dB；
3. `falsePeak`：真值峰达到 8 dB 可见门限，检测器仍选择了错误 NID2 或远端 timing。

`vote1` 的可见性取四条单链真值 PMR 的第二大值，因为投票按定义需要至少两条链；其余
臂直接用相应累积合并曲线。8 dB 只用于失败归因，不参与成功判决，也不在看数后调整。

每一点报告成功率和 Wilson 95% CI。`vote1/accum2/accum4` 分别与 `combined1` 做同 seed
精确双侧 McNemar，记录 rescue、loss 和 p；只在 `rescue>loss 且 p<0.05` 时称该点显著
改善。报告必须分开：(a) 低 SNR 噪声限制 waterfall；(b) 14/20/26 dB 高 SNR 平台及
falsePeak/miss/windowClip 构成。不得用高 SNR 平台代表噪声灵敏度，也不得从单个 SNR
外推 acquisition 可靠性。

## 30. R13 获取曲线、多帧累积与经开关同步代价（2026-07-15）

### 30.1 实现与等价门

新增 `type1_pss_complex_correlation` 和
`type1_run_phase2_pss_acquisition_statistics`。前者在取绝对值前保留复相关，因此可把
同一 TDL realization 的 signal/noise 相关严格配对到所有 SNR；显式 `Windowing=0` 后，
其幅度相对 `nrTimingEstimate` 的误差为 `6.55e-16`。固定随机轨迹下，开关对
`signal+a*noise` 的整链线性拆分误差为 `2.38e-16`。两项均远低于预注册 `1e-5` 门。

为控制内存，五帧连续物理信号按四个 10 ms 获取段处理；每段包含完整 frame-phase
搜索区和一个 PSS reference 尾长，除首段外先用一个 slot 的真实连续输入预热开关状态。
四段共享同一 TDL 信道且使用独立连续噪声/开关随机样本，不重复第一帧噪声。每 seed
只做 PSS 复相关，不调用 PBCH、DM-RS、RZF 或 BER 路径。4-seed smoke 先通过后才运行
冻结的 100-seed paper 档。正式目录为：

```text
/tmp/type1_phase2/type1_phase2_pss_acquisition_20260715_144558/
```

### 30.2 noise-limited waterfall 与 implementation-limited plateau

100 个 realization 的成功数如下；分母均为 100：

| SNR (dB) | combined1 | vote1 | accum2 | accum4 |
|---:|---:|---:|---:|---:|
| -20 | 1 | 1 | 1 | 1 |
| -16 | 1 | 1 | 3 | 6 |
| -12 | 3 | 3 | 13 | 32 |
| -8 | 14 | 15 | 35 | 54 |
| -6 | 26 | 29 | 49 | 57 |
| -4 | 35 | 36 | 55 | 62 |
| 0 | 41 | 44 | 57 | 63 |
| 8 | 52 | 53 | 63 | 68 |
| 14 | 52 | 57 | 65 | 69 |
| 20 | 52 | 57 | 66 | 70 |
| 26 | 52 | 58 | 66 | 70 |

单帧 combined 在 8--26 dB 完全固定为 52%，其 20 dB Wilson 95% CI 为
`[0.423,0.615]`：这不是噪声 waterfall，而是 realization/远端峰竞争平台。4 帧累积
把 -8 dB 提到 54%（CI `[0.443,0.634]`），20 dB 提到 70%
（CI `[0.604,0.781]`）；但 20--26 dB 仍固定 70%，所以多帧累积**抬高但没有消除**
implementation ceiling。不得把 combined 从约 50% 到 accum4 约 50% 所对应的横向
SNR 差读成纯处理增益：累积同时改变噪声峰和 realization 假峰的排序，曲线不是只有
AWGN 的平移关系。

### 30.3 成对显著性与默认接收机处置

高 SNR 的 paired rescue/loss 和精确双侧 McNemar 为：

| SNR | vote1 | accum2 | accum4 |
|---:|---:|---:|---:|
| 14 dB | 5/0, p=0.0625 | 13/0, p=2.44e-4 | 17/0, p=1.53e-5 |
| 20 dB | 5/0, p=0.0625 | 14/0, p=1.22e-4 | 18/0, p=7.63e-6 |
| 26 dB | 6/0, p=0.0313 | 14/0, p=1.22e-4 | 18/0, p=7.63e-6 |

因此 R11 vote 在 100 seeds 下仅 26 dB 达到预注册显著性，14/20 dB 仍未达到；不能写成
全平台显著改善。2/4 帧从 -12 dB 起相对 combined 大多数点显著，且 14--26 dB 无 loss。
没有预注册 accum4-vs-accum2 的直接检验，故只报告各自相对 combined 的结果。现有
`type1_analyze` 默认仍为 combined；是否把多帧 acquisition 集成到实时状态机，等待 R13
审议，不以本轮离线数据自行改默认。

### 30.4 失败归因与 switch on/off 对照

在 14/20/26 dB，combined 的 48 个失败和 accum4 的 31/30/30 个失败全部为
`falsePeak`，`miss=0`、`windowClip=0`。在 -20/-16/-12 dB，combined 的 miss 为
89/85/69，说明低端确为噪声限制；到 -8 dB 转为 falsePeak/miss=51/35，开始进入
实现限制。所有臂、所有点的 windowClip 均为零，符合完整窗口构造不变量。

`vote1` 的可见性按四条单链真值邻域 PMR 的第二大值定义；纯噪声时对多个 timing 样本
和四链取次序统计会抬高该值。因此 vote 在低 SNR 的 falsePeak/miss **细分仅是固定口径
诊断**，不应用于器件或噪声规格反解；主区域判定采用 combined/accum 曲线。该限制在
看到数据后没有通过更换门限掩盖。

20 dB 同 realization/signal/noise 下，switch-on combined 成功 52/100，switch-off
成功 75/100（Wilson 95% CI 约 `[0.657,0.825]`）；off 相对 on 的 rescue/loss 为
24/1，精确 McNemar `p=1.55e-6`。所以当前 25 dB 隔离、20 ns 建立、两类边界抖动的
**经开关同步代价为 23 percentage points，且成对显著**。反向 1 例说明开关改变支路
权重和峰竞争，不能逐 realization 假定 off 必优；该差值是整套 switch-on 模型的净代价，
不能归因给单一隔离度或建立时间参数。

R13 由此关闭两个问题：低 SNR waterfall 与高 SNR realization 平台已被分离；标准的
多帧非相干累积能显著抬高平台但不能消除假峰。下一步 R14 应在固定 acquisition 口径下
做论文级 TDL 多 realization 最终 BER/EVM 曲线，不能用“只保留成功 seed”隐藏 30%
残余获取失败；获取失败必须作为 outage 单独报告或由明确的 acquisition gate 排除。

## 31. R14 TDL 最终曲线与开关代价分解预注册（实验运行前冻结）

### 31.1 R13 审议文字勘误

R13 裁决正文把失败分类写成“6 dB PMR”，但冻结代码、§29 预注册和正式 MAT 的字段
`pmrThresholdDb` 均为既有 Track 门限 **8 dB**。高 SNR 所有失败的 PMR 均超过 8 dB，
所以 `falsePeak=48, miss=0, clip=0` 与三机制结论不受该笔误影响。R14 不修改 R13
阈值，也不重写已经验收的原始矩阵。

### 31.2 TDL paper-stop 与 outage 口径

R14 把 R4/R6 的隔离开关损伤场景从固定 flat anchor 换成 TDL-A 100 ns、Tx/Rx 指数
相关 0.3；用户 CFO/定时/功率/相噪保持理想，只研究 TDL 下的 fast-settling ICI 与
ICI-DF。每点按固定顺序尝试 seeds 20263001--20263032，至少需要 10 个**标准与 DF
均成功获取/解码**的配对 realization。达到以下任一条件才停止：

- 标准和 DF 都累计至少 100 raw bit errors；或
- 配对有效 bits 达到 `1e7`。

到 32 个 seed 仍未满足时标记 `paperCriterionMet=false`，不得外插或称论文级灵敏度。
每个尝试 seed 的 standard/DF acquisition failure、错误标识、条件 BER、EVM 和
`cond(Hhat)` 全部保存；outage 报尝试数分母上的 Wilson 95% CI，条件 BER 只用配对成功
seed，并同时报告 TDL-seed median/range。二者不得相加成一个含义不明的“总 BER”。

### 31.3 固定曲线与包络网格

20 dB、fast fraction 0.6、tauC=1 us 上共用同一批 link，跑
`Q={0,6,12,24}, iteration=1` 与 `Q=12, iteration={2,3}`；SNR 网格沿用 R4 的
`{-12,-10,-8,-4,0,4,8,12,16,20,24}` dB，接收机固定 Q=12、3 次 soft DF。
器件包络沿用 R6 主网格 `fast={0,.2,.4,.6,.8}`、
`tauC={0,8 ns,100 ns,1 us}`，并只在 1 us 加密 `{.5,.7,.75}`；不把加密点扩散到
其他 tauC 后再挑阈值。genie-beta 只作为 settling 可逆上界，不参与停止条件。

集成边界图使用两种不混量纲的面板：(a) R14 隔离 TDL 上同 seed 标准/DF 条件 BER
配对；(b) 已冻结 R11 received-drive MAT 上 L1/DDCE/received/L3 的同 seed BER 阶梯。
不把 residual-power capture、relative BER reduction 和 gap closure 画在同一纵轴。

### 31.4 20 dB 开关获取代价三分解

复用 R13 seeds、TDL、信号和噪声定义，比较同一批 `combined1`：

1. `switchOff`：四路全数字物理 RX，不交织；
2. `idealSwitchOn`：保留 4 相交织/122.88-to-30.72 MS/s 虚拟采样，但 isolation=Inf、
   rise=0、transition/boundary jitter=0；
3. `impairedSwitchOn`：R13 的 25 dB、20 ns、20 ps、100 ps 模型。

`off-ideal` 的成功率差定义为**交织采样结构净代价**，`ideal-impaired` 定义为**已建模
模拟损伤净代价**；两段都报告配对 rescue/loss 和精确 McNemar。只在理想臂重新生成的
switch-off 成败/timing/NID2 与 R13 原始矩阵逐 seed 完全一致后，才允许发布分解。

## 32. R14 TDL 最终曲线与集成边界结果（2026-07-15）

### 32.1 理想开关归因：23 pp 几乎全部来自已建模模拟损伤

正式结果位于：

```text
/tmp/type1_phase2/type1_phase2_r14_switch_attribution_20260715_155149/
```

首次实现错误地让 `nrTimingEstimate` 在“10 ms 搜索帧 + reference 尾长”的全部相关输出
上选峰，因而在 100/100 发布门被 regenerated-off/R13 不一致断言拒绝。修正为只搜索
前 10 ms frame phase 后重跑，100 个 seed 的 switch-off success/timing/NID2 与 R13
逐项一致，`offRegressionPassed=true`。该失败结果没有保存为正式归因。

| 20 dB acquisition 臂 | 成功数 | Wilson 95% CI |
|---|---:|---:|
| switch off | 75/100 | [0.657, 0.825] |
| ideal switch on | 76/100 | [0.668, 0.833] |
| impaired switch on | 52/100 | [0.423, 0.615] |

- 交织结构净代价 `off-ideal=-1 pp`；off 相对 ideal 的 rescue/loss=`0/1`，McNemar
  `p=1`，没有可测结构惩罚，反而有一个峰排序反向样本；
- 已建模模拟损伤净代价 `ideal-impaired=24 pp`；ideal 相对 impaired 为 `25/1`，
  `p=8.05e-7`；
- 两段代数相加为原 R13 总代价 `23 pp`，off/impaired=`24/1,p=1.55e-6`。

所以 P1 的归因从“开关总体造成 23 pp”升级为：**四相交织采样本身在当前带宽/采样率
下没有可测 acquisition 代价；25 dB 泄漏、20 ns 建立和 20/100 ps 两类抖动的联合
模型贡献约 24 pp 净代价。** 这是联合归因，尚不能在不做单变量消融的情况下继续拆成
某一个器件参数的责任。

### 32.2 paper-stop、outage 与 TDL 统计完整性

正式最终曲线位于：

```text
/tmp/type1_phase2/type1_phase2_r14_final_paper_20260715_155216/
```

core、11 个 SNR 点和 23 个包络点全部为 10/10 配对有效，标准/DF 都超过 100 errors，
`paperCriterionMet=true`；全部 acquisition outage 为零。每点因此在达到 error stop 前
至少平均 10 个独立 TDL realization，没有用单个高 BER realization 提前停止，也没有
通过丢弃同步失败 seed 压低 BER。R13 的 52% 平台在该隔离场景消失，说明 **TDL 本身
不是 full-stack 假峰平台的充分条件**；平台来自 TDL 与多用户 CFO/定时/功率/相噪及
impaired switch 的联合峰竞争。该句是受控场景差分推断，不声称已分解每项贡献。

### 32.3 Q、迭代与 SNR：正增益保留，但从 38--58% 缩到约 3%

20 dB、fast=0.6、tauC=1 us 的聚合结果：

| 接收机 | standard BER | DF BER | 相对降低 | 改善 seed |
|---|---:|---:|---:|---:|
| Q=0, iter=1 | 0.165672 | 0.165416 | 0.15% | 6/10 |
| Q=6, iter=1 | 0.165672 | 0.162920 | 1.66% | 9/10 |
| Q=12, iter=1 | 0.165672 | 0.162381 | **1.99%** | 10/10 |
| Q=24, iter=1 | 0.165672 | 0.163511 | 1.31% | 10/10 |
| Q=12, iter=2 | 0.165672 | 0.161513 | 2.51% | 9/10 |
| Q=12, iter=3 | 0.165672 | 0.160462 | **3.15%** | 9/10 |

Q=12 仍是偏差/方差折中最优，Q=24 因参数方差回落；迭代仍单调提升聚合收益。但
flat anchor 的 38--58% 恢复不能迁移为 TDL 平均声称。Q12/3 次的 per-seed 标准 BER
范围 `[0.1016,0.5006]`，DF `[0.0957,0.5008]`；唯一反噬 seed 20263006 是
`0.500581→0.500823` 的近随机判决 realization，其 `cond(Hhat)` 统计为
`[18.4,103,597]`。BER 与 cond 中位的样本相关约 0.58，但存在相近 cond 而 BER 正常的
seed，所以 cond 只能是风险特征，不是充分 outage 判据。

SNR 扫描中，−12/−10/−8 dB 的相对降低仅 0.045/0.028/0.088%；随 AWGN 下降，
4/8/12/16/20/24 dB 增至 1.24/1.98/2.65/2.95/3.15/3.26%。所有点 outage=0。
因此算法没有把噪声限制区伪装成 ICI 恢复；高 SNR 收益饱和在约 3%，瓶颈转向 TDL
深衰和信道估计。

### 32.4 TDL 器件包络：PSD 相关时间仍决定增益符号

fast=0 时四个 tauC 点逐位相同，验证 tauC 在零抖动下为空操作。主要结果为：

- tauC=0：fast=0.4/0.6/0.8 的相对变化为 `-0.22/-0.28/-0.24%`，轻微反噬；
- tauC=8 ns：对应约 `-0.15/-0.28/-0.21%`，仍无有用带状结构；
- tauC=100 ns：fast=0.2--0.8 均为正，但仅 `0.21--0.64%`；
- tauC=1 us：fast=0.2/0.4/0.5/0.6/0.7/0.75/0.8 的相对降低为
  `1.64/3.56/3.34/3.15/2.70/2.58/2.46%`，在 fast≈0.4--0.5 达峰，之后判决污染
  抵消更多捕获能量。

known-beta 逆滤波在所有 fast/tau 点约为 `BER=0.01006`，显示 settling 信息仍大体可逆；
但它会逆滤波噪声，单 realization 不保证逐点低于标准接收机，故只作代数/状态上界。
TDL 的 fast=0 标准 baseline 已为 0.0565，高于 R6 的 BER≤1e-2 目标，因此**不能从
本曲线反解新的 1.3x 器件容限倍率**。R6 flat 包络保留为机制与器件锚点，R14 则限定其
在频选/深衰信道下的端到端可兑现收益。

### 32.5 集成边界与下一步

`phase2_r14_integration_boundary.png` 左图保留全部 10 个 TDL seed 的标准→DF 配对，
包括 50% BER outlier；右图直接使用冻结的 R11 received-drive MAT，两个 full-stack
seed 的 received gap closure 为 10.89%/40.65%，跨 realization 不稳定且统一门失败。
图中没有混画 capture、relative reduction 与 gap closure。

R14 结论是：**隔离 TDL 上算法仍有可重复但温和的正恢复，实际可兑现量约 3%；进入
多用户 full stack 后又受信道估计质量与模拟状态可观测性双门控制。** B 线冻结维持，
默认实时接收机不改。Phase 2 仅剩 R15：OTA 多点归一化增量、文档定稿和提交整理；
在用户验收前不提交 Git。

## 33. R15 OTA 多点归一化交叉验证：预注册（2026-07-15）

R15 在查看新板卡数据前冻结以下口径。RX gain 取 `25/30/35 dB` 三档，每档至少保存
5 段彼此独立、持续时间不少于 20 ms 的 raw122 capture；每段必须同时满足正确 NID2、
PBCH CRC/MIB、理想数字开关路径平均 EVM 不超过 20%，且记录 gain、timestamp、sequence
和采集 attempt。未通过 gate 的段保留为失败审计，但不进入 OTA/离线增量分布。

每个合格 capture 的**同一份 raw122**分别走理想模型和 Phase 2 固定损伤模型：
`isolation=25 dB`、`rise=20 ns`、`transition jitter=20 ps`、`sampling-boundary
jitter=100 ps`，fast settling jitter 为零；随机流 seed 由 capture 序号唯一派生，禁止
两次独立采集冒充配对。主指标为 EVM 残差功率的归一化增量

\[
 \Delta_{EVM^2}=\frac{EVM_{imp}^2-EVM_{ideal}^2}{EVM_{ideal}^2}.
\]

选择功率而不是 RMS EVM，是因为独立残差在功率域相加。`cond(\hat H)` 中位/P95 的
归一化增量只作次级机制诊断，不承担验收：它包含信道估计插值伪影，且对深衰离群值
敏感。BER 在理想路径为零时分母不可识别，同样不作为归一化主指标。

离线预测对每段 capture 的理想路径 `snrNullDb` 四链中位数做 matched-SNR TDL-A
配对仿真，理想/损伤共享信号、信道、AWGN 与 seed，每段至少 10 个有效 TDL seed，报告
其中位增量。验收规则预注册为：(1) OTA 主增量与其 matched-SNR 离线中位预测的符号
一致率至少 90%；(2) 先分别对 OTA 和 matched-SNR 离线主增量取总体中位数，二者同号，
且正值比值落在 `[0.5,2]`。若 baseline EVM 为零/非有限、PBCH/PSS gate 失败或离线
acquisition outage，该配对不得静默计入；失败原因必须逐段记录。rxGain 不是 SNR 的
理论替代变量，最终匹配只使用实测 `snrNullDb`。

## 34. R15 实测结果与冻结裁决（2026-07-15）

### 34.1 板卡采集与可审计资产

TX 连续发送共享 Type-A 10 ms reference，RX 使用 25/30/35 dB 三档 gain，各采 5 段
20 ms raw122。15/15 段均在第一次 attempt 通过正确 NID2、PBCH CRC/MIB 和 ideal
EVM≤20% gate；ideal 路径 15/15 均为 raw BER=0。采集结束后显式执行
`type1_tx_stop`，返回 `cyclic TX disabled ret=0`。正式目录为：

```text
/home/bupt/tools/matlab_test/nr4x4_type1/data/type1_r15_ota_20260715_190556/
```

目录含 15 份 raw122、逐段 meta、同段 ideal/impaired paired MAT、manifest、正式结果
`type1_phase2_r15_ota_cross_validation.mat`（SHA-256
`132a3c281711468f1c21dc4744ee88228cce1db06f4dbf0e936833e66b24db76`）和不覆盖原结果
的 `type1_phase2_r15_metric_audit.mat`。整组约 1.4 GiB，不进入 Git。

### 34.2 预注册 EVM² 门：符号通过，倍率边界失败

15 段都使用同一份 raw122 先后注入 ideal 与 `25 dB/20 ns/20 ps/100 ps`，每段再以
实测 ideal `snrNullDb` 配 10 个有效 TDL-A seed。结果：

- ideal/impaired 两支 15/15 均保持 PSS/PBCH 正常、raw BER=0；
- EVM² 归一化增量 15/15 为正，matched-SNR 离线预测也 15/15 为正，符号一致率
  **100%**，通过 ≥90% 门；
- OTA 增量中位 0.83035，离线增量中位 0.39315，倍率 **2.1120**；超过预注册上限
  2.0 约 5.6%，所以正式字段 `acceptancePassed=false`，不得写成 R15 全门通过。

三档 gain 的 EVM² 中位 OTA/离线/倍率分别为 25 dB：0.2120/0.4936/0.430；30 dB：
1.0129/0.3699/2.738；35 dB：0.7592/0.3199/2.373。实测 SNR 范围在三档间明显重叠：
25 dB 为 35.1--42.0 dB、30 dB 为 32.9--43.4 dB、35 dB 为 40.0--40.8 dB。因此本轮
满足“3 个 gain 档”，但**不等于 3 个分离的 SNR 点**；不能据此声称跨 SNR OTA
标定已完成。数据说明方向/量级相关性成立，但仅按 SNR 的 TDL 预测不能把 OTA 段间
baseline 残差组成完全归一化。

### 34.3 双口径审计与最终裁决

R15 指令字面写的是对指标做 `(impaired-ideal)/ideal`。若指标取已有文档一直报告的
RMS EVM，完全由同一正式 MAT 代数换算，不换 seed、不重跑链路，则 OTA/离线中位为
0.35291/0.18032、倍率 **1.9571**，符号一致率 100%，字面门通过。项目方在看数前因
“独立残差在功率域相加”把主指标预注册为 EVM²，因此两个门结果相反。审计脚本
`type1_audit_phase2_r15_metrics` 同时保存两者，并设置 `adjudicationRequired=true`。

R15 最终裁决固定使用 EVM²：它既是看数前指标，也是新增误差功率的自然线性域；RMS
变换是凹压缩，会对更大的 OTA 增量施加更强压缩，恰好把 2.112 压到 1.957。因此
**不事后切换 RMS EVM，不修改 2× 门、seed 或离线模型**；正式结论为 ratio no-go。
`adjudicationRequired=true` 保留为裁决前审计资产，不覆盖历史 MAT；裁决结果由本节和
`REVIEW_VERDICTS.md` 固化。

### 34.4 缩放后的 OTA 主张与 Phase 2 关闭

本轮实测只能定义为：**高 SNR（33--43 dB）单簇、功能+趋势级 OTA 交叉验证；15/15
方向一致且两路径零误码，离线模型对高 SNR 损伤误差功率偏乐观约 2×。** 它把 Phase 1
单点锚点强化为 15 段簇，但不是多 SNR 定量标定，禁止使用“跨 SNR 标定至 ≤2×”或
“三 SNR 档通过”等措辞。

Phase 2 以该缩放主张正式关闭。`phase2-freeze-2026-07-15` 表示实验工作和审计资产
冻结，并不表示所有预注册门通过；tag 说明必须显式包含 EVM² ratio no-go 和高 SNR
单簇边界。若以后需要 5--25 dB 的多 SNR 定量主张，应使用外部衰减器或 TX 功率步进
重采；这是论文增强项，不阻塞 Phase 2 关闭，也不回改本轮冻结结果。

## 35. README 独立工程首页重构（2026-07-15）

本轮不修改算法、实验数据或冻结结论，只重构工程入口文档并补齐仓库内可复现资产：

- `README.md` 改为不依赖交接文档也能理解的独立首页，增加工程目标、物理边界、实时/
  离线双路径架构、快速入口和文档索引；
- Phase 0、Phase 1、Phase 2 改为同级章节，按“理想回归 → 静态损伤分类 → 时变损伤/
  恢复/集成边界”组织，不再把 Phase 0 错列为 Phase 1 子目录；
- 明确实时 MEX 已下放 DMA/ring、栅格、Type-1 DM-RS、4×4 RZF、QPSK 判决和 BER/EVM
  累积；Phase 2 的 ICI-DF、DDCE、CPE、统计扫描仍属于离线 MATLAB 研究路径；
- 使用 `tools/render_architecture.py` 生成正式架构图，并把 Phase 2 freeze 对应的七张结果图
  收入 `docs/images/` 后在 README 原位引用，避免“正文提图但仓库不可见”；
- 删除过时的单轮 60 s OTA 流水账和旧逐帧精度段，保留仍有意义的实时能力边界；Phase 1/
  Phase 2 的关键证据、门禁与 no-go 均按冻结口径重新归纳，R15 仍严格写为 EVM²
  ratio=2.112 no-go、高 SNR 单簇趋势锚点。

因此本轮结论仅是文档可读性、可追溯性与复现入口得到修复；不得据此声称新增实验结果
或 Phase 2 算法已经进入实时 MEX。

## 36. R16 前置：Phase 3 Part A 平台与退化回归（2026-07-15）

### 36.1 冻结实现边界

本轮严格按 `PHASE3_PLAN.md §7` 只实现 Part A，不启动端口选择或性能扫描。新增平台把
M 根物理端口在每个 raw 样点先坍缩为唯一标量

\[
y[k]=\sum_m S[m,q(k)]r_m[k],
\]

然后才按 N 个码相去交织。`type1_phase3_single_chain` 只返回 `Nsample×1` stitched 流
和由该标量流重排得到的 N 条 virtual 流，不暴露逐端口数字输出。

`type1_phase3_make_schedule/type1_phase3_validate_schedule` 使用规范张量
`A[m,n,q]=S[m,n]1[q=n]`：S 管 `Htilde=S^T H`，A 管 N 相码周期、链覆盖、每端口
占空比、循环切换次数、相位归属和可选 settling-interval 硬门。同一端口可在不同码相
进入不同虚拟链；同一码相给多个链标签的扇出会以 `type1:Phase3IllegalFanout` 拒绝。
多个天线在同一码相汇入唯一标量求和节点是冻结信号模型允许的 BABF，不属于扇出。

M 端口 TDL-A 由 `type1_phase3_make_tdl_a_channel` 单独实现，避免改变 Phase 2 冻结路径。
默认端口为半波长 ULA，RX 空间协方差固定由
`R(m1,m2)=J0(2*pi*|d_m1-d_m2|/lambda)` 生成；相关性不能脱离端口位置单独调参。

### 36.2 四门结果与复现审计

RX 服务器 MATLAB R2024a、seed `20260716` 的正式目录为：

```text
/home/bupt/type1_offline_captures/type1_phase3_part_a_20260715_201908/
```

`phase3_part_a_r16.mat` SHA-256 为
`0e0281db0ac7d941627107db618fec283128aa4a130d478bcfc5cb2d666991fb`。两次独立输出的
`result.report` 满足 `isequal=1`。结果如下：

| 预注册回归 | 结果 |
|---|---|
| M=N=4、S=I 退化 | 旧/新 stitched 逐位一致=1，virtual 逐位一致=1，数字化输出列数=1 |
| 理想开关与等效信道 | M=8 的 `v=rS` 相对误差=0，`Htilde=S^T H` 相对误差=`1.6872e-16` |
| 占空比守恒 | `sum_q A=S`、逐端口 duty、总 assignment 均精确；`Dmax=1` 超限按预期拒绝 |
| 非法并接/扇出拒绝 | 同一端口/同一码相写入两个链标签，以 `type1:Phase3IllegalFanout` 拒绝 |

M=8 端口位置为 `[0,0.5,...,3.5] lambda`，J0 相关矩阵最小特征值 `0.641113`，TDL
输出维度 `256×8`、抽头张量 `8×4×23` 均通过。为确认新增层未污染冻结基础设施，远端
同时重跑 `type1_validate_switch_impairments` 与 `type1_validate_channel_models`：两者通过；
后者该 seed 的四层 TDL BER 为 `[6.28e-6,5.72e-4,3.39e-4,2.70e-4]`，只作兼容回归，
不是 Phase 3 性能结果。

### 36.3 当前可得结论

R16 前置资产证明 A/S 映射、严格单标量链路、M 端口几何信道及四项拒绝门可复现，且
`M=N,S=I` 没有改写现有系统。它**不证明 M>N 的波束成形、SINR、速率或净增益为正**；
在专家完成 R16 裁决前不进入 Part B 扫描，也不改变 Phase 3 三个 go/no-go 门。

## 37. 面向通信同行的独立系统说明（2026-07-15）

新增 `SYSTEM_EXPLAINER.md`，本轮不修改模型、算法、运行结果或 R16 资产。该文档不采用
Phase 1/2 编年结构，而按“单链虚拟化原理 → 帧接收流程 → 用户/信道/开关/本振/同步/
实时计算非理想性 → 补偿效果 → OTA 边界 → M>N 后续工作”组织。

文档对 reference、虚拟 RF chain、PSS/PBCH/SSB、CFO、DM-RS、RZF、TDL-A、开关
瞬态、OU/AR(1)、采样边界位移、RX-LO/RX-PLL、CPE、ICI-DF、direct RX、MEX、
pending/dropNew、BABF/FAS/DBF/HBF 等术语在首次出现时解释，并提供集中术语表。

数字沿用冻结口径：逐用户 CFO 补偿、相关建立抖动、flat 与 TDL 的 ICI-DF 增益差异、
PSS 假峰平台、R15 EVM² 2.112 ratio no-go 和 Phase 3 Part A 仅完成代数地基。特别注明
当前 TDL 多普勒未启用、自定义上行 SSB 只是同步脚手架、当前 OTA 仍为四路 IQ 驱动的
数字开关模拟，避免把计划功能或算法验证写成物理原型能力。

为验证新增复现索引，RX 服务器在无 `sudo`、不访问板卡条件下 fresh 运行
`type1_run_offline_multiuser`，输出目录
`/home/bupt/type1_offline_captures/type1_offline_multiuser_20260715_231828/`。未补偿 BER
`[0,0.0137,0.2731,0.2587]`、补偿后 `[0,5.87e-5,9.49e-4,0]` 与冻结引用一致；三帧均
触发接近 ±1 kHz 混叠边界的告警，进一步确认说明文档没有隐去估计器适用范围。

## 38. R17 预注册：M=8 穷举标尺与门 1（2026-07-15）

R16 通过后放行 Part B，但本轮只执行 `PHASE3_PLAN.md §7.5` 门 1，不实现贪婪、松弛或
NetGain。为使“穷举”具有可验证含义，冻结可行集为 M=8、N=4、每条虚拟链恰好 2 根
端口、每根物理端口只属于 1 条链（`Dmax=1`）。四条链有标签、链内端口无顺序，因此
精确候选数为 `8!/(2!^4)=2520`；本轮结论不得外推到 `Dmax>1` 的码叠加空间。

每个候选在 51 个固定 RB 代表子载波上优化
`min_u mean_k SINR_dB(k,u)`，选出的同一个宽带 S 再在全部 612 个占用子载波上评价。
接收模型为 `v=S^T Hx+S^T n`，每端口噪声独立且方差相同，所以必须使用
`Rn=sigma2*S^T S` 的噪声感知线性 MMSE；禁止把两端口求和后的噪声仍按单端口计算。
M=4 基线为同一 M=8 TDL realization 的前四端口和 `S=[I4;0]`，因此信道、SNR 和 seed
严格配对。SNR 固定 20 dB，TDL seed 固定为 `20261701:20261720`；Gate 1 不加入开关
损伤、扫描开销或 acquisition，它们属于门 3。

paper 门在看结果前冻结为同时满足：

1. 20 个配对 seed 中至少 16 个（80%）的全 612-tone 增益为正；
2. 配对增益中位数严格大于 0 dB；
3. 把零/负增益保守视为失败的单侧精确符号检验 `p<0.05`。

同时报告固定相邻端口配对 `[1,2]/[3,4]/[5,6]/[7,8]`，用于区分“增加四根端口”与
“端口选择”本身；该固定臂不参与门。smoke 只准调试代码，不能改判 paper 门。

### 38.1 实现与独立代数检查

`type1_phase3_enumerate_pair_partitions` 生成 2520 个无重复 S，每列和恒为 2、每行和恒为
1；所有候选均通过 Part A 调度验证且单链输出宽度保持 1。`type1_phase3_wideband_metrics`
使用线性 MMSE 误差协方差恒等式 `SINR_u=1/E_uu-1`，并显式带入
`Rn=sigma2*S^T S`。在 3 个候选×7 个复信道音调上，与逐用户直接构造 MMSE 合并器的
SINR 相对误差为 `2.7748e-14`。候选数、唯一性、结构、指标等价和最大值审计全部通过，
五个新增 MATLAB 文件 `checkcode=0`。

### 38.2 paper 结果与 Gate 1 裁决

正式目录为：

```text
/home/bupt/type1_offline_captures/type1_phase3_r17_paper_20260716_000304/
```

正式 MAT SHA-256 为
`92b4ac29800518a2cd16f684c7ac9c70c74e27c1ad7d5d49a4a5ca250271322d`，PNG SHA-256
为 `c8e64c3b1c16130cc9b10219736208c8aa3cc3feda6a9c0a7285d38791cf523e`。另一次 fresh
20-seed 全量重跑的 `preRegistration/validation/summary/perSeed` 四项 `isequal` 均为 1。

全 612-tone 的配对结果为：

| 指标 | 结果 |
|---|---:|
| M=8 穷举优于 M=4 | 19/20 seed |
| min-user SINR 配对增益中位数 | **+2.42018 dB** |
| 增益范围 | `[-0.04973,+4.37325] dB` |
| 配对中位 bootstrap 95% 区间 | `[+1.86328,+3.61266] dB` |
| 单侧精确符号检验 | `p=2.0027e-5` |
| min-user rate 增益 | 20/20 为正，中位 `+0.70238 bit/s/Hz` |
| Gate 1 | **通过** |

20-seed 目标中位数为：M=4 identity `9.4174 dB`、M=8 固定相邻配对 `8.0961 dB`、
M=8 穷举 `11.7864 dB`。固定配对相对 M=4 仅 6/20 为正，中位 `-1.0298 dB`，所以
不能把结果解释为“多四根端口自然产生阵列增益”；正结果依赖端口分组选择。

唯一负例 seed `20261718` 在 51-tone 搜索目标上已经为 `-0.04137 dB`，全 612-tone 为
`-0.04973 dB`。因此负例不是代表音调抽样引起的符号翻转，而是冻结约束“每链必须 2 根、
全部 8 端口必须使用”在该 realization 确实不如四端口基线。它直接支持 Gate 2/3 中允许
关停端口或优化每链端口数，禁止声称 M=8 逐 realization 必然占优。

### 38.3 本轮结论边界

R17 只关闭 `Dmax=1`、每链 2 端口的理想开关 Gate 1，证明在几何相关 TDL-A 上存在
可重复的受约束端口选择增益。它没有覆盖一端口多码相的 `Dmax>1`、开关建立/泄漏、
acquisition、端口扫描开销、贪婪/松弛算法或 NetGain；上述项目仍分别属于 Gate 2/3。

## 39. R18：扩大可行集、在线算法与码叠加 Gate 2（2026-07-16）

### 39.1 预注册口径与实现

本轮严格使用 R17 的 `20261701:20261720`、20 dB、几何相关 TDL-A 和同一噪声感知
MMSE 指标。Gate 目标冻结在 51 个 RB 代表频点；选出的同一个 S 另在全部 612 个占用
子载波上做迁移审计，612 点结果不得反过来改写 Gate。

- F1 把每根端口编码为 `{off,c1,c2,c3,c4}`，要求四链均覆盖且 `Dmax=1`，按容斥精确
  生成 **166824** 个唯一调度；R17 的 2520 个满载配对全部属于 F1；
- F2 允许每天线进入至多两条不同码相的虚拟链，只运行算法，不声称穷举最优；
- 贪婪先在全部 `8P4=1680` 个满秩一端口覆盖初始化中选最好者，再只接受严格提高
  min-user SINR 的边；因此轨迹逐步单调且允许端口保持关闭；
- 松弛臂用 `fmincon` 对 `[0,1]^(8x4)` 的 soft-min 代理做局部连续优化，再投影为满足
  coverage、Dmax 和 `rcond(S^T S)>1e-12` 的二值调度并做坐标精化。该目标非凸，故这里
  明确标为**局部松弛诊断，不是经证明的全局上界**；禁止沿用“松弛必给上界”的表述；
- 固定相邻、R17 穷优、随机可行和 FAS 单端口 Max-SINR 均进入同 seed 基线。

正式运行前发现并修复一个量化器缺陷：第 7 个 paper seed 的 flat/F2 连续量化曾产生
两列完全相同的 S，使 `S^T S` 奇异。该未完成运行整体作废；修复是在量化硬约束中加入
噪声协方差满秩门，不调整任何性能门槛或 seed。修复后从 seed 1 全量重跑。

代数回归结果：F1 基数 166824、R17 超集成立、批量页 MMSE 与逐候选标量实现最大绝对
误差 `5.95e-14 dB`、F1/F2 贪婪轨迹均不下降、`M=N,S=I` 退化误差为 0。批量实现只利用
F1 下 `S^T S` 为对角阵进行白化，没有省略“多天线求和会同时累加噪声”这一守卫。

### 39.2 paper 结果与 Gate 2

正式目录：

```text
/home/bupt/type1_offline_captures/type1_phase3_r18_paper_20260716_003616/
phase3_r18_gate2.mat SHA-256:
14df40eb039a7b440633c708230a9c983b75d75b2922efb070812423704ccb18
```

| 指标（51-tone Gate 口径） | 结果 |
|---|---:|
| F1 穷优相对 M4 增益 | 中位 `+3.72221 dB`，范围 `[+2.25563,+5.34847] dB`，20/20 非负 |
| F1 贪婪胜 M4 | 20/20 |
| F1 贪婪保留穷优增益 | **中位 92.4%**（门槛 80%） |
| F1 局部松弛量化保留率 | 中位 85.6% |
| F2 贪婪相对 F1 穷优 | **中位 −0.203 dB，5/20 为正** |
| F2 松弛量化相对 F1 穷优 | 中位 `+0.053 dB，10/20 为正` |
| flat 下 F2 贪婪相对 F1 | 中位 `0 dB，7/20` 严格为正 |
| Gate 2 | **通过** |

全 612-tone 迁移审计同样给出 F1 穷优 20/20 非负、中位 `+3.69333 dB`；F1 贪婪
20/20 非负、中位 `+3.23837 dB`。因此结果不是 51 个代表频点上的符号翻转。基线中位
增益为：固定相邻 `−1.03255 dB`、R17 强制满载穷优 `+2.42153 dB`、FAS 单端口
`+0.37834 dB`、随机 `−0.97292 dB`。

**裁决边界**：Gate 2 只支持“F1 的关停自由度修复 R17 反例，在线贪婪可稳定保留大部
分穷优增益”。它不支持“Dmax=2 码叠加有稳定额外增益”的头条：F2 贪婪在 TDL 和 flat
均未形成正中位增量；松弛量化的 `+0.053 dB` 很小、仅 10/20 为正，且不是全局上界。

另一次完整 R18 运行与正式资产的 `perSeed/preRegistration/validation` 三项均
`isequal=1`，证明上述逐 seed 数据不依赖运行次序。

## 40. R19：M=8 带损伤单链、同步/扫描与 Gate 3（2026-07-16）

### 40.1 冻结模型与 NetGain 定义

R19 只评价 R18 已经定义并成对选出的 M=8 调度，不借本轮结果临时扩展到未经 R18 标定
的 M=12/16。每个 seed 用同一 M=8 TDL 抽取和同一物理端口噪声生成两帧全带宽波形，
再在 122.88 MS/s 标量链中比较 M4、F1 穷优、F1 贪婪和 F2 贪婪。任一码相只有
`y[n]=sum_m c_m[n]r_m[n]` 一列数字化输出。

损伤点在看结果前冻结为：25 dB 隔离、20 ns 10--90% 建立、`fast=0.2`、OU 相关时间
1 us；泄漏相位沿用 Phase 2 的零相位相干约定，不加入 CFO、LO 或新的用户损伤。一个
外部生成的相同 `beta[n]` 序列被四个调度共用，杜绝换调度同时换抖动 realization。
M 端口代数回归得到：M8 中仅开前四端口时与 M4 identity 逐样点误差 0，两端口同相求和
误差 0，标量输出列数 1，OU lag-1 `0.994506` 与理论一致。

专家给出的 `selection gain - impairment - sync/scan` 是概念分解，不能直接把概率、dB
和时间占空比相减。本轮主指标因此预注册为无量纲有效吞吐量

```text
G_eff = P_acq * (1 - scanFraction) * (1 - decodedBER)
```

M4 不需要额外端口扫描；M8 每次更新需多一个 10 ms 扫描帧。主口径冻结为每 100 ms
更新一次（10% 扫描），另报 1 s 更新（1%）敏感性。EVM 质量
`Q=-20log10(EVM_RMS)` 只用于把选择、差分损伤、同步与扫描分别记账，不可覆盖主门。

### 40.2 paper 结果、逐位复现与 Gate 3

正式资产采用第二次 fresh 全量运行：

```text
/home/bupt/type1_offline_captures/type1_phase3_r19_paper_20260716_004011/
phase3_r19_gate3.mat SHA-256:
5685b0cae5027f0ef6da90eba24e8b4a546586a510bba5310ad04b708e273df7
```

| 指标 | M4 | F1 穷优 | F1 贪婪 | F2 贪婪 |
|---|---:|---:|---:|---:|
| 理想开关 acquisition | 19/20 | 20/20 | 20/20 | 20/20 |
| 损伤后 acquisition | **20/20** | **19/20** | **19/20** | **19/20** |
| 损伤后成功帧平均 decoded BER | 3.20% | 1.03% | 1.15% | 1.20% |
| 理想选择 EVM-quality 增益 | 0 | +4.278 dB | +3.616 dB | +3.616 dB |
| 相对 M4 的差分损伤成本 | 0 | 1.457 dB | 1.296 dB | 1.467 dB |
| 含 acquisition+100 ms 扫描的净 EVM-quality | 0 | +2.141 dB | +1.640 dB | +1.468 dB |
| 100 ms 主口径 `G_eff` | 0.9680 | 0.8462 | 0.8452 | 0.8447 |
| 主口径相对 M4 | 0 | **−0.1218** | **−0.1229** | **−0.1233** |
| 1 s 敏感性相对 M4 | 0 | −0.0372 | −0.0384 | −0.0389 |

损伤后唯一的 M8 acquisition 失败是 seed `20261701`，三个由同一 min-SINR 目标导出的
M8 臂均失败；该 seed 的错误帧 BER 约 0.5，但主统计把它作为 acquisition outage 而不是
成功帧 BER。其余成功 realization 上，选择后的 BER/EVM 明显优于 M4，说明头room 未在
模拟损伤中消失；真正吞掉净吞吐量的是未进入目标函数的同步失效，再叠加扫描占空比。

本轮最初把 Gate 3 单独写成 no-go，专家 R18/R19 合并审议指出这会遗漏 §7.4 的原始
SINR/dB 定义，现按审议**保留修正痕迹并改为双重裁决**：

- 按 §7.4 的 `selection - differential impairment - sync - scan`，F1 穷优仍有
  `+2.141 dB`，所以 **SINR-quality Gate 3 通过**；
- 按后来增加、且更严格的固定 QPSK 有效吞吐量口径，100 ms 和 1 s 更新均低于 M4，
  所以 **fixed-QPSK goodput no-go**。

两者不能互相覆盖。前者证明器件/波束成形增益在损伤后真实存活，后者证明固定 QPSK
已接近饱和，其 BER 收益只有约 2.2%，不足以支付 5% acquisition 差异和 10% 扫描。
因此科学结论是：**M=8 选择本身没有失效，但端到端兑现依赖 AMC 工作点、同步统计和
扫描摊薄。** 本轮没有评估 M=12/16，因而不得把 fixed-QPSK no-go 外推成“所有 M 均负”。

两次独立 20-seed 全波形运行的 `ideal/impaired/betaMeta/summary/validation` 五项均
`isequal=1`。第一次目录为 `.../type1_phase3_r19_paper_20260716_003640/`；fresh 复现没有
覆盖旧资产或挑选更有利运行。

最终部署版本重新运行 R16/R17/R18/R19 四组代数回归，结果均通过；远端全部 15 个
`type1_phase3_*.m` 的 MATLAB Code Analyzer findings 为 0，两个 README 结果图 SHA-256
分别为 `2adda671...861cf523e`（R18）与 `cd8bac0e...fe8c1ef4`（R19）。本轮未执行 git
commit/push，保留给用户验收。

## 41. R20：AMC、同步感知选择、扫描摊薄与 M=12/16（2026-07-16）

### 41.1 预注册设计与实现边界

R20 同时落实四项重测要求，但不把不同证据混成一个结论。每个 seed 先生成一份
`M=16`、几何相关 TDL-A 信道，再用前 4/8/12/16 个端口形成严格嵌套的成对比较；50 个
seed (`20262201:20262250`) 全部执行一帧/四帧 PSS acquisition，前 20 个再执行两帧完整
PSS/PBCH/DM-RS/RZF/QPSK/BER/EVM。所有 M 仍冻结 `Dmax=1`，因为 R18 已经证明
`Dmax=2` 码叠加没有稳定增量；此处不借新一轮重新打开该自由度。

五个预注册臂为 `M4 / M8Data / M8Aware / M12Aware / M16Aware`。同步感知选择器以已知
TDL 信道计算 PSS MRC-SNR 代理，强制代理值不低于同 realization 的 M4 identity，再在
该约束内贪婪提高数据 RE 的 min-user MMSE-SINR。它是**oracle-channel 研究选择器**，
不是已经完成的在线信道扫描估计器；代理门通过也不等价于实际时域 PSS 必然成功。

AMC 使用看结果前冻结的 CQI-style 链路抽象：把完整接收机测得的
`Q=-20log10(EVM_RMS)` 映射到 15 个固定门限和频谱效率，并乘冻结的目标块成功率 0.9。
同时把全部门限整体平移 `-2/0/+2 dB` 做敏感性审计。这不是实际 16/64QAM 波形解码，
也不是 3GPP MCS 一致性声明；它只回答“R19 存活的 SINR/EVM 头room，在非饱和工作点
能否换成更高频谱效率”。扫描开销为每次更新 M4/M8/M12/M16 分别占用 0/1/2/3 个
10 ms 帧，更新周期预注册为 0.05--10 s，主门取 1 s。

新增 `type1_phase3_iir_mex.c` 只用于把 M=16、五帧、50-seed 的因果建立 IIR 加速到可
执行规模；源码实现 complex single/double 两条分支，本轮实际使用并回归的 single 输出
与 MATLAB 标量递推的最大绝对误差为 `2.55e-7`。其余回归包括 PSS 批/标量代理 0 dB
误差、streamed target 与显式 raw-M 构造的最大绝对误差 `4.50e-7`、AMC 单调性和同步
约束，全部通过。

### 41.2 作废运行与噪声口径修正

第一次完整目录 `.../type1_phase3_r20_paper_20260716_011035/` **整体作废，不参与任何
门或结论**。运行结束后的数量级审计发现，代码错误地把含静默 slot 的时域波形均方
功率噪声方差同时传给频域 MMSE 选择指标，使选择目标虚高到约 26--35 dB。修正后严格
分离两种物理口径：

```text
nv_waveform = mean(|r[n]|^2) / SNR       （只用于时域 AWGN）
nv_metric   = mean(sum_m |H_m,u[k]|^2) / SNR （只用于频域 MMSE）
```

修正 smoke 的选择目标回到 M4/M8/M12/M16 约 `8.69/12.71/15.02/15.22 dB`，与 R17--R19
相同量级。修正发生在查看正式 Gate 结论之前，seed、损伤、门限和判据均未改变；随后从
seed 1 重新跑完整 paper，禁止从作废目录摘取较好数字。

### 41.3 正式结果

正式目录和哈希为：

```text
/home/bupt/type1_offline_captures/type1_phase3_r20_paper_20260716_012732/
phase3_r20.mat SHA-256:
eb15cc84b05ac2880ac0f789f36faec45a2e86decf98ccc7e9fe010395c3bb13
phase3_r20.png SHA-256:
5db4ec00af7abe1cf811003a1bd6a2e1388347ef71347fabfab7ea42b243e29c
```

| 指标 | M4 | M8-data | M8-aware | M12-aware | M16-aware |
|---|---:|---:|---:|---:|---:|
| 1 帧 PSS acquisition / 50 | 46 | 47 | 48 | 48 | 47 |
| 4 帧 PSS acquisition / 50 | 46 | 47 | 48 | 48 | 47 |
| 完整解码有效 / 前 20 | 20 | 18 | 18 | 20 | 20 |
| EVM-quality 中位数 | 5.441 | 8.673 | 8.306 | 9.577 | 9.989 dB |
| 成功帧平均 decoded BER | 3.844% | 1.509% | 1.541% | 0.830% | 0.608% |
| 理想选择 min-SINR 中位数 | 8.539 | 12.565 | 12.355 | 14.385 | 15.711 dB |
| 1 s nominal AMC 增益 | 0 | +0.439 | +0.449 | **+0.614** | **+0.710 bit/s/Hz** |
| 1 s fixed-QPSK 增益 | 0 | +0.064 | +0.102 | +0.097 | +0.043 |

主门冻结为“1 s 更新、nominal AMC 表下 M12 或 M16 相对 M4 增益为正”，因此
**R20 Gate 3 重测通过**。门限整体平移 `-2/0/+2 dB` 时，M12/M16 的 1 s 增益仍分别约
`(+0.715,+0.787)/(+0.614,+0.710)/(+0.546,+0.621) bit/s/Hz`，正号不依赖单一门限对齐。

acquisition 比例的 Wilson 95% 区间分别为：46/50 `[0.812,0.968]`、47/50
`[0.838,0.979]`、48/50 `[0.865,0.989]`，高度重叠。M8-data/M8-aware/M12/M16 相对
M4 的成对 rescue/loss 分别为 `3/2、3/1、3/1、4/3`，也没有统计显著差异；因此 R20
不能把 AMC 主门通过改写成同步概率已经提高。

扫描曲线给出清晰的摊薄边界：50 ms 更新时 M12/M16 分别为 `-0.012/-0.295`，100 ms
已经转为 `+0.318/+0.234 bit/s/Hz`；随后随周期拉长单调趋近无扫描开销极限。故“更多
端口总能提高净吞吐”仍是错误的，更新过快时 2--3 个扫描帧会反噬；但 R19 单一
100 ms/固定 QPSK no-go 也不能外推为所有工作点和所有 M 失败。

### 41.4 同步子结论与最终边界

同步感知 M8 相对数据 M8 的四帧 acquisition 为 1 次 rescue、0 次 loss，McNemar
`p=1`；两者有 33/50 调度完全相同。四帧非相干累积与一帧计数逐臂完全相同。由此必须
拒绝两个过强主张：“同步感知选择已经统计显著提高 acquisition”和“高 SNR realization
假峰可由重复同一帧直接消除”。代理约束能防止明显牺牲 PSS 能量，但当前 50-seed 只给
出方向性、非显著的 `47 -> 48`，不能升为默认在线选择器。

R20 的正结果来自三个同时成立的条件：TDL 下 M 扩展确实提高数据质量；AMC 提供未饱和
工作点；扫描更新周期足以摊薄开销。它不证明真实在线扫描已经获得 oracle 调度，也不
证明物理单 RF 开关板已经实现 M=16。可发表的结论是：**R19 的“器件级 SINR 正、固定
QPSK goodput 负”分裂不是选择失效；在冻结 AMC 抽象和合理更新周期下，M=12/16 可把
存活的质量增益兑现成正净吞吐，但 acquisition 代理仍需在线化和更强的假峰特征。**

第二次独立 50-seed 全量运行保存在
`.../type1_phase3_r20_paper_20260716_014240/`；两次运行的
`preRegistration/validation/selection/data/acq1/acq4/acqDetail/summary` 八项
`isequaln` 全为 1。fresh MAT SHA-256 为
`48570643bc037d570dfe4315e5a408ee52f5a7f73ae2e91e90a8eace1ebdf9da`。最终部署版本重跑
R16--R20 五组代数回归全部通过，7 个 R20 MATLAB 文件的 Code Analyzer findings 为
0，`git diff --check` 通过。本轮未执行 git commit/push。

## 42. R21 Part D：闭式 SINR 与可达速率理论（2026-07-16，预注册）

R21 先做 Part D，不先做能效。原因不是理论预期更容易给正结果，而是 Part D 可以直接
对 R20 已冻结的 50-seed 数值资产做逐位等价门；Part C 的 GreenMO/DBF/HBF 功耗仍需
冻结器件参数和共同系统边界，若现在自行填写功耗数字，结论会由假设而非系统决定。

理论冻结为每个子载波

```text
G = S^T H,                 Rn = sigma^2 S^T S
Rz = Rn + E E^H
C  = (I + G^H Rz^(-1) G)^(-1)
SINR_u = 1/C_uu - 1
R_MMSE = sum_u log2(1+SINR_u)
C_logdet = log2 det(I + G^H Rz^(-1) G)
```

其中 `Ex` 作为与数据不相关的高斯自干扰处理是**保守可达率模型**，不是声称真实开关
残差与 `x` 独立。令 `F=Rn^(-1/2)G`、`D=Rn^(-1/2)E`，预注册的逐音调下界为

```text
min_u SINR_u >= sigma_min(F)^2 / (1 + ||D||_2^2).
```

空间相关不引入自由 `rho`：继续使用几何绑定的
`R_ij=J0(2*pi*|p_i-p_j|/lambda)`。对任一二值链向量 `s`，期望噪声归一化阵列增益为
`s^T R s/(s^T s)`，并受 `lambda_min(R)` 与 `lambda_max(R)` 夹逼。

R21 主门只要求闭式公式在同一 R20 seed/S/TDL/noise 上复现冻结的 51-tone 选择目标，
最大绝对误差 `<1e-9 dB`；MMSE 率不得超过 log-det，残余谱范数下界不得超过精确结果。
不预注册“速率必须随 M 单调”或“相关性增益必须为正”，避免用结果反向选择理论口径。

### 42.1 实现、回归与一次无效 smoke

新增 `type1_phase3_theory_metrics.m`、`type1_phase3_correlation_gain.m`、
`type1_validate_phase3_theory.m` 和 `type1_run_phase3_r21_theory.m`。第一次数值 smoke 在
生成 TDL taps 前即失败：为避免时域卷积开销传入了 `zeros(1,4)`，MATLAB `fft` 因第一维
为单例而沿第二维执行，导致数组尺寸不兼容。修复仅把占位波形改为 `zeros(2,4)`，确保
FFT 沿时间维；该输入不参与随机信道生成，也不改变 RandStream 消耗。失败 smoke 没有
形成 MAT/PNG，更没有进入结果。

独立回归结果为：闭式 SINR 与既有 MMSE 数值引擎相对误差 `9.91e-16`；用显式
`W=G^H(GG^H+Rz)^(-1)` 逐流拆出 desired/interference/noise 后，相对误差
`3.90e-15`；随机残余 E 下精确 eigen-SINR 与谱范数保守界的最小余量 `0.00229`，
log-det 相对逐流 MMSE sum-rate 的最小余量 `2.35 bit/s/Hz`。J0 二次型有限和与 50000
次相关 Rayleigh Monte Carlo 的最大相对误差 `0.00597`。四个新增 MATLAB 文件
Code Analyzer findings 均为 0。

### 42.2 50-seed paper 结果

正式资产：

```text
/home/bupt/type1_offline_captures/type1_phase3_r21_paper_20260716_090554/
phase3_r21_theory.mat SHA-256:
12cd11d9c356e49fb25db2fec7eb8b2d7b74b33a068a5b2c7bbe202f93e701ba
phase3_r21_theory.png SHA-256:
e5b1867b469a8b704c2a2e3b515cb569facb8f459d2b6e7c3a59001691895e64
```

闭式理论对冻结 R20 51-tone objective 的最大绝对复现误差为 **`8.88e-15 dB`**，远低于
`1e-9 dB` 主门，Part D 代数门通过。

| 50-seed 中位数 | M4 | M8-aware | M12-aware | M16-aware |
|---|---:|---:|---:|---:|
| 理想信道 min-user LMMSE rate | 3.093 | 4.226 | 4.847 | 5.263 bit/s/Hz |
| 逐流 MMSE sum-rate | 14.785 | 18.072 | 20.402 | 21.634 bit/s/Hz |
| joint log-det | 20.592 | 22.497 | 24.072 | 24.655 bit/s/Hz |
| log-det − MMSE sum-rate | 5.743 | 4.261 | 3.485 | 3.054 bit/s/Hz |
| 相对 M4 的 min-rate 胜出 seed | — | 49/50 | 49/50 | 50/50 |

这里的“理想信道”指 R20 同 seed、同 S、同 TDL 和同热噪声，但没有把 25 dB/20 ns/OU
全波形残差反推成 E；因此表格是**选择头room的理论闭合**，不能替代 R20 的实际 AMC
goodput。log-det 是允许联合最优高斯检测的互信息上界，不能当成当前逐流 RZF/MMSE
接收机已达到的吞吐量。两者间隙随 M 缩小，说明端口选择同时改善了逐流线性检测距
联合检测上界的差距，但仍有 3 bit/s/Hz 量级余量。

### 42.3 残余损伤与几何边界

对白化残余谱范数 `epsilon=||Rn^(-1/2)E||_2`，保守 min-user rate 中位数从
`epsilon=0` 到 `epsilon=2` 分别由

```text
M4 : 1.831 -> 0.653 bit/s/Hz
M8 : 2.867 -> 1.263 bit/s/Hz
M12: 3.580 -> 1.702 bit/s/Hz
M16: 3.955 -> 1.992 bit/s/Hz
```

下降。该界在全部点不超过精确 SINR。目标 10 dB 的中位规范化 epsilon 预算为
`[0,0,0.400,0.724]`；它说明更大 M 在该保守谱界下有更高残余容限，但 epsilon 是
**白化后的无量纲矩阵范数**，未映射回隔离度/建立时间前，禁止把 `0.724` 写成器件规格。

几何二次型给出同样重要的非单调边界。对固定 round-robin、Dmax=1、正权相加，在
M=24 时端口间距 `0.125 lambda` 的期望噪声归一化增益为 `-1.78 dB`，而
`0.25/0.5/1 lambda` 分别为 `+2.59/+1.99/+1.50 dB`。原因是 J0 相关具有符号振荡，
过密端口被固定分组后可能负相关相消；“端口越密/孔径越大必然越好”不是定理。

对 R20 自适应选择得到的 S，`s^T R s/(s^T s)` 的跨链平均中位约 0 dB、最差链中位
约 `[0,-0.331,-0.519,-0.553] dB`。这不否定 R20，因为 S 是观察 H 后选择的，固定 S
的无条件二阶矩不能代表条件选择增益；它反而表明 R20 收益主要来自 realization-specific
的端口选择和多用户条件数改善，而不是任意固定端口集合自带相干增益。

第二次完整运行目录为 `.../type1_phase3_r21_paper_20260716_090706/`；两次运行的
`preRegistration/validation/objectiveDb/minUserRate/sumMmseRate/capacityLogDet/`
`arrayMeanLinear/arrayMinLinear/lowerRate/epsilonBudget/summary` 共 11 个科学字段
`isequaln` 全为 1。R21 Part D 因而完成；Phase 3 尚余 Part C 能效和 oracle 在线化收口，
本轮不打 freeze tag、不执行 git commit/push。

## 43. R22 Part C：能效口径冻结（2026-07-16，预注册）

### 43.1 同一张组件表

本轮采用 GreenMO MobiCom'23 原论文 Table 1/§5(b.ii) 的原型功耗作为标称锚点，而不是
为本文另选更有利器件。原始来源为 GreenMO 作者页面/论文、MAX2829 和 AD9963 官方
数据页：

- GreenMO paper: https://wcsng.ucsd.edu/files/greenmo.pdf
- MAX2829: https://www.analog.com/en/products/max2829.html
- AD9963: https://www.analog.com/en/products/ad9963.html
- HBF power discussion: https://arxiv.org/abs/1807.07201

| 项目 | 标称值 | 共同计数方法 | 来源/边界 |
|---|---:|---|---|
| 单链 RFIC（含 LNA/mixer/filter/PLL/LO） | 354 mW | 本文/GreenMO 各 1 | GreenMO Table 1 的 MAX2829 单链模式 |
| 同步 MIMO RFIC | 408 mW/链 | DBF×M，HBF×N | GreenMO：4×408=1632 mW；LO 已含，禁止重复计费 |
| ADC | 100 mW/10 MS/s | 聚合采样率×10 mW/MS/s | GreenMO 对 AD9963 的线性模型；122.88 MS/s 属外推，不是 AD9963 BOM 保证 |
| 快速开关 | 1 mW/端口 | 本文/GreenMO×M | GreenMO 40 MHz、25% duty 实测近似 |
| 有源移相器 | 10 mW/个 | PC-HBF×M，FC-HBF×M×N | GreenMO 引用的有源 phase-shifter 口径 |
| 基带 FFT/输入处理 | 40.82 mW/数字输入 | 单链/GreenMO/HBF×N，DBF×M | 由下述 30% BB 锚点的一半分配得到，属明确派生假设 |
| N×N 检测 | N=4 时 163.29 mW | 按 `(N/4)^3` | 同上；复杂度敏感性，不是芯片实测 |
| 端口扫描 | `E_scan=(P_front+P_BB,scan)T_scan` | 本文/GreenMO/HBF 均计 | `T_scan=10 ms*(ceil(M/N)-1)`；DBF 同时观测 M 路，额外扫描为 0 |

基带绝对锚点来自 GreenMO §6 的 5G 组成中“BB 约 30%”：以其 8天线/4流/40 MHz
GreenMO 前端 `762 mW` 反解 `P_BB=0.3/0.7*762=326.57 mW`，再按 50/50 分给数字输入
和 N×N 检测。该分拆没有器件实测唯一性，因此必须另报全部组件 `0.5×/1×/1.5--2×`
敏感性，禁止把单一标称值写成硬件测量。

两条锚点回归必须精确复现：GreenMO 8天线/4流/10 MHz（不含派生 BB）
`354+400+8=762 mW`；4链 DBF 为 `4*408+4*100=2032 mW`。

### 43.2 公平比较和扫描能量

固定同一 4 流、51 RB、18.36 MHz 占用带宽、30.72 MS/s 每流、同一 R20 50-seed TDL
和 20 dB noise realization。比较五类前端：本文 Dmax=1、GreenMO-like many-to-many BABF、
M路 DBF、N链 partially-connected HBF、N链 fully-connected HBF。GreenMO-like/HBF 是
同信道模型下的理想算法基线，不声称逐位复现 GreenMO 室内实验。

主 EE 使用同一高斯 LMMSE sum-rate，避免把本文的实测 AMC 与基线的理想 capacity 混在
同一分子；本文另报 R20 AMC goodput/power 作为实际锚点，但不拿它与理想 DBF/HBF 直接
排名。扫描期间 RF/ADC/开关继续耗电，BB 运行训练而不传 payload：

```text
EE = B_occ * R_sum * (T_update-T_scan)
     / [P_front*T_update + P_BB,data*(T_update-T_scan) + P_BB,scan*T_scan]
```

因此扫描能量和扫描占空比只计一次，既不免单也不把同一 RF 功耗重复相加。主更新周期
沿用 R20 的 1 s，同时画 50 ms--10 s 曲线。R22 不预注册“本文必须打赢 DBF/HBF/
GreenMO”；若正负号随组件敏感性翻转，结论必须写成交叉点而不是选取标称档。

### 43.3 实现与回归

新增统一前端速率、HBF、GreenMO-like 码叠加、功耗表、逐架构能量账本、验证和 R22
入口共 7 个文件。关键回归全部通过：GreenMO `0.762 W`、4链 DBF `2.032 W` 逐位复现；
M16/N4/100 ms 的扫描占空比为 30%，scan energy 大于 0，且总能量等于各分量之和；统一
前端 SINR 与 R21 相对误差为 0。7 个文件 Code Analyzer findings 为 0。

第一次 smoke 后、正式运行前发现 R20 AMC 是每流 MCS efficiency，而 R22 理论量是四流
sum-rate；直接作为实际锚点会少算 4 倍。正式版本同时保存 per-stream 和 `N×` aggregate
字段，bits/J 使用四流 aggregate。跨架构理想 sum-rate 比较本来就是统一口径，未受该
修正影响；功耗参数、seed、Gate 均未改变。

### 43.4 50-seed paper 结果

正式资产：

```text
/home/bupt/type1_offline_captures/type1_phase3_r22_paper_20260716_094916/
phase3_r22_energy.mat SHA-256:
165eb3e2b5a17fec12a1a6ddb733826e780127de1706e556aff32c6de556477d
phase3_r22_energy_efficiency.png SHA-256:
25474d2ae242cf0e4f283668742147a4b6e7295e881d51ed27e6a1b7b406b84f
phase3_r22_energy_proportionality.png SHA-256:
d2a3dd17384a277b577c6ad0c1b2a039dedb2a0f5f3137680ceb5a823d12caff
```

本文 Dmax=1 理论 sum-rate 对 R21 的最大误差为 0，R22 Gate 通过。1 s 更新、4 流、标称
组件表下：

| M=16 架构 | 理想 sum-rate | 平均 RX 功耗 | 理想参考 EE |
|---|---:|---:|---:|
| 本文 Dmax=1 | 21.634 bit/s/Hz | **1.925 W** | **200.1 Mbit/J** |
| GreenMO-like many-to-many | 22.294 | **1.925 W** | **206.2 Mbit/J** |
| DBF（16 数字链） | 30.411 | 12.260 W | 45.5 Mbit/J |
| PC-HBF（4 RF 链） | 16.603 | 3.347 W | 88.3 Mbit/J |
| FC-HBF（4 RF 链） | 23.311 | 3.827 W | 108.5 Mbit/J |

本文相对 DBF 的标称 EE 比为 4.39×；在统一 low/nominal/high 功耗敏感性下分别为
5.22×/4.39×/4.06×，正号不依赖单一档。相对 PC-HBF 为 2.64×/2.27×/2.15×，相对
FC-HBF 为 2.09×/1.84×/1.85×。这些是**同一理想高斯速率分子下的组件模型结果**，
不是板卡功率实测，也没有计入 PA、冷却和回传。

GreenMO-like 从已验收 Dmax=1 S 出发，允许一天线加入多码相；M=8/12/16 中位只增加
2/1.5/3 条 membership。M16 中位 sum-rate 比本文高约 3.05%，但逐 seed 只有 34/50
更高，且它是局部贪婪、不是 GreenMO co-phase 算法复现。故本轮支持“本文电路能效与
GreenMO 单链包络相同，而简化 Dmax=1 只损失少量中位理想 rate”，不支持“本文打赢
GreenMO”或“完整 GreenMO 仅有 3% 增益”。

### 43.5 扫描、实测锚点与能量正比边界

M16 本文在 50 ms 更新时扫描 30 ms，理想参考 EE 只有 `82.5 Mbit/J`；100 ms、1 s、
10 s 时分别为 `144.4/200.1/205.7 Mbit/J`。因此扫描能量和 payload 损失没有被免除，
且能效结论仍然依赖更新周期。

把 R20 的每流 AMC goodput 乘 4 后，本文 M4/M8/M12/M16 在 1 s 更新的 full-stack
锚定 EE 仅为 `38.4/55.5/61.7/65.2 Mbit/J`；M16 约为理想参考 200.1 的三分之一。
该差距包含 AMC 离散化、acquisition、开关损伤和实际解码质量，证明 200.1 只能作为
电路/理想链路 headroom。由于 DBF/HBF 没有对应 full-stack 解码，本轮禁止用 65.2 与
它们的理想 45.5/88.3/108.5 直接排名。

固定 M=16、负载 N=1→4 时，本文平均功耗由 `0.721→1.925 W`，而始终开启全部数字链的
DBF 仅由 `12.099→12.260 W`；本文扫描能量则由 `0.108→0.058 J/次`，因为低负载虽
功耗较低，却需要更多扫描帧。这同时验证了能量正比优势和“低负载扫描并不免费”。

第二次完整运行在 `.../type1_phase3_r22_paper_20260716_095041/`；两次运行的
`preRegistration/validation/rate/greenAddedEdges/breakdown/summary` 六个科学字段
`isequaln` 全为 1。R22 Part C 由此完成，但 Phase 3 freeze/tag 仍等待专家对组件派生
假设和理想/full-stack 双口径的最终裁决；本轮不提交 git。

### 43.6 文档和最终远端审计

新增 `PHASE3_ENERGY_MODEL.md`，把五种架构的组件计数、GreenMO/MAX2829/AD9963/HBF
来源、扫描能量公式、理想/full-stack 双速率口径和不可外推边界放在一个可独立复核的
文件中；`RUN_COMMANDS.md` 新增 R22 验证、paper 运行、正式 SHA、字段级 fresh 对照和
错误 smoke 禁用说明；README 新增 R22 两张正式图、关键脚本、资产索引和 `.31` 变更行。

最终在 RX 服务器、无 `sudo` 条件下连续运行 R16--R22 七个验证器，输出依次为 PASSED；
R22 七个 MATLAB 文件的 `checkcode(...,'-id')` findings 全为 0。本地与服务器七文件
SHA-256 逐个相同；两张本地 README 图的 SHA 与正式远端资产分别为
`25474d2a...06b84f` 和 `d2a3dd17...d12caff`。三个新/修改文档的本地 Markdown 链接均
可解析，`git diff --check` 无输出。一次补充 MAT 读取在 SSH 密钥交换阶段被跳板瞬时
关闭，未启动 MATLAB、未改变远端状态；随即只读重试成功，六个科学字段仍为
`[1 1 1 1 1 1]`，并重新打印出本文 M16 `1.9254 W/200.1063 Mbit/J` 和四流全栈
`65.2141 Mbit/J`。

结论不因文档整理而改变：R22 完成的是统一组件模型下的能效和扫描代价表征，不是实物
功耗测量；R20 选择器仍是 oracle 上界。Phase 3 的三门、Part D 和 Part C 已完成，但
在 R22 专家裁决前不打 freeze tag、不提交或推送。

## 44. R22 通过与 Phase 3 冻结（2026-07-16）

`REVIEW_VERDICTS.md` 的 R22 已完成独立功耗复算、两次 run 字段对照和公平性审查，正式
裁决通过并授权关闭 Phase 3。审议特别冻结以下论文边界：4--5× 是统一理想参考速率下
的组件模型能效，不挂到 `65.2 Mbit/J` 全栈锚点；本文以约 69% 的 DBF 理想速率换取约
15% 的组件模型功耗；GreenMO-like 不是 GreenMO 算法复现；同步感知选择仍是 oracle
上界，M>8 没有穷举标尺。

代码按六个主题整理。前五个代码提交为：

```text
33718f9 feat: establish phase3 M>N platform and exhaustive anchor
a59986e feat: add phase3 constrained port-selection algorithms
22046f4 feat: validate phase3 full-stack net gain with AMC
5f7cb02 feat: add phase3 SINR and rate characterization
16ecc45 feat: add phase3 architecture energy comparison
```

第六个提交包含本节、R1--R22 审议记录、完整复现命令、独立系统/能效说明和冻结图片。
annotated tag `phase3-freeze-2026-07-16` 指向该文档闭环提交。旧的 `.claude` 本地配置、
R13/R14 临时思考稿及 pending 启动图不属于 Phase 3 冻结资产，没有纳入提交。

Phase 3 关闭结论：受单标量 RF 链和物理 A/S 约束的 M>N 端口选择，在 TDL、开关损伤、
同步和扫描同时存在时，借助 AMC 与至少 100 ms 的更新周期可获得 M=8/12/16 的
`+0.45/+0.61/+0.71 bit/s/Hz` 净吞吐；增益来自信道观测后的选择和条件数改善，不是
固定端口阵列增益。Dmax=2 码叠加没有稳定增值。R21 的理论是严谨表征与上下界而非新
容量定理；R22 能效是组件模型而非硬件测量。R1--R22 实验程序由此完备，下一阶段只做
论文写作或在新授权下开展增强实验。

## 45. 论文式技术手册（2026-07-16）

基于冻结的 `SYSTEM_EXPLAINER.md`、`IMPAIRMENT_MODELS.md`、R1--R22 结果和 Phase 3
理论/能效资产，新增 `TECHNICAL_MANUAL.md`。本轮不新增模型、代码或实验，不改变任何
冻结裁决；目标是把分散的工程说明和审议数据整理成可供通信大同行连续阅读的技术手册。

手册共 11 章正文和参考资料，叙事顺序为：前置术语/符号 → 背景与研究问题 → 单标量
链信号流 → 用户/信道/开关/RX-PLL 数学模型 → 静态/动态二分、CFO 门限、泄漏条件数、
OU、ICI 核、LMMSE 与能效推导 → 成对/分层/预注册实验方法 → 实时、Phase 0--3 的逐项
目的/设计/数据/结论 → 六条综合认识 → 应用场景、限制和复现地图。

为避免论文式手册只保留正结果，正文显式保留以下 no-go 和边界：ICI-DF 从 flat
38%--58% 收缩到 TDL 约 3%；公共 LO 必然更好的假设被否定；PSS 高 SNR false-peak
平台；R15 EVM² 倍率 2.112 no-go；R19 固定 QPSK goodput no-go；Dmax=2 码叠加不增值；
同步感知选择仍为 oracle；能效不是功率计实测。R22 的 69% 表述已拆成未扣扫描
sum-rate 71.1% 和扫描后有效理想速率约 69%，防止与表中 `21.634/30.411` 产生歧义。

手册引用的代表数据包括 C/MEX `-115 dB` 等价和 `9.380 ms/frame`、逐用户 CFO 补偿
`0.273→9.49e-4`、OU 相关时间导致 BER 约 10× 差异、TDL ICI-DF
`0.16567→0.16046`、R17 `+2.420 dB`、R18 92.4% 保留率、R20
`+0.449/+0.614/+0.710 bit/s/Hz`、R21 `8.88e-15 dB` 理论闭合，以及 R22
`200.1/45.5/65.2 Mbit/J` 的理想本文/理想 DBF/本文全栈三种不同口径。

本地审计：1354 行初稿的所有本地链接可解析，heading level 无跳级，88 个 `$$` 和
10 个代码围栏均成对，关键冻结数字全部存在，`git diff --check` 无输出；随后仅增加
术语补充、来源和索引，不改变数据。`RUN_COMMANDS.md` 新增手册结构检查及“无新实验
资产”的复现说明，README 新增入口和 `.33` 变更行。本轮等待用户验收，不提交 Git。

`PAPER_OUTLINE.md` 后续手册裁决已落实：开头新增一页式执行摘要、五个头条数字、统一
架构图、项目状态和仅三项补充计划；增加“本文 vs GreenMO vs 经典 FAS”对照表；修正
RX-PLL 公式中 `\sigma_\phi` 的 LaTeX 反斜杠，并明确公共 122.88 MS/s / 独立 30.72
MS/s 两个注入点的 `F_rate` 取值。审议仅“建议”把术语表移附录，而用户原始硬要求是
所有术语在使用前声明，因此术语表保留在第 0 章，正文首次出现复合术语时继续解释；
这是有意的读者约束取舍，不是漏改。原正文没有删除。

## 46. 投稿前 E1--E3 补充实验预注册（2026-07-16，运行前）

依据 `PAPER_OUTLINE.md`，只开放 E1 在线估计信道选择、E2 单用户 FAS 分集和 E3 扫描
周期到移动速度映射；明确不做 TX/TMA、ISAC、RIS、多 SNR OTA 重采和真实 PCB。本节在
查看 E1--E3 数据前冻结，禁止为通过而改变参数。

### 46.1 E1：DM-RS 估计信道端口选择

- 信道/SNR/损伤沿用 R20：20 dB、静态 TDL-A、J0 几何、25 dB 隔离、20 ns 建立、
  fast=0.2、`tauC=1 us`、Dmax=1；paper 使用 seeds `20262201:20262220`；
- 每个 M 的扫描帧使用互不重叠的四端口组，每帧最多把 4 个物理端口映射到 4 条码相；
  M=8/12/16 总共 2/3/4 帧，其中相对当前活动组的额外扫描开销仍为 1/2/3 帧；
- 每个扫描帧经过同一 AWGN、有限隔离和时变建立路径；用冻结 Type-1 DM-RS 与
  `nrChannelEstimate` 对 10 个 data slot 做复信道平均。不同扫描组的有效观测按已知名义
  泄漏权重矩阵做 LS 反演得到 `Hhat(M,N,K)`；不读取 TDL taps；时变建立残余不从真值
  校正，作为在线估计误差保留；
- oracle 与 estimated 都使用相同的 `type1_phase3_greedy_schedule(...,Dmax=1)`。estimated
  只看 Hhat；最终评价一律回到 true H、同一数据波形和完整损伤接收链；
- 主要量：每 seed 真 objective gain retention
  `(gainEstimated/gainOracle)`、paired win/loss、H NMSE、扫描噪声、PBCH/data success、
  decoded BER、EVM-quality、1 s frozen-AMC goodput。ratio 分母不正的 seed 单独标记，
  不强制截到 `[0,1]`；
- 不预注册“必须通过”的正门。若 estimated 的中位保留率和 AMC 增益为正，则可报告在线
  选择仍保留部分收益；若任一消失，则结论为“选择增益受信道估计质量门控”。

### 46.2 E2：单用户 FAS 分集模式

- 单用户、单位平均功率 Rayleigh/J0 相关端口；`M=[1,4,8,12,16]`，间距
  `[0.125,0.25,0.5] lambda`，paper 至少 100000 realization，固定随机种子；
- 每个 realization 选择瞬时功率最大的单端口，不做多端口相干求和；比较量为 outage
  vs 平均 SNR、10% outage 所需 SNR、相对 M=1 的 SNR gain 和中位选中功率；
- M=1 数值 outage 必须与解析 Rayleigh `1-exp(-gamma/rho)` 在蒙卡容差内一致；同一间距
  的 M 值使用同一 M16 draw 的前缀，保证嵌套端口成对且 outage 随 M 不增；
- 不预注册“间距越大必然单调更好”。J0 相关随间距振荡，任何非单调均按结果报告。

### 46.3 E3：更新周期到移动速度映射

- 采用裁决冻结公式 `Tc=0.423/fd`、`fd=v/lambdaC`、载频 3.2 GHz，
  `lambdaC=c/fc=9.375 cm`；
- 对 R20/R22 的 `updateSec=[0.05,0.1,0.2,0.5,1,2,5,10]` 计算满足
  `Tupdate<=Tc` 的最大速度，并给 m/s 与 km/h；
- 这是 Jakes/Clarke 近似下的适用性映射，不是新的空口测量，也不把 100 ms 转正点改写成
  标准规定。主结论应把 100 ms 对应的速度直接报告为准静态/游牧边界。

## 47. 投稿前 E1--E3 补充实验结果（2026-07-16）

### 47.1 实现与 smoke 审计

新增 `type1_phase3_scan_matrix.m` 和 `type1_phase3_estimate_scan_csi.m`：前者把 M 个候选
端口划成互不重叠的 4 端口扫描帧并生成名义泄漏权重矩阵，后者让每帧经过真实 AWGN、
有限隔离和 OU 建立状态，用冻结 Type-1 DM-RS/`nrChannelEstimate` 对默认 10 个 data
slot 平均，再对名义泄漏矩阵做 LS 反演。`meta.usesTrueChannel=false` 且
`settlingTruthCorrected=false`，选择器没有读取 TDL taps 或 beta 真值。

代数验证在 M=16 下得到扫描矩阵 rank=16、condition=1.9534、无噪声 H 恢复相对误差
`2.54e-16`、恢复前后贪婪 objective 差 `0 dB`。第一次 smoke 暴露一项计量问题：reference
在 OFDM 调制后对四层分别缩放至 0.72 峰值，而 DM-RS 估计把这一已知 TX 比例包含在
Hhat 中，未去嵌时 raw H NMSE 约 `+9--10 dB`。该 smoke 作废；修复只从共享
`txGrid/txWaveform` 计算已知层比例，不使用仿真 H。第二次 smoke 后 H NMSE 回到约
`-4 dB`，随后才启动 paper 运行。这个修正不改变信道/SNR/损伤/seed 或判据。

E2 新增 `type1_run_paper_e2_fas_diversity.m`，强制最强单端口而非相干合并；同一间距下
所有 M 使用同一 M16 Gaussian draw 的嵌套前缀。E3 新增
`type1_run_paper_e3_mobility_mapping.m`，只实现冻结 Clarke/Jakes 解析映射。六个新增
MATLAB 文件（含独立 E1 绘图器）远端 `checkcode` 无阻塞问题；E1 代数门、E2 M=1 解析门/嵌套 outage 门、
E3 单位恒等门均通过。

### 47.2 E1：估计信道选择结果

正式运行使用预注册 20 个 seed `20262201:20262220`。truth-CSI 与 estimated 两臂使用
同一贪婪算法，故前者是“读取真值的贪婪参考”而不是穷举最优；estimated 超过该参考的
少量 seed 属于局部搜索路径差异，不能称为超过 oracle 最优。

| 量 | M=8 | M=12 | M=16 |
|---|---:|---:|---:|
| truth-CSI 中位 objective 增益 | 3.9454 dB | 5.9390 dB | 6.6652 dB |
| estimated 中位 objective 增益 | 3.3727 dB | 4.3584 dB | 5.8641 dB |
| 中位 retention | 0.9017 | 0.7882 | 0.8545 |
| retention 极差 | 0.267--1.237 | 0.137--1.126 | 0.609--1.141 |
| estimated 正增益 seed | 19/20 | 20/20 | 20/20 |
| estimated vs truth-CSI win/loss | 3/17 | 2/18 | 4/16 |
| 中位 H NMSE | -3.9357 dB | -4.0899 dB | -4.0737 dB |
| full-stack success：truth/estimated | 18/18 | 18/19 | 19/17 |
| 1 s AMC gain：truth/estimated | 0.2187/0.1859 | 0.4063/0.3943 | 0.6460/0.3524 bit/s/Hz |

主结论为正但需缩放：非 oracle 的 DM-RS 扫描选择在三种 M 上均保留正中位 objective 和
正 full-stack AMC 增益，关闭了“所有 Phase 3 正结果只依赖真值信道”的最大缺口；但
M16 的 AMC 收益从 truth-CSI 参考 `+0.6460` 缩到 `+0.3524 bit/s/Hz`，且 success 从
19/20 降到 17/20，证实信道估计与 acquisition 仍是实质门控。它是静态 TDL 离线控制器
仿真，不是硬件实时选择器。

正式资产：

```text
/home/bupt/type1_paper_supplements/type1_paper_e1_paper_20260716_111405/
paper_e1_online_selection.mat  930796c9f18399185607e933c02aa1a21dc1faffa676876a8015b991234220ae
paper_e1_online_selection.png  80a05deb2517f6d5ad3604b3da759cc7c45216863677fede247d6d54483a2686
```

E1 另有第一次完整运行 `...110222/`。两次运行的
`validation/objectiveDb/hNmseDb/retention/schedule/scanMeta/data` 七个科学字段
`isequaln` 全为 1；第二次 MAT 新增成对汇总字段，并用固定 M8/M12/M16 顺序重绘正式图。

### 47.3 E2：单用户 FAS 分集结果

paper 使用 100000 realization。M=1 蒙特卡洛 outage 相对解析 Rayleigh 式的最大绝对
误差在三种间距分别为 `0.0029/0.0013/0.0023`，嵌套端口 outage 对 M 单调不增门通过。
10% outage 所需平均 SNR 与相对 M=1 收益如下：

| d/lambda | M1 | M4 | M8 | M12 | M16 | M16 gain |
|---|---:|---:|---:|---:|---:|---:|
| 0.125 | 9.713 | 3.472 | 1.147 | -0.059 | -0.886 | 10.599 dB |
| 0.25 | 9.778 | 1.789 | -0.497 | -1.571 | -2.262 | 12.040 dB |
| 0.5 | 9.791 | 1.061 | -1.165 | -2.170 | -2.785 | 12.576 dB |

这补齐了单用户 FAS 分集模式且结果符合相关性物理：0.125 lambda 强相关时增益最小，
0.5 lambda 时最大。该结论限于单用户平坦 Rayleigh/J0 最强端口选择，不能与四用户
TDL/损伤后的 R20 净吞吐混为同一指标。

```text
/home/bupt/type1_paper_supplements/type1_paper_e2_paper_20260716_111306/
paper_e2_fas_diversity.mat  bc505fea9cd95dc9911918826b65b88c97ed6dacf08600273c872455dd3a9457
paper_e2_fas_diversity.png  e8bde885762af89fbac94543a23b3f8b8594e55f40aecc60983a6aed45fd6154
```

### 47.4 E3：物理移动性边界

3.2 GHz、`Tc=0.423/fd` 下，更新周期 50/100/200/500 ms 对应最大名义速度
`0.793/0.397/0.198/0.0793 m/s`，即 `2.855/1.428/0.714/0.286 km/h`；1/2/5/10 s
进一步降为 `0.143/0.0714/0.0286/0.0143 km/h`。因此 R20 “至少 100 ms 扫描摊薄”与
移动性不是独立条件：100 ms 已把适用范围限定到准静态或缓慢游牧。此为解析边界，未做
移动信道闭环实测。

```text
/home/bupt/type1_paper_supplements/type1_paper_e3_20260716_111307/
paper_e3_mobility_mapping.mat  9e00991bc5f62bfab84b9157111597829c7e9af36b3caf93cb6327a3377cdefe
paper_e3_mobility_mapping.png  74f993c3e0b97bf9cfcfc896bfdde94ccb4b2d9b053824750d587c8401c96e53
```

### 47.5 本轮可得结论与下一步

E1--E3 已关闭 `PAPER_OUTLINE.md` 指定的三个投稿缺口：估计信道下仍有正收益、FAS 模式
阶梯有单用户锚点、100 ms 已转换成可解释移动速度。没有开启 E4 子带选择，也没有开展
TX/TMA、ISAC、RIS、多 SNR OTA 或真实 PCB。下一步是专家复核新增代码与正式 MAT；通过
后再决定是否形成新的 paper-supplement freeze 提交。本轮不提交 Git。

最终复现审计：E1 两次 paper 的七个科学字段全为 1；E2 fresh 目录
`.../type1_paper_e2_paper_20260716_112710/` 与正式目录的
`preRegistration/validation/outage/requiredSNR/gain/medianPower/selectedPower/summary` 八个
字段全为 1；E3 fresh 目录 `.../type1_paper_e3_20260716_112712/` 的四个科学字段全为 1。
七个新增 MATLAB 文件最终远端 `checkcode(...,'-id')` findings 均为 0；本地正式三图与
对应远端资产 SHA 一致。

## 48. 会话结束交接文档重构（2026-07-16）

按用户要求完全重写 `HANDOFF.md`，使无上下文新会话可以从一个入口恢复当前工程。本轮
不新增或重跑无线实验，不改变 E1--E3 及 R1--R22 结论。新交接文档补齐：当前论文任务、
Phase 0--3 与 E1--E3 完成状态、实时/离线物理边界、远端和 Git freeze、按 R 编号的全部
复现地图、E1--E3 正式路径/SHA、根目录文件逻辑分类、暂不移动文件的原因、当前脏工作树
归属、11 条未关闭边界、科研/物理/E1/C-MEX 禁止重踩清单和下一步验收/论文计划。

文件整理裁决是“先逻辑分类、暂不物理搬迁”：MATLAB 根路径、MEX build、远端复制和冻结
tag 都依赖当前平铺结构；目录重构必须在 E1--E3 独立验收/tag 后另开分支，先建立
`FILE_INDEX.md` 与统一 `startup.m/addpath`，再做全回归。交接文档明确标记
`REVIEW_VERDICTS.md`、`PAPER_OUTLINE.md`、`.claude/`、R13/R14 thinking 和 pending 图的
所有权，防止新会话误提交或清理。README 变更记录追加 `.35`；本轮等待用户验收，不提交。

## 49. R23 通过后的交接状态修订（2026-07-16）

在交接最终审计时发现专家已在 `REVIEW_VERDICTS.md` 追加 R23。R23 独立复核 E1 两次
运行、E2 解析极限和 E3 Clarke 映射，裁决 E1--E3 全部通过，R1--R23 实验程序关闭并
正式放行论文写作。因此 `HANDOFF.md` 和 README 的状态从“等待 E1--E3 审议”改为
“R23 已通过但尚未提交；下一阶段只写论文”。没有改写专家维护的 R23 原文。

R23 新增的论文 nuance 也写入交接：SINR-objective 域中位保留率为
`90.2%/78.8%/85.5%`，但 estimated/oracle AMC 吞吐增益保留率为
M8/M12/M16=`85.0%/97.0%/54.5%`。MCS 门限放大了 M16 的 CSI 估计损失，使 M12
`+0.394` 高于 M16 `+0.352 bit/s/Hz`，所以论文必须同时报告两个域，并说明现实 CSI
使最优端口数下移。当前不新增实验、不自行提交；下一会话从论文 §V/§VII 吸收该结论。

## 50. R23 资产提交打包（2026-07-16）

用户明确授权提交当前 Markdown 和修改代码。本次科学提交范围包括 E1--E3 七个 MATLAB
文件、三张正式图、`TECHNICAL_MANUAL.md`、`PAPER_OUTLINE.md`、R23
`REVIEW_VERDICTS.md`、`R13_thinking.md`、`R14_thinking.md`、README、RUN、EXPERT 与
HANDOFF。历史 thinking 文档随“所有 Markdown”授权进入版本控制，但不升级为冻结结论；
`REVIEW_VERDICTS.md` 仍归专家维护。

明确排除 `.claude/` 本地设置与两张未被当前文档引用的旧 pending 临时图。提交前保持
E1 两次七字段、E2 八字段、E3 四字段 fresh 一致性结论不变，七个新 MATLAB 文件远端
checkcode=0，Markdown 链接/公式/围栏与 `git diff --check` 通过。本轮只做本地 commit，
没有获得 push 授权。

## 51. R23 本地提交结果（2026-07-16）

科学资产已按上述范围提交为 `94c91ed feat: add R23 paper supplement experiments and
manual`，共 19 个文件；包含全部当前项目 Markdown、E1--E3 七个 MATLAB 文件与三张
正式图。`.claude/` 和两张旧 pending 临时图未进入提交。提交后仅追加本节、README 与
HANDOFF 的 commit 状态，形成独立的小型交接状态提交。未执行 `git push`，未创建新 tag。

## 52. 按实验组织的完整报告（2026-07-20）

按用户要求新增 `EXPERIMENT_REPORT.md`，保留 `TECHNICAL_MANUAL.md` 原有论文式组织，不
覆盖其当前未提交修改。新报告将实时工程、Phase 0--3、R1--R23 及 E1--E3 拆为 38 个
编号实验；每项固定给出目的、设计、输入/对照、指标、实测或仿真数据、分析、结论、失败门
和不可外推边界。报告纳入旧启动 517-block 高水位、尾段 PSS 失锁、白化 RZF no-go、R7
全栈 no-go、双 bank 反噬、DDCE/组合门失败、received-drive 差 1.22 pp、公共 LO 假设被
证伪、R15 EVM²=2.112 no-go、F2 码叠加负结果和 R19 fixed-QPSK goodput no-go，避免只
保留最终正结果。

本轮没有修改 MATLAB/C/MEX，没有重新运行或选择无线数据，也没有更改任何 R1--R23 裁决。
报告引用 21 张现有图片；本地审计确认实验编号 1--38 连续、全部图片路径存在、LaTeX/代码
围栏成对且 `git diff --check` 通过。精确无线复现仍以 `RUN_COMMANDS.md` 原 R 编号命令、
正式 MAT/SHA 和 `REVIEW_VERDICTS.md` 为准。本轮不提交 Git，等待用户验收。

## 53. 完整实验报告的初学者叙事重写（2026-07-20）

用户指出原报告从实验 6 开始仍默认读者理解“新增模型、off、退化、基准、随机流、索引和
路径污染”等工程术语，并要求每个实验增加“实验介绍”。本轮以用户已调整格式的当前
`EXPERIMENT_REPORT.md` 为唯一编辑基底，没有恢复旧排版，也没有改动其
`TECHNICAL_MANUAL.md` 工作区修改。

38 个实验现全部具有“实验介绍—实验目的—详细设计—实验结果—分析与结论”五类内容。
实验介绍不再概括结果，而是先说明现实问题如何产生、上一个实验为什么不足、控制变量和
对照分支为什么能够定位原因。实验 6 逐项定义新增模型、off 和基准，并把原“随机流/索引/
路径被污染”展开为：关闭模块仍取随机数导致后续 AWGN 换样本、数组下标使 DM-RS/data
错位、关闭模块仍经过插值/缩放引入误差。实验 12--28 补齐动态建立、白化负结果、genie、
ICI 核、全栈迁移和 OTA 指标的因果背景；实验 29--38 补齐噪声合并、关停端口、QPSK
饱和、AMC/扫描摊薄、估计 CSI 和移动性边界的教学解释。

格式审计确认 38 个实验对应 38 个“实验介绍”，全文没有使用反斜杠圆括号数学定界符，
仍使用 Markdown 支持的 `$...$` 与 `$$...$$`；现有 21 张图片链接有效，公式/代码围栏成对，
`git diff --check` 通过。本轮未修改或重跑 MATLAB/C/MEX 和冻结数据，不提交 Git。

## 54. 完整实验报告的逐实验计算展开、Phase 1 补图与软换行清理（2026-07-20）

用户要求每个实验不仅列配置，还必须解释量如何计算、误差为什么出现以及大小是否可接受；同时指出实验 8 的六条曲线/四张热图没有嵌入，且 Markdown 正文存在大量人工软换行。本轮保留用户当前格式基底，对实验 1--38 全部增加“计算过程与量级判断”，逐项展开 BER 分母、NMSE 线性量级、实时预算、共同/逐用户 CFO、开关一阶递推、有限样本门、ICI 核自由度、McNemar、goodput、AMC、LMMSE、能效、FAS outage 和移动速度换算。实验 6 具体记录 CP 相关 CFO 公式：850 Hz 对应 1024-sample 间隔 0.178 rad，相差 14 Hz 对应 0.168° CP 相关相位误差；14 Hz 仅为 30 kHz SCS 的 0.0467%，但若完全不跟踪仍会在 10 ms 累积 50.4°，所以文档不把它写成无条件可忽略。

为补齐实验 8，先核对 RX 服务器与本地 `type1_run_phase1_sweeps.m`、`type1_offline_link.m`、`type1_analyze.m` 的 SHA 一致，再在 RX 服务器纯离线运行 `TYPE1_SWEEP_PROFILE=pilot`、`TYPE1_SWEEP_FRAMES=3`。正式结果为 `/tmp/type1_report_phase1_20260720_195137/type1_phase1_pilot_20260720_195545/phase1_sweeps.mat`，复制到 `data/experiment_phase1_pilot_20260720.mat`，SHA-256 `c851764ad68143c7062ecc04339ad60dda366d6e76493ff5fc086ee116208ffd`。每点 1909440 bit，零错绘图下限 `5.237e-7`。主要结果：隔离 15 dB→理想时 EVM `3.5693→2.6443%`、cond P95 `2.7785→1.4887` 但均零错；固定建立 0→10 ns 时 EVM `2.6209→2.9296%`、cond `1.4891→1.9359` 且零错；CFO 压力 0.5/0.75/1.0 的 BER `0.0443/0.1025/0.1331`。CFO×隔离度图在满 CFO 时沿 15--50 dB 隔离只变化约 `0.1331--0.1333`，确认主效应来自未补偿逐用户 CFO，未观察到隔离耦合。timing×isolation 的 50 dB 行从 `1.5081→1.6219`，约 +7.55%，继续按 cond(Hhat) 插值伪影解释。

新增 `type1_plot_phase1_sweeps.m`，并让 `type1_run_phase1_sweeps.m` 调用它；绘图器可直接加载既有 MAT，不重跑链路，六张单变量子图同时显示 BER 与 EVM，四张热图使用完整物理轴名且不插值。图 SHA-256：single-variable `afdc6402eba0aba1a85a0173770a9003a61eead06173ff550bb80c26022f4d78`，heatmaps `592cc09d23168e40d0b33b152f3e84e8ff6d94f23c1bca43496aef7336bb526a`。另增 `tools/plot_experiment_report_figures.py`，只把 R1--R23 已冻结审计数字重绘为六张补充图，图面明确标注 “Frozen audit values — visualization only”，不把重绘当作新实验。

最后使用 Markdown 结构感知的机械整理合并普通段落和列表项中的人工换行；标题、空行、表格、图片、代码围栏和 `$$` 公式块保持原行结构。审计要求 38 个实验、38 个“实验介绍”、38 个“计算过程与量级判断”、全部图片存在、普通正文相邻软换行数为 0、公式/代码围栏成对且无反斜杠圆括号数学定界符。本轮没有改通信算法、没有访问 OTA 板卡、没有改 R1--R23 旧裁决；唯一新科学运行是上述 Phase 1 pilot 补图，尚未提交 Git。
