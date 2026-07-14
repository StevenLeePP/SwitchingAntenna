# 专家审议说明：4T4R Type-A 与单链开关仿真研究主干

更新时间：2026-07-14（Asia/Shanghai）  
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
