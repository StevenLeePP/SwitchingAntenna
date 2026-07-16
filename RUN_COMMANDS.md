# 运行命令

以下命令假定 TX 为 `10.156.64.30`、RX 为 `10.156.64.41`，工程均位于
`/home/bupt/tools/matlab_test/nr4x4_type1`。TX 与 RX 各占一个终端；先启动 TX，
再启动 RX。MATLAB 必须经 `sudo` 启动以访问板卡。

## 可视化界面：实时星座图与频谱

TX 终端（循环发送 75 s）：

```bash
ssh -tt bupt@10.156.64.30
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_TX_DURATION_SEC=75 /home/bupt/tools/matlab/bin/matlab -batch "type1_tx"
```

RX 图形终端（需本机有 X11/桌面显示；`-Y` 将 MATLAB 图窗转发回来）：

```bash
ssh -Y -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" TYPE1_LIVE_VISIBLE=on \
  TYPE1_LIVE_WARMUP_SEC=5 TYPE1_LIVE_DURATION_SEC=60 \
  /home/bupt/tools/matlab/bin/matlab -desktop -r "type1_rx_live"
```

此模式发送同一份共享 reference 的**循环 10 ms Type-A 4T 波形**：slot 0 是仅
TX1 的 PSS/SSB/PBCH，slot 1–10 是四个空间层的 QPSK 数据和 Type-1 DM-RS
port 1000–1003，slot 11–19 为静默。RX 接收四路 122.88 MS/s 原始 IQ，C MEX
完成四相虚拟接收；MATLAB 实时显示均衡前后星座图和频谱，并进行同步、RZF 和 BER。

## 非可视化界面：direct C/MEX 连续性能与 BER

TX 终端（RX 启动与 60 s 测量留出余量）：

```bash
ssh -tt bupt@10.156.64.30
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_TX_DURATION_SEC=75 /home/bupt/tools/matlab/bin/matlab -batch "type1_tx"
```

RX 终端：

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_DIRECT_DURATION_SEC=60 TYPE1_FIFO_RING_BLOCKS=2048 \
  TYPE1_DIRECT_STARTUP_MODE=two_stage \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_rx_direct"
```

该模式发送的空口信号与可视化模式完全相同，但 RX 仅在启动和低频健康检查时使用
MATLAB PSS/CFO 控制；连续数据面在 C/MEX 内完成 native ring 消费、四相抽取、
CFO、FFT、Type-1 DM-RS、4×4 RZF、QPSK 硬判决和 BER 累积。结果保存在
`captures/type1_direct_*/type1_direct_results.mat`，其中包含 `pending`、
`dropNew`、分段时延、BER 与 timestamp/sequence 审计。

若 TX 异常中断且未见 cleanup 日志，可在 TX 端执行：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo /home/bupt/tools/matlab/bin/matlab -batch "type1_tx_stop"
```

## 离线 Phase 2：时变开关损伤与白化 RZF 基线

此模式**不启动 TX/RX 板卡、不发射 OTA 信号**。它从共享 10 ms Type-A reference
生成四层波形，经受控 4×4 信道/AWGN 和四相开关模型，输出 BER、EVM、PBCH 状态、
采样边界截断计数和 MAT/PNG；默认 smoke 为每点 1 帧，只能用于结构验证。

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_PHASE2_PROFILE=smoke TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_validate_switch_impairments; type1_run_phase2_timevarying_switch"
```

输出目录为 `/tmp/type1_phase2/type1_phase2_timevarying_smoke_*/`，其中
`phase2_timevarying_switch.mat` 保存每点随机 seed、BER、EVM、PBCH 和边界截断计数，
PNG 仅是其可视化。运行 DM-RS 残差协方差白化 RZF 的理想退化回归：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo /home/bupt/tools/matlab/bin/matlab -batch "type1_validate_whitened_rzf"
```

验证快抖相关时间、data-RE 真值频域残差和已知 beta 的 genie 上界（同样不访问板卡）：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_validate_switch_impairments; type1_run_phase2_tau_correlation"
```

该命令固定扫描 `tau_c={0,8 ns,100 ns,1 us}`。输出
`phase2_tau_correlation.mat` 保存标准 RZF BER、已知 `beta[n]` 的 IIR 逆滤波
genie BER、beta lag-1、真值辅助 data-RE 残差频域 lag-1/lag-5 与 tau 下限触发比例。
其中 genie 与真值残差仅用于判定算法上界和相关性，不能作为 OTA 接收机功能宣称。

R3 的逐符号 ICI 核交叉拟合判决反馈（离线、`tau_c=1 us`、标准 RZF/DF/genie 三方
对比）运行如下：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_validate_ici_decision_feedback; type1_run_phase2_ici_decision_feedback"
```

该命令不访问板卡；以共享 Type-A reference、20 dB AWGN、20 ns 基础建立时间、
fastFraction=0.6、`tau_c=1 us` 和 seed `20260816` 生成同一离线窗口。输出
`phase2_ici_decision_feedback.mat` 包含标准 RZF、偶/奇子载波交叉拟合 13-tap ICI-DF、
以及已知 beta genie 的 BER/配置。ICI-DF 是研究接收机，genie 仅为已知 beta 的代数
上界，二者均不是 OTA 已部署功能。

R4 的成对 Q/迭代/SNR 统计扫描（默认 `pilot` 为每接收机 100 错或 1e7 聚合 bits；
`paper` 提高为 10,000 错或 1e7 聚合 bits）如下：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_PHASE2_DF_PROFILE=paper TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_validate_ici_decision_feedback; type1_run_phase2_ici_df_statistics"
```

该命令不访问 TX/RX 板卡。它以相同 seed 对每个标准 RZF/ICI-DF 点配对，扫描
`Q={0,6,12,24}`、`iterations={1,2,3}` 和 `SNR={-12,-10,-8,-4,0,4,8,12,16,20,24} dB`
（Q/迭代锚定 20 dB，SNR 扫描锚定 Q=12、2 次迭代）。结果目录中的
`phase2_ici_df_statistics.mat` 保存每点 BER、错误数、bits、seed、停止原因、
`C(Q)` 与 eta；若 PSS 无法保留完整帧，记录 `status=acquisitionFailure`，不会把该点
伪装成 DF BER。PNG 仅为同一 MAT 的 Q 捕获律、eta 与 SNR 曲线可视化。

R5 的器件规格包络（20 dB、标准 RZF / 3 次 soft-DF / 已知 beta genie）运行如下：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_PHASE2_ENVELOPE_PROFILE=paper TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_validate_ici_decision_feedback; type1_run_phase2_ici_df_feedback_ablation; type1_run_phase2_device_envelope"
```

该命令不访问板卡。`paper` 扫描 `fastFraction={0,0.2,0.4,0.6,0.8}` 与
`tau_c={0,8 ns,100 ns,1 us}`，固定 20 dB、20 ns、Q=12、3 次 soft-DF；标准/DF 各自
达到 10,000 错或 1e7 聚合 bits 才停止，genie 不参与停止条件。输出
`phase2_device_envelope.mat/png` 保存三接收机 BER、错误数、seed 和 tau-floor 比例；
BER<=1e-2 的规格结论应读取 MAT 中的 `thresholdBrackets`，它是离散网格括号而非连续
插值器件阈值。

为收紧 tau_c=1 us 的阈值括号，可运行 R6 加密点：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_PHASE2_ENVELOPE_PROFILE=refined TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase2_device_envelope"
```

`refined` 固定 `fastFraction={0.5,0.7,0.75}`、`tau_c=1 us`，并使用同一 10,000-error/
1e7-bit 停止规则。应将该 MAT 与 paper 网格共同解释：保证倍率取 DF 的通过下界除以
标准 RZF 的失败上界；零误码的 `zeroErrorUpper95` 是 95% BER 上界，不能写成 BER=0。

R7 CFO-aware 全损伤栈的回归、诊断和 8-seed pilot 均为离线命令，不访问板卡：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_validate_ici_user_cfo"

sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_diagnose_phase2_full_stack"

sudo env TYPE1_R7_PROFILE=pilot TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase2_full_stack_pilot"
```

组合接收机将逐用户 CFO 相位斜坡同时用于 RZF 信道列和 ICI 回归量。pilot 固定 8 个
TDL-A seed，保存 L0--L3 BER、gap closure、channel-bootstrap 95% CI、条件数、核能量、
失败 seed 与 L3/L0 IQ 不变量。只有 MAT 中 `goNoGo=true` 才允许设置
`TYPE1_R7_PROFILE=paper`；当前已验证结果为 no-go，因此不得运行或引用 paper 档。

## 离线 R8：两段式定时补偿与全栈中断审计

从本机连接 RX 服务器（经 TX 跳板）并进入工程：

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
```

以下命令只生成共享 Type-A reference 的纯 MATLAB 离线 TDL-A 波形，不访问板卡、不
启动 TX，也不产生空口信号。先验收压力 seed 上的两段式 timing 去斜，并回归组合
CFO-aware DF：

```bash
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_validate_timing_precompensation; type1_validate_ici_user_cfo"
```

第一项输出旧/新四层 BER、`cond(Hhat)` 中位/P95/max、配置与估计 timing；第二项检查
数据 H 列和 ICI 回归量使用同一逐用户 CFO 相位，并验证 750 Hz 告警。随后运行 R8 主
场景 8-seed pilot：

```bash
sudo env TYPE1_R7_PROFILE=pilot TYPE1_R8_SCENARIO=main \
  TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase2_full_stack_pilot"
```

主场景固定 SNR 20 dB、TDL-A 100 ns、Tx/Rx 相关 0.3/0.3、timing 残差 `+/-4`
样点、fast=0.2、`tau_c=1 us`。输出 MAT 除 L0--L3 BER、gap closure、CI 与 genie
不变量外，还保存已知前缀相对 timing、PSS peaks/metrics、NID2、PBCH CRC、
`failureClass` 和中断率。当前正式结果目录为
`/tmp/type1_phase2/type1_phase2_full_stack_pilot_20260714_224914/`，`goNoGo=false`，
不得运行 paper。原 0.5/0.5 相关、原 timing、fast=0.6 的压力场景仅在需要复现压力
边界时运行：

```bash
sudo env TYPE1_R7_PROFILE=smoke TYPE1_R8_SCENARIO=stress \
  TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase2_full_stack_pilot"
```

该 stress 命令未用于 R8 主场景统计，不能与 main 的 8-seed 中位数混报。

## 离线 R10：真值四支分解、双 bank 与 PSS 对照

以下均为 RX 服务器上的纯 MATLAB 离线实验，不访问 SDR。先验证真值重放并运行冻结的
四支分解：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_R10_STAGE=decompose TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_validate_phase2_truth_replay; type1_run_phase2_r10_decomposition"
```

输出 `phase2_r10.mat` 保存单/双 bank 真值捕获、L0/L1/current/xTrue/HTrue/joint 的
BER/EVM/gap、最低信道十分位误码占比及所有预注册布尔门禁。当前正式分解 MAT 为：

```text
/tmp/type1_phase2/type1_phase2_r10_decompose_20260714_231115/phase2_r10.mat
```

只有其中 `h1Confirmed=true` 才能运行双 bank 候选：

```bash
sudo env \
  TYPE1_R10_PRIOR_MAT=/tmp/type1_phase2/type1_phase2_r10_decompose_20260714_231115/phase2_r10.mat \
  TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_validate_ici_decision_feedback; type1_run_phase2_r10_double_bank"
```

当前 `h1Confirmed=true`，但实际 `retainDoubleBank=false`；输出位于
`/tmp/type1_phase2/type1_phase2_r10_double_bank_20260714_231436/`。默认接收机仍使用
single bank。反功率加权有独立强制门禁：

```bash
sudo env TYPE1_R10_STAGE=weighted \
  TYPE1_R10_PRIOR_MAT=/tmp/type1_phase2/type1_phase2_r10_decompose_20260714_231115/phase2_r10.mat \
  TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase2_r10_decomposition"
```

当前 `h2Confirmed=false`，所以该命令应以 `type1:R10H2Gate` 拒绝运行；这条命令只用于
说明复现门禁，不能绕过断言。PSS 四链/固定单链对照运行：

```bash
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase2_r10_pss_diversity"
```

输出每 seed 的 timing error、NID2、峰值及 combined/chain1--4 成功矩阵；正式结果目录
为 `/tmp/type1_phase2/type1_phase2_r10_pss_diversity_20260714_231713/`。该脚本复现的是
现有四链非相干合并，不是新 PSS 接收机。

## 离线 R11：DDCE、约束核、组合与 PSS 投票

全部命令仍为硬件无关离线 MATLAB。先运行 DDCE 门禁：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_validate_ici_decision_feedback; type1_run_phase2_r11_ddce"
```

输出目录 `/tmp/type1_phase2/type1_phase2_r11_ddce_20260714_233607/` 保存 fixed/DDCE
BER、EVM、gap 和逐子载波秩亏计数；当前 `ddcePassed=false`。随后运行只用真值轨迹的
物理约束核门禁：

```bash
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_validate_phase2_truth_replay; type1_run_phase2_r11_constrained_model"
```

正式 MAT 为
`/tmp/type1_phase2/type1_phase2_r11_constrained_model_20260714_233748/phase2_r11_constrained_model.mat`，
其中 `constrainedModelPassed=true` 才允许组合实验：

```bash
sudo env \
  TYPE1_R11_CONSTRAINT_MAT=/tmp/type1_phase2/type1_phase2_r11_constrained_model_20260714_233748/phase2_r11_constrained_model.mat \
  TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase2_r11_combined"
```

组合 MAT 位于 `/tmp/type1_phase2/type1_phase2_r11_combined_20260714_234122/`，保存
L0/L1/fixed/DDCE/physical-B/DDCE+physical-B/L3 的 BER、EVM、gap 与门禁；当前
`combinationPassed=false`，不得把 physical/combined 设成默认。

PSS 投票的 8-seed 对照与正式接口集成回归：

```bash
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase2_r10_pss_diversity; type1_validate_pss_vote"
```

最新结果目录为 `/tmp/type1_phase2/type1_phase2_r10_pss_diversity_20260714_234237/`，投票
成功 6/8、原合并 5/8。普通调用仍为 `type1_analyze(rx,package)`；只有显式调用
`type1_analyze(rx,package,"vote")` 才启用两链峰位一致投票和无一致簇回退。

## 离线 R11 收束：received-drive 最终门禁与 PSS 30×3 扩样

以下均为 RX 上的纯离线仿真，不访问板卡、不启动 TX。远程连接并运行 received-drive
两道门及兼容回归：

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_validate_ici_decision_feedback; type1_run_phase2_received_drive"
```

该命令构造的是 full-stack TDL-A 接收信号及 stitched 单链 ADC 差分 drive，不收发真实
空口信号。输出 exact/received capture、L0/L1/DDCE/received/L3 BER、EVM、gap 与两道
门禁；正式 MAT 为
`/tmp/type1_phase2/type1_phase2_received_drive_20260715_000817/phase2_received_drive.mat`。
当前 truth gate 通过、receiver gate 未通过，且脚本写明 B 线冻结。

PSS 投票的 30 seeds × 14/20/26 dB 成对统计：

```bash
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase2_pss_vote_statistics"
```

输出 combined/vote 每 realization 成败、timing/NID2、回退标记、逐 SNR rescue/loss 和
精确双侧 McNemar p；正式 MAT 位于
`/tmp/type1_phase2/type1_phase2_pss_vote_statistics_20260715_001401/`。当前 vote 成功数
18/19/19 对 combined 17/17/17，但 p=1/0.5/0.5，未升默认。

## 离线 R12：有界 RX-PLL、LO 拓扑与 CPE

以下命令均只在 RX 做纯离线 MATLAB，不访问板卡、不启动 TX。先运行四项验证和
2 deg/100 kHz 隔离打样：

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase2_rx_lo_pilot"
```

输出 OU alpha/lag-1、Welch SSB 锚定、off 恒等回归，以及
off/common/common+CPE/independent/independent+CPE 的 BER/EVM。正式打样 MAT 位于
`/tmp/type1_phase2/type1_phase2_rx_lo_pilot_20260715_140622/`。

运行固定 5×3 网格和 paper 停止规则：

```bash
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase2_rx_lo_statistics"
```

正式结果目录为 `/tmp/type1_phase2/type1_phase2_rx_lo_statistics_20260715_141225/`，保存
MAT 和 `phase2_rx_lo_topology.png`。每点至少 100 errors 或 1e7 bits；零错以 95% 上界
绘制。`hLo1EveryPoint=false`，不能报告公共 LO 的正规格倍率；H-LO3 EVM 功率拟合
R2 为 0.991/0.992/0.990。

复现公共慢相位的 CPE 象限/周跳归因，以及温和 full-stack 单点：

```bash
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_diagnose_rx_lo_cpe_slip; type1_run_phase2_rx_lo_full_stack"
```

诊断只用 oracle CPE 做失因，不进入接收机；正式诊断目录为
`/tmp/type1_phase2/type1_phase2_rx_lo_cpe_slip_20260715_140623/`。full-stack 目录为
`/tmp/type1_phase2/type1_phase2_rx_lo_full_stack_20260715_141253/`，只确认 LO 增量且明确
`doesNotReopenBLine=true`。

## 离线 R13：PSS 获取曲线、2/4 帧累积与开关 on/off

以下命令只运行 PSS acquisition，不做 PBCH、DM-RS、RZF 或 BER 解码，也不访问板卡。
先连接 RX 服务器并运行两项数值等价门：

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_validate_pss_acquisition"
```

输出必须同时满足 complex correlation 对 `nrTimingEstimate` 的相对误差不超过 `1e-5`，
以及固定随机轨迹的开关线性拆分误差不超过 `1e-5`；当前分别为
`6.55e-16` 和 `2.38e-16`。先跑 4-seed smoke 检查输出维度和图片：

```bash
sudo env TYPE1_R13_PROFILE=smoke TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase2_pss_acquisition_statistics"
```

正式 100-seed、11-SNR paper 档命令为：

```bash
sudo env TYPE1_R13_PROFILE=paper TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase2_pss_acquisition_statistics"
```

该命令用固定 TDL realization 和独立连续噪声成对比较 `combined1/vote1/accum2/accum4`，
报告 Wilson 95% CI、相对 combined 的精确 McNemar、falsePeak/miss/windowClip，并在
20 dB 比较同波形 switch on/off。当前正式目录为：

```text
/tmp/type1_phase2/type1_phase2_pss_acquisition_20260715_144558/
```

其中 `phase2_pss_acquisition.mat` 保存逐 seed 成败、timing/NID2、PMR、失败码和全部成对
统计；`phase2_pss_acquisition_probability.png` 是 waterfall/plateau 曲线，
`phase2_pss_plateau_failures.png` 是高 SNR 失败构成。运行中每 seed 还会覆盖写入
`phase2_pss_acquisition_checkpoint.mat`，中断时可用于审计已经完成的 realization；
checkpoint 不是自动续跑入口。

## 离线 R14：理想开关归因与 TDL 最终曲线

以下仍是 RX 服务器上的纯离线 MATLAB，不访问 SDR。先用 R13 正式 MAT 做 20 dB
三臂归因；smoke 只取前 4 个 seed：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_R14_PROFILE=smoke \
  TYPE1_R14_R13_MAT=/tmp/type1_phase2/type1_phase2_pss_acquisition_20260715_144558/phase2_pss_acquisition.mat \
  TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase2_r14_switch_attribution"
```

正式 100-seed 归因只把 profile 改成 paper：

```bash
sudo env TYPE1_R14_PROFILE=paper \
  TYPE1_R14_R13_MAT=/tmp/type1_phase2/type1_phase2_pss_acquisition_20260715_144558/phase2_pss_acquisition.mat \
  TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase2_r14_switch_attribution"
```

正式结果目录为
`/tmp/type1_phase2/type1_phase2_r14_switch_attribution_20260715_155149/`；程序必须先证明
重新生成的 switch-off success/timing/NID2 与 R13 逐 seed 一致。输出 off/ideal/impaired
成功数、Wilson CI 和两段精确 McNemar。

R14 TDL 最终曲线 smoke：

```bash
sudo env TYPE1_R14_PROFILE=smoke TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  TYPE1_R14_SWITCH_MAT=/tmp/type1_phase2/type1_phase2_r14_switch_attribution_20260715_155149/phase2_r14_switch_attribution.mat \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase2_r14_final_curves"
```

正式 paper-stop 命令：

```bash
sudo env TYPE1_R14_PROFILE=paper TYPE1_OFFLINE_OUTPUT_ROOT=/tmp/type1_phase2 \
  TYPE1_R14_SWITCH_MAT=/tmp/type1_phase2/type1_phase2_r14_switch_attribution_20260715_155149/phase2_r14_switch_attribution.mat \
  TYPE1_R14_RECEIVED_MAT=/tmp/type1_phase2/type1_phase2_received_drive_20260715_000817/phase2_received_drive.mat \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase2_r14_final_curves"
```

正式目录为 `/tmp/type1_phase2/type1_phase2_r14_final_paper_20260715_155216/`，保存 Q/迭代/
SNR/包络的逐 seed 条件 BER、EVM、`cond(Hhat)`、全部 acquisition failure、停止门和集成
边界 prior。只重新绘图、不重跑链路：

```bash
sudo /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_plot_phase2_r14_results('/tmp/type1_phase2/type1_phase2_r14_final_paper_20260715_155216/phase2_r14_final.mat')"
```

生成 `phase2_r14_final_curves.png`、`phase2_r14_integration_boundary.png` 和
`phase2_r14_switch_attribution.png`。主 BER 是配对获取成功后的 conditional BER；必须与
同一 MAT 中按所有 attempted seeds 统计的 outage 并列解释。

## R15：OTA 三档采集、同段注入与 matched-SNR 审计

先在 TX 启动足够覆盖 15 次独立 RX 打开的循环 Type-A 波形：

```bash
ssh -tt bupt@10.156.64.30
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_TX_DURATION_SEC=240 /home/bupt/tools/matlab/bin/matlab -batch "type1_tx"
```

RX 另一个终端采集 25/30/35 dB、每档 5 段 20 ms raw122；每段都必须过
PSS/PBCH/EVM gate：

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_OTA_CAPTURE_SETTLE_SEC=3 TYPE1_OTA_CAPTURE_TIMEOUT_SEC=30 \
  TYPE1_OTA_CAPTURE_BLOCKS=20 TYPE1_OTA_CAPTURE_MAX_EVM_PCT=20 \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase2_r15_capture_campaign"
```

记录命令打印的 `r15_capture_manifest.mat` 绝对路径。停止 TX 后执行
`sudo .../matlab -batch "type1_tx_stop"` 并确认 `ret=0`。随后在 RX 做纯离线同段配对
和每段 10 个 matched-SNR TDL seed（把路径替换为实际 campaign）：

```bash
sudo /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase2_r15_ota_cross_validation( ...
  '/home/bupt/tools/matlab_test/nr4x4_type1/data/type1_r15_ota_20260715_190556/r15_capture_manifest.mat')"

sudo /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_audit_phase2_r15_metrics( ...
  '/home/bupt/tools/matlab_test/nr4x4_type1/data/type1_r15_ota_20260715_190556/type1_phase2_r15_ota_cross_validation.mat')"
```

第一条分析命令冻结 EVM² 预注册门；第二条只做代数口径审计，不覆盖原结果。正式数据
为 `.../type1_r15_ota_20260715_190556/`：正式 EVM² 倍率 2.112（门失败）；RMS-EVM
字面倍率 1.957 只作凹压缩审计，不得用于改判。论文只能报告“33--43 dB 高 SNR
单簇功能+趋势验证，离线模型偏乐观约 2×”，不能报告多 SNR 标定通过。

## README 正式架构图复现

该命令不需要 MATLAB 或板卡，只依赖 Python 3 和 Matplotlib；输出会覆盖 README 引用的
`docs/images/system_architecture.png`：

```bash
cd /root/lap/SwitchingAntenna/c_demo
python3 tools/render_architecture.py
```

## R16：Phase 3 Part A 平台与四条代数回归

该实验是 RX 服务器上的纯离线 MATLAB，不访问 SDR、不启动 TX，也不需要 `sudo`：

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
TYPE1_PHASE3_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase3_part_a"
```

冻结 seed 为 `20260716`。命令必须同时报告：`M=N,S=I` 的 stitched/virtual 逐位一致、
M=8 理想标量链路和 `Htilde=S^T H` 的相对误差、占空比守恒/超限拒绝，以及
`type1:Phase3IllegalFanout` 非法同相扇出拒绝。首个正式结果为：

```text
/home/bupt/type1_offline_captures/type1_phase3_part_a_20260715_201908/
phase3_part_a_r16.mat SHA-256:
0e0281db0ac7d941627107db618fec283128aa4a130d478bcfc5cb2d666991fb
```

只验证四条代数地基，不运行 BER/SINR 扫描；不得把 `allPassed=true` 解读成 Phase 3
端口选择算法或净增益门通过。

## `SYSTEM_EXPLAINER.md` 主要数字复现索引

同行说明文档没有生成新实验结果，只重述已经冻结的数据。逐用户 CFO 基线与基础补偿可
在 RX 服务器用以下纯离线命令复现，不访问板卡、不需要 `sudo`：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
TYPE1_OFFLINE_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_offline_multiuser"
```

其余头条数字直接对应本文档已有章节：OU/相关建立抖动和 ICI-DF 对应“离线 Phase 2”，
RX-LO/CPE 对应 R12，PSS acquisition 对应 R13，TDL 最终 3.15% 对应 R14，OTA EVM²
2.112 no-go 对应 R15，M>N 四条代数地基对应 R16。禁止通过新跑 smoke 结果替换这些
paper/freeze 口径。

## R17：Phase 3 M=8 穷举标尺与 Gate 1

该命令在 RX 服务器运行纯离线 20-seed TDL-A 穷举，不访问板卡、不需要 `sudo`。paper
口径固定 2520 个 `M=8,N=4,Dmax=1` 候选、51 个搜索音调和全部 612 个评价子载波：

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
TYPE1_R17_PROFILE=paper \
TYPE1_PHASE3_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase3_r17_exhaustive"
```

正式资产：

```text
/home/bupt/type1_offline_captures/type1_phase3_r17_paper_20260716_000304/
phase3_r17_exhaustive.mat:
92b4ac29800518a2cd16f684c7ac9c70c74e27c1ad7d5d49a4a5ca250271322d
```

输出必须先通过 2520 候选唯一性、A/S 约束和 MMSE-SINR 直接公式等价回归，再打印每个
seed 的 M=4/fixed-M8/exhaustive-M8 指标。正式门结果为 19/20、配对中位 `+2.420 dB`、
单侧符号检验 `p=2.0027e-5`、`gatePassed=true`；seed `20261718` 的 `-0.050 dB` 必须
保留。该命令不含开关损伤、扫描或 acquisition，不能用来声称 Gate 2/3 或 NetGain 通过。

## R18：F1 精确穷举、在线算法与 Gate 2

这是 RX 服务器上的纯离线 20-seed 实验，不访问 SDR、不启动 TX、**不需要 sudo**。
它精确评价 166824 个 F1 调度，并成对运行 F1/F2 贪婪、局部松弛量化及四个基线：

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
TYPE1_R18_PROFILE=paper \
TYPE1_PHASE3_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase3_r18_gate2"
```

正式资产：

```text
/home/bupt/type1_offline_captures/type1_phase3_r18_paper_20260716_003616/
phase3_r18_gate2.mat:
14df40eb039a7b440633c708230a9c983b75d75b2922efb070812423704ccb18
```

输出应先报告 F1=166824、R17 是其子集、batch/scalar MMSE 误差约 `5.95e-14 dB`，随后
给出 20 个 seed。正式结果为 F1 20/20 不低于 M4、贪婪 20/20 胜 M4、中位保留
92.4%、`gatePassed=true`。F2 贪婪相对 F1 穷优的 TDL 中位为 `−0.203 dB`，不得删去。

## R19：M=8 带损伤全波形 NetGain 与 Gate 3

R19 必须显式指向已验收的 R18 MAT，保证调度、seed 和 TDL realization 成对。该命令会
运行 20 个两帧全带宽链路、122.88 MS/s M 端口标量开关、PSS/PBCH、DM-RS、RZF、BER
和 EVM，内存约 2.5 GB；仍是纯离线程序，不需要 `sudo`：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
TYPE1_R19_PROFILE=paper \
TYPE1_PHASE3_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
TYPE1_R19_R18_MAT=/home/bupt/type1_offline_captures/\
type1_phase3_r18_paper_20260716_003616/phase3_r18_gate2.mat \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_phase3_r19_gate3"
```

fresh 正式资产：

```text
/home/bupt/type1_offline_captures/type1_phase3_r19_paper_20260716_004011/
phase3_r19_gate3.mat:
5685b0cae5027f0ef6da90eba24e8b4a546586a510bba5310ad04b708e273df7
```

输出应先通过 identity/sum/scalar/beta 回归，再给出每 seed 的四臂 acquisition 与 BER。
正式结果为损伤后 acquisition `[20,19,19,19]/20`、100 ms 更新的有效吞吐量增量
`[0,−0.1218,−0.1229,−0.1233]`，因此代码中的固定-QPSK `gatePassed=false`。但 §7.4
预注册的 SINR-quality 分解为 `[0,+2.141,+1.640,+1.468] dB`，按该原始定义 Gate 3
通过。两者必须并列复现：前者是饱和 QPSK 加开销的系统 no-go，后者证明选择质量增益
没有被损伤抹掉。

逐位复现审计可比较两次 R19 目录，不重新解释统计口径：

```matlab
a=load('/home/bupt/type1_offline_captures/type1_phase3_r19_paper_20260716_003640/phase3_r19_gate3.mat');
b=load('/home/bupt/type1_offline_captures/type1_phase3_r19_paper_20260716_004011/phase3_r19_gate3.mat');
disp([isequal(a.report.ideal,b.report.ideal), ...
      isequal(a.report.impaired,b.report.impaired), ...
      isequal(a.report.betaMeta,b.report.betaMeta), ...
      isequal(a.report.summary,b.report.summary), ...
      isequal(a.report.validation,b.report.validation)])
```

预期输出为 `[1 1 1 1 1]`。

## R20：AMC、同步感知选择、扫描曲线和 M=12/16

R20 是 RX 服务器上的纯离线 50-seed TDL 实验，不访问 SDR、无需 `sudo`。先编译快速
因果 IIR；paper 模式对全部 50 个 seed 做一帧/四帧 PSS acquisition，对前 20 个做完整
解码。预计运行约 15 分钟、峰值内存约 3.2 GB：

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1

/home/bupt/tools/matlab/bin/mex -R2018a CFLAGS='$CFLAGS -O3' \
  type1_phase3_iir_mex.c

TYPE1_R20_PROFILE=paper \
TYPE1_PHASE3_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase3_r20"
```

正式资产：

```text
/home/bupt/type1_offline_captures/type1_phase3_r20_paper_20260716_012732/
phase3_r20.mat:
eb15cc84b05ac2880ac0f789f36faec45a2e86decf98ccc7e9fe010395c3bb13
```

冻结输出应为 `acq4=[46,47,48,48,47]/50`，五臂依次为
`M4/M8-data/M8-aware/M12-aware/M16-aware`；1 s nominal AMC 增益为
`[0,+0.439,+0.449,+0.614,+0.710] bit/s/Hz`，`gatePassed=true`。M8-aware 的
McNemar 为 1 rescue/0 loss、`p=1`，所以该命令**不支持**“同步感知选择显著改善同步”。
一帧和四帧计数相同，也必须原样报告。

查看扫描周期、AMC 门限敏感性和作废运行记录：

```matlab
f='/home/bupt/type1_offline_captures/type1_phase3_r20_paper_20260716_012732/phase3_r20.mat';
load(f,'report');
s=report.summary;
disp([s.acq1Count;s.acq4Count;s.dataValidCount])
disp([s.medianQualityDb;s.meanDecodedBER;s.medianSelectionObjectiveDb])
disp(squeeze(s.amcGain(:,:,2)).')       % nominal AMC，行=更新周期
disp(s.fixedQpskGainAt1Sec)
```

`.../type1_phase3_r20_paper_20260716_011035/` 使用了错误的频域 MMSE 噪声归一化，已在
数量级审计中整体作废；禁止用它替换上述正式资产。AMC 是冻结 CQI-style 链路抽象，
不是实际 16/64QAM 波形或 NR MCS 一致性测试。

fresh 全量复跑目录为 `.../type1_phase3_r20_paper_20260716_014240/`。比较两份结果时忽略
目录和创建时间，只比较科学字段：

```matlab
a=load('/home/bupt/type1_offline_captures/type1_phase3_r20_paper_20260716_012732/phase3_r20.mat');
b=load('/home/bupt/type1_offline_captures/type1_phase3_r20_paper_20260716_014240/phase3_r20.mat');
names={'preRegistration','validation','selection','data','acq1','acq4','acqDetail','summary'};
same=false(size(names));
for k=1:numel(names), same(k)=isequaln(a.report.(names{k}),b.report.(names{k})); end
disp(same)
```

预期为 `[1 1 1 1 1 1 1 1]`；fresh MAT SHA-256 为
`48570643bc037d570dfe4315e5a408ee52f5a7f73ae2e91e90a8eace1ebdf9da`。

## R21 Part D：闭式 SINR、可达速率和几何/损伤边界

R21 是纯离线理论闭合，不访问板卡、不需要 `sudo`。它读取冻结的 R20 MAT，按原 seed
重新生成 TDL taps，验证闭式公式能否逐位复现原选择目标：

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1

TYPE1_R21_PROFILE=paper \
TYPE1_R21_R20_MAT=/home/bupt/type1_offline_captures/\
type1_phase3_r20_paper_20260716_012732/phase3_r20.mat \
TYPE1_PHASE3_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase3_r21_theory"
```

正式资产：

```text
/home/bupt/type1_offline_captures/type1_phase3_r21_paper_20260716_090554/
phase3_r21_theory.mat:
12cd11d9c356e49fb25db2fec7eb8b2d7b74b33a068a5b2c7bbe202f93e701ba
```

输出应报告 R20 objective 最大误差 `8.88e-15 dB`、中位 min-user rate
`[3.093,4.226,4.847,5.263] bit/s/Hz`、`gate=1`。这组 rate 是同 seed/S/TDL/noise 的
理论选择头room，不包含全波形开关残差；实际系统净吞吐仍以 R20 AMC 结果为准。

单独运行代数/Monte Carlo 回归：

```bash
/home/bupt/tools/matlab/bin/matlab -batch "type1_validate_phase3_theory"
```

预期闭式/既有引擎相对误差约 `9.91e-16`、显式 combiner 误差约 `3.90e-15`、J0 二次型
与 50000-draw Monte Carlo 误差约 `0.00597`，且所有 bound/capacity slack 非负。

fresh 目录为 `.../type1_phase3_r21_paper_20260716_090706/`。复现比较：

```matlab
a=load('/home/bupt/type1_offline_captures/type1_phase3_r21_paper_20260716_090554/phase3_r21_theory.mat');
b=load('/home/bupt/type1_offline_captures/type1_phase3_r21_paper_20260716_090706/phase3_r21_theory.mat');
names={'preRegistration','validation','objectiveDb','minUserRate','sumMmseRate', ...
  'capacityLogDet','arrayMeanLinear','arrayMinLinear','lowerRate','epsilonBudget','summary'};
same=false(size(names));
for k=1:numel(names),same(k)=isequaln(a.report.(names{k}),b.report.(names{k}));end
disp(same)
```

预期为 11 个 1。第一次 smoke 使用单样点占位波形，因 MATLAB FFT 自动维度而在生成
信道前失败；修复为两样点后已全量重跑，该失败不产生可引用资产。

## R22 Part C：统一能效、扫描能量与能量正比曲线

R22 是纯离线功耗模型实验，不访问板卡、不需要 `sudo`。它读取冻结的 R20/R21 MAT，
在同一批 50 个 TDL seed 上比较本文、GreenMO-like、DBF、部分连接 HBF 和全连接 HBF。
功耗表、扫描公式及不可直接比较的口径见 [`PHASE3_ENERGY_MODEL.md`](PHASE3_ENERGY_MODEL.md)。

先运行组件/代数回归：

```bash
ssh -tt -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
/home/bupt/tools/matlab/bin/matlab -batch "type1_validate_phase3_energy"
```

预期输出包含：

```text
Phase-3 R22 energy validation PASSED: GreenMO=0.762 W, DBF=2.032 W, scan=30.0%, frontend=0.
```

正式 50-seed 运行：

```bash
TYPE1_R22_PROFILE=paper \
TYPE1_R22_R20_MAT=/home/bupt/type1_offline_captures/\
type1_phase3_r20_paper_20260716_012732/phase3_r20.mat \
TYPE1_R22_R21_MAT=/home/bupt/type1_offline_captures/\
type1_phase3_r21_paper_20260716_090554/phase3_r21_theory.mat \
TYPE1_PHASE3_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase3_r22_energy"
```

正式资产：

```text
/home/bupt/type1_offline_captures/type1_phase3_r22_paper_20260716_094916/
phase3_r22_energy.mat:
165eb3e2b5a17fec12a1a6ddb733826e780127de1706e556aff32c6de556477d
phase3_r22_energy_efficiency.png:
25474d2ae242cf0e4f283668742147a4b6e7295e881d51ed27e6a1b7b406b84f
phase3_r22_energy_proportionality.png:
d2a3dd17384a277b577c6ad0c1b2a039dedb2a0f5f3137680ceb5a823d12caff
```

输出应报告 `R21 rate error=0`、M=16 标称功耗
`[1.93,1.93,12.26,3.35,3.83] W`、统一理想分子下能效
`[200.1,206.2,45.5,88.3,108.5] Mbit/J` 和 `gate=1`。这些数字是组件模型，不是硬件
功率计测量；GreenMO-like 也不是 GreenMO 论文算法的复现。

查看统一功耗、更新周期和 R20 全栈锚点：

```matlab
f='/home/bupt/type1_offline_captures/type1_phase3_r22_paper_20260716_094916/phase3_r22_energy.mat';
load(f,'report'); s=report.summary;
disp(s.medianIdealSumRate)
disp(s.primaryPowerW(:,:,2))
disp(s.primaryEnergyEfficiencyMbitPerJ(:,:,2))
disp(squeeze(s.energyEfficiencyBitsPerJ(4,1,:,2))/1e6)
disp(s.measuredAnchorEeAggregateBitsPerJ(:,5)/1e6)
disp(s.loadCurve.powerW)
disp(s.loadCurve.scanEnergyPerUpdateJ)
```

最后一组 aggregate 全栈锚点应为 M4/M8/M12/M16 的
`[38.4,55.5,61.7,65.2] Mbit/J`。禁止将其中 M16 的 `65.2` 与 DBF/HBF 的理想能效
直接排名，因为后者没有经过相同的 acquisition、开关损伤、AMC 和解码链。

fresh 全量复跑目录为 `.../type1_phase3_r22_paper_20260716_095041/`。逐字段比较：

```matlab
a=load('/home/bupt/type1_offline_captures/type1_phase3_r22_paper_20260716_094916/phase3_r22_energy.mat');
b=load('/home/bupt/type1_offline_captures/type1_phase3_r22_paper_20260716_095041/phase3_r22_energy.mat');
names={'preRegistration','validation','rate','greenAddedEdges','breakdown','summary'};
same=false(size(names));
for k=1:numel(names),same(k)=isequaln(a.report.(names{k}),b.report.(names{k}));end
disp(same)
```

预期为 `[1 1 1 1 1 1]`。fresh MAT SHA-256 为
`510c8feb93a3b958e305b702fbfd452650eee080b7acaf6760edac39614e547e`。第一次 smoke 的
R20 AMC 锚点少乘四流聚合系数；该单位问题在正式运行前修复，smoke 不得引用。

## Phase 3 冻结点检查

R22 审议通过后，Phase 3 冻结于 annotated tag `phase3-freeze-2026-07-16`。本地或克隆
仓库后可用以下只读命令核对 tag、六个主题提交和工作树中的冻结代码：

```bash
git show --no-patch --decorate phase3-freeze-2026-07-16
git log --oneline phase2-freeze-2026-07-15..phase3-freeze-2026-07-16
git diff --stat phase2-freeze-2026-07-15..phase3-freeze-2026-07-16
```

冻结 tag 应包含平台/枚举、选择算法、全栈 AMC、理论、能效和文档审议六个主题提交。
R16--R22 验证命令仍按本文件相应章节运行；tag 不包含远端大体积 MAT/raw IQ，只保存
代码、正式路径、SHA-256、统计量和图片。

## 技术手册引用数据的复现说明

`TECHNICAL_MANUAL.md` 不产生新的实验资产，它把已经冻结的 Phase 0--3 结果按论文逻辑
重新组织。实时数据对应本文件 direct RX 章节；Phase 1/2 数据对应 R1--R15；M>N 端口
选择、理论和能效数据对应 R16--R22。复现某个表格时应运行相应 R 编号的正式命令并读取
指定 MAT，不能把手册中的排版表格当作新的原始数据源。

手册本身的结构和本地资源检查可执行：

```bash
git diff --check -- TECHNICAL_MANUAL.md README.md EXPERT_REVIEW.md RUN_COMMANDS.md
python3 - <<'PY'
from pathlib import Path
import re
p=Path('TECHNICAL_MANUAL.md')
s=p.read_text()
missing=[]
for m in re.finditer(r'!?\[[^]]*\]\(([^)]+)\)',s):
    target=m.group(1).split('#')[0]
    if target and '://' not in target and not (p.parent/target).exists():
        missing.append(target)
assert not missing, missing
assert s.count('$$') % 2 == 0
assert s.count('```') % 2 == 0
print('TECHNICAL_MANUAL structure: PASS')
PY
```

该命令只验证 Markdown、公式分隔符和仓库内图片/文档链接，不重新验证无线实验；无线数据
仍以相应 R 编号的 MATLAB 命令、正式 MAT 和 SHA-256 为准。

## 投稿前 E1--E3 补充实验

这三项均为 RX 服务器上的纯 MATLAB/离线统计，不访问板卡、不要 `sudo`。从本机经跳板
连接 RX：

```bash
ssh -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
cd /home/bupt/tools/matlab_test/nr4x4_type1
mkdir -p /home/bupt/type1_paper_supplements
```

先做代数门和 smoke。E1 的独特之处是用真实 DM-RS 扫描帧估计 M 端口 CSI，再与读取
TDL 真值的同算法参考成对；E2 是单用户 J0 相关端口的最强单端口选择，不做相干合并；
E3 是扫描周期到 Clarke/Jakes 移动速度的纯解析映射。

```bash
TYPE1_E1_PROFILE=smoke TYPE1_E2_PROFILE=smoke \
TYPE1_PAPER_OUTPUT_ROOT=/home/bupt/type1_paper_supplements \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_validate_paper_e1_online_selection; type1_run_paper_e1_online_selection; type1_run_paper_e2_fas_diversity; type1_run_paper_e3_mobility_mapping"
```

正式运行冻结 E1 的 20 个 TDL seed、E2 的 100000 realization 和 E3 的完整周期表：

```bash
TYPE1_E1_PROFILE=paper TYPE1_E2_PROFILE=paper \
TYPE1_PAPER_OUTPUT_ROOT=/home/bupt/type1_paper_supplements \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_paper_e1_online_selection; type1_run_paper_e2_fas_diversity; type1_run_paper_e3_mobility_mapping"
```

正式资产：

```text
/home/bupt/type1_paper_supplements/type1_paper_e1_paper_20260716_111405/
/home/bupt/type1_paper_supplements/type1_paper_e2_paper_20260716_111306/
/home/bupt/type1_paper_supplements/type1_paper_e3_20260716_111307/
```

读取头条量：

```matlab
a=load('/home/bupt/type1_paper_supplements/type1_paper_e1_paper_20260716_111405/paper_e1_online_selection.mat');
disp(a.report.summary.medianRetention)       % [0.9017 0.7882 0.8545]
disp(a.report.summary.estimatedAmcGain)      % [0.1859 0.3943 0.3524]
disp(a.report.summary.successCount)          % [20 18 18 18 19 19 17]
b=load('/home/bupt/type1_paper_supplements/type1_paper_e2_paper_20260716_111306/paper_e2_fas_diversity.mat');
disp(b.report.snrGainDbAtTargetOutage(:,end)) % [10.5987;12.0400;12.5759] dB
c=load('/home/bupt/type1_paper_supplements/type1_paper_e3_20260716_111307/paper_e3_mobility_mapping.mat');
disp(c.report.mapping)
```

E1 的第一次 smoke 未去嵌 reference 的逐层 0.72 峰值缩放，H NMSE 约 `+9--10 dB`；
该运行已明确作废，不得引用。正式实现只用共享 `txGrid/txWaveform` 去嵌该已知比例，
`usesTrueChannel=false`、`settlingTruthCorrected=false`。

E1 fresh 逐字段复现：

```matlab
a=load('/home/bupt/type1_paper_supplements/type1_paper_e1_paper_20260716_110222/paper_e1_online_selection.mat');
b=load('/home/bupt/type1_paper_supplements/type1_paper_e1_paper_20260716_111405/paper_e1_online_selection.mat');
names={'validation','objectiveDb','hNmseDb','retention','schedule','scanMeta','data'};
same=false(size(names));
for k=1:numel(names),same(k)=isequaln(a.report.(names{k}),b.report.(names{k}));end
disp(same) % [1 1 1 1 1 1 1]
```

第二次 E1 正式 MAT/PNG SHA-256 分别为
`930796c9...220ae` / `80a05deb...2686`；E2 为
`bc505fea...9457` / `e8bde885...6154`；E3 为
`9e00991b...defe` / `74f993c3...6e53`。完整 SHA 见 `EXPERT_REVIEW.md` §47。

E2/E3 fresh 目录分别为 `.../type1_paper_e2_paper_20260716_112710/` 和
`.../type1_paper_e3_20260716_112712/`；E2 的八个科学字段、E3 的四个科学字段逐项
`isequaln` 均为 1，比较字段名和结果留痕见 `EXPERT_REVIEW.md` §47.5。
