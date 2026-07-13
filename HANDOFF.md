# 交接文档：Type-A 4T4R C/MEX 实时接收系统

更新时间：2026-07-13（Asia/Shanghai）

本文记录当前已经实现、部署和测试过的状态；不包含后续研发计划。新会话应先读
本文与 `README.md`，再改动工程。

## 1. 工程、分支与远端

本地工程：

```text
/root/lap/SwitchingAntenna/c_demo
```

Git 分支为 `cmex`，远端为 `origin`（`git@github.com:StevenLeePP/SwitchingAntenna.git`）。
最近提交为：

```text
6fcdf2a feat: add staged startup discard and continuous constellation
```

远端工程目录（TX/RX 相同）：

```text
/home/bupt/tools/matlab_test/nr4x4_type1
```

| 角色 | 主机 | 备注 |
|---|---|---|
| TX | `bupt@10.156.64.30`（cell-04） | 连接发射板卡 |
| RX | `bupt@10.156.64.41`（cell-08） | 连接接收板卡；从当前环境经 TX 跳板访问 |

MATLAB 路径：`/home/bupt/tools/matlab/bin/matlab`。

RX/TX 板卡设备需要 root 权限访问。已授权的测试方式是以 `sudo` 启动 MATLAB；
root 操作仅限板卡编译/收发测试，测试结束应确认 TX 输出：

```text
Type-A TX cleanup: cyclic disable ret=0; YunSDR device closed.
```

RX 连接示例：

```bash
ssh -o 'ProxyCommand=ssh -W %h:%p bupt@10.156.64.30' bupt@10.156.64.41
```

## 2. 当前波形

- 30 kHz SCS、51 RB、NFFT=1024；TX 30.72 MS/s，RX 122.88 MS/s；
- 10 ms NR 帧、20 个 slot、4 TX layer / 4 DM-RS port / 4 RX；
- Type-A Type-1 单符号 DM-RS，`l=2`；数据 RE 使用 QPSK、默认无编码；
- slot 0 为 PSS/SSB/PBCH；默认 half 模式中 slot `1:10` 为有效载荷，
  slot `11:19` 静默；
- 唯一 BER 真值为共享的 `nr4_type1_reference.mat`，TX/RX 必须一致。

`TYPE1_PAYLOAD_SLOT_MODE=half` 是当前默认。修改 payload mode 后必须重新生成
reference 并同步至两台机器。

## 3. 当前实时架构

```text
YunSDR 4 路 RX (122.88 MS/s)
  -> type1_yunsdr_rx_mex.c pthread / native int16 ring
  -> MATLAB 低频控制面：PSS Acquire/Track、窄窗健康检查、CFO/时间校正
  -> direct consumer：四相抽取、CFO、固定 C FFT、持久 maps、C PHY
  -> type1_decode_frame_grid_mex：Type-1 DM-RS、4x4 RZF、QPSK 判决、BER
  -> MAT 结果：BER、时延、pending、dropNew、事件与 timestamp/sequence 审计
```

`type1_yunsdr_rx_mex.c` 已实现：

- 4 路 DMA 背景读取、原始 IQ ring、producer/consumer sequence；
- 1 ms raw-DMA-block 队列计数、`dropNew`、high-water；
- persistent DM-RS/data/QPSK/coded-bit reference maps；
- native-ring 四相抽取、CFO、154 symbol × 4 路固定 radix-2 1024 FFT；
- `directstart/directpoll/directstatus/directstop` 持久消费者；
- `directsetcfo/directsettiming` 低频同步控制；
- `directflush`、`directlatesttimestamp` 和 `directaudit` 启动/时间审计。
- `switchphase [0..3]` 固定 virtual-to-physical RX 循环映射；运行配置为
  `cfg.switchPhaseOffset`（默认 0），所有 virtual snapshot/FIFO/direct 路径一致。

`type1_decode_frame_grid_mex.c` 承担 Type-1 DM-RS、4×4 RZF、硬判决、EVM 与
BER 累积。C direct consumer 内部通过 MEX API 调用该 C frame-PHY 内核；栅格在
两个 MEX 内核间仍以内部 `mxArray` 传递。

## 4. 已验证的数值一致性

`type1_compare_direct_stages.m` 在同一 PSS 锁定 OTA 帧上的结果：

| 路径 | raw bit errors | 平均 EVM |
|---|---:|---:|
| 标准 MATLAB `type1_analyze` | 0 | 1.925% |
| MATLAB 默认 OFDM + C PHY | 0 | 2.111% |
| MATLAB CP-end OFDM + C PHY | 0 | 2.377% |
| native-ring C FFT + C PHY | 0 | 2.377% |

native-ring 相对 MATLAB CP-end 的 grid NMSE 为 `-115.63 dB`，H NMSE 为
`-115.91 dB`，单帧 raw errors 一致。C FFT 与 C PHY 在正确时间对齐下未引入
可观察误码。

已固定的关键实现细节：

- 四相天线选择使用相对 DMA 起点的相位，不能对绝对 timestamp 直接 `% 4`；
- 当前 C OFDM 使用 CP-end 窗口；简单 CP 中点不能等价 MATLAB 默认窗口；
- CFO 在每个 10 ms active frame 内跨 slot 连续；各虚拟 RX 的 8.138 ns 固定时偏
  作为每 RX 常相位由 DM-RS H 吸收；frame-PHY 的第 3 输出为实际 DM-RS 残差噪声方差；
- `type1_decode_frame_grid_mex.c` 内插必须避免 `mwSize k-1` 的无符号下溢；
- `directsettiming` 跨 DMA block 时会归一化 ring origin，并写入审计记录。

## 5. 两阶段启动、队列与审计

`type1_rx_direct.m` 默认 `TYPE1_DIRECT_STARTUP_MODE=two_stage`：

1. MATLAB 在 20 ms virtual snapshot 上粗 PSS 锁定；
2. `directflush` 丢弃已进入软件 ring 的冷启动数据；
3. 窄窗 PSS 跟踪、C persistent map 建立、DMA 生产速率观察；
4. 再次 `directflush`，选择 PSS 对齐且有效半帧已完整到达的启动点；
5. 启动 native direct consumer，并从 x=0 保存 `pendingTrace`。

`summary.startupDiscardBlocks`、`startupDiscardCoarseBlocks`、
`startupDiscardPreStartBlocks` 与 `startupTimestampAudit` 记录上述切换。

`pending` 的单位为 1 ms raw DMA block，因此数值可近似按 ms 解读。`dropNew=0`
表示软件 FIFO 没有因满而拒收新块；它不等同于 pending 为零。

已保存的 60 s 基线（旧 517 ms 启动版本）：

```text
captures/type1_direct_20260713_155645/type1_direct_results.mat
```

| 项目 | 实测 |
|---|---:|
| 已解码帧数 | 6041 |
| `dropNew` | 0 |
| 最终/峰值 pending | 10 / 517 block |
| `extractMs` / `fftMs` / `phyMs` / `totalMs` | 2.142 / 5.141 / 1.943 / 9.380 ms |
| 各层 BER | `[1.66e-8, 3.02e-8, 1.04e-9, 1.98e-8]` |
| timestamp 审计 | 116 条，overflow=0，invariant=1 |

当前两阶段 10 s OTA 启动测试：

```text
captures/type1_direct_20260713_171338/type1_direct_results.mat
```

| 项目 | 单阶段历史对比 | 当前两阶段 |
|---|---:|---:|
| x=0 pending | 约 482 block | 84 block |
| 峰值 pending | 约 558 block | 约 103 block |
| 稳态/最终 pending | 10 s 后约 214 block | 约 20 / 15 block |
| `dropNew` | 0 | 0 |

`directflush` 只清空已进入 MEX 软件 ring 的块。启动时可能仍观察到 timestamp
已接近当前帧而 producer sequence 领先几十个 block：这是 YunSDR/驱动 DMA
描述符尚未入软件 ring 后被后台线程批量读入的积压，不是软件 flush 未执行。

`type1_plot_pending_compare.m` 从两个结果 MAT 中离线画出 `pendingTrace`；
最近生成的本地比较图为 `pending_startup_20260713_171338.png`。

## 6. 实时可视化

`type1_rx_live.m` 是 latest-snapshot 图形监视器，不用于验证顺序连续 BER。

- 星座图固定显示 QPSK 理想点和 `[-2,2]` 坐标轴；
- 始终绘制已均衡 data RE，最多 500 点/层，按低频 cadence 刷新；
- 虚拟 IQ 信号门限判为无信号时不再清空散点，也不再显示 `NO SIGNAL`；
  无信号/切换阶段的均衡噪声云会直接显示；
- 该门限仍控制 BER/覆盖率有效性，样本标记为 `no-signal-fast-gate`，不计为
  `decoded`。

## 7. 关键文件与常用命令

| 文件 | 当前用途 |
|---|---|
| `type1_tx.m` | 循环发射共享 reference 的 10 ms 波形，退出时关闭 cyclic TX。 |
| `type1_rx_direct.m` | 两阶段启动的无图形 direct consumer，保存 `type1_direct_results.mat`。 |
| `type1_rx_live.m` | 图形监视器与连续均衡星座图。 |
| `type1_yunsdr_rx_mex.c` | YunSDR/ring/direct consumer/启动审计 MEX。 |
| `type1_decode_frame_grid_mex.c` | C DM-RS/RZF/QPSK/BER 内核。 |
| `type1_validate_native_ring_grid.m` | native C grid 与 MATLAB CP-end grid 对照。 |
| `type1_compare_direct_stages.m` | MATLAB/C PHY/native ring 分阶段数值对照。 |
| `type1_plot_pending_compare.m` | 两个 pending 结果的离线对比图。 |

RX 编译：

```bash
cd /home/bupt/tools/matlab_test/nr4x4_type1
/home/bupt/tools/matlab/bin/matlab -batch "type1_build_rx_mex"
```

60 s direct RX：

```bash
TYPE1_DIRECT_DURATION_SEC=60 TYPE1_FIFO_RING_BLOCKS=2048 \
  /home/bupt/tools/matlab/bin/matlab -batch "type1_rx_direct"
```

所有 direct 结果保存为：

```text
captures/type1_direct_YYYYMMDD_HHMMSS/type1_direct_results.mat
```

## 8. 提交记录维护规则

每次代码修改并提交时，必须同步在 `README.md` 的“提交变更记录”追加一行，
格式为“版本 -- 主要变更”。当前记录：

```text
cmex-2026.07.13.2 -- frame-PHY 噪声输出、帧内连续 CFO/DM-RS 吸收虚拟 RX 时偏、固定可校准 switch-phase 映射；OTA grid/H/EVM/bit 等价通过。
```
