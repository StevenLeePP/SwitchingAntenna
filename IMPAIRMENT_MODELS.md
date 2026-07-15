# 非理想性模型：严格公式、理论预测与实验验证

更新时间：2026-07-15（Asia/Shanghai）
适用代码版本：`cmex` 分支，`9ea0f7c` + 未提交 Phase-1 工作区
验证数据来源：2026-07-14 独立复现运行（RX 服务器 `/tmp/review_checks.log`、
`/home/bupt/type1_offline_captures/type1_phase1_smoke_20260714_111607/phase1_sweeps.mat`、
`type1_offline_multiuser_20260714_111758`、
`data/type1_valid_ota_iq_20260714_004458_seq2230_*_paired_switch_injection.mat`）

> 本文档给出当前离线链路中**每一个已实现的非理想性因素**的精确数学模型、
> 对系统指标（BER / EVM / cond(H)）的理论预测，以及与实测数据的逐项对照。
> 所有实测数字均来自上述已保存的运行产物，可按第 8 节命令复现。

---

## 0. 记号与链路基准

| 记号 | 含义 |
|---|---|
| $F_s = 30.72\,\mathrm{MS/s}$ | TX / 虚拟链采样率（`cfg.txSampleRate`） |
| $F_r = 4F_s = 122.88\,\mathrm{MS/s}$ | 物理 RX / 开关采样率，$T_r = 1/F_r = 8.138\,\mathrm{ns}$ |
| $\Delta f_{sc} = 30\,\mathrm{kHz}$ | 子载波间隔 |
| $T_{sym} \approx 1096/F_s = 35.677\,\mathrm{\mu s}$ | 常规 OFDM 符号周期（CP=72；slot 首符号 CP=88，近似忽略） |
| $x_p[n]$ | 用户（layer）$p$ 的基带发射波形，$p=1..4$ |
| $r_k[n]$ | 物理天线 $k$ 的 30.72-MS/s 接收流，$k=1..4$ |
| $v_q[m]$ | 去交织后的虚拟链 $q$（30.72 MS/s） |
| DM-RS | Type-1、单符号、$l=2$；每 slot（0.5 ms）估计一次每链每层信道 |

**开关-去交织恒等式**（理想开关，[type1_digital_switch.m](type1_digital_switch.m)）：

$$v_q[m] = \text{raw122}(4m+q,\; q), \qquad q = 1..4$$

即虚拟链 $q$ = 物理天线 $q$ 在原始采样相位 $q$ 上的 4 倍抽取，各链间有固定
$T_r$ 时偏（每链常相位，被 DM-RS 的 $\hat H$ 吸收）。

**基准锚点**（无任何非理想性，flat 信道，32 dB SNR，850 Hz 公共 CFO）：
四层 BER = 0，EVM ≈ 2.72–2.78%，condP95 ≈ 1.49。

---

## 1. 中心结论：静态可吸收 / 动态残余 二分定理

**命题**：若某非理想性使"4 路天线信号 → 4 条虚拟链"的端到端映射是
**线性、4 样点移不变、系数在一帧内恒定**的（即 polyphase LTI），则该映射在
每个子载波上退化为一个恒定 4×4 复矩阵 $G(f)$，等效信道变为
$\tilde H(f) = G(f)\,H(f)$。Type-1 DM-RS 逐子载波估计的正是 $\tilde H$，
RZF 直接对 $\tilde H$ 求逆，因此该类损伤**在高 SNR 下不产生 BER**，只通过
$\mathrm{cond}(\tilde H)$ 的噪声放大反映在 EVM 上。

**推论（分类）**：

| 类别 | 损伤 | 判据 |
|---|---|---|
| 静态可吸收 | 固定隔离度泄漏、固定建立时间、用户定时偏移、用户功率不平衡、支路增益/相位失配 | 一帧内系数恒定 → polyphase LTI |
| 动态残余 | 用户间差分 CFO、相位噪声、过渡时钟抖动、时变建立时间、信道时变 | 系数在帧内时变 → 逃逸 LTI 等价类 |

**实验验证**（smoke 扫描，每点 636,480 bits，零误码显示为上界 $1.57\times10^{-6}$）：

| 1-D 扫描 | 参数范围 | BER 实测 | 预测 | 符合 |
|---|---|---|---|---|
| isolation | 15 dB → ∞ | 平坦 @1.57e-6 | 静态吸收 → 0 | ✅ |
| rise | 0 → 10 ns | 平坦 @1.57e-6 | 静态吸收 → 0 | ✅ |
| power | 0 → ±3 dB | 平坦 @1.57e-6 | 静态吸收 → 0 | ✅ |
| phaseNoise | 0 → σ=2.5e-4 | 平坦 @1.57e-6 | 漂移 <1.6°，低于判决余量 | ✅ |
| jitter | 0 → 100 ps | 平坦 @1.57e-6 | 扰动 −55 dB，不可见 | ✅ |
| **cfo** | 0 → 满幅 | **1.57e-6 → 0.133** | 残余旋转越过 45° 判决界 | ✅ |

六条曲线的"平坦/非平坦"分裂与二分定理的预测**完全一致**。

---

## 2. 用户级非理想性

### 2.1 功率不平衡

**实现**（[type1_offline_link.m:32](type1_offline_link.m#L32)）：

$$x_p'[n] = g_p\, x_p[n], \qquad g_p = 10^{P_p/20}$$

测试值 $P = [-3, 0, 3, -1.5]$ dB。

**理论**：等效信道列缩放 $\tilde H = H\,\mathrm{diag}(g)$，被 $\hat H$ 完全吸收。
唯一残余机制：RZF 正则项 $\lambda = \lambda_0 \cdot \overline{\|H\|^2}$
按平均功率缩放，弱用户的解算噪声放大 $\propto 1/g_p$；±3 dB 在 32 dB SNR
下余量充足。

**预测**：BER 不变。**实测**：power 扫描平坦 ✅。

### 2.2 定时偏移（带限分数延迟）

**实现**（[type1_offline_link.m:84-97](type1_offline_link.m#L84)）：DFT 域精确延迟

$$x_p'[n] = \mathrm{IFFT}\!\left[\mathrm{FFT}(x_p)\cdot e^{-j2\pi f \tau_p}\right]$$

（零填充至 $2^{\lceil\log_2 2N\rceil}$，无线性插值的高频幅度滚降伪损伤。）
测试值 $\tau = [-12.5, 3.25, 8.5, -6.75]$ 样点，全部在 CP（72 样点）内。

**理论**：每子载波上给用户 $p$ 的信道列乘 $e^{-j2\pi f_k \tau_p/F_s}$ ——
**酉列缩放**，被 $\hat H$ 吸收，且**真实信道的奇异值/条件数不变**。

**预测**：BER、EVM、真 cond 均不变。
**实测**：BER 平坦 ✅；但 `timingIsolation` 热图中即使隔离度 50 dB，
condP95 仍随定时从 1.507 涨至 1.625（+8%）。**该增长不是物理效应**：
它来自 `nrChannelEstimate` 在频域相位斜坡下的插值失配，是 $\mathrm{cond}(\hat H)$
的估计器伪影（见第 7 节开放问题 O2）。

### 2.3 载波频偏（CFO）——当前多用户场景的主导损伤

**实现**（[type1_offline_link.m:34,37-38](type1_offline_link.m#L34)）：

$$x_p'[n] = x_p[n]\, e^{j2\pi (f_c + \Delta f_p) n / F_s}$$

测试值 $f_c=850$ Hz（公共），$\Delta f = [-350, 125, 620, -900]$ Hz（每用户）。

**理论**：接收机只估计一个公共 CFO $\hat F$（PSS/CP 基），残余
$\delta_p = f_c + \Delta f_p - \hat F$。两个效应：

**(a) 帧内相位旋转（主导）**。DM-RS 在 $l=2$ 估计信道后，数据符号 $l$ 的星座
相对旋转

$$\theta_{p,l} = 2\pi\,\delta_p\,(l-2)\,T_{sym}$$

QPSK 硬判决在 $|\theta|>\pi/4$ 时单比特翻转（无噪声时每符号 BER=0.5，
$|\theta|>3\pi/4$ 时为 1）。无噪声逐层 BER 预测：

$$B(\delta_p) = \frac{1}{13}\sum_{l\in\{0,1,3..13\}}\left[\tfrac12\,\mathbb{1}_{\pi/4<|\theta_{p,l}|\le 3\pi/4} + \mathbb{1}_{|\theta_{p,l}|>3\pi/4}\right]$$

45° 判决界对应的残余门限（最远符号 $\Delta l = 11$）：

$$\delta_{th} = \frac{1}{8 \cdot 11 \cdot T_{sym}} \approx 318\ \mathrm{Hz}$$

**(b) ICI（次级）**。$\mathrm{SIR}_{ICI} \approx 3/(\pi\,\delta_p/\Delta f_{sc})^{-2}$，
即功率比 $(\pi\varepsilon)^2/3$，$\varepsilon = \delta_p/\Delta f_{sc}$。
在 $\delta=793$ Hz 时 $-26.4$ dB（EVM 贡献约 4.8%），不构成主导。

**理论 vs 实测**（3 帧，实测残余 $\hat\delta = [-171.4, 300.9, 792.9, -737.5]$ Hz）：

| Layer | $\hat\delta_p$ (Hz) | 旋转/符号 | >45° 的符号数 | **BER 预测** | **BER 实测** | 偏差 |
|---|---:|---:|---:|---:|---:|---:|
| 1 | −171.4 | 2.20° | 0（最大 24.2°） | 0 | 0 | — |
| 2 | +300.9 | 3.87° | 0（最大 42.5°，距界 2.5°） | ≈0（噪声致边界抖动） | 0.0137 | 定性符合 |
| 3 | +792.9 | 10.18° | 7（$\Delta l\ge5$） | **0.2692** | **0.273** | **+1.4%** |
| 4 | −737.5 | 9.47° | 7（$\Delta l\ge5$） | **0.2692** | **0.259** | **−3.8%** |

EVM 预测（旋转主导，$\mathrm{EVM}\approx\mathrm{rms}_l\,2|\sin(\theta_l/2)|$）：

| Layer | EVM 预测 | EVM 实测 | 备注 |
|---|---:|---:|---|
| 1 | 24.1% | 24.9% | +3% |
| 2 | 42.0% | 47.2% | +12%（ICI/相噪贡献） |
| 3 | 100.5% | 115.4% | +15%（同上） |
| 4 | 93.5% | 94.5% | +1% |

**结论：CFO 模型的 BER 与 EVM 均被解析公式定量命中（BER 误差 <4%），
层间分裂由 318 Hz 门限精确解释。** Layer 2 恰在门限边缘（42.5° vs 45°），
其小 BER（0.0137）与噪声边界抖动一致。

**逐用户 CFO 补偿基线**（[type1_analyze_user_cfo.m](type1_analyze_user_cfo.m)）：
跨 slot DM-RS 相关相位 $\hat\delta_p = \mathrm{median}_s\,\angle\langle \hat h_{p,s},\hat h_{p,s+1}\rangle / (2\pi\cdot 0.5\,\mathrm{ms})$，
再以时变列相位 $e^{j2\pi\hat\delta_p \Delta t}$ 修正 RZF 信道。
实测：BER $[0, 0.0137, 0.273, 0.259] \to [0, 5.87\times10^{-5}, 9.49\times10^{-4}, 0]$
（Layer 3 降低 288 倍）。

> **估计器边界（必须遵守）**：slot 间隔 0.5 ms ⇒ 无模糊范围 $\pm 1$ kHz。
> 当前实测残余已达 793/−738 Hz（界限的 74–79%）。任何 $|\delta|>1$ kHz 的
> 场景（如计划中的 ±2 kHz 压力）该估计器将混叠且无告警——使用前必须加
> $|\hat\delta| > 800$ Hz 告警断言或改用更短基线的估计。

### 2.4 相位噪声（自由振荡 Wiener 模型）

**实现**（[type1_offline_link.m:99-107](type1_offline_link.m#L99)）：

$$\phi_p[n] = \sum_{k\le n} \sigma_p w_p[k], \quad w\sim\mathcal N(0,1);\qquad x_p'[n] = x_p[n]e^{j\phi_p[n]}$$

测试值 $\sigma = [1.5, 2.0, 1.0, 2.5]\times10^{-4}$ rad/sample。

**理论**：扩散系数 $D=\sigma^2 F_s$；载波谱为 Lorentzian，
FWHM 线宽 $\Delta\nu = D/2\pi$；远端相噪：

$$\boxed{\;L(f) = \frac{\sigma^2 F_s}{4\pi^2 f^2}\;}\qquad(\text{IEEE } L(f)=\tfrac12 S_\phi^{one\text{-}sided}\text{ 与 Lorentzian 尾部一致})$$

> **勘误**：EXPERT_REVIEW.md §9 原公式 $\sigma^2F_s/(8\pi^2f^2)$ **错误**，
> 低估相噪 3.01 dB。本文公式经数值证伪实验确认（下表），以本文为准。

**数值验证**（Welch 谱，$N=2^{24}$ 样本，$\sigma=1.5\times10^{-4}$，$F_s=30.72$ M）：

| 量 | 值 |
|---|---:|
| 实测 $L(10\,\mathrm{kHz})$ | **−97.27 dBc/Hz** |
| $4\pi^2$ 公式（本文） | **−97.57 dBc/Hz**（差 0.30 dB ✅） |
| $8\pi^2$ 公式（原文档） | −100.58 dBc/Hz（差 3.31 dB ❌） |

**σ ↔ 器件 mask 换算表**（$F_s = 30.72$ MS/s，@10 kHz）：
$\sigma = 2\pi f\sqrt{L(f)/F_s}$

| $\sigma$ (rad/sample) | $L(10\,\mathrm{kHz})$ |
|---:|---:|
| $1.0\times10^{-4}$ | −101.1 dBc/Hz |
| $1.06\times10^{-4}$ | −100.6 dBc/Hz |
| $1.5\times10^{-4}$ | −97.6 dBc/Hz |
| $2.5\times10^{-4}$ | −93.1 dBc/Hz |

**BER 影响预测**：DM-RS（$l=2$）每 slot 重估 CPE；至最远数据符号的漂移
std $=\sigma\sqrt{11\times1096}$ = 0.94°（σ=1.5e-4）～1.57°（σ=2.5e-4），
远小于 45° 判决余量 → 零 BER。**实测**：phaseNoise 扫描平坦 ✅。
线宽 $\Delta\nu$=0.11 Hz ≪ PSS/CP 估计分辨率 → 对同步无影响 ✅。

**适用边界**：Wiener 模型只对应**自由振荡器**；锁定 PLL 的相噪有界
（环内平坦、环外跟随），Phase 2 起改用单极/双极 PLL PSD 成形。

---

## 3. 开关级非理想性

（[type1_apply_switch_impairments.m](type1_apply_switch_impairments.m)）

### 3.1 隔离度 / 关断泄漏

**实现**（:33-39, :67）：raw 样点 $n$（相位 $q(n) = n \bmod 4$）的合成目标

$$t[n] = \sum_{k=1}^{4} L_{q(n),k}\, r_k[n], \qquad
L = \begin{cases} L_{qq}=1 \\ L_{qk}=\alpha\, e^{j\varphi_{qk}},\ k\ne q\end{cases},
\quad \alpha = 10^{-\mathrm{IS}/20}$$

默认 $\varphi\equiv 0$（同相最坏情形）。

**理论**：$L$ 恒定 → polyphase LTI → $\tilde H(f) = L\,D(f)\,H(f)$，被 DM-RS 吸收
→ **BER 不变**；代价是条件数。同相等幅泄漏时 $L = (1-\alpha)I + \alpha J$
（$J$ 全 1 阵），特征值 $\{1+3\alpha,\ (1-\alpha)^{\times 3}\}$：

$$\mathrm{cond}(L) = \frac{1+3\alpha}{1-\alpha}
\qquad\Rightarrow\qquad \mathrm{IS}=25\,\mathrm{dB}:\ \alpha=0.0562,\ \mathrm{cond}(L)=1.238$$

即 25 dB 隔离度预测 cond 乘性膨胀 **+23.8%**（一阶，well-conditioned $H$ 时）。

**实测验证**（25 dB + 5 ns 联合注入；5 ns 建立附加约 −31 dB 链间混合，见 3.2）：

| 路径 | condP95 (ideal → impaired) | 相对增量 | 预测 +23.8% |
|---|---|---:|---|
| OTA 同段 raw122 配对 | 4.4739 → 5.6021 | **+25.2%** | ✅（差 1.4 pp） |
| 离线 flat 锚点 | 1.4879 → 1.9119 | **+28.5%** | ✅（差 4.7 pp，含建立/估计噪声） |
| BER（两路径） | 0 → 0 | 0 | ✅ 静态吸收 |
| OTA EVM | 2.178% → 2.257% | +0.079 pp | 方向一致 |

**cond 增量的解析预测与 OTA/离线双路径实测在 5 个百分点内吻合**——这是
静态泄漏模型最强的定量验证。

### 3.2 有限建立时间（一阶响应）

**实现**（:53-60, :65-74）：raw 速率一阶 IIR

$$y[n] = (1-\beta)\,y[n-1] + \beta\, t[n], \qquad
\beta = 1 - e^{-T_r/\tau},\quad \tau = \frac{t_{rise}}{\ln 9}\ (10\text{–}90\%)$$

**理论**：常数 $\beta$ 展开为 $y[n] = \sum_{i\ge0}\beta(1-\beta)^i t[n-i]$。
去交织后虚拟链 $q$ 获得来自**前一开关相位**（即前一天线组合）的几何衰减
贡献，首阶链间混合系数 $(1-\beta)$，且映射仍是 polyphase LTI（4 样点周期
恒定）→ **被 DM-RS 吸收，BER 不变**；DC 增益 $\sum\beta(1-\beta)^i = 1$，无净幅度损失。

| $t_{rise}$ | $\tau$ | $\beta$ | 链间混合 $1-\beta$ |
|---:|---:|---:|---:|
| 5 ns | 2.2756 ns | 0.97204 | 0.02796（**−31.1 dB**） |
| 10 ns | 4.5512 ns | 0.83272 | 0.16728（**−15.5 dB**） |

**实测验证**：
- 代数回归输出 `beta@10ns=0.832723`，与解析值 $1-e^{-8.1380/4.5512}=0.832723$
  **6 位有效数字一致** ✅；
- 递推不变量 $y[2]=(1-\beta)y[1]+\beta t[2]$ 通过 ✅；
- rise 扫描（0→10 ns）BER 平坦 ✅（即使混合达 −15.5 dB，静态吸收成立）；
- 25 dB+5 ns 联合注入的 cond 增量超出纯泄漏预测的部分（+1.4~4.7 pp）
  与 −31 dB 建立混合的量级一致。

**物理含义**：在 122.88 MS/s（$T_r$=8.14 ns）下，10 ns 级商用开关的
建立混合高达 −15.5 dB——但只要它是**恒定**的，DM-RS 就能校准。真正的
器件风险在于建立时间的**时变部分**（温度、驱动抖动），见 3.3 与 Phase 2。

### 3.3 过渡时钟抖动

**实现**（:44-51, :57）：

$$dt[n] = T_r + (j[n]-j[n-1]),\quad j\sim\mathcal N(0,\sigma_j^2);\qquad
\beta[n] = 1-e^{-dt[n]/\tau}$$

**理论**：抖动通过时变 $\beta[n]$ 产生**时变链间混合** ——这是当前模型中
唯一天然的非 LTI 开关项。一阶灵敏度：

$$\sigma_\beta = \frac{1-\beta}{\tau}\,\sqrt2\,\sigma_j
\quad\xrightarrow{\ t_{rise}=5\,\mathrm{ns},\ \sigma_j=100\,\mathrm{ps}\ }\quad
\sigma_\beta = 1.74\times10^{-3}\ (\textbf{−55.2 dB})$$

**预测**：−55 dB 扰动在 32 dB SNR 下不可见 → BER/EVM 无变化。
**实测**：jitter 扫描（0→100 ps）平坦 ✅。

**作用域声明（重要）**：
1. 本模型中抖动**只**调制建立递推；$t_{rise}=0 \Rightarrow \beta\equiv1$，
   抖动数学上是空操作。它**不**模拟采样边界位移本身（即"采到过渡中样点"
   的效应）。"抖动无影响"是**本模型该参数区间的结论**，不是物理普适结论。
2. 达到可见效应（−40 dB 混合扰动）所需 $\sigma_j \approx 0.58$ ns
   （$t_{rise}=5$ ns 时）——远超实际时钟抖动。Phase 2 若要研究抖动 ICI，
   必须扩展模型加入边界位移项（亚样点插值）。

---

## 4. 信道与噪声

### 4.1 3GPP TDL-A + Kronecker 空间相关

**实现**（[type1_make_tdl_a_channel.m](type1_make_tdl_a_channel.m)）：

$$h_{r,t}(\tau) = \sum_{k=1}^{23}\sqrt{p_k}\,\big[L_R W_k L_T^H\big]_{r,t}\,\delta(\tau - d_k\cdot DS)$$

- $d_k, p_k$：TS 38.901 Table 7.7.2-1 TDL-A 归一化时延/功率（23 抽头），
  功率归一 $\sum p_k = 1$；
- $DS = 100$ ns（可配）；
- Kronecker 相关：$R_R(i,j)=\rho_r^{|i-j|}$、$R_T = \rho_t^{|i-j|}$（$\rho=0.5$），
  $L_R L_R^H = R_R$（Cholesky）；$W_k$ i.i.d. $\mathcal{CN}(0,1)$；
- 频域施加（$2^{\lceil\log_2(N+\tau_{max})\rceil}$ 零填充，无循环卷绕）；
- **静态实现**（`dopplerHz==0` 断言）——时变信道是显式的未来参数，不做静默近似。

**预测**：频选衰落下部分子载波深衰，uncoded QPSK 在 32 dB SNR 有非零
BER 地板；cond 显著高于 flat。
**实测**：PBCH/MIB 通过；BER $[6.3\times10^{-6}, 5.7\times10^{-4}, 3.4\times10^{-4}, 2.7\times10^{-4}]$，
condP95 = 40.3（flat 为 1.49）✅ 与频选深衰预期一致。

### 4.2 AWGN 注入点

**实现**（[type1_offline_link.m:47-51](type1_offline_link.m#L47)）：信道输出后、
开关前，按后信道平均功率定义 SNR，每天线支路独立注入。

**与真实单链的等价性说明**：白噪声不同时刻样点独立 ⇒ 对**理想开关**，
"每支路 30.72-M 预注入"与"合成后单链 122.88-M 后注入再去交织"给出同分布
的 4 条独立噪声流——两种注入点**等价**。差异仅在非理想开关：预注入噪声
会被 $L$ 矩阵与建立 IIR 一同混合（链间噪声相关），后注入不会。当前选择
偏保守（噪声也被开关损伤染色）。单链 $N\times B$ ADC 噪声系数/ENOB 模型
属 Phase 2 条目。

---

## 5. OTA 配对注入交叉验证（单点，趋势级）

同一段后稳定期 OTA raw122（PSS/PBCH 有效、ideal EVM 2.18%，采集器
[type1_capture_ota_valid_raw122.m](type1_capture_ota_valid_raw122.m) 三门限筛选）
上，ideal 与 25 dB/5 ns 两支配对（[type1_analyze_raw122_switch_pair.m](type1_analyze_raw122_switch_pair.m)）：

| 指标 | 理论预测 | OTA 实测 | 离线实测 |
|---|---|---|---|
| BER | 不变（静态吸收） | 0 → 0 ✅ | 0 → 0 ✅ |
| PSS/PBCH | 不受影响 | 均通过 ✅ | 均通过 ✅ |
| cond 相对增量 | +23.8%（cond(L)）| +25.2% ✅ | +28.5% ✅ |
| EVM 增量方向 | 正 | +0.079 pp ✅ | +0.407 pp ✅ |

**边界**：这是单点"功能与趋势"验证；EVM 增量绝对值 OTA 与离线相差 5 倍，
归因于 SNR/真实信道/噪声协方差未拟合一致——**不得**表述为"绝对幅度已校准"。
论文级结论需多 SNR × 多信道实现的归一化增量统计。

---

## 6. 理论-实验验证总表

| # | 模型 | 关键公式 | 预测 | 实测 | 吻合度 |
|---|---|---|---|---|---|
| V1 | 建立 IIR 系数 | $\beta=1-e^{-T_r\ln9/t_{rise}}$ | 0.832723 @10ns | 0.832723 | 6 位精确 |
| V2 | 0 dB 同相泄漏 | $y=\sum_k r_k$ | 相干和 | 代数回归 <1e-12 | 精确 |
| V3 | CFO→BER | $B(\delta)$ 45° 计数式 | 0.2692 / 0.2692 | 0.273 / 0.259 | ±4% |
| V4 | CFO→EVM | $\mathrm{rms}\,2\sin(\theta/2)$ | [24.1, 42.0, 100.5, 93.5]% | [24.9, 47.2, 115.4, 94.5]% | 1–15% |
| V5 | CFO 门限 | $\delta_{th}=318$ Hz | L1,2 无错 / L3,4 大错 | 层分裂完全一致 | ✅ |
| V6 | 泄漏→cond | $(1+3\alpha)/(1-\alpha)=1.238$ | +23.8% | +25.2% (OTA) / +28.5% (离线) | 1.4–4.7 pp |
| V7 | 相噪 PSD | $L(f)=\sigma^2F_s/(4\pi^2f^2)$ | −97.57 dBc/Hz | −97.27（数值谱） | 0.3 dB |
| V8 | 相噪→BER | 漂移 ≤1.6° ≪ 45° | 0 | 扫描平坦 | ✅ |
| V9 | 抖动扰动 | $\sigma_\beta$=−55 dB | 不可见 | 扫描平坦 | ✅ |
| V10 | 静态吸收 | polyphase LTI | iso/rise/power/timing BER 不变 | 4 条扫描平坦 + 双路径 BER 0→0 | ✅ |
| V11 | 补偿基线 | 跨 slot DM-RS 相位 | 大幅消除旋转 BER | 0.273→9.49e-4（288×） | ✅ |

---

## 7. 未解释观测与开放问题（必须诚实携带）

| # | 观测 | 现状 |
|---|---|---|
| O1 | 补偿后 Layer 3 残余 BER $9.49\times10^{-4}$（453 bits），而 $\|\hat\delta\|$ 更接近门限的 Layer 4 为 0 | 候选归因：残余估计误差、未补偿 ICI（−26 dB @793 Hz）、相噪叠加；需 Phase 2 消融定位，暂不得写成已解释 |
| O2 | 隔离度 50 dB 时 cond 仍随定时偏移 +8%（理论应不变） | 已定性归因为 $\mathrm{cond}(\hat H)$ 的信道估计插值伪影；论文必须区分 $\mathrm{cond}(H)$ 与 $\mathrm{cond}(\hat H)$，或改报真信道 cond |
| O3 | `cfoIsolation` 热图三行在 4 位小数内相同——静态隔离度与 CFO **零交互** | 与二分定理一致的**负结果**；论文应作为鲁棒性结论呈现，交互效应研究转向时变损伤 |
| O4 | 残余 CFO 估计器 ±1 kHz 混叠界 | 未设告警；±2 kHz 压力测试前必须处理（见 2.3） |
| O5 | 文档引用数与默认参数复现值有漂移（0.011 vs 0.0137 等） | 引用处须注明 frames/seed，或以提交版代码重新生成 |

---

## 8. 复现命令

```bash
# RX 服务器（无需 sudo，纯离线）
cd /home/bupt/tools/matlab_test/nr4x4_type1

# V1/V2：代数回归
/home/bupt/tools/matlab/bin/matlab -batch "type1_validate_switch_impairments"

# 4.1：信道模型回归
/home/bupt/tools/matlab/bin/matlab -batch "type1_validate_channel_models"

# V3-V5, V11：多用户 + 逐用户 CFO 补偿（3 帧配对）
TYPE1_OFFLINE_FRAMES=3 TYPE1_OFFLINE_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_offline_multiuser"

# V8-V10, O3：smoke 扫描（每点 1 帧，结构回归）
TYPE1_SWEEP_PROFILE=smoke TYPE1_SWEEP_FRAMES=1 \
TYPE1_OFFLINE_OUTPUT_ROOT=/home/bupt/type1_offline_captures \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_run_phase1_sweeps"

# 第 5 节：OTA 配对注入（需已有合格 raw122；采集器需板卡+sudo）
TYPE1_OTA_RAW_FILE=type1_valid_ota_iq_20260714_004458_seq2230_raw122_csingle_iq4.bin \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_validate_ota_switch_model"
```

V7（相噪谱数值验证）脚本存于 RX `/tmp/review_checks.m` 第 [R4] 节，
16.7M 样本 Welch 谱，约 20 s。

---

## 9. 与论文写作的映射

- 第 1 节二分定理 → 论文 System Model 后的核心 Lemma（静态开关损伤的
  DM-RS 可吸收性），V10 为其实验证据；
- V3–V6 的定量命中 → 论文 "model validation" 小节，是审稿人信任
  后续扫描结果的基础；
- O1–O5 → 论文 limitations / future work 的诚实来源，也是 Phase 2
  （时变损伤 + 白化 RZF）的动机链。

---

## 10. Phase 2：时变建立、ICI 捕获与物理约束核

### 10.1 有限带宽的建立时间过程

名义 10--90% 建立时间 `rise` 对应 $\tau_0=t_{rise}/\ln 9$。当前 Phase 2 模型为

$$
\tau[n]=\tau_0\max\{0.01,1+a_s\sin(2\pi f_s n/F_r)+a_f w[n]\},\qquad
\beta[n]=1-\exp\!\left(-\frac{\Delta t[n]}{\tau[n]}\right),
$$

其中 OU/AR(1) 快过程满足

$$w[n]=\alpha w[n-1]+\sqrt{1-\alpha^2}\,\epsilon[n],\qquad
\alpha=\exp[-1/(F_r\tau_c)],\quad \epsilon\sim\mathcal N(0,1).$$

实测 `betaLag1` 与该 $\alpha$ 在 8 ns/100 ns/1 us 三点吻合到 3--4 位；fast=0.6 的
`tauFloorHit=4.92%` 与高斯尾概率 4.94% 一致。同边缘方差下，BER 随相关时间由 i.i.d.
的约 $1.7\times10^{-3}$ 升至 1 us 的 $8.2\times10^{-3}$--$1.12\times10^{-2}$，
所以器件包络必须约束抖动 PSD/相关时间，不能只给一个方差。

### 10.2 一阶误差递推与精确 drive

动态输出与静态孪生分别为

$$y_n=(1-\beta_n)y_{n-1}+\beta_n t_n,\qquad
y_{0,n}=(1-\beta_0)y_{0,n-1}+\beta_0t_n.$$

令 $e_n=y_n-y_{0,n}$、$\delta\beta_n=\beta_n-\beta_0$，忽略二阶
$\delta\beta_n e_{n-1}$ 后得到

$$e_n\approx(1-\beta_0)e_{n-1}+\delta\beta_n
\underbrace{(t_n-y_{0,n-1})}_{D_n}.$$

R10 的近似 bank `{t[n],t[n-1]}` 只能捕获 47.5/51.3%；改用精确 drive
$D_n=t_n-y_{0,n-1}$ 后升至 63.7/64.5%。这是回归量定义修正，不是相互矛盾的实验。

实际单链 ADC 不知道 $t_n$ 或静态态，但在名义 $\beta_0$ 下可形成

$$\hat t_n=\frac{y_n-(1-\beta_0)y_{n-1}}{\beta_0},\qquad
\hat D_n=\hat t_n-y_{n-1}=\frac{y_n-y_{n-1}}{\beta_0}.$$

`type1_received_drive` 只实现右式，并用配置的 rise/Fs 求 $\beta_0=0.591005$；不读任何
动态真值。20 dB 两 seed 的 received capture 为 63.65/64.35%，与 200 dB 的
63.65/64.34% 几乎相同，说明该场景的主要边界不是 drive 是否存在于 ADC 数据，而是
能否在信道/判决误差下稳定兑现为 BER 增益。

### 10.3 ICI 核、捕获律与自由度

对带限实值调制，频域核满足

$$B(-u)=B^*(u).$$

因此 Q 半宽核不是 $2(2Q+1)$ 个实自由度，而是中心 1 个实数加 Q 对共轭复数：
$1+2Q$ real DOF。冻结 Q=12 时即 100-real-DOF 无约束双 bank压缩为 25 real DOF；
13 DOF 只对应 Q=6，不能混用。

对一阶低通快过程，半宽 Q 可捕获的核能量近似

$$C(Q)=\frac{2}{\pi}\arctan\!\left(\frac{Q+1/2}{T_{sym}f_c}\right),\qquad
\mathrm{gap\ reduction}\approx\eta\,C(Q),$$

其中 $\eta$ 表示判决、信道估计与迭代造成的实现效率。隔离场景 Q/迭代消融在三点
±4% 命中，3 次 soft-DF 的 $\eta\approx0.795$；这条捕获律不应外推成 full stack
必然获得相同效率。

### 10.4 天花板与集成边界表

| 层级/回归量 | seed 20261001 | seed 20261003 | 解释 |
|---|---:|---:|---|
| R10 单 bank 真值 capture | 0.2617 | 0.3527 | 核模型缺跨相位态 |
| R10 近似双 bank capture | 0.4746 | 0.5134 | `{t[n],t[n-1]}` 近似 |
| R11 exact constrained capture | 0.6372 | 0.6452 | 精确 $t-y_{0,prev}$，25 DOF |
| received-drive capture (20 dB) | 0.6365 | 0.6435 | ADC 可观测 $\hat D$ |
| DDCE+received gap closure | 0.1089 | 0.4065 | realization 离散；统一门失败 |

received-drive 相对 DDCE 的 gap 增量为 8.78/32.60 pp；第一点低于预注册 10 pp，故
实际接收机未通过。这个结果与 64% capture 并不冲突：capture 用同 realization 真值
残差回答模型结构上限，BER gap 还受深衰、Hhat 和判决错误定位共同约束。Phase 2 的
最终表述是“状态结构可观测，但 full stack 的稳定迁移受信道估计质量和模拟状态
可观测性双门控制”，不是“不可恢复”或“已完成恢复”。

---

## 11. Phase 2：有界 RX-PLL 相噪与 LO 拓扑

### 11.1 单极 OU/AR(1) 模型与 PSD

RX-LO 相位采用稳态有界过程

$$\phi[n]=\alpha\phi[n-1]+\sigma_\phi\sqrt{1-\alpha^2}\,w[n],\qquad
\alpha=e^{-2\pi B_{PLL}/F_{rate}},$$

其中 $\mathrm{var}(\phi)=\sigma_\phi^2$。连续极限双边相位 PSD（也等于小相位近似下的
SSB $L(f)$）为

$$L(f)=\frac{\sigma_\phi^2}{\pi B_{PLL}}
\frac{1}{1+(f/B_{PLL})^2}.$$

2 deg、100 kHz、30.72 MS/s 的数值 Welch 在 10.1 kHz 得 -85.14 dBc/Hz，理论
-84.16 dBc/Hz，误差 -0.98 dB。该模型是单极有界 PLL 近似，不是 TX 用户侧的
自由 Wiener 相噪；两者在配置和文档中分开。

### 11.2 common/independent 注入与 CPE

common 在开关合成后的 stitched122 上乘 $e^{j\phi[n]}$；independent 在开关前四个
30.72-MS/s 支路乘 $\mathrm{diag}(e^{j\phi_1[n]},...,e^{j\phi_4[n]})$。前者每个物理
时刻只有一个相位，但去交织后的四个 virtual 分量相差 8.138 ns，因此只有在四相周期
内相位近似不变时才能写成同一时刻的公共标量。

逐符号 CPE 使用

$$\hat\theta_l=\angle\sum_{k,p}\hat x^*_{k,p,l}\hat x^{eq}_{k,p,l}.$$

QPSK 决策使该值存在 $\pi/2$ 模糊；正式实现以 DM-RS 已吸收的相位为零锚点，向前/
向后选择连续分支，但相邻符号变化超过 $\pi/4$ 时仍可能周跳。10 kHz/8 deg 的坏 seed
中 11/130 个 memoryless 象限错误承载 99.96% 误码，oracle CPE 为零错；连续展开将
25498 errors 降至 8364，却不能消除全部 acquisition failure。

### 11.3 已验证的物理结论

- independent+CPE 的增量 EVM 功率随 $\sigma_\phi^2$ 缩放，三个 Bpll 的拟合
  $R^2=0.991/0.992/0.990$，支持独立 LO 残余是二阶相位扰动；
- “公共 LO 是共享状态、已知时容易校正”成立（oracle 坏 seed 零错）；
- “因此公共 LO 的 blind BER 必然低于独立 LO”不成立。slow/mid-band 公共相位的
  集中突发与独立四支路的空间平均可使排序反转；
- BER<=1e-3 网格没有识别出正的规格放宽倍率：independent 在三个 B 都 `>=8 deg`，
  common+CPE 仅 100 kHz 被夹在 `[4,8) deg`，其余也 `>=8 deg`。

所以器件第三规格轴必须至少是 `(sigmaPhi,Bpll,phase-acquisition capability)`，不能只给
一个 RMS 相位或声称单链拓扑自动放宽 A 倍。更强的导频辅助/贝叶斯 CPE tracker 可作为
后续算法，但不属于当前 R12 的一参数判决基线。

### 11.4 LO 拓扑的文献锚点与条件结论

独立振荡器相噪可被阵列合并部分平均、共同振荡器相噪保留为共模状态的区分，可参见
[Björnson--Matthaiou--Debbah, IEEE TWC 2015](https://doi.org/10.1109/TWC.2015.2420095)
和 [Björnson--Matthaiou--Pitarokoilis--Larsson, EUSIPCO 2015](https://doi.org/10.1109/EUSIPCO.2015.7362822)。
本工程的 flat/full-stack 排序翻转与该机理一致：独立 4-LO 的有效方差还取决于均衡
权重集中度，公共 LO 的可恢复性还取决于相位获取。因此后续只报告
`(sigmaPhi,Bpll,cond(Hhat))` 条件拓扑，不再把 common/independent 压缩成普适倍率。

## 12. R14：开关 acquisition 成本与 TDL 算法迁移

### 12.1 acquisition 成本的可加分解

在同一信号、噪声和 TDL realization 上定义成功概率
$P_{off}$、$P_{ideal}$、$P_{imp}$，其中 ideal 保留四相交织但关闭泄漏、建立和抖动。
边际成功率差满足恒等式

$$P_{off}-P_{imp}=(P_{off}-P_{ideal})+(P_{ideal}-P_{imp}).$$

实测为 $0.75-0.52=(0.75-0.76)+(0.76-0.52)=-0.01+0.24$。
第一段 McNemar 0/1、p=1，不支持交织结构代价；第二段 25/1、p=8.05e-7，说明当前
23 pp 总 acquisition 代价主要来自已建模模拟损伤联合体，而不是 4:1 交织本身。

### 12.2 条件 BER 与 outage 必须分开

R14 对每点同时报告

$$\widehat{BER}_{cond}=\frac{\sum_{i\in\mathcal A}N_{e,i}}
{N_{bits/frame}|\mathcal A|},\qquad
\widehat P_{out}=1-\frac{|\mathcal A|}{N_{attempt}},$$

其中 $\mathcal A$ 是 standard 与 DF 都成功获取/解码的配对 seed。R14 所有隔离 TDL 点
均为 10/10 有效、$P_{out}=0$；这不能覆盖 R13 full-stack 的 52% 平台，而是证明 TDL
单项不是平台的充分条件。

### 12.3 TDL 迁移后的算法边界

20 dB、fast=0.6、tauC=1 us 下，Q=12、3 次 soft DF 把聚合 BER 从 0.16567 降至
0.16046（相对 3.15%），9/10 realization 改善；Q=24 反而回落到 1.31%，保持了
偏差/方差折中。tauC=0/8 ns 的强抖动点有约 0.2--0.3% 反噬，100 ns 只有
0.2--0.6% 正收益，1 us 在 fast=0.4--0.5 达到约 3.3--3.6%。因此相关时间/PSD 结构
仍决定 ICI-DF 是否有可用杠杆，但频选深衰与信道估计把 flat anchor 的 38--58% 收益
压缩到约 3%。

## 13. R15：OTA 多点归一化模型边界

对同一 OTA raw122 的 ideal/impaired 两支，Phase 2 固定损伤参数为 25 dB 隔离、
20 ns 建立、20 ps 转换抖动和 100 ps 采样边界抖动。功率域主增量定义为

$$\Delta_{EVM^2}=\frac{EVM_{imp}^2-EVM_{ideal}^2}{EVM_{ideal}^2}.$$

15 段 × 10 个 matched-SNR TDL seed 的方向一致率为 100%，但 OTA/离线总体中位倍率
为 2.112，略超预注册 2× 门；RMS-EVM 字面增量的同一倍率为 1.957。两者不是数据
矛盾，而是 $\Delta_{EVM^2}=(1+\Delta_{EVM})^2-1$ 的非线性口径差异。当前以更严格、
看数前冻结的功率口径保留 no-go，等待审议方裁定，不用事后改指标宣告通过。

该实验还确定一个模型边界：改变 RX gain 没有在本次高 SNR 场景形成分离的 SNR 档，
且 matched-SNR 本身不能匹配真实 OTA baseline 中的信道估计误差/硬件残差组成。因此
R15 支持“损伤方向和整体量级可迁移”，但不支持“只给定 SNR 即可精确预测任意 OTA
段的增量”。`cond(\hat H)` 仍只作估计信道诊断，不升级为真实信道条件数。
