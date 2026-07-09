# 4T4R Type-A 单符号 Type-1 DM-RS 实时实验

## 1. 程序概述

本项目实现了一个基于 YunSDR 软件无线电平台的 4T4R MIMO 实时通信系统。接收端以 122.88 MS/s（4 倍于发射采样率）轮询四根天线，通过数字域解交织恢复四路 30.72 MS/s 虚拟接收流，在单 RF 链条件下实现 4×4 MIMO 空间复用。

**系统架构**

发射端周期发射一个 10 ms NR 无线帧：Slot 0 承载标准 SS/PBCH block（仅 TX1 发送），Slot 1～19 承载 Mapping Type A、Type-1 单符号 DM-RS 的四层 QPSK 数据。每层每 slot 独立进行 K=7、R=1/2 卷积编码（7950 信息 bit → 7956 QPSK 符号），四层采用单位预编码直接映射到四根物理发射天线。

接收端 C MEX 后台线程以 122.88 MS/s 连续采集四路物理 RX IQ 并写入环形缓冲区。MATLAB 前台周期取快照，经数字射频开关解交织得到四路 30.72 MS/s 虚拟接收流，执行 PSS 定时同步 → CP 细频偏估计与补偿 → OFDM 解调 → SSS 校验 → PBCH 解码与 MIB 比对 → 每 slot 独立 Type-1 DM-RS OCC 解扩信道估计 → 逐 RE 的 RZF 均衡 → 硬判决 + Viterbi 解码 → BER/EVM 统计。

**技术要点**

- 物理层遵循 3GPP NR 标准：30 kHz SCS、51 RB、Type-1 DM-RS 的 FDM+CDM 四端口复用、标准 SS/PBCH block。
- 数字射频开关将四相轮询建模为模 4 选通与因子 4 解交织，通道间固定偏移由 DM-RS 信道估计吸收。
- 接收机支持运行时选择 RX 通道数（1～4），RX 不足 4 时自动退化为频谱/同步/PBCH 监测模式。
- 实时显示采用带内 vs 保护带 PSD 差（> 8 dB）检测信号存在性，TX 消失时即时清空星座图。
- 离线自检（`type1_selftest.m`）不依赖硬件，可注入已知 CFO 和 AWGN 完整验证链路。

**文件组织**

| 层次 | 主要文件 |
|------|----------|
| 配置 | `type1_config.m`, `type1_pdsch_config.m`, `type1_carrier_config.m` |
| 参考生成 | `type1_build_package.m`, `type1_generate_reference.m`, `type1_make_mib_bits.m` |
| 发射 | `type1_tx.m`, `type1_tx_stop.m` |
| 接收 | `type1_rx_live.m`, `type1_yunsdr_rx_mex.c`, `type1_build_rx_mex.m`, `type1_digital_switch.m` |
| 分析 | `type1_analyze.m`, `type1_analyze_fast.m`, `type1_read_initial_iq.m` |
| 工具 | `type1_load_package.m`, `type1_selftest.m`, `plot_type1_resources.py` |

## 2. 快速使用

### 2.1 可视化界面运行
TX 端运行 `type1_tx.m`
RX 端运行 `type1_rx_live.m`持续接收

正确 RX 程序启动后应打印：

```text
========== YunSDR Type-A live RX ==========
```

### 2.2 无显示界面运行（用于远程服务器）

TX，限时 60 秒：

```bash
printf '1\n' | sudo -S -p '' \
  env TYPE1_TX_DURATION_SEC=60 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_tx"
```

RX，无图形窗口，运行 10 秒：

```bash
printf '1\n' | sudo -S -p '' \
  env TYPE1_LIVE_DURATION_SEC=10 \
      TYPE1_LIVE_UPDATE_SEC=0.1 \
      TYPE1_LIVE_VISIBLE=off \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_rx_live"
```

首次部署或 MEX 失效时重新编译：

```bash
printf '1\n' | sudo -S -p '' \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_build_rx_mex"
```

异常退出后显式关闭循环发射：

```bash
printf '1\n' | sudo -S -p '' \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_tx_stop"
```

### 2.3 常用参数

| 参数 | 默认值 | 作用 |
|------|--------|------|
| `cfg.nLayers` | 4 | 发射空间层数/DM-RS 端口数，默认对应 TX1～TX4 |
| `cfg.nHardwareRxChannels` | 4 | MEX 从 YunSDR 采集的物理 RX 通道数 |
| `cfg.rxChannelSelect` | `1:4` | 参与分析的虚拟 RX 通道编号 |
| `cfg.nRxChannels` | 4 | 实际参与 DSP 的 RX 维度数，由 `rxChannelSelect` 决定 |
| `TYPE1_RX_CHANNEL_SELECT` | 空 | 运行时选择 RX，例如 `1,3`（`TYPE1_RX_CHANNELS` 为等效别名） |
| `TYPE1_N_RX_CHANNELS` | 空 | 运行时选择前 N 根 RX，例如 `2` 表示 RX1/RX2 |
| `TYPE1_LIVE_UPDATE_SEC` | 0.10 | 实时刷新周期 |
| `TYPE1_LIVE_VISIBLE` | `on` | `off` 表示无显示界面运行 |
| `TYPE1_TX_DURATION_SEC` | `inf` | TX 自动停止时间 |

注意：`cfg.nLayers` 是发射层数，不是接收天线数。当前发射端默认是
4 层空间复用；如果 RX 只启用 1～3 个通道，接收机仍可做频谱、
PSS/SSS、PBCH/MIB 监测，但 4 层数据 RZF、BER 和 EVM 会被显式禁用。
这是因为欠定系统没有足够观测量分离 4 个同时发射的空间层。

### 2.4 启动时 20 ms IQ 保存与读取

`type1_rx_live` 启动后台采集后，会在进入实时循环前保存最早抓到的
20 ms IQ。20 ms 对应 30.72 MS/s 下的 2 个 frame / 40 个 slot。

每次运行会在 `data/` 下生成三类文件：

```text
type1_initial_iq_YYYYMMDD_HHMMSS_seqXXXX_raw122_csingle_iq4.bin
type1_initial_iq_YYYYMMDD_HHMMSS_seqXXXX_virtual30_csingle_iq4.bin
type1_initial_iq_YYYYMMDD_HHMMSS_seqXXXX_meta.mat
```

含义：

- `raw122`：122.88 MS/s，4 个物理 RX 通道，20 ms；
- `virtual30`：经过数字开关/解交织后的 30.72 MS/s，4 个虚拟 RX 维度，正好 2 个 frame （ 40 个 slot）；
- `meta.mat`：采样率、样本数、时间戳、sequence 等辅助信息。

二进制格式为：

```text
complex single, MATLAB column-major, interleaved I/Q
```

也就是对矩阵 `x = [nSamples × 4]` 按 `x(:)` 展开，并写成：

```text
real(x1), imag(x1), real(x2), imag(x2), ...
```

读取并简要分析：

```matlab
cd('/home/bupt/tools/matlab_test/nr4x4_type1')
type1_read_initial_iq
```

该脚本会用 `fopen/fread` 找到最新的 `raw122` 和 `virtual30` 文件，打印每通道 RMS、峰值和 DC，并绘制时域幅度与快速频谱。

## 3. 文件说明

| 文件 | 作用 |
|------|------|
| `type1_config.m` | 射频、OFDM、SSB、Type-A 和编码参数（全局唯一配置源） |
| `type1_carrier_config.m` | 创建标准 nrCarrierConfig 对象，供 OFDM 调制/解调使用 |
| `type1_pdsch_config.m` | 创建严格 Type-A、Type-1 四端口 DM-RS 的 PDSCH 配置 |
| `type1_make_mib_bits.m` | 构造确定性 24-bit MIB 比特字段 |
| `type1_build_package.m` | 构造资源网格、比特、DM-RS 和四通道发射波形 |
| `type1_generate_reference.m` | 调用 build_package 并保存为 TX/RX 共用的 MAT 文件 |
| `nr4_type1_reference.mat` | 四层比特、QPSK、DM-RS、网格和 307200×4 波形 |
| `type1_load_package.m` | 加载并校验共享 MAT 文件（格式版本/端口/映射类型） |
| `type1_digital_switch.m` | 四相射频开关：122.88 MS/s 轮询 → 四路 30.72 MS/s 虚拟接收 |
| `type1_tx.m` | 四通道 30.72 MS/s 周期发射；函数退出时自动清理 |
| `type1_tx_stop.m` | 显式关闭板卡循环发送，异常退出后必须执行 |
| `type1_rx_live.m` | 实时频谱、同步、均衡、星座和 BER；支持运行时选择 RX 通道 |
| `type1_analyze.m` | 全 19 slot 分析：CFO、PSS/SSS/PBCH、DM-RS 估计和 nRx×nLayer RZF |
| `type1_analyze_fast.m` | 实时窗口使用的单 slot 快速分析（单 PSS 假设，仅均衡 slot 10） |
| `type1_read_initial_iq.m` | 用 `fopen/fread` 读取启动时保存的 20 ms IQ 并简要分析 |
| `type1_yunsdr_rx_mex.c` | 122.88 MS/s 四通道后台 pthread 环形缓冲采集 |
| `type1_build_rx_mex.m` | 编译 YunSDR 后台采集 MEX（链接 libyunsdr_ss.so） |
| `type1_selftest.m` | 不访问板卡的完整软件闭环（注入 CFO + AWGN，验证 BER/EVM） |
| `plot_type1_resources.py` | 生成英文帧结构和 DM-RS 资源网格图 |
| `data/` | 每次 RX 启动时保存的 raw122 和 virtual30 短 IQ 及离线分析脚本 |

## 4. 基本参数

| 参数 | 数值 |
|------|------|
| 中心频率 | 3.2 GHz |
| 标称带宽 | 20 MHz |
| 子载波间隔 | 30 kHz |
| RB 数 | 51 |
| 有效子载波 | 612 |
| FFT | 1024 |
| CP | normal CP，72/88 点 |
| TX 采样率 | 30.72 MS/s |
| RX 采样率 | 122.88 MS/s |
| slot | 0.5 ms，14 OFDM 符号 |
| frame | 10 ms，20 slot，280 OFDM 符号 |
| TX | 4 层、4 物理发射通道 |
| RX | 硬件采集 4 通道；分析通道数可由 `rxChannelSelect` 选择 |

## 5. 10 ms 帧结构

### 5.1 Slot 0：专用 SSB slot

Slot 0 不发送自定义数据：

- 符号 2～5 中央 240 个子载波放置标准 SS/PBCH block；
- 包含 PSS、SSS、PBCH、PBCH DM-RS 和可校验 MIB；
- SSB 从 TX1 发射，TX2～TX4 在该 slot 静默。

因此当前 slot 0 只有一根物理发射天线 TX1 工作，而且发送的是
同步/PBCH信号，不是四层 QPSK 有效载荷。

这一个 slot 为 RX 提供帧起点、PCI 和 PBCH/MIB 验证。

### 5.2 Slot 1～19：Type-A 数据 slot

每个数据 slot 都占用完整 51 RB：

| OFDM 符号，0 起始 | 内容 |
|-------------------|------|
| 0、1 | 四层不同 QPSK 数据 |
| 2 | 单符号 Type-1 四端口 DM-RS |
| 3～13 | 四层不同 QPSK 数据 |

因此每个数据 slot 严格包含 1 个 DM-RS 符号和 13 个数据符号。
符号 0 并未留空。DM-RS 位于符号 2，是 Mapping Type A 的
`dmrs-TypeA-Position=pos2`。

每层每 slot 的数据 RE 数：

$$
N_{\mathrm{data,slot,layer}}
=612\times13=7956.
$$

每层每帧共有：

$$
7956\times19=151164
$$

个 QPSK 数据 RE。

## 6. Type-1 FDM+CDM 四端口原理

MATLAB 端口 0～3 对应 3GPP DM-RS 端口 1000～1003。

| 3GPP 端口 | CDM group | 频移 $\Delta$ | 频域 OCC |
|-----------|-----------|---------------|----------|
| 1000 | 0 | 0 | $[+1,+1]$ |
| 1001 | 0 | 0 | $[+1,-1]$ |
| 1002 | 1 | 1 | $[+1,+1]$ |
| 1003 | 1 | 1 | $[+1,-1]$ |

Type-1 DM-RS 子载波位置满足：

$$
k=4n+2k'+\Delta,\qquad k'\in\{0,1\}.
$$

因此：

- CDM group 0 和 group 1 通过频率位置错开，即 FDM；
- 每个 group 内两个端口占用相同 RE，通过两芯片频域 OCC 分离；
- 单端口每 RB 有 6 个 DM-RS RE；
- 四端口整体看，两个 group 填满 12 个子载波，所以 DM-RS 符号
  是一整列块状资源，而不是旧版的自定义 `k mod 4` 导频。

接收端不是自行假设 OCC，而是调用：

```matlab
nrPDSCHDMRS
nrPDSCHDMRSIndices
nrChannelEstimate(..., 'CDMLengths', [2 1])
```

离线检查得到：

```text
CDM groups       = [0 0 1 1]
FrequencyWeights = [1  1  1  1
                    1 -1  1 -1]
```

## 7. 四层数据与卷积码

四层在同一个数据 RE 上发送不同 QPSK 符号，并使用单位预编码：

```text
Layer 1 / port 1000 -> TX1
Layer 2 / port 1001 -> TX2
Layer 3 / port 1002 -> TX3
Layer 4 / port 1003 -> TX4
```

每个 slot、每个 layer 单独编码：

- 7950 个信息 bit；
- 添加 6 个终止零 bit；
- 约束长度 $K=7$；
- 生成多项式 $[171_8,133_8]$；
- 编码后 15912 bit；
- 映射成 7956 个 QPSK 符号。

每个 slot 独立终止，可以立即计算该 slot 的 BER，不依赖下一帧。

## 8. 共享 MAT 文件

运行：

```matlab
type1_generate_reference
```

生成 `nr4_type1_reference.mat`，TX 和 RX 必须使用完全相同的文件。
当前文件约 9.27 MiB，包含：

- 完整配置和格式版本；
- MIB 和 BCH codeword；
- 四层、19 个 slot 的原始信息 bit；
- 卷积码 bit；
- QPSK 数据；
- 每 slot 的标准 DM-RS 符号和线性索引；
- 标准数据 RE 索引；
- 612×280×4 资源网格；
- 307200×4 的 10 ms 发射波形；
- OFDM CP 信息和卷积码 trellis。

TX 直接读取其中的四路波形；RX 读取同一文件完成已知比特 BER。

## 9. 接收算法

### 9.1 数字射频开关

四通道以 122.88 MS/s 连续采集。数字域依次保留：

```text
RX1: n mod 4 = 0
RX2: n mod 4 = 1
RX3: n mod 4 = 2
RX4: n mod 4 = 3
```

解交织后得到四路 30.72 MS/s 虚拟接收维度。

### 9.2 同步与频偏

1. PSS 求 10 ms 帧起点；
2. CP 与有效符号尾部相关，估计 $\pm15$ kHz 范围内的细频偏；
3. 时域补偿 CFO；
4. SSS 检查 PCI；
5. PBCH DM-RS估计、PBCH/Polar 解码和 MIB 比对。

CP 频偏估计：

$$
\hat f=
\frac{F_s}{2\pi N_{\mathrm{FFT}}}
\arg\left(
\sum_l\sum_n
y_l^*[n]y_l[n+N_{\mathrm{FFT}}]
\right).
$$

实测收发板残余 CFO 约为 265～293 Hz。未补偿时，单个前置
DM-RS无法跟踪 slot 内公共相位旋转，星座呈圆弧，EVM 达
35%～40%；补偿后 EVM 降到约 2%～3%。

### 9.3 四端口信道估计与均衡

每个数据 slot 独立调用标准 OCC 解扩，得到：

$$
\hat{\mathbf H}[k,l]\in\mathbb C^{N_{\rm RX}\times N_{\rm layer}}.
$$

随后逐数据 RE 使用 RZF：

$$
\hat{\mathbf x}=
\left(\hat{\mathbf H}^H\hat{\mathbf H}
+\lambda\mathbf I\right)^{-1}
\hat{\mathbf H}^H\mathbf y,
$$

其中：

$$
\lambda=10^{-3}\frac{\|\hat{\mathbf H}\|_F^2}{4}.
$$

默认 $N_{\rm RX}=N_{\rm layer}=4$，即 4×4 RZF。若运行时选择的
RX 通道数小于发射层数，矩阵欠定，程序不会输出数据 BER/EVM，也
不会绘制“看似正常”的均衡后星座。均衡前星座只取选中 RX 中第一路
的有效数据 RE，是四层混合；均衡后分别绘制端口 1000～1003 的数据。
PSS、SSS、PBCH、DM-RS和空 RE 均不进入数据星座图。

### 9.4 低时延实时显示路径

`type1_analyze.m` 会处理全部 19 个数据 slot，适合离线验证，但
一次分析约需 0.8～1.4 s。实时窗口改用 `type1_analyze_fast.m`：

- 只相关已知 PCI 对应的一个 PSS 序列；
- 仍执行 PSS、CFO、SSS、PBCH CRC 和 MIB；
- 每次只均衡代表性数据 slot 10，而不是全部 19 个 slot；
- BER 只表示当前 slot 10 的 7950 个信息 bit/层；
- 频谱 FFT 从 8192 点降为 2048 点；
- 星座每层最多绘制 500 点。

绘图前计算带内 $\lvert f\rvert\le8.5$ MHz 与保护带
$25\le\lvert f\rvert\le55$ MHz 的中位 PSD 差：

$$
M_{\rm presence}=
\operatorname{median}(S_{\rm inband})
-\operatorname{median}(S_{\rm guard}).
$$

当该指标低于 8 dB 时，程序只刷新噪声频谱并立即清空星座，不再
对归一化噪声强行执行 PSS/信道估计。完成一次分析后还会重新取得
最新 1 ms IQ；如果 TX 在分析期间关闭，旧星座不会被提交到图窗。

这解决了旧逻辑的两个滞后来源：

1. 旧代码先取得快照，再花约 1 s 处理，最后才显示这份旧数据；
2. `nrTimingEstimate` 对纯噪声也总能返回一个最大值，旧代码会把
   这个噪声峰误当成 PSS，进而画出假的星座。

## 10. MATLAB/YunSDR 工程适配要点

### 10.1 YunSDR 采集与缓存

RX 端通过 `type1_yunsdr_rx_mex.c` 启动一个后台 pthread，持续调用
YunSDR C API 读取 4 路 122.88 MS/s IQ，并写入 MATLAB 外部的环形
内存。前台 MATLAB 不直接阻塞读板卡，而是周期性执行：

```matlab
[raw122, timestamps, sequence] = type1_yunsdr_rx_mex('snapshot', blocks);
```

这样做的设计考量：

- 板卡高速采集与 MATLAB 绘图解耦，避免图形刷新阻塞 DMA；
- `sequence` 为软件环形缓冲接收的 block 总数；
- `timestamps` 来自 YunSDR 硬件时间戳，按 122.88 MS/s 推进；
- 厂商报告的硬件缓冲深度仅供参考，真正是否丢数需检查 timestamp
  连续性、overflow/count/timeout 事件和 `sequence` 增量。

每次停止时会读取：

```matlab
events = type1_yunsdr_rx_mex('events');
```

其中三列分别是 overflow、sample count、timeout。若 timestamp
出现跳变或 overflow 非零，说明 MATLAB/MEX/驱动链路没有及时消费
数据。

### 10.2 多接收天线接口

硬件 MEX 仍默认采集 4 路，DSP 层通过 `cfg.rxChannelSelect` 选择
参与分析的虚拟 RX 列：

```matlab
[~, virtualRF] = type1_digital_switch(raw122);
virtualRF = virtualRF(:, cfg.rxChannelSelect);
```

因此可以现场快速测试：

```bash
env TYPE1_RX_CHANNEL_SELECT=1,3 TYPE1_LIVE_VISIBLE=on ...
env TYPE1_N_RX_CHANNELS=2 TYPE1_LIVE_VISIBLE=off ...
```

选 4 路时完整执行 4 层 RZF、BER 和 EVM；选 1～3 路时只做频谱、
同步和 PBCH/MIB，数据均衡部分打印 `spatial_decode=0`。

### 10.3 实时绘图策略

实时窗口只画“有工程诊断价值”的少量数据：

- 频谱：最近 1 ms IQ，2048 点 Hann periodogram；
- 均衡前星座：只取选中第一路 RX 的有效数据 RE，不包含同步、
  PBCH、DM-RS 或空 RE；
- 均衡后星座：每层最多 500 点，避免 MATLAB scatter 成为瓶颈；
- `drawnow limitrate` 用于限制 GUI 刷新；
- 分析完成后再读最新 1 ms 频谱，如果 TX 已消失，则丢弃旧星座。

这套逻辑的目标是现场判断“频谱是否存在、同步是否稳、均衡是否
收敛”，不是完整离线后处理。完整 19 个数据 slot 的 BER 仍应使用
`type1_analyze.m` 或离线保存的 IQ 做复核。

## 11. 详细命令与排障

### 11.1 离线自检

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
/home/bupt/tools/matlab/bin/matlab -batch "type1_selftest"
```

自检额外注入 850 Hz CFO，并验证估计值、PBCH/MIB和四层 BER。

### 11.2 TX，cell-04

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
printf '1\n' | sudo -S -p '' \
  env TYPE1_TX_DURATION_SEC=60 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_tx"
```

不设置 `TYPE1_TX_DURATION_SEC` 时循环发射，直到人工停止。

`type1_tx.m` 必须保持为函数文件，不能改回脚本。设备句柄和
`onCleanup` 对象位于函数工作区，因此下列情况都会自动调用
`close_tx(device)`，先关闭循环发送，再释放设备：

- 到达 `TYPE1_TX_DURATION_SEC` 后正常返回；
- 在 MATLAB 内按 Stop 或 Ctrl+C；
- 初始化或状态循环中抛出 MATLAB 异常。

MATLAB 的 Pause 仅暂停执行，TX 继续发射，不触发清理。按 Stop 或 Ctrl+C
才会退出函数并执行清理。成功清理时终端打印：

```text
Type-A TX cleanup: cyclic disable ret=0; YunSDR device closed.
```

板卡的循环发送由硬件/驱动保持。MATLAB GUI 被关闭或进程被强制
终止后，不能仅凭“看不到 MATLAB 进程”断定射频已经停止；异常退出
时，板卡可能继续重复最后一次写入的波形。噪声测试前应在 TX 机器
显式执行：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
printf '1\n' | sudo -S -p '' \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_tx_stop"
```

成功时打印：

```text
YunSDR cyclic TX is explicitly disabled (ret=0).
```

检查 MATLAB 和板卡设备占用：

```bash
pgrep -a MATLAB
sudo fuser -v /dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_user
```

若要强制清理 MATLAB，应先正常停止 TX；不得把 `kill` 当作关闭
硬件循环发送的替代方法。

通过 SSH 在外层直接按 Ctrl+C 可能只会中断本地 `ssh` 客户端，而
没有把 MATLAB 中断送到远端进程。远程运行时应先进入 TX 主机的
交互式 shell，再启动 MATLAB 并在该 MATLAB 终端中停止；否则退出
后再运行一次 `type1_tx_stop`。

### 11.3 实时 RX，cell-08

首次部署编译 MEX：

```bash
printf '1\n' | sudo -S -p '' \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_build_rx_mex"
```

实时运行：

```bash
printf '1\n' | sudo -S -p '' \
  env TYPE1_LIVE_DURATION_SEC=10 \
      TYPE1_LIVE_UPDATE_SEC=0.1 \
      TYPE1_LIVE_VISIBLE=off \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_rx_live"
```

`TYPE1_LIVE_VISIBLE=on` 时显示实时窗口。

在 MATLAB 图形界面中，不要运行旧文件
`/home/bupt/tools/matlab_test/nr4x4/rx_nr4_live.m`。它对应“四个
PCI + 自定义梳状导频”版本，与本目录的单 PCI、标准 Type-1 DM-RS
TX 不兼容。GUI 命令窗口应执行：

```matlab
cd('/home/bupt/tools/matlab_test/nr4x4_type1')
addpath('/home/bupt/tools/matlab_test')
addpath(pwd)
clear functions
which type1_rx_live -all
which type1_analyze_fast -all
type1_rx_live
```

`which` 的第一项必须位于 `nr4x4_type1`。正确程序启动后首先打印：

```text
========== YunSDR Type-A live RX ==========
```

每次分析行以 `type1 t=` 开头，并包含 `presence`、`CFO`、
`PBCH_CRC_OK` 和 `MIB_match`。如果看到 `live t=`、
`PSS_peak[NID2 0/1/2]` 或 `SSS_rel_dB[PCI 0 1 2 3]`，说明误运行了
旧版 `rx_nr4_live.m`。

接收机始终会画出频谱曲线，因为热噪声、量化噪声和板卡本底也有
PSD；“存在频谱坐标和噪声曲线”不代表存在 OFDM 信号。实时程序用
20 MHz 带内与远端保护带的中位 PSD 差检测信号：

- 指标小于 8 dB：显示红色 `NO SIGNAL`，清空两幅星座，隐藏理想
  QPSK 参考叉号，并且不执行 PSS/SSS/PBCH、信道估计和均衡；
- 指标大于等于 8 dB：才执行完整同步与快速数据 slot 分析；
- 分析结束前再读取最新 1 ms，若 TX 已消失，则丢弃刚计算出的旧
  星座，防止 MATLAB 绘图延迟造成“关 TX 后仍在画”的假象。

## 12. 帧结构与时频资源图

运行：

```bash
python3 plot_type1_resources.py
```

生成：

- `type1_frame_structure.png`：20-slot 帧结构、SSB slot、Type-A
  数据 slot 和完整收发流程；
- `type1_dmrs_resource_grid.png`：单 RB 的 12×14 RE 网格、端口/CDM
  组、OCC 表和资源数量。

图片只使用英文字符，避免 Python/Matplotlib 中文字体缺失。

## 13. 2026-07-06 实机结果

cell-04 TX → cell-08 RX，8 秒测试：

| 项目 | 结果 |
|------|------|
| PSS | NID2=0 正确 |
| SSS 归一化指标 | 约 0.98～0.995 |
| PBCH CRC | 每次通过 |
| MIB | 每次逐比特匹配 |
| CFO | 约 +265～+293 Hz |
| CP 相关质量 | 0.993～0.998 |
| 编码 bit BER | 0 或约 $3.31\times10^{-6}$ |
| Viterbi 后信息 BER | 四层全部为 0 |
| 均衡后中位 EVM | 约 1.9%～3.1% |
| $\kappa(H)$ 中位/95%/最大 | 约 4.7 / 5.0 / 5.0 |
| timestamp 缺口 | 0 |
| RX overflow/timeout | 全部为 0 |
| TX underflow | 全部为 0 |

结果目录：

```text
/home/bupt/tools/matlab_test/nr4x4_type1/captures/type1_live_20260706_113133
```

该结果说明：单符号标准 Type-1 FDM+CDM 可以在当前 4T4R 板卡上
实时完成四端口估计和四层数据分离，但必须先处理独立板卡之间的
残余 CFO。对于高速移动或快速时变信道，单符号 DM-RS仍可能不足，
届时应使用 additional DM-RS 或 PT-RS，而不是在接收端用已知数据
掩盖信道变化。

### 13.1 快速绘图与 TX 关闭测试

让 TX 自动停止、RX 继续运行的 20 s 测试结果：

| 状态 | 实测结果 |
|------|----------|
| TX 存在 | 带内/保护带指标约 56～62 dB |
| 快速分析 | 预热后约 166～266 ms，中位数约 200 ms |
| 有信号图形刷新 | 约 2.5 次/s |
| TX 关闭发生在分析中 | 当前旧星座被抑制，没有提交到图窗 |
| TX 关闭后 | 指标约 2.4～3.9 dB，星座立即清空 |
| 无信号频谱刷新 | 约 5.6 次/s |
| timestamp/overflow/timeout | 全部为 0 |

测试目录：

```text
/home/bupt/tools/matlab_test/nr4x4_type1/captures/type1_live_20260706_163748
```

### 13.2 “未启动 TX 仍出现 OFDM/星座”的排查结论

2026-07-06 在 cell-04 发现 root 用户的 MATLAB GUI 进程仍持有：

```text
/dev/xdma0_c2h_0
/dev/xdma0_h2c_0
/dev/xdma0_user
```

因此当时并非真正的“无发射”状态，而是板卡仍在循环发射先前写入
的 Type-A 波形。执行 `type1_tx_stop`，返回 `ret=0` 并确认设备不再
被进程持有后，在 cell-08 单独运行 RX 5 秒，结果为：

- 信号存在指标约 2.8～3.9 dB，始终低于 8 dB 门限；
- 每次刷新均打印 `NO SIGNAL, constellation cleared`；
- 没有进入 PSS、PBCH、DM-RS 或 RZF 均衡；
- timestamp 缺口为 0，overflow/count/timeout 全部为 0。

结果目录：

```text
/home/bupt/tools/matlab_test/nr4x4_type1/captures/type1_live_20260706_170153
```

另用纯复高斯噪声直接测试分析器时，PBCH CRC 和 MIB 均失败，四层
编码 BER 约为 0.5、信息 BER 约为 0.5、EVM 大于 700%。这说明均衡
器不会把无结构噪声变成可正确解码的 QPSK；此前看到的有效星座来
自未关闭的硬件循环发射，而非噪声被“强制拟合”为 QPSK。

### 13.3 自动清理修改后的链路复测

将 `type1_tx.m` 改为函数入口后，cell-04 TX → cell-08 RX 的 12 秒
复测结果：

| 项目 | 结果 |
|------|------|
| 信号存在指标 | 约 60.7～61.6 dB |
| PSS 峰值/中位数 | 约 15.0～15.1 dB |
| SSS 指标 | 约 0.983～0.995 |
| PBCH CRC / MIB | 每次通过 / 每次匹配 |
| 四层 coded BER | 全部为 0 |
| 四层 Viterbi 后 BER | 全部为 0 |
| EVM | 约 1.8%～4.6% |
| timestamp/overflow/timeout | 全部为 0 |

结果目录：

```text
/home/bupt/tools/matlab_test/nr4x4_type1/captures/type1_live_20260706_183351
```

均衡前图取的是 RX1 上四层信号的叠加：

$$
y_1=h_{11}x_1+h_{12}x_2+h_{13}x_3+h_{14}x_4+n_1,
$$

它本来就不是四点 QPSK，呈现云团是正确现象。右侧均衡后才是分离
出的四层 QPSK；本次实测四个点簇清晰，且 BER 为 0。

### 13.4 GUI 误运行旧接收机的典型表现

若 Type-1 TX 正在发射，却运行旧 `nr4x4/rx_nr4_live.m`，旧接收机
仍可能通过 TX1 上的 PCI 0 SSB 找到一个相关峰，但它随后会用旧的
四小区数据位置和自定义梳状导频估计当前 Type-1 四端口信号。两套
资源网格不一致，典型结果是：

- coded BER 和 info BER 都约为 0.5；
- EVM 约为 250%；
- `cond(H)` 很大且最大值可达数百；
- 输出前缀为 `live t=`，并枚举三个 NID2 和四个 PCI。

这不是射频链路突然失效，也不是 Type-1 DM-RS 解码器的输出；它是
旧接收机解释新帧结构产生的必然结果。
