# 交接文档：4T4R Type-A DM-RS 连续实时接收实验

更新时间：2026-07-13（Asia/Shanghai）

本文写给没有任何此前上下文的新会话。先读本文，再改代码。

## 1. 当前任务

项目是一个 YunSDR 4T4R 试验系统，用于验证：发射端四个空间层/信号源
同时发射不同的 QPSK 数据；接收端从四路 122.88 MS/s 原始 IQ 通过数字
四相轮询/抽取恢复四路 30.72 MS/s 虚拟接收流，再进行同步、Type-1 DM-RS
信道估计、4x4 MIMO/RZF 分离、BER、SNR 和 `cond(H)` 评估。

最终目标不是“偶尔看到正确 BER”，而是：

1. 连续处理每个有效数据 slot，不能用 latest snapshot 跳过中间帧；
2. FIFO 不溢出，即 `dropNew=0`，队列深度不随时间持续上升；
3. 保持现有通信逻辑和结果一致：PSS/时序、CFO、DM-RS、RZF、QPSK
   硬判决、BER 的语义不能因加速而改变；
4. 最终至少运行 60 秒，记录处理时延、FIFO 深度、BER、内存/RSS、硬件
   overflow/timeout。

当前用户决定让下一窗口完成“将跨 MATLAB/MEX 的 IQ 搬运及解调进一步
下沉到 C/MEX 持久消费者”的实现。

## 2. 目录与远端环境

本地工作目录：

```text
/root/lap/SwitchingAntenna/demo
```

远端工程目录（TX 和 RX 相同）：

```text
/home/bupt/tools/matlab_test/nr4x4_type1
```

机器角色：

| 角色 | 主机 | 备注 |
|---|---|---|
| TX | `bupt@10.156.64.30`（cell-04） | 只有 TX 端口接天线 |
| RX | `bupt@10.156.64.41`（cell-08） | 只有 RX 端口接天线 |
| 跳板 | `.30` | 本环境到 `.41` 需经 `.30` 的 ProxyCommand |

MATLAB：

```text
/home/bupt/tools/matlab/bin/matlab
```

此前用户明确授权：当前只有其本人使用板卡；若存在残留 MATLAB 进程，可
终止它。TX 已改为函数且有 `onCleanup`，正常结束、Ctrl+C 或异常会关闭
循环发射。测试后应确认没有残留 MATLAB，并确认 TX 日志有：

```text
Type-A TX cleanup: cyclic disable ret=0; YunSDR device closed.
```

常用连接形式（密码不要写入源码或文档）：

```bash
# TX
ssh bupt@10.156.64.30

# RX（通过 TX 跳板）
ssh -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
```

远端同步通常须把修改后的 `.m`、`.c` 同步到两端；RX 端改变 MEX C 源后
必须重编译。

## 3. 当前波形与帧结构

关键配置在 `type1_config.m`。

- 30 kHz SCS、51 RB、NFFT=1024、30.72 MS/s TX；
- RX 物理采样率 122.88 MS/s；
- 10 ms 一帧，20 个 slot，每 slot 14 个 OFDM 符号；
- 4 TX 层、4 DM-RS port、4 RX 通道；
- 标准 Type-A、Type-1、单符号 DM-RS，位于 `l=2`；
- 数据符号是 `[0 1 3:13]`，QPSK，默认无信道编码；
- slot 0 保留单个标准 SSB/PBCH（仅 TX1）；
- **当前默认半帧模式**：slot `1:10` 为十个有效数据 slot；slot `11:19`
  完全置零，不映射 DM-RS 或数据，也不解码；
- `TYPE1_PAYLOAD_SLOT_MODE=full` 可暂时恢复 `1:19`，但必须重新生成并
  将共享 MAT 文件同步到 TX/RX；
- `TYPE1_PAYLOAD_SLOT_MODE=half` 是当前默认/目标模式。

共享参考文件：`nr4_type1_reference.mat`。它包含 TX waveform、每个 slot
的 DM-RS index/symbol、数据 index、QPSK reference、原始 bits。它是 BER
比对的唯一真值来源，TX 和 RX 必须严格相同。

TX 端保留了一份测试前满载参考备份：

```text
/home/bupt/tools/matlab_test/nr4x4_type1/nr4_type1_reference_full_backup_20260712.mat
```

重新生成半帧无编码参考：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
TYPE1_PAYLOAD_SLOT_MODE=half \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_generate_reference('none')"
```

生成后复制 `nr4_type1_reference.mat` 到另一台机器。不要只改 RX 或只改 TX。

## 4. 已完成的功能

### 4.1 同步与控制面

`type1_analyze_fast.m` 已从“每次全窗口 PSS”改成状态机：

- Acquire：启动或失锁时，20 ms 窗口 `nrTimingEstimate` 全量 PSS；
- Track：根据硬件 raw timestamp 预测帧位置；
- 每 `cfg.fastPSSCheckIntervalFrames=50` 帧仅在预测位置 `±512` virtual
  samples 局部 PSS；
- CFO 低频更新，通常每 50 帧；
- PBCH/MIB 快路径默认关闭；SSS/PSS 健康检查低频执行。

注意：PSS/同步逻辑的现有正确性基线来自 MATLAB 5G Toolbox。若 C 化 PSS，
请先保留/对照它，而不是直接替换后假定正确。

### 4.2 已有 C/MEX 加速器

| 文件 | 功能 |
|---|---|
| `type1_yunsdr_rx_mex.c` | YunSDR 后台 pthread、4 路原始 IQ ring、C 侧四相虚拟接收、FIFO 命令 |
| `type1_dmrs_type1_mex.c` | 固定 4 port Type-1 单符号 DM-RS OCC 解扩与频域插值 |
| `type1_rzf_qpsk_mex.c` | 固定 4x4 RZF、QPSK 硬判决、EVM、bit error |
| `type1_decode_frame_grid_mex.c` | 已解调频域网格上的多 slot DM-RS/RZF/BER 批量 C kernel |

现有构建脚本：

```matlab
type1_build_rx_mex
type1_build_dmrs_mex
type1_build_decode_mex
type1_build_frame_mex
```

`type1_decode_frame_grid_mex.c` 曾有一个非常隐蔽但严重的 bug：对
`mwSize k` 做 `k-1` 会无符号下溢；port 2/3 的子载波 0 被错误插值，造成
H NMSE 约 -27 dB、EVM 恶化和少量 BER。正确写法必须先转浮点：

```c
.5f * ((float)k - 1.f)
```

不要改回 `.5f*(k-1)`。

### 4.3 帧级批量数据面

文件：

- `type1_decode_frame_batch.m`
- `type1_decode_frame_grid_mex.c`
- `type1_validate_frame_batch.m`
- `type1_profile_frame_batch.m`

当前半帧数据面只对 slot 0:10（5.5 ms，154 OFDM symbols）做
`nrOFDMDemodulate`；slot 11:19 不进行 FFT。随后一次调用 frame-grid MEX
处理所有十个数据 slot。

验证命令（RX 有保存的 `data/*_virtual30_csingle_iq4.bin` 时）：

```bash
/home/bupt/tools/matlab/bin/matlab -batch \
  "type1_build_frame_mex; type1_validate_frame_batch; type1_profile_frame_batch"
```

最近离线验证结论：

- 十个 slot × 四层的硬判决 error 矩阵逐元素一致；
- 首 slot H NMSE 为约 `-141.46 dB`；
- EVM 会有约 1～2 个百分点差异（整段与逐 slot OFDM 解调的相位参考差），
  但 BER 不变；
- 半帧离线数据面中位约 `8.85 ms/10 ms`；近期 OTA batch 中位约 `7.51 ms`。

**逻辑一致性验收的最低要求**：`isequal(old.rawBitErrors,
new.rawBitErrors)`。如果准备替换 C kernel，必须同时对 H NMSE、EVM、BER
逐层比对；不要只看星座图“看上去像 QPSK”。

### 4.4 FIFO 连续 BER 框架

文件：`type1_rx_fifo.m`。

它与 `type1_rx_live.m`（最新快照/图形监视器）不同：FIFO 模式按顺序消费，
一旦 `dropNew>0` 或 timestamp gap，连续 BER 结果立即标记为 **INVALID**。

当前已做的优化：

- `fifostart` 后 C ring 以“保护未读、满则丢新数据”运行；
- `dequeuevirtual` 每次默认取 10 个 1 ms block；
- MATLAB 侧 `streamIQ` 改为固定预分配 buffer，避免 `[streamIQ; block]`
  的持续扩容；
- 后半帧 slot 11:19 不进入 `type1_decode_frame_batch`；
- SNR/`cond(H)` 每约 1 s 做一次，不在每帧热路径执行；
- 打印 `pending/high/dropNew/dequeue/decode/CFO/OFDM/PHY`；
- 保存 `frameBatchMs`、`dequeueMs`、FIFO 状态到结果 MAT。

可配置环境变量：

```text
TYPE1_FIFO_DURATION_SEC       # 运行秒数
TYPE1_FIFO_RING_BLOCKS        # 软件 FIFO 容量，单位 1 ms；测试常用 2048
TYPE1_FIFO_DEQUEUE_BLOCKS     # 每次 C->MATLAB 出队的 1ms block 数；默认 10
```

运行：

```bash
TYPE1_FIFO_RING_BLOCKS=2048 TYPE1_FIFO_DEQUEUE_BLOCKS=10 \
TYPE1_FIFO_DURATION_SEC=60 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_rx_fifo"
```

## 5. 最近真实 OTA 结果与当前瓶颈

最近一次有效信号测试结果目录：

```text
/home/bupt/tools/matlab_test/nr4x4_type1/captures/type1_fifo_20260712_230550
```

运行条件：half mode、10 payload slots、FIFO=2048 ms、每次 dequeue=10 ms。

观察到：

| 项 | 结果 |
|---|---:|
| batch decode median / P95 / max | 7.51 / 10.43 / 17.04 ms |
| C dequeue median / P95 / max | 1.20 / 1.33 / 2.44 ms |
| 可靠锁定期间 BER | 四层基本 0（末尾 TX 停止后不应计入） |
| `cond(H)` 中位 | 约 4.5 |
| 有效吞吐 | 约 85–90 frame/s，而输入为 100 frame/s |
| FIFO | `pending` 约从 0.59 s 持续升至 1.8 s；最终 `dropNew>0` |

因此：**纯 PHY batch 已低于 10 ms，但整体 MATLAB 前台流水仍不能连续实时。**
剩余差额来自：

1. C ring 复制 virtual IQ 到 MATLAB mxArray；
2. MATLAB/MEX 调用边界；
3. MATLAB 侧 frame assembly、slice、调度；
4. 低频 PSS/CFO/诊断的偶发抖动。

增加 FIFO 容量不是实时解决方案，只会推迟 `dropNew`。将吞吐结果写成“实时”
的前提必须是：60 秒内 `dropNew=0`，且 pending 没有正斜率。

## 6. 下一步：应实现的 C/MEX 持久消费者

不要继续只微调 MATLAB。建议在 `type1_yunsdr_rx_mex.c` 中实现一个新命令族，
例如：

```text
directsetup(reference/maps/config)
directstart(frame_raw_timestamp, cfo, sync state)
directpoll(max_frames) -> per-frame statistics only
directstatus
directstop
```

目标数据路径：

```text
YunSDR RX pthread → native int16 ring
  → C persistent consumer
     → 四相抽取（直接从 ring，不创建 MATLAB IQ 大数组）
     → 保留 slot 0:10、跳过 slot 11:19
     → 1024-point OFDM FFT
     → Type-1 DM-RS / 4x4 RZF / QPSK hard decision
     → 累积 BER、EVM、时延、队列深度
  → MATLAB 每 0.5~1s 读取小型统计量、少量星座抽样和频谱
```

### 6.1 必须保留的控制面

- 初次 Acquire PSS 可以继续由 MATLAB `type1_analyze_fast` / 5G Toolbox
  完成；它不在每帧热路径；
- C consumer 应接收锁定后的 frame raw timestamp 与 CFO；
- 每 50 帧做 PSS health check。第一版可仍交给 MATLAB，但该检查不能把
  每帧 IQ 搬回 MATLAB；建议 C side 保留小型 PSS 窗口或提供按 timestamp
  的 1 ms 窗口；
- 一旦 PSS health 或 BER/信号存在性显示失锁，停止累积连续 BER，回到
  Acquire；绝不能继续对错位帧计算 BER。

### 6.2 C FFT 的实现建议

- 没有确认系统安装 FFTW；不要假设可链接 FFTW；
- MATLAB `nrOFDMDemodulate` 已是优化 C 实现，因此“把完全相同的全帧
  FFT 翻译为 C”不保证快；真正收益来自 **不搬运 IQ、只 FFT 154 个必要
  OFDM symbol、持久缓存映射/工作区**；
- 可实现固定 NFFT=1024 的 radix-2 iterative complex FFT，预计算 bit
  reversal 和 twiddle，避免每 symbol 分配内存；
- 必须复现当前 OFDM 的：CP 长度模式、FFT shift、612 active SC 选择、
  缩放、slot/符号位置。先离线与 `nrOFDMDemodulate` 比较 grid NMSE；
- 先用保存 IQ 逐帧验证；通过后再接 SDR。

### 6.3 建议的分阶段验收

1. **离线 C OFDM 单元测试**：以保存 virtual30 IQ 与 MATLAB grid 比较；
2. **离线整帧比对**：相同 `timingOffset`、CFO、reference MAT，比较
   H、EVM、raw bit errors；
3. **ring direct consumer 但无 OTA**：从 ring 注入/保存 IQ，检查 C
   consumer 不泄漏、timestamp 单调；
4. **OTA 10 秒**：`dropNew=0`、BER 合理、pending 无单调增长；
5. **OTA 60 秒**：记录 median/P95/max、RSS、overflow/timeout、队列斜率。

## 7. 绝对不要再踩的坑

1. **不要把“显示正确”当作连续实时。** `type1_rx_live.m` 使用 latest
   snapshot，允许跳过历史数据；只有 `type1_rx_fifo.m` 的顺序消费者能
   验证全部数据。
2. **不要只看 BER=0。** 如果 `dropNew>0`，连续 BER 结论必为 INVALID；
   队列深度持续上升也表示迟早失效。
3. **不要用大 FIFO 伪装实时。** 它只延后溢出。
4. **不要让 TX/RX reference MAT 不一致。** 改 `dataSlots`、编码、PCI、
   payload 后，必须重新生成并同步 MAT。
5. **不要启用 full mode 却沿用 half MAT，或相反。** 当前默认是 half。
6. **不要在每帧做全量 PSS、PBCH 或 SNR/cond(H)。** PSS 应 Acquire/Track；
   PBCH 快路径关闭；SNR/cond(H) 低频诊断。
7. **不要在热路径用 `[streamIQ; block]`。** 这会反复分配/复制；当前
   FIFO 已改为预分配 buffer。
8. **不要在未锁定或 TX 已关闭时把噪声 BER 纳入结果。** 噪声会产生约 0.5
   BER；错误 PSS 可能出现看似有结构的星座。TX 停止后必须清空/失锁。
9. **不要再次引入 `mwSize` 无符号下溢。** 特别是 Type-1 port 2/3 的
   `k-1` 插值表达式，见第 4.2 节。
10. **不要假设 slot 0 是数据。** slot 0 是 SSB/PBCH；当前 data slots 是
    1:10。
11. **不要在 C ring 满时覆盖未读数据却不报告。** 当前策略是保护未读、
    丢新并递增 `dropNew`；这一语义是 BER 可信度的基础。
12. **不要在 RX 程序运行期间同时启动多个 MATLAB/多个 FIFO consumer。**
    `g_consumer_sequence` 是单消费者设计。
13. **不要遗留循环 TX。** 结束后检查 TX cleanup；需要时运行
    `type1_tx_stop.m`。

## 8. 有用的命令和文件

| 目的 | 文件/命令 |
|---|---|
| TX | `type1_tx.m` |
| 强制停止 TX | `type1_tx_stop.m` |
| 最新画面/图形监视 | `type1_rx_live.m` |
| 顺序 FIFO 连续 BER | `type1_rx_fifo.m` |
| 单 slot 快速分析/同步 | `type1_analyze_fast.m` |
| 帧级 batch wrapper | `type1_decode_frame_batch.m` |
| 帧级 C PHY | `type1_decode_frame_grid_mex.c` |
| SDR ring MEX | `type1_yunsdr_rx_mex.c` |
| 一致性验证 | `type1_validate_frame_batch.m` |
| 时延 profile | `type1_profile_frame_batch.m` |
| 人类可读技术说明 | `README.md` |

## 9. 当前远端状态

截至本文更新：

- 两台远端均已同步半帧配置、FIFO 脚本、帧级 MEX 相关源码；
- RX 已编译 `type1_decode_frame_grid_mex.mexa64`；
- 之前用于测试的 TX 采用有限时长，日志显示自动 cleanup；
- 最近检查时没有残留 MATLAB TX/RX 进程；
- 不要假定此状态长期有效；开始前先 `pgrep -af matlab` 并确认共享 MAT
  的 `package.cfg.dataSlots` 为 `1:10`。

最重要的一句话：**现在的问题不是无线链路 BER，而是 100 frame/s 的端到端
软件流水吞吐；任何新实现都必须以 FIFO 连续性和逐帧等价性证明自己。**
