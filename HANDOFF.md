# 交接文档：快速开关单链多用户 MIMO 研究与实时 C/MEX 平台

更新时间：2026-07-26（Asia/Shanghai）

工程：`/root/lap/SwitchingAntenna/c_demo`

分支：`cmex`

最近已推送冻结点：`phase3-freeze-2026-07-16`，commit `4c60340`

最新本地交接提交：`f4a92a3`（记录 R23 补充实验和交接状态；未 push）

当前状态：Phase 0--3 已冻结；投稿前 E1--E3 已由 R23 审议通过。当前正在把全部既有实验重新整理成一份从零可读、包含成功与失败结果的 `EXPERIMENT_REPORT.md`。该报告及配套图、绘图脚本和少量 Phase 1 补跑资产目前仍在工作树中，尚未提交；下一阶段的工程实验设计将主要从这份报告出发，但不得绕过预注册、正式 MAT 和专家裁决。

本文写给一个完全没有上下文的新会话。假设接手者不知道系统结构、Phase 的含义、OTA 与离线仿真的区别，也不知道哪些算法曾经失败。不要根据文件名猜项目状态，不要只从某张好看的图或某个单点正结果开始继续扩展；先按第 0 节顺序阅读，再检查第 9 节的工作树归属。

---

## 0. 本次交接最重要的事情：先理解 `EXPERIMENT_REPORT.md`

### 0.1 为什么它是后续工作的主要入口

`EXPERIMENT_REPORT.md` 是当前工程最重要的实验级入口。过去的资料分别按 Phase、代码提交、专家轮次和论文章节组织；对零上下文接手者而言，这会导致模型、算法和结论像是凭空出现。新报告改成按“问题出现的原因 → 实验如何控制变量 → 得到什么数据 → 为什么这样解释 → 哪些结论不能外推”的顺序，完整收纳了 38 个实验：

- 实验 1--5：reference、C/MEX 等价、direct RX、实时队列和可视化；
- 实验 6--11：Phase 0--1 基线、静态开关损伤、多用户 CFO、TDL-A、相噪锚定和 OTA 单段配对；
- 实验 12--28：Phase 2 时变开关、OU 抖动、ICI-DF、全栈迁移失败、RX-LO、PSS acquisition、TDL 最终曲线和 15 段 OTA 配对；
- 实验 29--35：Phase 3 的 M>N 单链约束、穷举标尺、端口选择、AMC、扫描开销、理论表征和能效；
- 实验 36--38：投稿补充 E1--E3，即估计 CSI 的非 oracle 选择、单用户 FAS 分集和扫描周期到移动速度的映射。

报告不是只保存成功实验。它明确保留预注册 no-go、被数据推翻的假设、作废的 smoke、genie/oracle 上界和无法迁移到 TDL 全栈的算法。后续项目工程的具体实验设计应优先查阅这份报告，因为新实验通常不是孤立功能，而是要回答旧实验留下的某个物理问题、统计缺口或部署边界。如果不先阅读相关实验，很容易重复已经被证伪的路线，或在 flat/single-seed 场景再次得到无法迁移的漂亮数字。

### 0.2 怎样阅读一个实验

报告中每个实验尽量使用同一结构。接手者应按以下顺序阅读，而不是只看“实验结果”：

1. **实验介绍**：解释系统此前遇到了什么问题、为什么需要这个实验，以及它和前后实验的因果关系；
2. **实验目的**：把本轮要回答的问题压缩成可以被数据判定的目标；
3. **详细设计**：说明输入波形、信道、损伤、对照臂、控制变量、seed、统计档和接收算法；
4. **计算过程与量级判断**：在看结果前说明公式、单位、预期量级和合理性检查；
5. **实验结果**：给出正式数字、表格和图片；
6. **分析与结论**：说明数据支持什么、不支持什么，以及结果是通过、no-go、趋势级还是上界；
7. **复现/脚本索引**：把实验映射到运行器、验证器、正式资产和命令文档。

设计新实验时，应先在报告第 2 节索引中找到最接近的旧实验，再检查该实验的详细设计和边界。例如要继续研究动态开关补偿，应从实验 12--22 和实验 27 开始，而不是只读实验 15 的 flat 正结果；要继续研究端口选择，应同时阅读实验 30--33、36 和 38，因为它们分别限定了理想 headroom、全栈净收益、估计 CSI 损失和移动速度边界。

### 0.3 报告很重要，但它不是唯一事实源

不同文件承担不同职责，不能互相替代：

| 问题 | 首要依据 |
|---|---|
| 为什么做这个实验、实验之间有什么因果关系 | `EXPERIMENT_REPORT.md` |
| 代码实际实现了什么 | 对应 `.m/.c` 源码和 validation 脚本 |
| 精确运行命令、远端目录、环境变量和 sudo 条件 | `RUN_COMMANDS.md` |
| 每次修改、seed、预注册门槛和正式原始数字 | `EXPERT_REVIEW.md` |
| 专家是否验收、如何裁决 pass/no-go | `REVIEW_VERDICTS.md` |
| 最精确的数值和逐 seed 结果 | 正式 `.mat` 资产及其 SHA |
| 面向论文的模型、理论和整体叙事 | `TECHNICAL_MANUAL.md`、`IMPAIRMENT_MODELS.md`、`PAPER_OUTLINE.md` |

若报告、代码和冻结资产不一致，优先级不是“哪份 Markdown 写得最新”，而是：先检查预注册和专家裁决，再核对正式 MAT 与生成它的冻结代码，最后修正文档。报告中的 PNG 只是正式 MAT 或冻结审计数字的可视化，不是独立证据；图与表冲突时不能凭图片改结论。

### 0.4 当前报告的已知缺口

`EXPERIMENT_REPORT.md` 的实验 8 目前存在一个已经识别、尚未完成闭环的设计/表述缺口：文字把“分数定时”写进了单变量因素，但 `type1_run_phase1_sweeps.m` 实际六条一维曲线只有隔离度、建立时间、CFO、相噪、建立边沿抖动和功率；分数定时只出现在“定时系数×隔离度”的二维 `cond(Hhat)` 热图中。四张二维图是围绕隔离度的有限筛查，不是已经证明“最重要”的四组交互。

新会话不得把现有二维图冒充定时单变量结论。若用户授权补齐，应先预注册第七条定时单变量扫描，至少同时记录 BER、EVM、信道估计 NMSE、`cond(Hhat)` 和真实/模型复合信道条件数，并用交互残差区分“定时主效应、隔离度主效应和真正交互”。纯 CP 内定时偏差理论上主要给每个用户信道列增加单位模相位斜坡；现有 `cond(Hhat)` 增长包含信道估计插值伪影，不能写成物理信道真的恶化。

### 0.5 新会话首先做什么

按以下顺序读取，职责不要混淆：

1. `HANDOFF.md`：当前任务、状态、环境、风险和下一步，即本文；
2. `EXPERIMENT_REPORT.md`：38 个实验的背景、设计、结果、失败边界和脚本覆盖；这是后续实验设计的主要入口；
3. `README.md`：工程首页、实时/离线架构、MEX 下放边界、关键脚本和结果图；
4. `TECHNICAL_MANUAL.md`：面向通信同行的论文式完整技术叙事；
5. `EXPERT_REVIEW.md`：每次改动、预注册、seed、原始数字、结论及边界的项目总账；
6. `REVIEW_VERDICTS.md`：专家 R1--R23 裁决，属于专家维护文件；
7. `RUN_COMMANDS.md`：所有远端、离线、OTA、fresh 对照和正式资产路径；
8. `PAPER_OUTLINE.md`、`PAPER_DETAILED_OUTLINE.md`：论文结构和补充要求，属于用户/专家维护内容；
9. `IMPAIRMENT_MODELS.md`、`PHASE3_PLAN.md`、`PHASE3_ENERGY_MODEL.md`：精确模型、Phase 3 物理约束和能效口径；
10. `OTA_CAMPAIGN_PREREG.md`：若重新开放 OTA 采集，必须遵守的预注册设计。

随后只读检查：

```bash
cd /root/lap/SwitchingAntenna/c_demo
git status --short
git log -8 --oneline --decorate
git show --no-patch --decorate phase2-freeze-2026-07-15
git show --no-patch --decorate phase3-freeze-2026-07-16
```

不要先提交、清理、移动或覆盖任何文件。当前工作树包含用户正在修改的实验报告、代码、正式图片、补跑 MAT、论文大纲和 OTA 预注册文件，不是可以随意 reset 的临时目录。

---

## 1. 我们到底在做什么

### 1.1 最初目标

研究一套 5G-NR 风格四用户上行接收系统：用一条宽带射频接收链和高速端口开关，把多个
物理天线端口编码为时间交织的标量采样流，再恢复多个虚拟 MIMO 观测。核心问题不是理想
去交织，而是：

- 开关有限隔离、有限建立、时变抖动和采样边界误差会造成什么损伤；
- 用户独立 CFO、定时、功率、相噪和宽带 TDL 多径下还能否分离四用户；
- PSS/PBCH acquisition、数据检测、端口扫描和队列实时性如何共同影响系统净吞吐；
- M>N 时，受单标量链和真实开关约束的端口选择能否在扣除损伤、同步和扫描后仍有正收益；
- 相比 DBF/HBF/GreenMO-like 参考，速率、功耗和扫描能量的边界是什么。

### 1.2 现在的论文主线

当前形成的是一条完整证据链：

```text
共享 reference 和实时 C/MEX 基线
  -> 静态/动态损伤分类
  -> 时变开关、RX-PLL、同步和 ICI-DF
  -> TDL/full-stack 迁移边界
  -> M>N 物理约束端口选择
  -> AMC、扫描开销、闭式表征和能效
  -> 非 oracle DM-RS 选择、单用户 FAS、移动速度适用边界
```

最诚实的总论是：该架构不是无条件替代 DBF。它在准静态/缓慢游牧、允许 AMC、扫描周期
足够长、候选端口多于用户数的场景中有可重复净收益；在高速移动、固定 QPSK、过密扫描、
病态 TDL 或估计失败时，收益会缩小或消失。

---

## 2. 不可越过的物理和表述边界

### 2.1 单链红线

任意 Phase 3 调度最终必须坍缩为一个标量射频流：

$$
y[t]=\sum_m c_m[t]r_m[t].
$$

数字化后按码相去交织得到虚拟链，不允许把同一个模拟端口在同一时刻免费扇出成多条独立
RF 链。`sum(A,2)<=1`、标量输出恒为一列、占空比和因果建立约束已经由 R16 回归保护。

### 2.2 当前硬件边界

- OTA 使用真实 YunSDR 4T4R TX/RX 板卡；
- RX 硬件实际同时采集四路 122.88 MS/s raw IQ；
- 单 RF 链高速开关行为是在 raw IQ 上受控模拟，不是已经制造的物理开关 PCB；
- 因此可以声称“算法、同步、实时化和 OTA 原始数据锚定平台”，不能声称“物理单链开关板
  原型已完成”。

### 2.3 实时与离线边界

- direct RX 的 C/MEX 热路径已实时运行；
- Phase 1--3 的损伤注入、ICI-DF、端口选择、理论和能效主要是离线 MATLAB；
- E1 已用 DM-RS 扫描估计代替 truth CSI，但仍是离线控制器仿真，没有部署到实时
  `type1_rx_direct.m`；
- R22 能效是统一组件模型，不是板卡功率计实测。

---

## 3. 环境、Git 与远端

### 3.1 本地和远端

```text
本地：/root/lap/SwitchingAntenna/c_demo
远端：git@github.com:StevenLeePP/SwitchingAntenna.git
分支：cmex
TX：bupt@10.156.64.30（cell-04）
RX：bupt@10.156.64.41（cell-08，经 TX 跳板）
TX/RX 工程：/home/bupt/tools/matlab_test/nr4x4_type1
MATLAB：/home/bupt/tools/matlab/bin/matlab
离线正式结果根：/home/bupt/type1_offline_captures 或各轮指定目录
投稿补充结果根：/home/bupt/type1_paper_supplements
```

RX 连接：

```bash
ssh -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
```

本地没有 MATLAB。所有 MATLAB、5G Toolbox、MEX 和大规模统计验证都在 RX 服务器完成。
普通离线实验不要使用 `sudo`；只有实际访问 TX/RX 板卡时才用 `sudo` 启动 MATLAB，且
必须严格审查 root 操作。不要把密码写进脚本、Markdown、shell history 或 Git。

### 3.2 冻结点

```text
phase2-freeze-2026-07-15 -> 0f0b721
phase3-freeze-2026-07-16 -> 4c60340
origin/cmex               -> 4c60340（交接时）
local cmex                -> R23 科学提交 94c91ed 及其后续文档闭环；用 git log 查看，未 push
```

Phase 2 tag 表示 R1--R15 实验资产和 no-go 边界冻结，不代表所有门通过。Phase 3 tag 表示
R16--R22 平台、选择、全栈、理论、能效和审议闭环，不代表在线选择器或真实功耗已经完成。

---

## 4. 共同波形、实时架构和队列语义

### 4.1 波形

- 3.2 GHz 载频；30 kHz SCS；51 RB；NFFT=1024；
- TX 30.72 MS/s；RX/raw switch 域 122.88 MS/s；
- 10 ms 帧、20 slot、4 layer、Type-1 DM-RS ports 1000--1003；
- slot 0 为 SSB/PSS/PBCH；默认 half 模式中 slot 1--10 为 QPSK payload，11--19 静默；
- 默认无信道编码；唯一 BER 真值为 `nr4_type1_reference.mat`；
- 修改 `TYPE1_PAYLOAD_SLOT_MODE`、编码或栅格后必须重新生成 reference，并同步 TX/RX。

### 4.2 实时数据面

```text
YunSDR 4 路 RX 122.88 MS/s
  -> type1_yunsdr_rx_mex.c：DMA pthread + native ring
  -> MATLAB 控制面：PSS/PBCH acquire/track、CFO/timing、两阶段启动
  -> direct_make_grid：四相抽取、连续 CFO、固定 radix-2 FFT、612 子载波
  -> type1_decode_frame_grid_mex.c：DM-RS、4x4 RZF、QPSK、EVM、BER
  -> directstatus：pending/dropNew/highWater/时延/timestamp/sequence
```

MEX 持久保存 DM-RS/data/QPSK/coded-bit reference maps。Phase 2/3 算法没有下放 direct
consumer；`type1_phase3_iir_mex.c` 只是离线批量加速器。

### 4.3 两阶段启动与队列

`type1_rx_direct.m` 默认 `TYPE1_DIRECT_STARTUP_MODE=two_stage`：粗 PSS 后 flush 软件 ring，
建立 maps/跟踪后再 flush 并从有效 PSS 对齐点启动。这样不会强迫约 517 ms 冷启动历史进入
一个平均约 9 ms/10 ms frame 的消费者。

- `pending` 单位是 1 ms raw DMA block，不是 slot；
- `pending=10` 约为 10 ms 待处理数据；
- `highWater=517` 表示历史峰值约 517 个 block，不是单帧解码耗时；
- `directflush` 只能清软件 ring，驱动/DMA 描述符中尚未入 ring 的块随后仍可能到达；
- `dropNew=0` 只表示软件 ring 未满，不表示 pending 必须为零；
- 连续验证有效性还要求硬件 overflow/timeout=0、timestamp invariant=1、pending 无持续正斜率。

### 4.4 已验证实时数字

旧 60 s 517 ms 启动版本：

```text
captures/type1_direct_20260713_155645/type1_direct_results.mat
6041 frames；dropNew=0；final/peak pending=10/517 blocks
extract/FFT/PHY/total=2.142/5.141/1.943/9.380 ms
BER=[1.66e-8,3.02e-8,1.04e-9,1.98e-8]
timestamp audit=116；overflow=0；invariant=1
```

两阶段 10 s：

```text
captures/type1_direct_20260713_171338/type1_direct_results.mat
x=0 pending=84；peak约103；稳态/最终约20/15；dropNew=0
```

同一 OTA 帧的 native-ring C FFT 相对 MATLAB CP-end grid/H NMSE 分别约
`-115.63/-115.91 dB`，raw bit errors 一致，说明实时化没有以精度换时延。

---

## 5. 已完成了什么：按科学问题而不是提交顺序

### 5.1 Phase 0：reference-to-BER 主干

纯 MATLAB、无硬件依赖的共同主干已经完成：

```text
reference -> 用户损伤 -> flat/TDL-A + AWGN -> 数字开关 -> PSS/PBCH
          -> Type-1 DM-RS -> 4x4 RZF -> QPSK/BER/EVM
```

默认 3 帧相干锚点四层经验 BER 均为 0，平均 EVM
`[2.718,2.775,2.714,2.738]%`。有限样本零错只能报告零错上界，禁止直接声称理论 BER=0。

### 5.2 Phase 1：静态损伤与多用户独立化

- 每用户 CFO、分数 timing、功率、TX 相噪；
- Type-1 DM-RS、4×4 RZF、逐用户残余 CFO 基础补偿；
- 静态泄漏矩阵、固定一阶建立、TDL-A 和空间相关；
- smoke 3×3、pilot 至少 5×5 的二维扫描基础设施。

关键结论：固定周期泄漏/建立在去交织后是多相 LTI，通常被 DM-RS 吸收到等效信道；真正
需要算法处理的是帧内时变残余。独立用户压力点 Layer 3 BER 从 `0.27307` 经基础 CFO
补偿降到 `9.49e-4`。

### 5.3 Phase 2：动态损伤、恢复与迁移边界

- 建立时间慢漂、i.i.d./OU 快抖、亚样点采样边界位移；
- beta genie、逐符号 ICI 核、hard/soft ICI-DF、DDCE、双 bank 和 received-drive；
- 有界 RX-PLL、公共单 LO vs 独立 4-LO、CPE/周跳审计；
- PSS acquisition waterfall、高 SNR 假峰平台、2/4 帧累积；
- TDL 多 realization、full-stack L0--L3、器件规格包络；
- 15 段高 SNR OTA 同 raw IQ ideal/impaired 配对。

关键结果：

- 同 RMS 快抖下，相关时间从近 i.i.d. 到 1 us 可使 BER 增加约 10×，规格必须约束 PSD；
- ICI-DF 在 flat 隔离场景恢复约 38%--58% BER gap，但在最终 TDL 全栈只剩约 3.15%；
- 真值 capture 约 64%，说明信息结构存在，实际收益受 Hhat 质量和模拟状态可观测性双门控；
- 公共 LO 必然优于独立 LO 的预注册假设被数据否定，独立振荡器可产生相噪空间平均；
- R15 功率域 EVM² OTA/离线倍率 `2.112>2`，预注册 ratio no-go；RMS 倍率 1.957 不得改判；
- OTA 三档 gain 实际都在 33--43 dB，属于高 SNR 单簇，不能称为多 SNR 定量标定。

### 5.4 Phase 3：M>N 物理端口选择

R16--R22 已完成：

- M=N 退化、标量单链、占空比、非法扇出回归；
- M=8 的 2520 个受约束穷举标尺；
- F1 166824 精确枚举、贪婪和松弛量化；
- F2/Dmax=2 码叠加消融；
- TDL、开关损伤、同步、扫描、AMC 下 M=8/12/16 全栈；
- LMMSE SINR/速率表征、log-det 上界、残余谱下界、J0 几何；
- GreenMO-like/DBF/HBF 统一组件功耗与 bits/Joule。

关键结果：

- M=8 理想穷举相对 M4 中位 `+2.42 dB`，19/20 seed 胜；
- F1 关停自由度修复强制用满端口的反例，贪婪保留穷优中位增益 92.4%；
- 配对波束选择约 `+3.69 dB`，传统单端口 FAS 参考约 `+0.38 dB`；
- Dmax=2 码叠加平坦中位 0、TDL 中位 -0.20 dB，无稳定增值；
- R19 出现“净 SINR +2.14 dB、固定 QPSK goodput 为负”，不是选择失效，而是 QPSK 饱和
  和扫描/获取开销遮蔽；
- AMC + 至少约 100 ms 扫描摊薄后，M8/M12/M16 净增益
  `+0.449/+0.614/+0.710 bit/s/Hz`；
- 固定端口 min-chain array gain 为负，收益来自观察信道后的选择和条件数改善，不是天然
  固定阵列增益；
- M16 模型功耗约为 DBF 的 15%，扫描后有效理想速率约 69%，理想参考能效约 4.39×；
  M16 full-stack AMC 锚点为 `65.2 Mbit/J`，不能与 DBF/HBF 理想分子直接排名。

### 5.5 投稿补充 E1--E3（当前最新工作）

E1 使用扫描帧 Type-1 DM-RS 估计 M 端口 CSI，经过同一 20 dB AWGN、25 dB 隔离、
20 ns 建立、fast=0.2、1 us OU 路径；不读取 TDL taps，不用 beta 真值修正。20 个成对
TDL seed 结果：

| 指标 | M8 | M12 | M16 |
|---|---:|---:|---:|
| truth-CSI 贪婪中位 objective 增益 | 3.945 dB | 5.939 dB | 6.665 dB |
| estimated 中位 objective 增益 | 3.373 dB | 4.358 dB | 5.864 dB |
| 中位保留率 | 90.2% | 78.8% | 85.5% |
| estimated 正增益 seed | 19/20 | 20/20 | 20/20 |
| 中位 H NMSE | -3.94 dB | -4.09 dB | -4.07 dB |
| 1 s AMC 净增益 | +0.186 | +0.394 | +0.352 bit/s/Hz |

truth-CSI 臂只是同一贪婪算法读取真值后的参考，不是穷举全局最优；estimated 偶尔超过它
是局部搜索路径差异，不能写成“估计算法超过 oracle 最优”。

R23 补充了必须进入论文的双域解释：estimated/oracle AMC 吞吐增益保留率约为
M8/M12/M16=`85.0%/97.0%/54.5%`。因此 SINR-objective 域虽然三种 M 都保留 79%--90%，
MCS 门限量化会放大 M16 的估计损失；现实估计 CSI 下 M12 的 `+0.394` 反而高于 M16 的
`+0.352 bit/s/Hz`。结论应写成“估计误差会侵蚀大 M 优势并使最优端口数下移”，不能只
报告 SINR 域保留率。

E2 是单用户、单位功率 Rayleigh/J0 相关端口的最强单端口选择，100000 realization；
M16 在 10% outage 处相对 M1 的 SNR gain 随 0.125/0.25/0.5 lambda 间距为
`10.599/12.040/12.576 dB`。它不做相干合并，也不等价于四用户宽带波束选择。

E3 用 `Tc=0.423/fd`、`fd=v/lambda` 做解析映射。3.2 GHz 下 100 ms 对应
`0.397 m/s=1.428 km/h`，确认当前甜区是固定、准静态或缓慢游牧，不是高速移动。

---

## 6. 如何复现所有数据

先在 `EXPERIMENT_REPORT.md` 找到实验编号，理解它为什么运行、有哪些对照臂和哪些结果不可外推；再到报告第 12 节找到对应运行器/验证器，最后使用 `RUN_COMMANDS.md` 的精确命令。`RUN_COMMANDS.md` 是唯一权威命令文档。本节只给冷启动路径；任何数字应回到对应 R 编号的正式 MAT，而不是从 README 或实验报告中的四舍五入表格反推。

最短追溯链是：

```text
科学问题
  -> EXPERIMENT_REPORT.md 的实验编号和详细设计
  -> 对应 type1_run_* / type1_validate_* 源码
  -> RUN_COMMANDS.md 的命令、环境变量和输出目录
  -> 正式 MAT/PNG 及 SHA
  -> EXPERT_REVIEW.md 的预注册与项目方解释
  -> REVIEW_VERDICTS.md 的独立复现和最终裁决
```

不要只运行正文提到的主脚本而跳过 validation。报告中的“通过”通常同时依赖代数不变量、同 seed 成对、fresh 重跑和字段级 `isequaln`，不是“MATLAB 没报错”就算通过。

### 6.1 同步代码到 RX 前的规则

只复制本轮明确需要的文件，不要用会删除远端资产的 `rsync --delete`。先比较 SHA 或使用
临时目录。当前 E1--E3 文件已经复制到 RX 项目；远端大 MAT 不回传 Git。

### 6.2 最小离线基线

在 RX 普通用户下：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
TYPE1_OFFLINE_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_validate_switch_impairments; type1_run_offline_baseline"
```

Phase 0 正式锚点示例：

```text
/home/bupt/type1_offline_captures/type1_offline_baseline_20260713_233453/
```

### 6.3 Phase 2 全链复现地图

按 `RUN_COMMANDS.md` 以下标题依次运行：

1. “离线 Phase 2：时变开关损伤与白化 RZF 基线”；
2. “离线 R8：两段式定时补偿与全栈中断审计”；
3. “离线 R10：真值四支分解、双 bank 与 PSS 对照”；
4. “离线 R11：DDCE、约束核、组合与 PSS 投票”；
5. “离线 R11 收束：received-drive 最终门禁与 PSS 30×3 扩样”；
6. “离线 R12：有界 RX-PLL、LO 拓扑与 CPE”；
7. “离线 R13：PSS 获取曲线、2/4 帧累积与开关 on/off”；
8. “离线 R14：理想开关归因与 TDL 最终曲线”；
9. “R15：OTA 三档采集、同段注入与 matched-SNR 审计”。

R15 访问板卡的采集步骤需要 `sudo`；R2--R14 离线步骤不需要。每节给出 profile、seed、
正式输出目录、MAT SHA 和预期字段。不要把 smoke 当 paper 统计。

### 6.4 Phase 3 全链复现地图

按 `RUN_COMMANDS.md` 运行：

```text
R16 Part A 回归
R17 M8 穷举 Gate 1
R18 F1/F2 Gate 2
R19 带损伤 Gate 3
R20 AMC/扫描/M12/M16
R21 闭式 SINR/速率
R22 统一能效
```

Phase 3 tag 核对：

```bash
git log --oneline phase2-freeze-2026-07-15..phase3-freeze-2026-07-16
git diff --stat phase2-freeze-2026-07-15..phase3-freeze-2026-07-16
```

R20/R21/R22 的正式路径、两次运行字段级 `isequaln` 和 SHA 均在 `RUN_COMMANDS.md` 对应
章节，不要另选一个临时 smoke 目录。

### 6.5 E1--E3 正式复现

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
TYPE1_E1_PROFILE=paper TYPE1_E2_PROFILE=paper \
TYPE1_PAPER_OUTPUT_ROOT=/home/bupt/type1_paper_supplements \
  /home/bupt/tools/matlab/bin/matlab -batch \
  "type1_run_paper_e1_online_selection; type1_run_paper_e2_fas_diversity; type1_run_paper_e3_mobility_mapping"
```

正式资产：

```text
E1 /home/bupt/type1_paper_supplements/type1_paper_e1_paper_20260716_111405/
   MAT 930796c9f18399185607e933c02aa1a21dc1faffa676876a8015b991234220ae
   PNG 80a05deb2517f6d5ad3604b3da759cc7c45216863677fede247d6d54483a2686

E2 /home/bupt/type1_paper_supplements/type1_paper_e2_paper_20260716_111306/
   MAT bc505fea9cd95dc9911918826b65b88c97ed6dacf08600273c872455dd3a9457
   PNG e8bde885762af89fbac94543a23b3f8b8594e55f40aecc60983a6aed45fd6154

E3 /home/bupt/type1_paper_supplements/type1_paper_e3_20260716_111307/
   MAT 9e00991bc5f62bfab84b9157111597829c7e9af36b3caf93cb6327a3377cdefe
   PNG 74f993c3e0b97bf9cfcfc896bfdde94ccb4b2d9b053824750d587c8401c96e53
```

Fresh 审计：E1 两次 paper 的七个科学字段全相同；E2 fresh `...112710/` 的八个字段、
E3 fresh `...112712/` 的四个字段全相同。七个新增 MATLAB 文件远端
`checkcode(...,'-id')` 均为 0。精确比较命令见 `RUN_COMMANDS.md` 最后一节。

### 6.6 实时 TX/RX

只有这一节访问板卡，需严格审查 `sudo`。先 TX 后 RX；TX 留足比 RX 更长的时长。

TX 主机：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_TX_DURATION_SEC=75 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_tx"
```

RX 主机：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
sudo env TYPE1_DIRECT_DURATION_SEC=60 TYPE1_FIFO_RING_BLOCKS=2048 \
  TYPE1_DIRECT_STARTUP_MODE=two_stage \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_rx_direct"
```

结束时必须确认 TX 输出 `cyclic disable ret=0` 和设备关闭。可视化、无图 direct、编译和
板卡停止的完整命令在 `RUN_COMMANDS.md` 开头两节。

---

## 7. 文件为什么这么多，以及如何分类

### 7.1 当前逻辑分类

根目录大量 `.m` 文件是历史形成的平铺 MATLAB 工程。按前缀可稳定分类：

| 类别 | 文件模式/代表文件 | 意义 |
|---|---|---|
| 公共配置/reference | `type1_config.m`、`type1_build_package.m`、`type1_load_package.m`、`nr4_type1_reference.mat` | 全链唯一波形和真值 |
| 实时 TX/RX/MEX | `type1_tx*.m`、`type1_rx*.m`、`type1_yunsdr_rx_mex.c`、`type1_decode_frame_grid_mex.c` | 板卡和 C/MEX 数据面 |
| 标准 MATLAB 接收 | `type1_analyze*.m`、DM-RS/RZF/CFO/OFDM helpers | 标准对照和离线解码 |
| Phase 0/1 | `type1_offline_*`、`type1_run_phase1_*`、`type1_apply_switch_impairments.m` | 理想主干、用户损伤、静态模型 |
| Phase 2 | `type1_run_phase2_*`、`type1_analyze_ici_*`、RX-LO/PSS helpers | 动态损伤、ICI-DF、同步、OTA |
| Phase 3 | `type1_phase3_*`、`type1_run_phase3_*`、`type1_validate_phase3_*` | M>N 平台、选择、理论、能效 |
| 投稿补充 | `type1_run_paper_*`、`type1_validate_paper_*`、`type1_phase3_estimate_scan_csi.m` | E1--E3 |
| 实验主报告 | `EXPERIMENT_REPORT.md` | 38 个实验的背景、详细设计、结果、失败边界、图片和脚本覆盖；后续实验设计首要入口 |
| 其他文档 | 根目录其余 Markdown | 架构、模型、审议、复现、论文叙事和预注册 |
| 正式 Git 图片 | `docs/images/` | README/手册引用的冻结图 |
| 工具 | `tools/` | 架构图等确定性生成脚本 |
| 小型样例 | `data/` | 可进 Git 的短 IQ/reference 辅助数据 |
| 大结果 | 远端 capture/output root | MAT/raw IQ，不进 Git |

### 7.2 能否物理移动到子目录

可以，但**当前不要顺手移动**。原因：

- MATLAB 从项目根启动时默认只发现根目录函数；移动后需要统一 `startup.m/addpath`；
- MEX build、远端 `scp`、MAT 文件中的函数名和文档链接存在平铺假设；
- R1--R22 的 freeze tag 与当前平铺结构是可复现基线；
- 在 E1--E3 尚未独立提交/tag 时同时做目录重构，会把科学改动和工程改动混在一起。

推荐顺序：

1. 先按用户授权完成 R23 资产的独立提交/tag；
2. 新建单独的“repository-layout”分支；
3. 先生成 `FILE_INDEX.md`，只做索引，不移动；
4. 再考虑 `experiments/phase1|phase2|phase3|paper`、`realtime/`、`models/`、`validation/`；
5. 增加统一 `startup.m` 和从干净 shell 启动的全回归；
6. 本地/远端路径、MEX build、README 链接、R16--R22 验证全部通过后单独提交。

不要把 `nr4_type1_reference.mat`、实时入口和 MEX C 源移动作为第一次整理动作。

---

## 8. 关键文件的职责

| 文件 | 职责 |
|---|---|
| `EXPERIMENT_REPORT.md` | 当前最重要的实验级说明和设计入口；按 38 个实验解释背景、控制变量、结果、失败边界及代码映射 |
| `README.md` | 独立工程首页和结果索引 |
| `SYSTEM_EXPLAINER.md` | 面向通信大同行的较短说明 |
| `TECHNICAL_MANUAL.md` | 论文式完整手册；含执行摘要、术语、模型、实验、应用 |
| `EXPERT_REVIEW.md` | 改动/数据/结论唯一总账；新工作必须追加 |
| `REVIEW_VERDICTS.md` | 专家裁决；不要替专家改写历史 |
| `RUN_COMMANDS.md` | 所有复现命令和正式资产 |
| `PAPER_OUTLINE.md` | 用户/专家维护的论文大纲和补充要求 |
| `RESEARCH_REPORT.md` | Phase 0 前后的历史论文方向诊断；部分“未完成”判断已被 Phase 1--3 关闭，不能当当前状态 |
| `IMPAIRMENT_MODELS.md` | 损伤公式和验证边界 |
| `PHASE2_MIDTERM_REPORT.md` | Phase 2 中期定位与收官附录 |
| `PHASE3_PLAN.md` | A/S 约束、三门和执行纪律 |
| `PHASE3_ENERGY_MODEL.md` | R22 功耗口径与来源 |
| `type1_rx_direct.m` | 两阶段无图实时消费者 |
| `type1_rx_live.m` | 低频可视化；不承担顺序 BER 证明 |
| `type1_yunsdr_rx_mex.c` | DMA/ring/direct consumer/timestamp 审计 |
| `type1_decode_frame_grid_mex.c` | C DM-RS/RZF/QPSK/EVM/BER 内核 |
| `type1_run_phase3_r20.m` | AMC、扫描周期、M12/M16 系统净收益 |
| `type1_run_phase3_r21_theory.m` | LMMSE/速率/几何和残余界 |
| `type1_run_phase3_r22_energy.m` | 统一功耗和 bits/Joule |
| `type1_run_paper_e1_online_selection.m` | 非 oracle DM-RS 扫描选择 |
| `type1_run_paper_e2_fas_diversity.m` | 单用户 FAS 最强端口分集 |
| `type1_run_paper_e3_mobility_mapping.m` | 扫描周期到移动速度解析映射 |

---

## 9. 当前工作树与文件归属

R23 已验收资产进入本地 commit `94c91ed`，交接状态进入 `f4a92a3`；两者都尚未推送到 `origin/cmex`。在此之后，用户又开展了实验报告重写和图表补全，因此当前工作树不是干净的冻结树。

截至 2026-07-26，本轮最重要的未提交资产是：

| 资产 | 当前意义 | 接手规则 |
|---|---|---|
| `EXPERIMENT_REPORT.md` | 38 个实验的全量报告，后续实验设计主要入口 | 不得删除或用旧手册覆盖；修改前先核对对应代码和冻结证据 |
| `type1_run_phase1_sweeps.m` | Phase 1 pilot 扫描的当前实现 | 已知不含独立 timing 一维曲线；不要让文档继续声称已运行 |
| `type1_plot_phase1_sweeps.m` | 从保存 MAT 重绘六条一维和四张二维图 | 只重绘，不产生新的通信实验数据 |
| `data/experiment_phase1_pilot_20260720.mat` | 实验 8 当前 pilot 小型结果 | 属于补图/有限统计资产，不是 paper 级 BER |
| `tools/plot_experiment_report_figures.py` | 将冻结审计数字画成报告补充图 | 图必须标注来源，不能伪装为 fresh 仿真 |
| `docs/images/experiment_*.png` | 实验报告引用的图像 | 图表不一致时以正式 MAT 和裁决为准 |
| `OTA_CAMPAIGN_PREREG.md` | 若重开多 SNR OTA 的预注册 | 未获授权不得擅自开始板卡采集 |
| `PAPER_DETAILED_OUTLINE.md` | 用户/专家的详细论文结构 | 保持用户内容，不代替实验事实总账 |
| `EXPERT_REVIEW.md`、`README.md`、`RUN_COMMANDS.md`、`TECHNICAL_MANUAL.md` | 与报告重写相关的已修改文档 | 提交前逐一审查 diff，不能假定全由当前任务产生 |

以下仍应默认视为本地工具或早期临时资产，除非用户明确要求，否则不要混入科学提交：

```text
.claude/                  # 本地工具配置
pending_startup_*.png     # 早期队列图；先确认是否已被实验报告引用及是否需要迁入 docs/images
```

上述列表只是本次交接快照，不代替实时 `git status --short`。开始工作前必须重新检查状态和 diff；用户可能继续修改实验报告或专家文档。即使 `REVIEW_VERDICTS.md` 已被 Git 跟踪，也不要代专家重写。不要使用 `git reset --hard`、`git checkout --`、`git clean` 或批量清理 untracked。

---

## 10. 当前仍存在的问题和边界

1. **E1--E3 已由 R23 通过并本地提交。** 数据已两次复现，代码静态检查通过；是否
   push 和打 paper-supplement tag 仍由用户决定。
2. **E1 不是实时闭环。** 它解决了 truth-CSI 依赖，但未把扫描 CSI、选择决策和控制下发
   接入板卡 direct RX。
3. **E1 的 M16 acquisition/data success 为 17/20。** AMC 收益为正但明显低于 truth-CSI
   参考，信道估计和同步门控仍然存在。
4. **真实高速开关 PCB 未制造。** OTA 是四路 raw IQ 上的受控单链模拟。
5. **Phase 2 ICI-DF 迁移受限。** flat 38%--58% 不可写成 TDL 全栈收益；最终约 3.15%。
6. **R15 不是多 SNR OTA 标定。** 只有 33--43 dB 高 SNR 单簇，EVM² ratio 2.112 no-go。
7. **M>8 无穷举最优标尺。** M12/M16 只有贪婪，不知道距全局最优的差距。
8. **Dmax=2 码叠加无增值。** 不要为了贴 GreenMO 叙事强行保留复杂 many-to-many 结构。
9. **移动性很窄。** 100 ms 在 3.2 GHz 约 1.43 km/h；高速移动需新跟踪/扫描架构。
10. **能效不是实测。** 4.39× 是统一组件模型和理想分子口径；65.2 Mbit/J 是本文
    full-stack 锚点，两者不能混排。
11. **两阶段启动只做了 10 s 最新对比。** 旧 60 s 数据来自 517 ms 启动版本；若论文要
    声称最新启动的 60 s 队列统计，应重新 OTA 实测，而不是拼接旧结果。
12. **`EXPERIMENT_REPORT.md` 尚处于工作树审校阶段。** 它已经覆盖 38 个实验和脚本清单，但还没有形成新的提交/freeze；不能因为文字完整就把它当成已经由 R24 审议的冻结事实。
13. **实验 8 缺独立分数定时单变量扫描。** 当前六条一维曲线不含 timing，timing 只在二维 `timingIsolation` 中出现；报告表述必须先改准确，是否补跑第七条曲线需用户明确授权和预注册。
14. **报告图片的证据级别不同。** 一部分直接来自正式 MAT，另一部分由 Python 把冻结审计数字可视化；后者用于帮助阅读，不等于重新运行了实验。所有图必须保留来源说明。

---

## 11. 绝对不要再踩的坑

### 11.1 科研纪律

- 不得看数后把预注册 EVM² 指标切成 RMS-EVM；R15 已用 no-go 证明纪律；
- 不得只挑单 seed、flat 场景或成功帧声称算法有效；必须 TDL、多 seed、同源成对；
- 不得把有限样本零错写成理论 BER=0；报告 bits、errors 和 95% 上界；
- 不得因为代码是自己实现的就降低门槛；R10/R11 多次正确拒绝了自己的功能；
- 不得改代码迁就专家记录中的笔误，例如 R13 PMR 应以冻结代码 8 dB 为准；
- 不得覆盖 `REVIEW_VERDICTS.md` 和 `PAPER_OUTLINE.md` 的用户/专家内容。

### 11.2 物理和算法

- 固定周期泄漏/建立通常被 DM-RS 吸收，不要无证据称其为 ICI；
- Wiener 相噪锚定是 `L(f)=sigma^2 Fs/(4*pi^2 f^2)`，不是 8π²，后者差 3 dB；
- 跨 0.5 ms DM-RS 的 CFO 无模糊范围为 ±1 kHz；接近 800 Hz 必须告警，±2 kHz 会混叠；
- timing 下 `cond(Hhat)` 的变化包含估计/插值伪影，不是真实信道条件数；
- DM-RS in-sample 残差低估 data-RE 残差约 3.1×，白化协方差不能直接用拟合残差；
- i.i.d. 快抖产生近白 ICI，统计带状白化理论增益近零；只有相关 OU 实现级核才有结构；
- 空间白化不能在同 RE 上分离与信号同子空间的自干扰；
- genie beta 零错表示代数可逆天花板，不是实际估计器保证；
- 公共 LO 不必然优于独立 LO；独立 LO 可相噪空间平均，病态信道时排序可反转；
- PSS 高 SNR 平台主要是 realization false peak，不是继续提高 SNR 就能消失；
- M>N 多端口求和的噪声协方差必须用 `Rn=sigma^2*S.'*S`，遗漏会制造虚假阵列增益；
- 固定 QPSK 在高 SINR 饱和，不能用它否定真实 SINR headroom；用 AMC 时必须先冻结表；
- 端口扫描时间、能量和 acquisition 都不能免单。

### 11.3 E1 特有坑

- reference 在 OFDM 后对每层缩放到 0.72 峰值。DM-RS Hhat 包含该已知 TX 比例；未去嵌
  会得到约 +9--10 dB 的虚假 H NMSE。第一次 smoke 已作废；正式代码只用共享 reference
  去嵌，不读取 H truth；
- truth-CSI greedy 不是全局 oracle optimum，estimated 偶尔超过它不矛盾；
- 保留率允许大于 1，分母非正的 seed 必须记 NaN，不能裁剪到 [0,1]；
- 扫描帧必须经过与数据相同的 AWGN、泄漏和 settling，不能用干净 Hhat 给在线臂作弊。

### 11.4 实时/C/MEX

- switch phase 以 DMA/block 起点为基准，不要对绝对 timestamp 直接 `%4`；
- CFO 在 10 ms active frame 内连续，不能每 slot 重置相位；
- C 使用 CP-end FFT 窗；不能把简单 CP 中点当作 MATLAB 默认 OFDM 等价；
- `mwSize k-1` 会无符号下溢，C 内插边界必须显式保护；
- `directflush` 不清硬件/驱动 DMA 描述符；不要把随后到达的积压误判为 flush 失效；
- 可视化 latest-snapshot 不是顺序连续 BER 证据；
- 板卡测试才用 sudo，普通离线 MATLAB 不用 sudo；结束必须关闭 cyclic TX。

---

## 12. 下一步计划

### 12.1 后续任何实验的标准入口

后续项目工程实现的具体实验设计，大部分应从 `EXPERIMENT_REPORT.md` 出发，遵守以下顺序：

1. 在第 2 节实验索引中找到最接近的既有实验，并完整阅读其“实验介绍—目的—设计—量级—结果—边界”；
2. 明确新工作是在补旧实验的哪一个缺口，而不是只写“优化性能”；
3. 从旧实验复制共同 reference、信道、seed、对照臂和统计口径，只改变本轮预注册的目标因素；
4. 先写代数不变量和 off 退化回归，再运行 smoke；smoke 只验证路径，不能形成论文结论；
5. 在看结果前把变量坐标、主指标、置信区间、pass/no-go 门槛、失败分类和停止规则写入 `EXPERT_REVIEW.md` 或用户指定的预注册文档；
6. pilot/paper 必须使用同 seed 成对、多 TDL realization，并保留 outage、失败 seed 和反例；
7. 得到数据后同时更新实验报告、`EXPERT_REVIEW.md` 和 `RUN_COMMANDS.md`，说明可以得出什么以及不能得出什么；
8. 只有专家裁决通过后，才能把结论升级为冻结主张；no-go 和作废运行同样要保留。

特别注意：报告是设计入口，不是允许直接照抄旧参数的理由。新实验若改变物理问题，例如从 flat 变为 TDL、从 oracle 变为估计 CSI、从离线变为 OTA、从固定信道变为移动信道，就必须重新审查指标和门槛。

### 12.2 立即下一步

1. 完成 `EXPERIMENT_REPORT.md` 的逐实验审校，当前优先修正文档中凭空出现、名词未解释、图表缺失或设计与代码不一致的内容；
2. 对实验 8 明确区分“历史实际六条一维扫描”和“尚未运行的 timing 一维扫描”；未经授权不要补数据；
3. 按 R23 将“吞吐域 M12 成为甜点、估计误差使最优 M 下移”写入论文 §V/§VII；
4. 以 `PAPER_OUTLINE.md`/`PAPER_DETAILED_OUTLINE.md` 为骨架进入论文写作，R1--R23 已冻结的实验不因改写报告而自动重开；
5. 提交前检查当前工作树中报告、图片、绘图脚本、Phase 1 pilot MAT 和既有用户修改的归属，不能一把全加；
6. 由用户决定是否 push 和是否打新的 paper/report tag；当前不要自行 push；
7. 写作中若发现真正的实验缺口，先单独预注册并请求用户重新开放实验。

### 12.3 若论文审稿前只做必要增强

- 若用户批准，补做实验 8 的分数定时一维曲线和交互残差分析，避免把 `cond(Hhat)` 插值伪影解释成真实物理恶化；
- 把 E1 DM-RS 选择器部署到 direct RX 控制面，做真实控制时延/扫描更新闭环；
- 若需要多 SNR OTA 定量标定，用外部衰减器或 TX 功率步进覆盖约 5--25 dB，不能只调
  RX gain；
- 若需要最新队列主张，重跑两阶段 60 s OTA 并报告 pending/dropNew/分段时延。

### 12.4 明确不在当前论文继续做

R23 已明确“下一阶段为论文写作，不再新增实验”。当前对 `EXPERIMENT_REPORT.md` 的补充属于既有证据整理，不等于开放新的无线实验。TX/TMA、ISAC、RIS、子带 E4、多 SNR OTA 重采和真实 PCB 均未获当前轮授权；除非用户明确重新开放，不要主动扩展。真实开关 PCB、移动跟踪和目录重构适合作为独立后续项目。

---

## 13. 长期协作和提交规则

每次代码或实验改动必须同时完成：

1. `EXPERIMENT_REPORT.md`：新增或修改对应实验的背景、目的、设计、结果、分析、边界、图和脚本索引；不能只追加一个结论数字；
2. `EXPERT_REVIEW.md`：记录改了什么、配置/seed、原始数字、可得结论、不能得到什么；
3. `RUN_COMMANDS.md`：维护可复制命令、输入输出、远端/sudo 条件和正式路径；
4. `README.md`：提交变更记录精简追加一行；
5. 最终回复：简短说明做了什么、效果、下一步；
6. 修改专家意见前先审查其物理和统计合理性；有实质冲突时停止并请求裁决；
7. R23 已完成科学验收和本地提交，但未经用户明确授权仍不要 push 或创建远端 tag。

文档/代码交付前至少执行：

```bash
git diff --check
git status --short
```

MATLAB 新文件在 RX 上执行 `checkcode(...,'-id')`，关键正式运行至少做一次 fresh 字段级
`isequaln`。图片必须来自正式 MAT/脚本，SHA 与远端一致。不要把临时 smoke、scratch、
本地工具配置或大体积 raw IQ 混入科学提交。
