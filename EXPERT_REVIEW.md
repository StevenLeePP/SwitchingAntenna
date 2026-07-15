# 专家审议说明：4T4R Type-A 与单链开关仿真研究主干

更新时间：2026-07-15（Asia/Shanghai）
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

### 34.3 专家字面指标与项目预注册指标冲突

R15 指令字面写的是对指标做 `(impaired-ideal)/ideal`。若指标取已有文档一直报告的
RMS EVM，完全由同一正式 MAT 代数换算，不换 seed、不重跑链路，则 OTA/离线中位为
0.35291/0.18032、倍率 **1.9571**，符号一致率 100%，字面门通过。项目方在看数前因
“独立残差在功率域相加”把主指标收紧为 EVM²，因此两个裁决相反。审计脚本
`type1_audit_phase2_r15_metrics` 同时保存两者，并设置 `adjudicationRequired=true`。

处置遵循预注册纪律：**不事后把主指标切回 RMS EVM 来宣告通过，也不修改 2× 门、
seed 或离线模型。** R15 板卡实验和代码已经完成，但在审议方裁定 EVM 语义前，Phase 2
不写“正式关闭”，不打 `phase2-freeze-2026-07-15` tag。当前可安全声称的是：同参数
损伤在真实 OTA 和 matched-SNR 离线上的 EVM 方向 100% 一致，整体量级处于约 2×
边界；更严格的 EVM² 口径以 2.112× 边界失败。
