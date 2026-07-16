# 快速开关单链多用户接收技术手册

副标题：从系统动机、非理想性建模、损伤感知接收到多端口选择与能效边界

版本日期：2026-07-16

适用代码：本仓库冻结分支

证据范围：第二十二轮专家审议结束后的冻结实验及投稿前 E1--E3 补充实验

---

## 执行摘要

### 一句话结论

本工作证明：用一条宽带射频接收链和高速端口开关，可以把多个物理天线端口变成可用于
多用户分离的时间—空间观测；在真实多径、器件损伤、同步失败和扫描开销同时计入后，
该架构并非无条件优于全数字接收机，但在低速或准静态、允许自适应调制且端口选择更新
周期不短于约 100 ms 的场景中，可获得可重复的净吞吐和能效收益。

### 五个头条数字

| 结论 | 冻结数字 | 应如何解读 |
|---|---:|---|
| 实时处理成立 | `9.380 ms/10 ms frame`，C 与 MATLAB 网格 NMSE 约 `-115 dB` | 数据面已达到约 100 frame/s，且没有用精度换时延 |
| 用户频偏可补偿 | Layer 3 BER `0.273 → 9.49e-4`，约 288× | 逐用户载波频偏是基础多用户场景的主导损伤，解析 318 Hz 门限命中 |
| 损伤算法有明确迁移边界 | ICI-DF 在 flat 场景恢复 38%--58%，到 TDL 全栈约 3.15% | 真值结构存在，但实际收益受信道估计和模拟状态可观测性双门控制 |
| M>N 端口选择能兑现净收益 | M=8/12/16 为 `+0.449/+0.614/+0.710 bit/s/Hz` | 需 AMC 和至少约 100 ms 的扫描摊薄；固定 QPSK 或 50 ms 扫描可为负 |
| 能效折中为正 | M=16 扫描后有效理想速率约为 DBF 的 69%，模型功耗约 15%，能效 4.39× | 是统一组件模型，不是功率计实测；本文全栈 AMC 锚点为 `65.2 Mbit/J` |

其中，BER 是比特误码率；NMSE 是归一化均方误差；ICI-DF 是载波间干扰判决反馈；
flat 表示频率平坦信道；TDL 表示多抽头频率选择性信道；AMC 是自适应调制编码；QPSK
是每个复符号携带 2 bit 的正交相移键控；DBF 是每端口独立数字化的全数字波束成形。

![单链实时路径、离线损伤研究和 M>N 端口选择的统一架构](docs/images/system_architecture.png)

### 当前状态

- Phase 0--3、R1--R22 已冻结，所有既有数字通过独立复现；
- 已完成静态/动态损伤分类、时变开关与本振模型、ICI-DF 边界、同步统计、M>N 选择、
  理论表征和统一能效账本；
- 当前 OTA 使用四路并行板卡采集后受控模拟单链开关，不是已制造的物理单 RF 链开关板；
- 投稿前 E1 已用扫描帧 DM-RS 替换真实信道输入，完成 20-seed 非 oracle 仿真选择；
  它仍是离线实现，不是已经部署到板卡 direct RX 的实时控制器。

### 本工作与 GreenMO、经典 FAS 的区别

FAS 指通过多个空间端口的选择或移动获得分集的流体天线系统；GreenMO 是已有的单链
码域多天线原型。本表只比较研究问题和已验证范围，不把不同论文的数值放在一起排名。

| 维度 | 本工作 | GreenMO | 经典 FAS 端口选择 |
|---|---|---|---|
| 核心目标 | 5G-NR 风格四用户上行的损伤、同步、M>N 选择和能效闭环 | 用高速开关与码域处理减少多天线射频链 | 从多个空间位置选择较强端口以获得单用户分集 |
| 物理观测 | 一条高速标量流，严格约束 A/S 调度；当前硬件为四路 raw IQ 后受控模拟 | 物理单链开关原型与码域多天线处理 | 依文献而异，通常是单端口选择或可移动端口模型 |
| 信道与波形 | 51 RB、30 kHz 子载波间隔、TDL-A 多径、J0 几何相关 | 原型空口与论文配置，非本工程的逐位复现对象 | 多采用相关端口衰落；宽带、多用户和同步不一定同时研究 |
| 器件非理想 | 隔离、建立、OU 抖动、采样边界、公共/独立 LO、PSD 规格 | 非本工程所做的完整损伤分类与规格包络 | 通常不是主要研究对象 |
| 同步 | PSS/PBCH 获取、waterfall/假峰平台、多帧累积和开关代价归因 | 不使用本工程相同的 NR 获取与审计链 | 通常假设信道/端口质量可获得 |
| 端口算法 | F1 穷举、贪婪、松弛、Dmax=2 码叠加消融；码叠加无稳定增值 | 码域 many-to-many/co-phase 思路 | 经典模式通常选择最强单端口 |
| 主要新信息 | 静态/动态二分、ICI-DF 迁移边界、系统净收益条件和扫描能效 | 证明单链码域多天线原型可行 | 给出端口选择的分集与相关性规律 |
| 诚实边界 | 无真实开关 PCB、在线选择器尚未完成、能效非功率计实测 | 由其原论文定义 | 不应直接外推到四用户单链码域复用 |

### 投稿前只补的三项（已完成）

1. 扫描帧 DM-RS 估计选择保留 truth-CSI 贪婪参考中位增益的 79%--90%；
2. 单用户 FAS 最强端口模式在 M=16、10% outage 处得到 10.60--12.58 dB SNR 收益；
3. 50 ms--10 s 更新周期已映射到 3.2 GHz 下的相干时间和允许移动速度。

TX 侧时间调制阵列、感知通信一体化、智能反射面、多 SNR OTA 重采和真实开关 PCB 不进入
本篇补充实验，只在 future work 中说明。

---

## 阅读说明

本手册面向理解数字通信、无线信道和多天线系统，但不熟悉“高速开关单射频链多用户
接收”这一细分方向的读者。全文按论文的研究逻辑组织，而不是按代码提交顺序组织：

1. 先解释研究背景和核心矛盾；
2. 再建立统一的系统、信道、器件与接收机数学模型；
3. 从模型中推导哪些损伤能被导频吸收、哪些损伤会留下动态残余；
4. 用分层、成对、预注册的实验验证每条推导；
5. 最后讨论多端口选择的系统净收益、能效和应用边界。

为避免“先使用、后解释”，第 0 章集中声明全文使用的术语、缩写和符号。正文中首次
引入少数复合概念时仍会再次用自然语言说明。

---

## 第 0 章　术语、缩写与符号

### 0.1 无线波形与同步术语

| 术语或缩写 | 英文全称 | 本手册中的含义 |
|---|---|---|
| 3GPP | 3rd Generation Partnership Project | 制定第五代蜂窝通信等规范的国际标准组织 |
| NR | New Radio | 3GPP 第五代蜂窝系统的新空口标准 |
| OFDM | Orthogonal Frequency-Division Multiplexing | 正交频分复用，把宽带信号分解到多个正交子载波 |
| FFT / IFFT | Fast Fourier Transform / Inverse FFT | 快速傅里叶变换及其逆变换，用于 OFDM 解调和调制 |
| CP | Cyclic Prefix | 循环前缀，把符号尾部复制到前端以抵抗有限时延扩展 |
| SCS | Subcarrier Spacing | 子载波间隔；本工程为 30 kHz |
| RB | Resource Block | 资源块；一个 RB 含 12 个连续子载波 |
| RE | Resource Element | 资源元素，即一个 OFDM 符号上的一个子载波位置 |
| slot | slot | 时隙；本工程一个时隙为 0.5 ms |
| frame | radio frame | 无线帧；本工程一帧为 10 ms |
| SSB | Synchronization Signal Block | 同步信号块，含同步序列和广播信道 |
| PSS | Primary Synchronization Signal | 主同步信号，用于发现候选帧头和小区标识的一部分 |
| SSS | Secondary Synchronization Signal | 辅同步信号，与 PSS 一起确定完整物理小区标识 |
| PBCH | Physical Broadcast Channel | 物理广播信道，用于验证同步结果并传输广播信息 |
| DM-RS | Demodulation Reference Signal | 解调参考信号；接收机用它估计数据经历的复信道 |
| acquisition | initial acquisition | 初始获取：从未知时间和频率位置寻找可靠帧头的过程 |
| tracking | synchronization tracking | 跟踪：获取成功后只在预测位置附近持续更新同步状态 |
| CFO | Carrier Frequency Offset | 载波频率偏移，即收发振荡器频率不一致造成的相位斜坡 |
| CPE | Common Phase Error | 公共相位误差，一个 OFDM 符号整体经历的星座旋转 |
| ICI | Inter-Carrier Interference | 载波间干扰，能量从目标子载波泄漏到其他子载波 |
| QPSK | Quadrature Phase-Shift Keying | 正交相移键控，每个复符号携带 2 个比特 |
| PRACH | Physical Random Access Channel | NR 物理随机接入信道，用于上行初始接入 |
| UE | User Equipment | 用户设备，例如终端或传感器节点 |

### 0.2 多天线、检测和端口选择术语

| 术语或缩写 | 英文全称 | 本手册中的含义 |
|---|---|---|
| MIMO | Multiple-Input Multiple-Output | 多输入多输出，利用多空间观测传输或分离并行数据流 |
| layer | spatial layer | 一个并行用户或空间数据层；本工程有 4 层 |
| RF | Radio Frequency | 射频，指数字基带以上的模拟高频信号与电路 |
| RF chain | Radio-Frequency chain | 从天线、低噪声放大、混频、滤波到模数转换的一套接收链 |
| virtual RF chain | virtual radio-frequency chain | 由单个高速标量采样流按开关码相去交织得到的数字观测，不是新增硬件链 |
| FAS | Fluid Antenna System | 流体天线系统，通过多个空间端口的切换或选择获得信道多样性 |
| BABF | Binarized Analog Beamforming | 二值模拟波束成形，每个端口权重只能取接通或关断 |
| DBF | Digital Beamforming | 全数字波束成形，通常每个物理端口具有独立射频链和数字采样 |
| HBF | Hybrid Beamforming | 混合波束成形，以模拟网络把多个端口压缩到少量射频链 |
| RZF | Regularized Zero Forcing | 正则化迫零检测器，在抑制层间干扰与限制噪声放大之间折中 |
| LMMSE | Linear Minimum Mean-Square Error | 线性最小均方误差检测；与适当正则参数下的 RZF 等价 |
| AMC | Adaptive Modulation and Coding | 自适应调制编码，根据信道质量选择不同调制和编码效率 |
| MCS | Modulation and Coding Scheme | 调制编码方案，规定调制阶数和编码率 |
| F1 / F2 | feasibility set 1 / 2 | Phase 3 两类调度集；F1 每端口至多属于一条链，F2 允许跨码相属于两条链 |
| Dmax | maximum assignments | 一个物理端口允许加入的最大虚拟链数 |
| oracle | truth-assisted upper-bound algorithm | 使用真实信道等实际不可直接获得信息的上界算法，不是在线实现 |
| genie | ideal truth-assisted diagnostic | 知道损伤真值的理想诊断器，用于确定可恢复天花板 |
| PC-HBF / FC-HBF | partially / fully connected HBF | 部分连接 / 全连接混合波束成形 |
| GreenMO | GreenMO prototype architecture | 已公开的单链码域多天线原型，本工程能效参数的重要对照来源 |
| GreenMO-like | GreenMO-inspired local reference | 本工程允许跨码相多重归属的局部贪婪参考，不是 GreenMO 算法复现 |

### 0.3 器件、随机过程和实现术语

| 术语或缩写 | 英文全称 | 本手册中的含义 |
|---|---|---|
| TX / RX | Transmitter / Receiver | 发射机 / 接收机 |
| LO | Local Oscillator | 本地振荡器，用于射频与基带之间的混频 |
| RX-LO | Receiver Local Oscillator | 接收机本地振荡器 |
| PLL / RX-PLL | Phase-Locked Loop / Receiver PLL | 锁相环 / 接收机本振锁相环，用反馈限制相位漂移 |
| RFIC | Radio-Frequency Integrated Circuit | 集成射频收发或接收芯片 |
| ADC | Analog-to-Digital Converter | 模数转换器，把模拟基带转换为数字采样 |
| IQ | In-phase and Quadrature | 同相和正交分量，合起来表示复基带采样 |
| AWGN | Additive White Gaussian Noise | 加性白高斯噪声，常用热噪声抽象 |
| TDL-A | Tapped Delay Line model A | 3GPP 规定的一种多抽头频率选择性信道功率时延模型 |
| Kronecker model | Kronecker spatial model | 用发射、接收相关矩阵的 Kronecker 结构生成空间相关信道 |
| Rayleigh fading | Rayleigh fading | 无直达主径时常用的复高斯衰落模型，其幅度服从 Rayleigh 分布 |
| Clarke/Jakes model | Clarke/Jakes isotropic-scattering model | 用各向同性散射近似多普勒谱、空间相关和相干时间的经典模型 |
| ULA | Uniform Linear Array | 均匀线阵，天线端口沿直线等间距排列 |
| Wiener process | Wiener random walk | 增量独立、累计方差随时间增长的随机游走过程 |
| AR(1) | first-order autoregressive process | 一阶自回归过程，当前值由上一值和新随机创新组成 |
| OU process | Ornstein--Uhlenbeck process | 有限相关时间、均值回归的连续随机过程；离散后可写成 AR(1) |
| RMS | Root Mean Square | 均方根，用于描述随机扰动的典型幅度 |
| PSD | Power Spectral Density | 功率谱密度，描述随机过程功率在频率上的分布 |
| IIR | Infinite Impulse Response | 无限脉冲响应递推，输出依赖历史状态 |
| LTI | Linear Time-Invariant | 线性时不变系统 |
| polyphase LTI | polyphase linear time-invariant system | 以固定码周期重复、在去交织后成为各相位间固定线性映射的系统 |
| MEX | MATLAB Executable | MATLAB 可调用的编译型 C/C++/Fortran 模块 |
| PHY | Physical Layer | 完成同步、信道估计、检测和判决的物理层处理 |
| BB | Baseband | 基带；本手册功耗公式中的 BB 表示数字基带处理 |
| direct RX | persistent direct receiver | C/MEX 持久消费者承担数据热路径的实时接收模式 |
| DMA | Direct Memory Access | 板卡不经处理器逐字节参与而直接向内存搬运数据的机制 |
| ring | ring buffer | 生产者和消费者之间循环使用的环形缓冲区 |
| pending | pending DMA blocks | 尚待消费者处理的原始数据块数；本工程每块约 1 ms |
| dropNew | dropped-new-block counter | 环形缓冲已满时拒绝接收的新数据块计数 |
| raw122 | 122.88-MS/s raw IQ capture | 四路 122.88 MS/s 原始 IQ 采集及其保存格式 |
| timestamp / sequence | sample time / block order index | 样点时间戳 / 数据块顺序号，用于检查连续性、重复和跳块 |
| MS/s | mega-samples per second | 每秒百万个采样 |
| Hz / kHz / MHz | hertz / kilohertz / megahertz | 每秒周期数及其千倍、百万倍单位 |
| ns / µs / ms | nanosecond / microsecond / millisecond | 纳秒、微秒、毫秒 |

### 0.4 算法、指标和统计术语

| 术语或缩写 | 英文全称 | 本手册中的含义 |
|---|---|---|
| reference | waveform reference package | 保存的共同发射波形、资源映射、导频、符号和比特真值包 |
| BER | Bit Error Rate | 比特误码率，错误比特数除以判决比特数 |
| EVM | Error Vector Magnitude | 误差矢量幅度，衡量均衡星座点偏离理想符号的程度 |
| EVM² | squared EVM | 归一化误差功率；损伤功率增量比较的自然线性域 |
| RMS-EVM | root-mean-square EVM | EVM 的常见幅度表达；其增量不是误差功率的线性增量 |
| SNR | Signal-to-Noise Ratio | 信号功率与噪声功率之比 |
| SINR | Signal-to-Interference-plus-Noise Ratio | 信号功率与干扰加噪声功率之比 |
| CSI | Channel State Information | 信道状态信息，即接收机用于检测或端口选择的信道估计 |
| LS | Least Squares | 最小二乘，通过最小化拟合残差估计未知参数 |
| NMSE | Normalized Mean-Square Error | 归一化均方误差 |
| cond | condition number | 条件数；矩阵越病态，求逆时越容易放大噪声与估计误差 |
| Hhat | estimated channel matrix | 由导频估计得到的信道矩阵，记作 $\hat H$ |
| outage | acquisition/decoding outage | 因同步或解码失败而没有产生有效数据结果的试验 |
| ICI-DF | ICI decision feedback | 用首次判决重建并消除载波间干扰的判决反馈接收机 |
| DDCE | Decision-Directed Channel Estimation | 判决引导信道估计，用已判数据辅助重新估计信道 |
| seed | pseudorandom seed | 随机种子，用于精确复现信道、噪声和随机损伤 |
| realization | random realization | 由一个随机种子生成的一次具体信道或噪声实现 |
| ideal / impaired | ideal / impairment-injected branch | 关闭目标损伤的理想分支 / 注入目标损伤的受损分支 |
| baseline | baseline reference | 其他方法共同对照的基准配置或结果 |
| paired experiment | paired controlled experiment | ideal 和 impaired 分支共享信号、信道和噪声的成对受控实验 |
| CI | Confidence Interval | 置信区间，用于描述有限样本统计量的不确定性 |
| McNemar test | paired binary test | 比较两个方法在相同样本上成功/失败差异的成对统计检验 |
| go/no-go gate | preregistered decision gate | 看结果前冻结的通过/拒绝判据，防止事后挑选有利指标 |
| pp | percentage point | 百分点，例如 52% 到 76% 是增加 24 pp |
| bits/Joule | energy efficiency | 每焦耳能量传输的有效比特数，表示能效 |
| dB / dBc/Hz | decibel / carrier-relative density | 对数功率比 / 相对载波且归一到 1 Hz 的噪声功率密度 |
| flat channel | frequency-flat channel | 研究带宽内近似不随子载波变化的信道，用于机制隔离和代数回归 |
| full-stack | full receiver stack | 同步、信道估计、损伤、检测和统计全部打开的端到端路径 |
| payload | useful data payload | 除同步、导频和开销外承载用户信息的数据部分 |
| goodput | useful delivered throughput | 扣除误码、获取失败和扫描时间后的有效吞吐量 |
| headroom | available performance margin | 尚可被损伤或开销消耗的性能余量，不等于最终净收益 |
| smoke / pilot / paper | test profiles | 结构冒烟 / 中等规模 / 论文级统计配置 |
| hard / soft decision | hard / reliability-weighted decision | 只给离散符号的硬判决 / 同时携带可靠度的软判决 |
| capture fraction | modeled-residual capture | 给定回归模型可解释或重构的真值残差功率比例 |
| gap closure | performance-gap closure | 算法相对无补偿与 genie 天花板之间已关闭的性能差距比例 |
| bank / drive | regressor bank / physical excitation | ICI 核拟合使用的一组回归量 / 激发动态误差的一阶物理差分项 |
| lag-1 | one-sample-lag correlation | 随机过程与其前一个样点之间的相关系数 |
| floor hit | lower-bound activation | 随机建立时间触发预设最小值的事件和比例 |
| waterfall / platform | noise-limited slope / error floor | 成功率随 SNR 快速转折的噪声区 / 高 SNR 不再改善的平台区 |
| false peak | false synchronization peak | 相关器选择了错误但较强的同步峰 |
| P95 | 95th percentile | 95% 样本不超过的分位数，用于描述尾部而非最大值 |
| bootstrap CI | resampling confidence interval | 对样本重复有放回重采样得到的置信区间 |
| CQI | Channel Quality Indicator | 信道质量指示；本工程用 CQI-style 门限表抽象 AMC |
| aggregate | aggregate across streams or seeds | 把多层、多个随机实现或多个统计项按预定规则汇总后的量 |
| min-user SINR | minimum user SINR | 所有用户中最小的 SINR，用于保障最弱用户而非只优化总和 |
| sum-rate | sum spectral efficiency | 所有用户或空间流频谱效率之和，单位通常为 bit/s/Hz |
| MAT | MATLAB data file | MATLAB 保存结构化变量的二进制数据文件 |
| SHA-256 | Secure Hash Algorithm 256-bit | 文件内容哈希，用于确认本地、远端或两次资产逐字节一致 |
| R1--R22 | review rounds 1 through 22 | 本项目从第一轮到第二十二轮的专家审议编号 |
| M4/M8/M12/M16 | shorthand for physical-port counts | 物理候选端口数 $M$ 分别为 4/8/12/16 的配置简称 |

### 0.5 核心符号

| 符号 | 含义 |
|---|---|
| $N$ | 用户数或目标虚拟链数；本工程主要为 $N=4$ |
| $M$ | 候选物理天线端口数；Phase 3 扫描 $M=4,8,12,16$ |
| $p,m,q$ | 用户索引、物理端口索引、开关码相或虚拟链索引 |
| $x_p[n]$ | 用户 $p$ 的离散复基带发射样本 |
| $r_m[n]$ | 物理端口 $m$ 接收到的复基带样本 |
| $y[n]$ | 所有端口经开关和模拟求和后唯一的高速标量样本流 |
| $v_q[\ell]$ | 从 $y[n]$ 按码相 $q$ 去交织得到的虚拟链样本 |
| $H[k]$ | 子载波 $k$ 上的 $M\times N$ 物理信道矩阵 |
| $S$ | $M\times N$ 二值端口选择矩阵 |
| $A[m,n,q]$ | 描述端口、虚拟链和码相关系的三维物理调度张量 |
| $G[k]$ | 选择后的等效信道，理想情况下 $G[k]=S^T H[k]$ |
| $R_n[k]$ | 选择后噪声协方差 |
| $\lambda$ | RZF 正则参数 |
| $F_s,F_r$ | 每虚拟链采样率和高速物理采样率 |
| $T_r$ | 高速采样间隔，$T_r=1/F_r$ |
| $\tau,\beta$ | 开关一阶时间常数与每样点建立系数 |
| $\tau_c$ | OU/AR(1) 快抖动的相关时间 |
| $B_{PLL},\sigma_\phi$ | PLL 等效带宽与稳态相位均方根 |
| $DS,\lambda_c$ | TDL 时延扩展 / 射频载波波长 |
| $\mathrm{IS},t_{rise}$ | 开关隔离度 / 10%--90% 建立时间 |
| $Q,\eta$ | ICI 核半宽 / 判决、估计和迭代的综合实现效率 |
| $P_{acq}$ | 成功完成初始同步获取的概率 |
| $B_{occ},R_{sum},\mathrm{EE}$ | 占用带宽、各流和速率、能效 |

---

## 第 1 章　研究背景、问题与贡献

### 1.1 为什么要减少射频链

传统上行多用户 MIMO 基站若要同时获得 $N$ 条空间观测，通常需要 $N$ 套并行射频链、
ADC、时钟和数字输入。当天线规模增加时，射频链和 ADC 的功耗、成本、校准量及数据搬运
压力随端口数增长。全数字架构性能强，但在小型基站、专用网络、低功耗接入点和大规模
候选端口场景中，未必是唯一可接受的实现。

本项目研究另一条路线：只保留一条宽带物理接收链，用高速射频开关在不同天线端口之间
周期切换。唯一标量流以 $N$ 倍采样率数字化，接收机再按开关码相去交织成 $N$ 条虚拟
观测。它没有凭空创造信息维度，而是用更高时间采样带宽交换并行射频硬件。

### 1.2 真正困难的不是理想开关，而是现实器件与系统闭环

理想开关下的数学去交织并不困难。论文级问题来自四个相互耦合的层次：

1. **同步问题**：开关和多径之后，PSS 能否稳定找到帧头；
2. **用户分离问题**：DM-RS 能否估计等效多用户信道，RZF 能否分开 4 个用户；
3. **器件非理想问题**：有限隔离度、有限建立、驱动抖动、本振相噪会不会产生无法校准的
   动态残余；
4. **系统净收益问题**：增加候选端口得到的 SINR 增益，扣除同步失败、扫描时间和能耗后
   是否仍为正。

### 1.3 本项目最终回答了什么

冻结结果形成六条主要贡献或结论：

1. 建成共享同一 reference 的实时 OTA 与纯离线双路径，并把持续 FFT、DM-RS、4×4
   RZF、QPSK 判决和 BER 累积下放到 C/MEX 数据面；
2. 提出并用实验验证“静态可吸收、动态残余”的损伤分类：固定周期损伤通常成为 DM-RS
   可估计的等效信道，真正导致 BER 的是帧内时变部分；
3. 把开关建立时间扩展为带相关时间的 OU/AR(1) 过程，证明同样 RMS 下 BER 可随
   $\tau_c$ 增大约 10 倍，所以器件规格必须约束 PSD，而不能只给单一方差；
4. 建立 ICI-DF、genie、真值 capture 和 full-stack 迁移链，既得到 flat 信道 38%--58%
   的恢复，也如实确认在 TDL 全栈中只剩约 3% 的增益；
5. 把 $M=N=4$ 扩展为受物理约束的 $M>N$ 端口选择，证明选择增益在 TDL、开关损伤、
   同步和扫描都存在时可通过 AMC 兑现为 `0.45--0.71 bit/s/Hz` 的净吞吐；
6. 建立统一组件能量账本，显示 M=16 时本文未扣扫描的理想 sum-rate 为 DBF 的约 71%，
   扣除扫描 payload 后的有效理想速率约为 69%，组件模型功耗约为 DBF 的 15%，理想
   参考能效约为 DBF 的 4.39 倍。

### 1.4 必须先声明的硬件边界

当前 OTA 板卡实际采集四路并行 RX 原始 IQ；单链高速开关行为是在 `raw122` 数据上受控
模拟。实时 direct RX 已证明 C/MEX 数据面、队列、时延和空口解码可运行，但尚未制造
真正的单 RF 链高速开关板。因此本文是“开关接收机算法、器件模型和实时化平台”，不是
“已经完成的单链射频硬件原型”。

---

## 第 2 章　系统架构与端到端信号链

### 2.1 波形和帧结构

冻结配置使用 30 kHz SCS、51 RB、1024 点 FFT、10 ms 帧和 4 层 QPSK。TX 的每虚拟链
采样率为

$$F_s=30.72\ \mathrm{MS/s},$$

高速接收/开关域采样率为

$$F_r=4F_s=122.88\ \mathrm{MS/s},\qquad T_r=8.138\ \mathrm{ns}.$$

slot 0 携带 SSB/PBCH，slot 1--10 携带 4 层 payload，slot 11--19 静默。Type-1
DM-RS 是 3GPP 规定的第一类梳状频域导频映射；本工程使用参考信号端口编号
1000--1003，并在每个 0.5 ms slot 的指定 OFDM 符号上估计信道。

### 2.2 reference 是所有实验的共同真值

reference 包不仅是一段波形，还保存：

- 完整 TX 时域 IQ；
- PSS、PBCH、DM-RS 和 data RE 的位置；
- DM-RS 符号、QPSK 数据符号和编码比特真值；
- 每层资源映射和帧参数。

实时路径和离线路径共享同一个 reference，因此 C 与 MATLAB、ideal 与 impaired、离线与
OTA 都能在同一 bit truth 上比较，避免不同波形实现造成伪差异。

### 2.3 唯一标量流和虚拟链

设第 $m$ 个物理端口接收样本为 $r_m[n]$，码相为 $q(n)\in\{1,\ldots,N\}$。理想二值
选择矩阵为 $S\in\{0,1\}^{M\times N}$。数字化前的物理输出必须始终只有一列：

$$
y[n]=\sum_{m=1}^{M}S_{m,q(n)}r_m[n].
$$

随后按码相去交织：

$$v_q[\ell]=y[N\ell+q].$$

这条式子是项目的“单链红线”。若代码先形成多列并行数字流再相加，就已经偷偷恢复成
多射频链系统。三维张量 $A[m,n,q]$ 进一步审计端口 $m$ 是否在码相 $q$ 合法地服务虚拟
链 $n$；同一码相把一个端口复制给多个链会被拒绝。

### 2.4 接收处理顺序

一帧数据依次经过：

1. PSS 相关搜索候选帧头；
2. 共同 CFO 粗估计与去旋；
3. PBCH 解码确认同步不是假峰；
4. 去 CP 和 FFT，抽取 612 个有效子载波；
5. Type-1 DM-RS 估计 $\hat H[k]$；
6. 4×4 RZF 分离 4 层；
7. QPSK 硬判决，与 reference 比特比较得到 BER；
8. 同时计算 EVM、`cond(Hhat)`、同步状态和队列时延。

### 2.5 实时数据面与离线研究面

实时 direct RX 的 DMA、ring、四相抽取、FFT、DM-RS、RZF、QPSK、EVM 和 BER 位于
C/MEX 热路径；MATLAB 只保留低频 PSS/PBCH 控制、CFO/timing 更新、状态检查和绘图。
Phase 1--3 的损伤注入、ICI-DF、端口选择和大规模统计仍在离线 MATLAB 研究面，不能
误称为已经进入实时 MEX。

![实时与离线共享 reference 的工程架构](docs/images/system_architecture.png)

---

## 第 3 章　统一数学模型

### 3.1 多用户物理信道

第 $p$ 个用户发射 $x_p[n]$。第 $m$ 个接收端口的信号可写为

$$
r_m[n]=\sum_{p=1}^{N}(h_{m,p}*x_p)[n]+w_m[n],
$$

其中 $*$ 表示离散卷积，$h_{m,p}$ 是多径信道，$w_m$ 是 AWGN。进入频域后，子载波
$k$ 上写成

$$\mathbf r[k]=H[k]\mathbf x[k]+\mathbf w[k],\qquad H[k]\in\mathbb C^{M\times N}.$$

理想端口选择后的等效信道和噪声协方差为

$$
G[k]=S^T H[k],\qquad R_n[k]=\sigma_w^2S^TS.
$$

第二式非常重要：多端口相干求和也会合并噪声。若仍错误地使用 $\sigma_w^2I$，会制造
不存在的阵列增益。Phase 3 的所有选择结果都显式使用 $S^TS$。

### 3.2 flat 与 TDL-A 信道

flat 信道在整个带宽内近似一个常矩阵，用于代数回归和隔离机制研究。它可控、易解释，
但不能代表宽带深衰落。

TDL-A 使用 3GPP 的 23 个抽头，可在部分子载波形成深衰落，即信号幅度远低于相邻频率：

$$
h_{r,t}(\tau)=\sum_{i=1}^{23}\sqrt{p_i}
[L_RW_iL_T^H]_{r,t}\,\delta(\tau-d_iDS),
$$

其中 $p_i,d_i$ 是标准化功率和时延，$DS=100$ ns 是时延扩展，$W_i$ 为独立复高斯矩阵，
$L_R,L_T$ 由空间相关矩阵分解得到。Phase 1 使用 Kronecker 指数相关；Phase 3 进一步
用 ULA 几何和零阶 Bessel 函数 $J_0(2\pi d/\lambda_c)$ 描述各向同性散射下随端口间距
振荡的空间相关性，并将相关性绑定到端口间距和波长
$\lambda_c$。这样才能研究“更多、更密端口是否一定更好”。

### 3.3 用户级非理想性

#### 功率不平衡

$$x'_p[n]=10^{P_p/20}x_p[n].$$

它缩放等效信道的列；只要帧内恒定，DM-RS 可以估计该缩放。

#### CP 范围内的分数定时偏移

$$X'_p(f)=X_p(f)e^{-j2\pi f\tau_p}.$$

实现采用频域带限分数延迟，避免线性插值引入额外幅度滚降。CP 内定时偏移只给每个用户
信道列增加随子载波变化的相位，不改变真实信道奇异值。

#### 每用户 CFO

$$x'_p[n]=x_p[n]e^{j2\pi(f_c+\Delta f_p)n/F_s},$$

其中 $f_c$ 是共同 CFO，$\Delta f_p$ 是用户独立偏移。单个共同 CFO 估计不能同时消除
所有 $\Delta f_p$，残余会在 DM-RS 与数据符号之间产生持续相位旋转。

#### TX Wiener 相位噪声

$$
\phi_p[n]=\phi_p[n-1]+\sigma_pw_p[n],\qquad
x'_p[n]=x_p[n]e^{j\phi_p[n]},
$$

其中 $w_p[n]\sim\mathcal N(0,1)$。该模型对应自由振荡随机游走，不用于描述锁定的
RX-PLL。

### 3.4 开关有限隔离度

有限隔离表示关断端口仍有小幅泄漏。码相 $q$ 的目标信号为

$$
t[n]=\sum_{m=1}^{M}L_{q(n),m}r_m[n],\qquad
L_{qq}=1,\quad L_{qm}=10^{-\mathrm{IS}/20}e^{j\varphi_{qm}},
$$

其中 `IS` 是以 dB 表示的隔离度。默认同相泄漏是保守情形。固定 $L$ 会改变等效信道和
噪声协方差，但仍是周期固定线性映射。

### 3.5 有限建立时间和开关瞬态

开关不能在一个数学瞬间从旧端口跳到新端口。本项目用一阶 IIR 表示：

$$
y[n]=(1-\beta)y[n-1]+\beta t[n],
$$

$$
\beta=1-e^{-T_r/\tau},\qquad \tau=\frac{t_{rise}}{\ln 9},
$$

其中 $t_{rise}$ 是 10%--90% 建立时间。固定 $\beta$ 时，前一码相以几何衰减方式混入
当前码相，但映射仍按固定周期重复。

### 3.6 时变建立、OU 快抖动与采样边界位移

真实器件的建立时间会受温度、驱动和电源噪声影响。模型写成

$$
\tau[n]=\tau_0\max\{0.01,1+a_s\sin(2\pi f_sn/F_r)+a_fw[n]\},
$$

$$
w[n]=\alpha w[n-1]+\sqrt{1-\alpha^2}\epsilon[n],\qquad
\alpha=e^{-1/(F_r\tau_c)}.
$$

$a_s$ 是慢漂幅度，$a_f$ 是快抖幅度，$\tau_c$ 是相关时间。另一个独立机制是采样边界
位移：把理想采样位置移动一个亚样点量，再用带限插值获得样本。它即使在
$t_{rise}=0$ 时仍然有效，修复了“零建立时间时抖动成为空操作”的模型盲区。

### 3.7 RX-PLL 和 LO 拓扑

锁定本振用有界 OU/AR(1) 相位过程：

$$
\phi[n]=\alpha_{PLL}\phi[n-1]+\sigma_\phi\sqrt{1-\alpha_{PLL}^2}u[n],
\qquad \alpha_{PLL}=e^{-2\pi B_{PLL}/F_{rate}}.
$$

公共 LO 在开关合成后的高速标量流上注入，因此 $F_{rate}=122.88$ MS/s；独立 4-LO 在
四个开关前物理支路上注入，因此每支路 $F_{rate}=30.72$ MS/s。两种路径用同一物理
$B_{PLL}$，但离散相关系数必须按各自注入采样率计算，不能直接复用同一个 $\alpha_{PLL}$。

公共单 LO 在开关合成后的标量流上乘 $e^{j\phi[n]}$；独立 4-LO 在开关前四个支路分别
乘 $e^{j\phi_m[n]}$。前者是可共享估计的共模状态，后者可能通过空间合并平均相噪，但
也会破坏不同接收行之间的相对相位。

### 3.8 RZF、判决和误差指标

对每个子载波，RZF 组合器为

$$
W[k]=(\hat H^H[k]\hat H[k]+\lambda I)^{-1}\hat H^H[k],
\qquad \hat{\mathbf x}[k]=W[k]\mathbf y[k].
$$

QPSK 硬判决只根据实部和虚部符号选择象限。BER 直接与 reference bit truth 比较。EVM
衡量均衡符号与参考符号的均方根距离；EVM² 则是归一化误差功率。`cond(Hhat)` 只表示
估计矩阵的病态程度，可能包含导频插值伪影，不能自动等同真实 $H$ 的条件数。

---

## 第 4 章　理论主线与可检验预测

### 4.1 静态可吸收、动态残余

本项目最核心的物理判断可以表述为一个等效信道命题。

若从物理端口到虚拟链的映射满足：

1. 对输入是线性的；
2. 按固定 $N$ 样点码周期重复；
3. 系数在一个导频估计有效区间内不随时间改变；

那么去交织后，该映射在每个子载波上等价为一个固定矩阵 $G_s[k]$：

$$
\mathbf v[k]=G_s[k]H[k]\mathbf x[k]+G_s[k]\mathbf w[k].
$$

DM-RS 实际估计的是复合信道

$$\tilde H[k]=G_s[k]H[k],$$

RZF 不需要知道损伤矩阵和传播信道各自是什么，只需对 $\tilde H[k]$ 检测。因此固定
隔离度、固定建立时间、固定增益/相位和 CP 内固定定时偏移通常不会直接产生高 SNR BER；
它们主要改变条件数和噪声协方差。

如果 $G_s$ 在 DM-RS 与数据之间变化，则一个 $\hat H$ 无法同时代表所有数据符号：

$$
\mathbf y_l[k]=\{\tilde H[k]+E_l[k]\}\mathbf x_l[k]+\mathbf n_l[k].
$$

$E_l[k]$ 就是动态残余。用户差分 CFO、相位噪声、时变建立、边界抖动和时变信道属于
这一类。该二分不是说静态损伤“没有代价”，而是说算法优先级应从静态参数本身转向
动态漂移、病态放大和同步失败。

### 4.2 CFO 的 QPSK 判决门限

DM-RS 位于符号 $l_0=2$。用户 $p$ 的残余 CFO 为 $\delta_p$ 时，数据符号 $l$ 相对导频
旋转

$$\theta_{p,l}=2\pi\delta_p(l-l_0)T_{sym}.$$

QPSK 的最近判决边界是 $45^\circ$。最远数据符号与导频相隔 11 个符号，故第一判决门限

$$
\delta_{th}=\frac{1}{8\times11\times T_{sym}}\approx318\ \mathrm{Hz}.
$$

这给出直接可检验预测：残余 CFO 低于约 318 Hz 的层应主要保持正确，高于该门限的层会
从远端数据符号开始出现规律性误码。ICI 功率在当前数值下只是次要项，主导因素是符号间
相位累积。

### 4.3 静态泄漏对条件数的预测

四端口同相等幅泄漏矩阵可写为

$$L=(1-a)I+a\mathbf1\mathbf1^T,\qquad a=10^{-\mathrm{IS}/20}.$$

其特征值为 $1+3a$ 和三重的 $1-a$，因此

$$
\mathrm{cond}(L)=\frac{1+3a}{1-a}.
$$

25 dB 隔离度时 $a=0.0562$，预测条件数乘性膨胀 23.8%。这条推导不预测 BER 上升，
而预测估计信道更病态、EVM 略增。

### 4.4 建立系数与前相位混合

10 ns 建立对应

$$\tau=4.5512\ \mathrm{ns},\qquad \beta=0.832723,$$

故首阶前相位混合为 $1-\beta=0.16728$，约 `-15.5 dB`。5 ns 建立的首阶混合约
`-31.1 dB`。虽然幅度并不总是很小，但固定递推仍属于 polyphase LTI，所以“混合明显”
不等于“必然产生不可校准 ICI”。

### 4.5 相关时间为什么比单一 RMS 更重要

OU/AR(1) 的 lag-1 相关系数为

$$\rho_1=e^{-T_r/\tau_c}.$$

当 $\tau_c$ 很短，快抖动在一个 FFT 窗内快速正负变化，部分自平均；当 $\tau_c$ 接近
OFDM 符号尺度，扰动不再均匀铺成近似白 ICI，而表现为符号尺度的信道漂移。于是即便
边缘方差相同，BER 仍会大幅不同。器件规格应至少写成“RMS + 相关带宽或 PSD mask”，
不能只给“建立时间抖动小于某个数”。

### 4.6 一阶动态误差与可观测 drive

动态和静态孪生递推分别为

$$y_n=(1-\beta_n)y_{n-1}+\beta_nt_n,$$

$$y_{0,n}=(1-\beta_0)y_{0,n-1}+\beta_0t_n.$$

令 $e_n=y_n-y_{0,n}$、$\delta\beta_n=\beta_n-\beta_0$，忽略二阶项后

$$
e_n\approx(1-\beta_0)e_{n-1}+\delta\beta_n(t_n-y_{0,n-1}).
$$

括号内的 $D_n=t_n-y_{0,n-1}$ 是正确一阶 drive。实际 ADC 不知道 $t_n$，但可由当前
标量流构造

$$
\hat D_n=\frac{y_n-y_{n-1}}{\beta_0}.
$$

这说明动态状态并非原则上不可观测；难点在于信道估计和判决错误是否允许接收机稳定利用
这部分结构。

### 4.7 ICI 核、自由度和捕获律

若时域调制为实值，有限半宽 $Q$ 的频域核满足共轭对称

$$B(-u)=B^*(u).$$

因此核只有 $1+2Q$ 个实自由度，而不是把正负频率各当作独立复数。冻结 $Q=12$ 时，
约束核为 25 个实自由度。

对一阶低通过程，半宽 $Q$ 捕获的核能量近似

$$
C(Q)=\frac{2}{\pi}\arctan\left(\frac{Q+1/2}{T_{sym}f_c}\right),
$$

接收机的 BER gap reduction 经验上写成

$$\mathrm{gap\ reduction}\approx\eta C(Q),$$

其中 $\eta$ 汇总信道估计、判决和迭代效率。这条式子在 flat 隔离实验中成立，但不能
外推为 TDL full-stack 必然具有同样 $\eta$。

### 4.8 二值选择下的 LMMSE SINR 和速率界

选择后等效信道为 $G=S^TH$。把开关残余协方差记为 $R_e$，总扰动协方差为

$$R_z=\sigma_w^2S^TS+R_e.$$

单位功率高斯输入下，逐流 LMMSE SINR 可写成

$$
\gamma_u=\frac{1}{\left[(I+G^HR_z^{-1}G)^{-1}\right]_{u,u}}-1.
$$

线性接收机的逐流和速率为

$$R_{LMMSE}=\sum_u\log_2(1+\gamma_u),$$

联合高斯检测上界为

$$R_{joint}=\log_2\det(I+G^HR_z^{-1}G).$$

后者不是实际线性接收机吞吐量，也不是新容量定理；它只是同一信道和协方差下的联合检测
上界。R21 的理论贡献应表述为“严谨表征与上下界”，而不是发明了新的 LMMSE 公式。

### 4.9 器件残余预算

若开关残余矩阵 $E$ 满足谱范数界 $\|E\|_2\le\epsilon$，则可用矩阵扰动界计算在目标
SINR 下允许的最大 $\epsilon$。这把端口选择增益与器件规格连接起来：选择改善的条件数
和最小奇异值越大，系统能容忍的动态残余预算越高。该预算是理论到器件设计的桥，不是
直接测得的某个商用开关型号保证。

### 4.10 能效与扫描记账

减少射频链的方案必须扫描端口，不能只计算稳态功耗。每次更新需要

$$
N_{scan}=\lceil M/N\rceil-1,\qquad
T_{scan}=10\ \mathrm{ms}\times N_{scan}.
$$

更新周期 $T_u$ 内的总能量为

$$
E_u=P_{front}T_u+P_{BB,data}(T_u-T_{scan})+P_{BB,scan}T_{scan},
$$

能效定义为

$$
\mathrm{EE}=\frac{B_{occ}R_{sum}(T_u-T_{scan})}{E_u}.
$$

扫描期间 RFIC、ADC 和开关仍耗电，基带处理训练数据但不传 payload。该公式同时计入
扫描能量和 payload 时间损失，并避免重复计费。

---

## 第 5 章　实验方法：为什么这样设计

### 5.1 双路径而不是只做仿真或只做 OTA

离线路径负责可重复科学：固定 seed、逐项开关模型、保存真值并做大规模扫描。OTA 路径
负责现实锚点：验证真实时钟、驱动、DMA、同步、队列和空口信道没有使离线结论完全失去
意义。两者共享 reference 和接收机定义，但承担不同证据任务。

### 5.2 成对控制

每个 ideal/impaired 或算法 A/B 比较都尽量共享：

- 同一发射波形；
- 同一 TDL realization；
- 同一 AWGN realization；
- 同一随机损伤流，除被比较因素外不改变随机数消耗；
- 同一停止规则和 bit truth。

这样差值主要来自目标变量，而不是新抽到一个更好或更坏的深衰信道。

### 5.3 分层证据链

每个新机制按以下顺序进入系统：

1. **代数回归**：验证关闭模型时逐位退化、极端参数符合解析不变量；
2. **flat 隔离点**：排除频选深衰，确认机制方向和可恢复上限；
3. **TDL 多 realization**：检验宽带深衰与空间相关下是否稳定；
4. **full-stack**：把同步、信道估计、损伤和算法一起打开；
5. **OTA 锚点**：在真实 raw IQ 上做同段配对注入或实时连续运行。

这一层级防止把“flat 上算法有效”误写成“真实系统已经有效”。ICI-DF 正是通过该流程
从 38%--58% 的隔离增益收缩到 TDL 全栈约 3%，从而暴露了迁移边界。

### 5.4 预注册门与负结果

关键实验在看数据前冻结 go/no-go 条件。例如：

- ICI-DF full-stack 必须跨 seed 稳定降低 BER，而不是只挑一个正 seed；
- Phase 3 贪婪算法至少保留 F1 穷优增益中位 80%；
- 端口选择最终必须在扣除损伤、同步和扫描后仍有正净收益；
- OTA EVM² 增量与离线的倍率必须不超过 2 才能称定量标定通过。

门未通过就保留 no-go，不改指标、不事后换成更容易通过的 RMS-EVM，也不删除反噬 seed。

### 5.5 BER、零错误与 outage

有限样本“没有观察到错误”不等于真实 BER 为数学零。smoke 单点 636,480 bit 无错只支持
约 $1.57\times10^{-6}$ 的经验分辨率；论文级零错点应报告二项分布 95% 上置信界。

同步失败的 seed 不进入条件 BER 的分子，但必须单独进入 outage：

$$
\widehat{BER}_{cond}=\frac{\sum_{i\in\mathcal A}N_{e,i}}
{N_{bits/frame}|\mathcal A|},\qquad
\widehat P_{out}=1-\frac{|\mathcal A|}{N_{attempt}}.
$$

只报告成功帧 BER 而隐藏 acquisition failure，会系统性高估真实链路。

### 5.6 实验总览

| 实验组 | 主要目的 | 关键控制 | 主要指标 |
|---|---|---|---|
| 实时 C/MEX | 验证持续处理、队列和 C/MATLAB 等价 | 同一 OTA reference、timestamp/sequence 审计 | 时延、pending、dropNew、BER、NMSE |
| Phase 0 | 建立 reference-to-BER 回归锚点 | flat 满秩信道、固定 seed | PSS/PBCH、BER、EVM |
| Phase 1 | 区分静态可吸收和动态残余 | 六条 1-D、四张 2-D、同帧配对 | BER、EVM、`cond(Hhat)` |
| CFO 基线 | 验证每用户 CFO 的解析门限和补偿 | 同用户参数、补偿开/关 | 分层 BER、残余 CFO |
| Phase 2 OU | 验证相关时间而非仅 RMS 决定退化 | 同边缘方差、同随机流、扫 $\tau_c$ | BER、lag-1、floor hit |
| ICI-DF | 测量可恢复结构和算法效率 | Q、迭代、hard/soft、genie | BER、gap closure、capture |
| RX-LO | 比较公共与独立本振拓扑 | 同 $\sigma_\phi,B_{PLL}$、成对 seed | BER、EVM²、CPE slip |
| acquisition | 分离噪声 waterfall 和假峰平台 | 100 seed、多 SNR、1/2/4 帧累积 | 成功率、false peak、McNemar |
| R15 OTA | 检验离线损伤是否能迁移到真实 IQ | 同一 raw122 ideal/impaired 配对 | EVM² 增量、方向一致率 |
| Phase 3 | 验证 M>N 的算法和系统净收益 | TDL 优先、穷举/贪婪、完整损伤、扫描 | min-SINR、AMC goodput、bits/Joule |

---

## 第 6 章　实验过程、数据和结论

### 6.1 实时链路：C/MEX 是否真的跟得上空口

#### 实验目的

离线算法即使正确，如果每 10 ms 帧的处理时间超过 10 ms，环形队列仍会持续增长，最终
丢数据。因此首先验证 direct RX 的数值等价、分段时延、缓冲积压和连续 BER。

#### 设计

MATLAB 先用 PSS 完成粗同步，再采用两阶段启动：第一次丢弃冷启动历史，建立持久 maps 和
窄窗跟踪后再次 flush（清空软件 ring），然后从新的 PSS 对齐 timestamp 启动 C
consumer（消费者）。每一帧保存 extract（抽取）、FFT、PHY 和 total（总计）时延，同时
审计 producer/consumer（生产者/消费者）sequence、timestamp、
pending、dropNew、硬件 overflow 和 timeout。

#### 结果

- native-ring C grid 与 MATLAB grid 的 NMSE 约 `-115 dB`；信道 NMSE 约 `-115 dB`；
  单帧 raw bit errors 完全一致；
- 一次旧启动方式的 60 s 运行解码 6041 帧，分段时延
  `2.142/5.141/1.943 ms`，总时延 `9.380 ms/frame`；
- 该运行 `dropNew=0`，最终 pending 为 10 block，历史峰值为 517 block；四层 BER 为
  `[1.66e-8,3.02e-8,1.04e-9,1.98e-8]`；
- 517 表示启动期间曾积压约 517 个 1 ms 数据块，不是“一帧解码耗时 517 ms”；
- 两阶段 10 s 对比把启动时 pending 从约 482 降到 84、峰值从约 558 降到约 103、
  最终从约 214 降到约 15，且 `dropNew=0`。

另一次 60 s 运行在约 59 s 出现 PSS 跟踪失败，pending 从约 20 升至 206，包含失锁尾段
的全程 BER 变为约 `7.1e-3`；失锁前 58.7 s 汇总约 `6.3e-8`。该反例说明数据面接近
实时不等于控制面永不失锁，连续 BER 必须和同步事件一起解释。

#### 结论

C/MEX 数据面已经达到约 100 frame/s 的实时级处理速度，并且没有因数值近似牺牲与
MATLAB 的等价性。两阶段启动能显著降低冷启动积压，但不能消除硬件描述符和后续同步
失锁风险。

### 6.2 Phase 0：建立无硬件依赖的 reference-to-BER 主干

#### 实验目的与设计

在加入任何新损伤前，需要一个关闭模型即可逐位回归的基线。配置为 32 dB SNR、确定性
满秩 4×4 flat 信道、850 Hz 公共 CFO、理想四相开关和 3 帧数据。完整运行
PSS、PBCH、DM-RS、RZF、QPSK 和 BER，而不是跳过同步直接向检测器喂理想网格。

#### 结果

- 四层有限样本经验 BER 均为 0；
- 平均 EVM 为 `[2.718,2.775,2.714,2.738]%`；
- 公共 CFO 估计约 `861--864 Hz`，相对 850 Hz 的偏差低于冻结的 25 Hz 回归阈值。

#### 结论

这不是“证明真实 BER 为零”，而是建立了稳定的功能和数值回归锚点。所有后续模型关闭时
必须退化回该主干。

### 6.3 Phase 1：静态损伤分类与逐用户 CFO

#### 为什么先做六条单变量和四张热图

同时打开隔离、建立、功率、定时、相噪和 CFO 会产生很多可能归因。单变量扫描先回答
每项是否独立影响 BER；二维图再检查交互是否存在。smoke 采用至少 3×3 网格只做结构
验证，pilot 至少 5×5；不把 2×2 四角点冒充交互曲面。

#### 静态项结果

隔离度 15 dB 到理想、固定建立 0--10 ns、功率不平衡 0--±3 dB、100 ps 递推抖动和
小幅 Wiener 相噪扫描均未观察到 BER 变化。25 dB 隔离 + 5 ns 建立的同段 OTA 配对中：

- `cond(Hhat)` P95 从 `4.4739` 增到 `5.6021`，相对增加 25.2%；
- 解析泄漏矩阵预测增加 23.8%，误差只有 1.4 pp；
- OTA EVM 从 `2.178%` 增到 `2.257%`；
- ideal 和 impaired 两支有限样本均无 bit errors。

离线 flat 锚点的条件数增加 28.5%，方向和量级一致。这验证了“静态损伤被等效信道
吸收，但通过病态化提高噪声放大”的理论。

#### CFO 压力实验

用户 CFO 为 `[-350,125,620,-900] Hz`，另叠加 850 Hz 公共 CFO，并加入 CP 内分数定时、
`[-3,0,3,-1.5] dB` 功率不平衡和独立 TX 相噪。仅做共同 CFO 补偿后，实测残余为
`[-171.4,300.9,792.9,-737.5] Hz`，四层 BER 为

```text
[0, 0.0137, 0.273, 0.259].
```

318 Hz 判决门限正确预测第 3/4 层有 7 个远端数据符号越过 45°，无噪声 BER 预测均为
0.2692；实测偏差低于 4%。跨 slot DM-RS 估计逐用户残余并在 RZF 信道列上施加时间相位
斜坡后，BER 变为

```text
[0, 5.87e-5, 9.49e-4, 0],
```

第 3 层降低约 288 倍。

#### 边界

跨 slot 间隔为 0.5 ms，所以估计器无模糊范围只有 ±1 kHz；当前 793 Hz 已接近边界。
它不能在 ±2 kHz 场景中自动正确解缠。定时扫描中 `cond(Hhat)` 增长约 8% 是信道估计
插值伪影，不是纯列相位改变了真实信道条件数。

### 6.4 Phase 2-A：时变建立与 OU 相关时间

#### 实验目的

Phase 1 已证明固定建立不会直接产生 BER，故下一步不是继续加大固定 rise，而是让
$\beta[n]$ 在帧内变化，并检查相关时间是否产生不同频谱结构。

#### 代数验证

高速样点间隔 8.138 ns 下，理论与实测 lag-1 为：

| $\tau_c$ | 理论 $e^{-T_r/\tau_c}$ | 实测 beta lag-1 |
|---:|---:|---:|
| 8 ns | 0.3616 | 0.3600 |
| 100 ns | 0.9218 | 0.9214 |
| 1 µs | 0.9919 | 0.9918 |

fast=0.6 时，$\tau$ 下限触发率实测 4.92%，高斯尾理论为 4.94%。这些结果确认随机过程、
创新方差和截断审计均正确。

#### BER 结果

在相同边缘方差下，标准接收机 BER 从近 i.i.d. 的约 `1.7e-3` 上升到 8 ns 的约
`2.0e-3`、100 ns 的 `5e-3--7e-3`、1 µs 的 `8.2e-3--1.12e-2`。genie 知道完整
$\beta[n]$ 时四点均可恢复到有限样本零错。

#### 结论

信息没有在代数意义上不可逆丢失，但同等 RMS 下，慢相关扰动比白抖动危险约一个数量级。
开关驱动规格应约束 PSD 或相关时间；只写 RMS 会把两个 BER 相差约 10 倍的器件视为等价。

### 6.5 Phase 2-B：ICI-DF 在隔离场景中的正结果

#### 设计

第一遍 RZF 产生判决 $\hat x$，按每个 OFDM 符号估计有限宽 ICI 核，再重建干扰、消除并
二次判决。扫描核半宽 $Q$、迭代次数以及 hard/soft 回归量。soft 使用判决置信度减轻错误
符号污染；hard 只使用象限硬判决。

#### 结果

在 flat 隔离锚点上：

- $Q=6/12/24$ 的 soft ICI-DF 相对 BER 降低 `36.9/47.9/53.2%`；
- $Q=12$ 的 1/2/3 次迭代降低 `47.9/52.1/57.9%`；
- 对应实现效率 $\eta=0.658/0.716/0.795$；
- soft 相对 hard 额外降低约 8.5%；
- 在 `BER<=1e-2` 的 flat 包络中，$\tau_c=1$ µs 快抖容限保证放宽超过 1.25 倍，
  插值估计约 1.3 倍。

![ICI-DF 的核半宽、迭代和 SNR 统计](docs/images/phase2_ici_df_statistics.png)

![ICI-DF 的 flat 器件规格包络](docs/images/phase2_device_envelope.png)

#### 结论与限制

该实验建立了“动态开关损伤具有可恢复结构”的正向机制证据，也验证了捕获律。但它是
flat、条件良好的隔离场景，不是论文最终系统结果。

### 6.6 Phase 2-C：为什么算法进入 TDL 后只剩约 3%

#### 机制分解

R10/R11 分解发现：单 bank 真值 capture 只有 `26.2/35.3%`；加入前相位近似 bank 后为
`47.5/51.3%`；改用精确 drive 和 25 实自由度共轭约束后升到 `63.7/64.5%`；从 ADC
构造 received-drive 仍为 `63.65/64.35%`。这证明 ICI 结构真实存在且部分可观测。

然而实际 DDCE + received-drive 在两个 seed 的 gap closure 为 `10.89/40.65%`，第一点
没有达到预注册的 10 pp 增量门，跨 realization 不稳定。信道估计误差和深衰子载波上的
判决错误会污染回归量，使真值 capture 无法稳定转化为 BER 收益。

#### 最终 TDL 结果

20 dB、fast=0.6、$\tau_c=1$ µs 的 10 个 TDL realization 中，$Q=12$、3 次 soft DF
把聚合条件 BER 从 `0.16567` 降至 `0.16046`，相对降低 3.15%，9/10 seed 改善；
$Q=24$ 只剩 1.30%，说明频选深衰下存在捕获带宽与估计噪声的偏差/方差折中。

![ICI-DF 在 TDL 中的最终 Q、迭代和 SNR 曲线](docs/images/phase2_r14_final_curves.png)

![隔离机制与 full-stack 迁移边界](docs/images/phase2_r14_integration_boundary.png)

#### 裁决

ICI-DF 在机制层面通过，在 full-stack 默认接收机升级门上 no-go。正确表述是“动态状态
结构可恢复，但稳定迁移受信道估计质量和模拟状态可观测性双门控制”，而不是“ICI 不可
恢复”，也不是“算法已经解决全栈问题”。

### 6.7 RX-LO：公共本振不一定总比独立本振好

#### 原假设与实验

原先假设公共 LO 只产生一个标量相位，更容易跟踪，因此 BER 应始终不差于独立 4-LO。
实验以相同 $\sigma_\phi$ 和 $B_{PLL}$ 成对比较公共、公共+CPE、独立三种路径，并验证
零相噪恒等、公共相位跨列一致、OU lag-1 和 PSD 锚点。

#### 结果

- independent+CPE 的增量 EVM 功率随 $\sigma_\phi^2$ 缩放，三个 PLL 带宽的
  $R^2=0.9913/0.9915/0.9901$；
- 10 kHz、8° 的坏 seed 中，11/130 个周跳符号承载 25487/25498，即 99.957% 的错误；
- oracle CPE 可恢复到有限样本零错；连续 $\pi/2$ 锚定把 25498 errors 降到 8364；
- 慢 PLL 下独立 LO 可通过空间平均显著优于公共 LO；病态信道又会因行相位失配使排序
  反转。

![公共单 LO、独立 4-LO 和 CPE 的条件排序](docs/images/phase2_rx_lo_topology.png)

#### 结论

“公共相位是共享状态、知道时容易校正”成立，但“公共 LO blind BER 必然更好”被证伪。
规格轴至少要包含 $(\sigma_\phi,B_{PLL},\mathrm{cond}(\hat H))$ 和相位获取能力，不能
压缩成一个普适的规格放宽倍率。

### 6.8 PSS acquisition：噪声 waterfall 与假峰平台

#### 设计

只运行同步路径，不做完整解码，以 100 个 TDL seed 扫 SNR。比较单帧四链合并、峰位投票、
2 帧和 4 帧非相干累积；另在 20 dB 比较 switch-off（关闭开关）、ideal-interleaving
（只保留理想四相交织）和 impaired-on（打开完整开关损伤）。

#### 结果

- 单帧 combined 在 8--26 dB 始终只有 `52/100` 成功，高 SNR 不再改善；
- 4 帧累积把 -8 dB 成功数从 14 提高到 54，约把 waterfall 左移 5 dB；
- 4 帧累积把高 SNR 平台提高到 70%，但剩余失败仍为 false peak；
- 20 dB 的 switch-off / ideal-interleaving / impaired-on 为 `75/76/52`；
- 交织结构差为 0 rescue/1 loss，McNemar `p=1`；模拟损伤差为 25 rescue/1 loss，
  `p=8.05e-7`。

![PSS acquisition 的噪声区、平台和多帧累积](docs/images/phase2_pss_acquisition_probability.png)

![交织结构和模拟开关损伤的获取成本分解](docs/images/phase2_r14_switch_attribution.png)

#### 结论

获取失败由两个机制组成：低 SNR 的噪声 waterfall 和高 SNR 的 realization 假峰平台。
当前 23 pp 开关获取代价几乎全部来自联合模拟损伤，而不是四相交织结构本身。多帧累积
有效但不能消除假峰。

### 6.9 R15 OTA：模型方向成立，但定量标定 no-go

#### 设计

采集 rxGain 25/30/35 各 5 段、每段 20 ms 的合格 raw122。每段先通过 PSS、PBCH 和 EVM
门，再对完全相同的原始 IQ 分别执行 ideal 和 25 dB 隔离、20 ns 建立、20 ps 转换抖动、
100 ps 边界抖动两支。主指标预注册为误差功率域

$$
\Delta_{EVM^2}=\frac{EVM_{imp}^2-EVM_{ideal}^2}{EVM_{ideal}^2}.
$$

#### 结果

- 15/15 段 gate 通过，ideal/impaired 两支有限样本均无 bit errors；
- OTA 与 matched-SNR 离线的损伤方向 15/15 一致；
- OTA 中位增量 0.83035，离线中位增量 0.39315，倍率为 **2.112**；
- RMS-EVM 字面倍率为 1.957，但这是凹压缩，不能在看数后替换预注册 EVM²；
- 三档 rxGain 的实际 SNR 全部重叠在 33--43 dB，并不构成三个独立 SNR 点。

#### 裁决

预注册门要求倍率不超过 2，故正式 no-go。可支持的主张是“高 SNR 单簇下，离线和 OTA
损伤方向一致、量级相近，离线模型对新增误差功率偏乐观约 2 倍”；不可声称“多 SNR
定量标定通过”。

### 6.10 Phase 3-A：M>N 平台和穷举标尺

#### R16 代数地基

M=N、$S=I$ 时新平台与旧系统逐位一致；M=8 理想标量链相对误差为 0；$S^TH$ 相对误差
为 `1.69e-16`；占空比守恒、超限拒绝和非法同相扇出拒绝全部通过。无论 M 取多少，
物理输出始终只有一列。

#### R17 Gate 1

冻结 M=8、N=4、每链恰好 2 端口且每端口只属于 1 条链，共 2520 个唯一调度。在 20 个
成对 TDL seed 上：

- 19/20 个穷优结果优于 M4；
- 全 612 个子载波的最差用户 SINR 中位增益为 `+2.420 dB`；
- bootstrap 95% CI 为 `[+1.863,+3.613] dB`；
- 单侧符号检验 `p=2.00e-5`；
- 固定相邻配对中位为 `-1.030 dB`；强制满 8 端口仍有一个 `-0.050 dB` 反例。

![M=8 的 2520 候选穷举标尺](docs/images/phase3_r17_exhaustive.png)

#### 结论

理想开关下确实存在 M>N 选择 headroom，但收益来自“选对端口”，不是简单把更多端口
相加。强制使用所有端口不保证每个 realization 获益。

### 6.11 Phase 3-B：关停自由度、贪婪算法与码叠加负结果

F1 允许每个端口关停或只加入一条链，每链至少一个端口，共 166824 个候选，且包含 M4
基线和 R17 的 2520 个调度。20 个 TDL seed 上：

- F1 穷优 20/20 不低于 M4，修复了 R17 的强制满端口反例；
- 贪婪 20/20 胜 M4，保留 F1 穷优增益的中位 92.4%，超过预注册 80% 门；
- F1 穷优/贪婪中位增益为 `+3.693/+3.238 dB`；
- 传统 FAS 每链单端口选择只有 `+0.378 dB`；随机基线为 `-0.973 dB`。

F2 允许同一端口跨码相加入两条链，但相对 F1 穷优仅 5/20 为正，中位 `-0.203 dB`；
flat 中位为 0。局部松弛量化只有 `+0.053 dB` 中位且 10/20 为正，也不是全局上界。

![F1/F2、穷举、贪婪和基线对比](docs/images/phase3_r18_gate2.png)

结论是一个有价值的架构简化：在当前设置中，GreenMO 式 many-to-many 码叠加没有稳定
增值，简单 Dmax=1 端口划分已获得主要增益。

### 6.12 Phase 3-C：从 SINR 正收益到系统净吞吐

#### R19 为什么先 no-go

把 M=8 调度送入 122.88 MS/s 标量开关，加入 25 dB 隔离、20 ns 建立、fast=0.2、
$\tau_c=1$ µs、acquisition 和扫描。成功帧平均 BER 从 M4 的 3.20% 降到 F1 穷优/
贪婪的 1.03%/1.15%，说明数据质量改善仍在。SINR-quality 分解为

```text
选择 +4.28 dB - 损伤 1.46 dB - 同步 0.22 dB - 扫描 0.46 dB
= 净 +2.14 dB。
```

但固定 QPSK 已接近吞吐饱和，按每 100 ms 扫一个 10 ms 帧后，M8 有效吞吐相对 M4
约为 `-0.122`，因此固定-QPSK goodput no-go。这个结果没有被用 SINR 正收益掩盖。

#### R20 如何闭合系统收益

R20 将 M 扩展为 8/12/16，用 50 个同源 TDL seed，加入冻结的 CQI-style AMC 和扫描周期
曲线。四帧 acquisition 成功数为 M4/M8-data/M8-aware/M12/M16 的
`[46,47,48,48,47]/50`。前 20 个完整解码 seed 中：

| 指标 | M4 | M12 | M16 |
|---|---:|---:|---:|
| EVM-quality 中位数 | 5.44 dB | 9.58 dB | 9.99 dB |
| 成功帧平均 BER | 3.84% | 0.83% | 0.61% |

1 s 更新时，M8-aware/M12/M16 的净 AMC 增益为

```text
+0.449 / +0.614 / +0.710 bit/s/Hz。
```

AMC 门限整体移动 ±2 dB 时 M12/M16 仍为正。50 ms 更新时 M12/M16 分别为
`-0.012/-0.295`，100 ms 后才转正。

![SINR 正、固定 QPSK 负、AMC 正的系统闭环](docs/images/phase3_r20.png)

同步感知 oracle 相对纯数据选择只有 1 rescue、0 loss，McNemar `p=1`；不能声称同步
感知选择显著有效。净收益来自 AMC、更多候选端口和扫描摊薄，而不是同步 oracle。

### 6.13 Phase 3-D：理论闭合

R21 对 R20 的 50 个 seed 和同一 $S,H,R_n$ 重算闭式 LMMSE 目标，最大误差只有
`8.88e-15 dB`。M4/M8/M12/M16 的中位最差用户理论速率为

```text
3.093 / 4.226 / 4.847 / 5.263 bit/s/Hz，
```

相对 M4 分别在 49/49/50 个 seed 胜出。联合 log-det 始终不低于 LMMSE sum-rate，残余
谱界给出保守下界。

更重要的归因是，固定所选端口集的中位 min-chain array gain 为
`[0,-0.33,-0.52,-0.55] dB`。即固定端口阵列增益并没有随 M 增大，R20 正收益来自观察
信道后的选择和条件数改善。J0 几何还显示 M=24 时 0.125 波长间距为 `-1.78 dB`，
0.25 波长为 `+2.59 dB`，所以更密端口不必然更好。

![闭式 LMMSE 速率、上下界和几何边界](docs/images/phase3_r21_theory.png)

### 6.14 Phase 3-E：统一能效模型

#### 公平口径

组件表采用同一 RFIC、ADC、开关、移相器和派生基带口径。LO 已包含在 RFIC 中，不重复
计费。本文、GreenMO-like 和 HBF 均计端口扫描能量；DBF 因同时观察所有端口无需额外
扫描。跨架构分子统一使用理想 LMMSE sum-rate；本文另报 R20 full-stack AMC 锚点，
但不拿它与基线的理想速率直接排名。

#### M=16、N=4、1 s 更新结果

| 架构 | 理想 sum-rate | 平均 RX 功耗 | 理想参考能效 |
|---|---:|---:|---:|
| 本文 Dmax=1 | 21.634 bit/s/Hz | 1.925 W | 200.1 Mbit/J |
| GreenMO-like | 22.294 bit/s/Hz | 1.925 W | 206.2 Mbit/J |
| DBF | 30.411 bit/s/Hz | 12.260 W | 45.5 Mbit/J |
| 部分连接 HBF | 16.603 bit/s/Hz | 3.347 W | 88.3 Mbit/J |
| 全连接 HBF | 23.311 bit/s/Hz | 3.827 W | 108.5 Mbit/J |

本文相对 DBF 的 low/nominal/high 组件敏感性能效比为 `5.22/4.39/4.06` 倍；正号不依赖
单一标称参数。原始理想 sum-rate 比为 `21.634/30.411=71.1%`，再扣除本文 3% 扫描
payload 后的有效比约为 69%。更准确的论文表述是“以约 69% 的扫描后有效理想速率、约
15% 的模型功耗，获得约 4.39 倍理想参考能效”，而不是“性能等同 DBF”。

![统一组件表下的功耗、能效和更新周期](docs/images/phase3_r22_energy_efficiency.png)

本文 M=16 的更新周期从 50 ms 放宽至 100 ms/1 s/10 s 时，理想参考能效为
`82.5/144.4/200.1/205.7 Mbit/J`，清楚显示扫描不能免单。固定 M=16，活动流 N=1 到 4
时，本文功耗从 `0.721` 增至 `1.925 W`，DBF 仅从 `12.099` 增至 `12.260 W`；本文具有
负载能量正比性，但低 N 因扫描更多端口组，每次扫描能量反而从 `0.108` 到 `0.058 J`。

![活动流数与扫描能量](docs/images/phase3_r22_energy_proportionality.png)

R20 四流汇总的 full-stack AMC 能效仅为 M4/M8/M12/M16 的
`38.4/55.5/61.7/65.2 Mbit/J`。M16 的 65.2 约为理想 200.1 的三分之一，反映同步、
开关损伤、离散 AMC 和实际解码的共同代价。DBF/HBF 没有同等 full-stack 结果，因此
不能用 65.2 与其理想 45.5/88.3/108.5 排名。

### 6.15 投稿前补充：估计信道选择、单用户 FAS 与移动速度边界

#### E1：非 oracle 的 DM-RS 扫描选择

E1 回答 R20 最大的部署问题：若贪婪选择器看不到 TDL 真值、只能使用扫描帧上的 Type-1
DM-RS 估计信道，原有选择增益还剩多少。每 10 ms 扫描帧观测一组互不重叠的四个端口，
M=8/12/16 分别需要 2/3/4 帧；观测经过与 R20 相同的 20 dB AWGN、25 dB 隔离、20 ns
建立、fast=0.2 和 1 us OU 相关时间。已知的名义泄漏矩阵用于 LS 反演，但算法不读取
TDL taps，也不使用真实建立系数修正残差。

reference 在 OFDM 调制后对各层分别做 0.72 峰值缩放，故 DM-RS 估计天然包含一项已知
发射比例。首轮 smoke 因未去嵌该比例而作废；正式代码只从共享 reference 计算并去除
比例，不读取信道真值。扫描矩阵 16 阶满秩，纯代数恢复相对误差为 `2.54e-16`。

20 个成对静态 TDL seed 的结果为：

| 指标 | M=8 | M=12 | M=16 |
|---|---:|---:|---:|
| truth-CSI 贪婪相对 M4 的中位 objective 增益 | 3.945 dB | 5.939 dB | 6.665 dB |
| DM-RS 估计选择的中位 objective 增益 | 3.373 dB | 4.358 dB | 5.864 dB |
| 增益保留率中位数 | 90.2% | 78.8% | 85.5% |
| 估计选择仍有正 objective 增益的 seed | 19/20 | 20/20 | 20/20 |
| H NMSE 中位数 | -3.94 dB | -4.09 dB | -4.07 dB |
| 1 s full-stack AMC 净增益 | +0.186 | +0.394 | +0.352 bit/s/Hz |

这里的“truth-CSI 贪婪”只是同一贪婪算法读取真实信道后的参考，不是全可行集穷举最优；
因此估计版有少量 seed 可因搜索路径变化超过该参考，保留率允许大于 100%。正式数据表明
在线信息约束没有消灭正增益，但 M12/M16 的 full-stack 增益低于 R20 oracle 头条值，
选择收益仍受信道估计和 acquisition 成功率门控。该实验是离线模拟的非 oracle 控制器，
不能改写成板卡上已完成实时闭环。

![DM-RS 估计选择相对 truth-CSI 贪婪参考的保留率、AMC 与 H NMSE](docs/images/paper_e1_online_selection.png)

#### E2：单用户 FAS 最强端口分集

E2 把工作模式补成三级：单用户最强端口分集、M=N 多用户分离、M>N 多用户选择。单用户
实验生成单位功率 Rayleigh 衰落，端口相关为
$R_{ij}=J_0(2\pi |x_i-x_j|/\lambda)$；每个相干期只选择瞬时功率最大的一个端口，不做
多端口相干求和。10 万个 realization 使用同一 16 端口高斯基底及嵌套端口前缀。

M=1 的蒙特卡洛 outage 与解析式 $1-e^{-\gamma/\rho}$ 的最大绝对误差为
`0.0029/0.0013/0.0023`。在 10% outage 目标处，M=16 相对 M=1 的所需平均 SNR 收益为：

| 相邻端口间距 | 0.125 lambda | 0.25 lambda | 0.5 lambda |
|---|---:|---:|---:|
| M=16 SNR gain | 10.599 dB | 12.040 dB | 12.576 dB |

这证明经典 FAS 选择分集在同一 J0 几何模型中成立；间距较小时相关更强，收益较小。它是
单用户平坦 Rayleigh 模式，不等价于第 6.12 节的四用户宽带波束选择，也不包含扫描损伤。

![单用户 FAS outage 与 10% outage 的选择分集增益](docs/images/paper_e2_fas_diversity.png)

#### E3：扫描周期到移动速度的解析映射

采用 Clarke/Jakes 的 50% 相干时间近似 $T_c=0.423/f_D$ 和
$f_D=v/\lambda_c$。3.2 GHz 下 $\lambda_c=9.375$ cm；要求更新周期不超过相干时间，可得：

| 更新周期 | 50 ms | 100 ms | 200 ms | 500 ms | 1 s | 2 s | 5 s | 10 s |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 最大速度（m/s） | 0.793 | 0.397 | 0.198 | 0.0793 | 0.0397 | 0.0198 | 0.00793 | 0.00397 |
| 最大速度（km/h） | 2.855 | 1.428 | 0.714 | 0.286 | 0.143 | 0.0714 | 0.0286 | 0.0143 |

R20 的 100 ms 转正点因此对应约 1.43 km/h，只适合准静态、缓慢游牧或固定无线环境。
这是一条解析适用边界，不是移动场景闭环实测，也不表示相关系数在 $T_c$ 后突然归零。

![扫描/选择更新周期与最大名义移动速度](docs/images/paper_e3_mobility_mapping.png)

---

## 第 7 章　从全部实验得到的技术认识

### 7.1 第一条认识：静态器件指标不是 BER 的唯一答案

隔离度和固定建立时间可以很差，却仍被导频估计为等效信道；反之，一个平均值看似很好、
但在帧内缓慢漂移的器件可能产生更大 BER。设计规格必须从“静态值”升级到“静态值、
动态 RMS、PSD/相关时间和可校准周期”的联合描述。

### 7.2 第二条认识：算法的真值天花板和全栈收益是两件事

genie 零错或 64% 真值 capture 只说明信息结构存在，不代表实际接收机能估到它。TDL 深衰、
`Hhat` 误差和错误判决的子载波分布决定结构能否迁移。论文应同时给出 mechanism result、
TDL result 和 full-stack gate，而不能只展示最好的一层。

### 7.3 第三条认识：同步是系统吞吐的一部分

高 SNR 下 PSS 仍有 realization 假峰平台；只提高数据 SINR不能保证 acquisition 成功。
多帧累积能左移噪声 waterfall，却不能完全消除假峰。吞吐公式必须包含 $P_{acq}$，不能
只在成功帧上报告 BER。

### 7.4 第四条认识：更多端口的价值来自选择，不是固定求和

固定相邻端口、强制使用全部端口和固定 round-robin 都出现负例。M>N 的收益来自先观察
信道，再选能改善最差用户和条件数的端口。Dmax=2 码叠加没有稳定增值，说明更复杂的
many-to-many 连接并不自动换来性能。

### 7.5 第五条认识：器件级 SINR 收益要通过系统工作点兑现

R19 的 `+2.14 dB` SINR 净收益在固定 QPSK 中变成负 goodput，因为 QPSK 已饱和且扫描
需要时间。AMC 把约 2 dB 质量提升转成更高 MCS 后，M=12/16 才稳定获得正净吞吐。
因此“算法有增益”必须与调制工作点和更新周期一起表述。

### 7.6 第六条认识：能效优势不等于速率等同

单链方案的主要优势是 RFIC/ADC 数量减少和随活动流数缩放的功耗，而不是达到 DBF 的
全部理想速率。最诚实的结果是速率—功耗折中：未扣扫描的理想 sum-rate 约为 DBF 的
71%，扫描后有效理想速率约为 69%，模型功耗约为 15%，理想参考 bits/Joule 约为 4.39 倍。

---

## 第 8 章　应用场景与工程落地方式

### 8.1 低功耗小型基站和专用网络

工厂、园区、仓储和室内专用网络通常用户数有限、信道变化较慢，端口选择更新周期可达到
100 ms 以上。这与 Phase 3 正净收益所需的“AMC + 扫描摊薄”条件相符。单链前端可降低
RFIC、ADC 和时钟树功耗，同时维持 4 用户上行分离。但 E3 表明 3.2 GHz、100 ms 对应
的名义速度仅约 1.43 km/h，所以这里主要指固定设备、缓慢移动终端或可长期保持端口质量
的环境，不应泛化到厂区高速车辆。

### 8.2 大量候选端口、少量同时活动用户

当物理候选端口 $M$ 明显大于活动用户数 $N$ 时，全数字化所有端口成本很高。本技术可在
信道相干期内低频扫描端口，选出改善最差用户的子集，然后用一条宽带链持续接收。适合
流体天线端口阵列、可重构天线面板和空间端口选择接入点。

### 8.3 能量正比的接收前端

DBF 往往需要始终开启 M 条链。本文模型中，活动流从 1 增到 4 时功耗从 0.721 增至
1.925 W，表现出随负载增长的能量正比性。对长时间低负载、偶尔多用户突发的接入设备，
这种特性比单一峰值吞吐更有价值。

### 8.4 器件规格和算法协同设计

本项目不仅给出接收算法，也给器件工程师提供规格语言：

- 固定隔离度决定等效条件数和噪声放大；
- 平均建立时间决定静态前相位混合；
- 建立时间快抖动必须同时给 RMS 和 PSD/相关时间；
- RX-PLL 必须同时给稳态 RMS、带宽和相位获取能力；
- 端口扫描周期必须与信道相干时间共同设计。

这使“选一个更快开关”转化为可计算的器件—信号处理协同问题。

### 8.5 研究和测试平台

离线/OTA 共 reference、同 raw IQ 配对注入、C/MATLAB 逐帧等价和完整审计链，使该工程
也适合作为开关接收机算法、同步方法、动态器件模型和端口选择算法的研究基准平台。

### 8.6 目前不适合直接声称的场景

- 高速移动、信道相干时间短于约 100 ms 的场景，扫描开销可能吞掉收益；
- 需要每根天线独立数字波束赋形或高阶空间复用上限的场景，DBF 仍更合适；
- 未制造真实高速开关板前，不能把当前 OTA 描述为单链 RF 原型验证；
- E1 虽已替换 oracle 信道输入，但未部署板卡实时控制闭环，不能声称端口选择器已经实时部署。

---

## 第 9 章　限制、风险和后续增强

### 9.1 当前结论的五条冻结限制

1. 固定 QPSK 或更新周期不超过 50 ms 时，端口选择净吞吐可能为负；
2. Dmax=2 码叠加没有稳定增值；
3. acquisition-aware 选择器的同步改善不显著；E1 已完成 DM-RS 估计选择，但尚未部署实时闭环；
4. M>8 只有贪婪结果，没有穷举最优差距标尺；
5. 能效是统一组件模型，不是板卡功率计测量。

### 9.2 OTA 覆盖不足

R15 的 15 段数据全部位于 33--43 dB 高 SNR 单簇。未来若要做多 SNR 定量标定，应使用
外部衰减器或 TX 功率步进，把 SNR 真正覆盖到约 5--25 dB，而不是只调 RX gain。

### 9.3 真实开关硬件

下一项最关键的硬件增强是制造真正的 122.88 MS/s 码相控制射频开关板，并测量隔离矩阵、
建立过程、温漂、抖动 PSD、插损和整机功耗。当前模型可以给设计指标，但不能替代这些
测量。

### 9.4 在线端口选择

E1 已在离线全栈中以扫描帧 DM-RS 估计 $H$，并把估计时间、扫描 payload、错误选择与
acquisition 计入 20-seed 对照；中位保留率 79%--90%，三种 M 的 AMC 净增益保持为正。
下一步若做硬件增强，应把该估计器和调度下发部署到实时 direct RX 控制面，并计入真实
控制消息、端口开关时序与信道随扫描过程变化的误差。当前不能声称这一闭环已实时部署。

### 9.5 标准化上行同步

当前波形把 SSB/PBCH 用作方便、可审计的同步脚手架。面向标准 NR 上行接入时，应研究
PRACH 或调度导频下的初始接入和端口扫描，不把当前自定义帧结构直接说成标准 UE 流程。

---

## 第 10 章　代码、数据与复现地图

### 10.1 关键入口

| 任务 | 主要文件 |
|---|---|
| 生成共同 reference | `type1_generate_reference.m`、`type1_build_package.m` |
| 完整 MATLAB 接收机 | `type1_analyze.m` |
| 实时 direct RX | `type1_rx_direct.m`、`type1_yunsdr_rx_mex.c` |
| C 帧级 PHY | `type1_decode_frame_grid_mex.c` |
| Phase 1 损伤与扫描 | `type1_apply_switch_impairments.m`、`type1_run_phase1_sweeps.m` |
| ICI-DF | `type1_analyze_ici_decision_feedback.m`、`type1_run_phase2_ici_df_statistics.m` |
| acquisition 统计 | `type1_run_phase2_pss_acquisition_statistics.m` |
| Phase 3 平台与选择 | `type1_phase3_make_schedule.m`、`type1_phase3_greedy_schedule.m` |
| Phase 3 全栈 | `type1_run_phase3_r19_gate3.m`、`type1_run_phase3_r20.m` |
| 理论 | `type1_phase3_theory_metrics.m`、`type1_run_phase3_r21_theory.m` |
| 能效 | `type1_phase3_power_breakdown.m`、`type1_run_phase3_r22_energy.m` |
| E1 估计信道选择 | `type1_phase3_estimate_scan_csi.m`、`type1_run_paper_e1_online_selection.m` |
| E2 单用户 FAS | `type1_run_paper_e2_fas_diversity.m` |
| E3 移动速度映射 | `type1_run_paper_e3_mobility_mapping.m` |

### 10.2 文档职责

| 文档 | 用途 |
|---|---|
| `README.md` | 工程首页、架构、关键脚本和冻结结果索引 |
| `SYSTEM_EXPLAINER.md` | 面向通信同行的较短系统说明 |
| `TECHNICAL_MANUAL.md` | 本手册，完整论文式技术叙事 |
| `IMPAIRMENT_MODELS.md` | 非理想性精确公式和模型级验证 |
| `PHASE3_ENERGY_MODEL.md` | R22 组件功耗和公平比较口径 |
| `EXPERT_REVIEW.md` | 每轮改动、配置、原始数据、结论与边界 |
| `REVIEW_VERDICTS.md` | R1--R22 独立专家裁决 |
| `RUN_COMMANDS.md` | 本地、远端、离线和 OTA 的可复制命令 |

### 10.3 冻结点

Phase 2 冻结 tag 为 `phase2-freeze-2026-07-15`，Phase 3 冻结 tag 为
`phase3-freeze-2026-07-16`。R16--R22 的平台、选择、全栈、理论、能效和文档提交均包含
在 Phase 3 tag 中。大体积 raw IQ 和 MAT 不进入 Git，仓库保存正式路径、SHA-256、结果
摘要和可复现命令。E1--E3 是 freeze tag 之后的投稿前补充，尚未并入新的冻结 tag。

---

## 第 11 章　总结

这项技术的核心不是“用一个开关神奇地替代所有射频链”，而是建立一个严格受约束的
时间—空间观测变换：以单个宽带标量流和高速码相切换换取多个虚拟 MIMO 观测，再依靠
导频估计、线性检测和端口选择恢复用户数据。

研究首先证明，固定周期的开关泄漏和建立过程通常会被 DM-RS 吸收到等效信道中；真正的
瓶颈是用户差分 CFO、时变建立、相关抖动、相位获取、频选深衰和同步假峰。损伤感知
ICI-DF 在隔离场景中能恢复 38%--58% 的 BER gap，但在真实 TDL 全栈中被压缩到约 3%，
由此明确了信道估计和模拟状态可观测性的迁移边界。

在此基础上，M>N 端口选择证明了理想和损伤后都存在真实选择 headroom。固定 QPSK 曾使
系统 goodput no-go，但 AMC 和至少 100 ms 的扫描摊薄使 M=8/12/16 获得
`0.45/0.61/0.71 bit/s/Hz` 的正净增益。统一能效模型进一步表明，M=16 时本文未扣扫描的
理想 sum-rate 约为 DBF 的 71%，扫描后有效理想速率约为 69%，模型功耗约为 15%，理想
参考能效约为 DBF 的 4.39 倍。

投稿前补充进一步关闭了三个解释缺口：DM-RS 扫描估计仍保留 truth-CSI 贪婪参考约
79%--90% 的中位 objective 增益，说明正收益不是只存在于 oracle；单用户 FAS 模式在
M=16 时提供 10.60--12.58 dB 的 10% outage SNR 收益；而 100 ms 更新在 3.2 GHz 下只
对应约 1.43 km/h，定量确认该架构当前的移动性甜区是准静态和缓慢游牧。

因此，本项目最终给出的不是一个无条件优于全数字接收机的结论，而是一张清晰的技术
适用图：当用户数较少、候选端口较多、信道变化足够慢、系统允许 AMC 和低频扫描时，
单链快速开关接收机可以用可量化的速率损失换取显著的射频链和能效优势；当同步、信道
变化或在线估计成本越过边界时，收益会消失。这个“正结果与边界同时可复现”的结论，
正是后续论文和硬件原型设计的基础。

---

## 参考资料与证据来源

### 标准与公开文献

1. 3GPP TS 38.211，NR 物理信道与调制；用于 OFDM、PSS/SSS/PBCH 和 DM-RS 定义。
2. 3GPP TR 38.901，5G 信道模型；用于 TDL-A 功率时延参数。
3. [GreenMO 项目与论文](https://wcsng.ucsd.edu/greenmo/)；用于单链码域多天线背景和
   R22 功耗锚点。
4. [MAX2829 官方资料](https://www.analog.com/en/products/max2829.html)与
   [AD9963 官方资料](https://www.analog.com/en/products/ad9963.html)；用于解释 RFIC/ADC
   功耗参数来源及外推边界。
5. [Björnson、Matthaiou、Debbah，IEEE TWC 2015](https://doi.org/10.1109/TWC.2015.2420095)；
   用于公共/独立振荡器相噪空间平均的理论背景。
6. [混合波束成形功耗模型参考](https://arxiv.org/abs/1807.07201)；用于 R22 HBF 组件口径。

### 本工程冻结证据

- 全部实验配置、seed、原始统计量和结论边界：[`EXPERT_REVIEW.md`](EXPERT_REVIEW.md)；
- 独立复现和 R1--R22 裁决：[`REVIEW_VERDICTS.md`](REVIEW_VERDICTS.md)；
- 精确非理想性公式：[`IMPAIRMENT_MODELS.md`](IMPAIRMENT_MODELS.md)；
- 完整运行命令和正式资产路径：[`RUN_COMMANDS.md`](RUN_COMMANDS.md)；
- R22 能效口径：[`PHASE3_ENERGY_MODEL.md`](PHASE3_ENERGY_MODEL.md)。
