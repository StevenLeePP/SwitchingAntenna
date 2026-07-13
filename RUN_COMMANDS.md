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
