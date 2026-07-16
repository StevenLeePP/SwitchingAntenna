# Phase 3 R22 能效模型与公平比较口径

本文档冻结 R22 Part C 的功耗、吞吐量与端口扫描记账方法。它的用途是让审稿人能够从
组件参数逐项重算 `bits/Joule`，不是给尚未制造的单 RF 链开关板提供实测功耗声明。

## 1. 比较对象与共同系统条件

五种接收前端在相同的 4 个用户流、51 RB、18.36 MHz 占用带宽、30.72 MS/s 每数字输入、
同一批 50 个 TDL-A 信道及噪声 realization 上比较：

| 名称 | 模型含义 | RF/数字链与模拟网络 |
|---|---|---|
| ProposedD1 | 本文 `Dmax=1` 单链码域端口选择 | 1 个 RFIC，N 路等效数字输入，M 个开关 |
| GreenMOLike | 在本文调度上局部增加 many-to-many membership | 与 ProposedD1 相同的电路包络 |
| DBF | 每个物理端口完整数字化 | M 个 RFIC，M 路 ADC/数字输入 |
| PC-HBF | 部分连接混合波束成形 | N 个 RFIC，M 个有源移相器 |
| FC-HBF | 全连接混合波束成形 | N 个 RFIC，M×N 个有源移相器 |

`GreenMOLike` 不是 GreenMO 论文算法或原型实验的逐位复现；HBF 组合器也是理想、未量化、
无插损的参考上界。它们用于统一信道上的体系结构对照，不能改写成实物性能排名。

## 2. 同一张组件表

| 组件 | 标称参数 | 计数规则 | 来源与限制 |
|---|---:|---|---|
| 单链 RFIC，含 PLL/LO | 354 mW | Proposed/GreenMO-like 各 1 | GreenMO Table 1 的 MAX2829 单链口径 |
| 同步 MIMO RFIC | 408 mW/链 | DBF×M，HBF×N | LO 已包含，禁止再次计费 |
| ADC | 10 mW/(MS/s) | 聚合采样率线性计费 | GreenMO 的 AD9963 模型；122.88 MS/s 是模型外推 |
| 快速 RF 开关 | 1 mW/端口 | Proposed/GreenMO-like×M | GreenMO 原型近似 |
| 有源移相器 | 10 mW/个 | PC-HBF×M，FC-HBF×M×N | HBF 文献口径 |
| FFT/数字输入基带 | 40.82 mW/输入 | 按数字输入数 | 由下述 30% 基带锚点派生，不是芯片实测 |
| N×N 检测基带 | N=4 时 163.29 mW | 按 `(N/4)^3` 缩放 | 同上，是复杂度敏感性假设 |

原始资料：

- [GreenMO 项目与论文](https://wcsng.ucsd.edu/greenmo/)、[GreenMO PDF](https://wcsng.ucsd.edu/files/greenmo.pdf)
- [MAX2829 官方产品页](https://www.analog.com/en/products/max2829.html)
- [AD9963 官方产品页](https://www.analog.com/en/products/ad9963.html)
- [混合波束成形功耗模型论文](https://arxiv.org/abs/1807.07201)

基带标称值从 GreenMO 5G 组成中约 30% 的基带占比派生：先以其 M=8、N=4、10 MHz
前端 `354+4×100+8×1=762 mW` 得到
`P_BB=(0.3/0.7)×762=326.57 mW`，再按 50/50 分给输入处理和检测。由于这种分拆并不
唯一，正式结果必须同时报告 low/nominal/high 组件敏感性，不能称为 BOM 或板卡测量。

两个精确锚点是模型单元测试：GreenMO 前端 `0.762 W`，4 链 DBF 前端
`4×408+4×100=2.032 W`。

## 3. 扫描能量与吞吐量

减少 RF 链的前端不能同时观察全部 M 个端口，故每次选择更新需要

```text
scanFrames = ceil(M/N) - 1
Tscan      = 10 ms × scanFrames
```

DBF 同时数字化 M 路，额外 `Tscan=0`。扫描期间前端仍通电，基带运行训练但不发送有效
payload。每个更新周期的正式定义为

```text
Etotal = Pfront × Tupdate
       + PBB,data × (Tupdate - Tscan)
       + PBB,scan × Tscan

EE = Boccupied × Rsum × (Tupdate - Tscan) / Etotal
```

因此扫描的 RF 能量、训练基带能量和 payload 时间损失都已计入，而且只计一次。主结果
使用 `Tupdate=1 s`，同时扫描 `50 ms--10 s`；更新过快时扫描会显著降低能效。

## 4. 速率分子的两种口径

跨架构排名统一使用理想高斯输入的 LMMSE sum-rate，以免用本文全波形 AMC 去对比
DBF/HBF 的理想容量。本文另外报告 R20 的完整开关/acquisition/AMC 结果作为现实锚点：

- M=16 理想参考：`200.1 Mbit/J`；
- M=16 R20 四流 aggregate 全栈锚点：`65.2 Mbit/J`。

二者约三倍差距包含 AMC 离散化、同步、开关损伤和实际解码质量。由于 DBF/HBF 没有
同等的全栈解码结果，禁止拿 `65.2` 直接与其理想 `45.5/88.3/108.5 Mbit/J` 排名。

## 5. R22 结论边界

在 M=16、N=4、1 s 更新和标称组件表下，Proposed/GreenMO-like/DBF/PC-HBF/FC-HBF 的
平均 RX 功耗为 `1.925/1.925/12.260/3.347/3.827 W`；统一理想分子下的能效为
`200.1/206.2/45.5/88.3/108.5 Mbit/J`。本文相对 DBF 的 low/nominal/high 能效比为
`5.22×/4.39×/4.06×`，但这仍是组件模型结论，不是功率计测量。

GreenMO-like 的 M=16 中位理想 rate 仅比本文高约 3.05%，但只在 34/50 个 seed 更高，
且算法只是局部贪婪。因此可声称两者处于相同单链电路包络、本文简化调度的中位速率
损失较小；不可声称本文打赢 GreenMO，也不可声称完整 GreenMO 只增益 3%。

固定 M=16、N 从 1 增到 4 时，本文功耗从 `0.721 W` 增到 `1.925 W`，DBF 从
`12.099 W` 增到 `12.260 W`，显示减少链路具有能量正比优势；但本文每次更新的扫描能量
从 `0.108 J` 到 `0.058 J`，低负载因需扫描更多端口组而并不免费。

## 6. 代码与正式资产

入口为 `type1_run_phase3_r22_energy.m`，组件参数与逐项账本分别在
`type1_phase3_power_parameters.m`、`type1_phase3_power_breakdown.m`；统一速率、HBF 和
GreenMO-like 参考分别在 `type1_phase3_frontend_metrics.m`、
`type1_phase3_hbf_combiner.m`、`type1_phase3_greenmo_like_schedule.m`。

正式 MAT：

```text
/home/bupt/type1_offline_captures/type1_phase3_r22_paper_20260716_094916/
phase3_r22_energy.mat
SHA-256 165eb3e2b5a17fec12a1a6ddb733826e780127de1706e556aff32c6de556477d
```

完整命令和 fresh-run 对照见 [`RUN_COMMANDS.md`](RUN_COMMANDS.md) 的 R22 节，所有修改、
数值和裁决边界见 [`EXPERT_REVIEW.md`](EXPERT_REVIEW.md) §43。R22 已完成两次逐字段一致
复现并通过专家审议；Phase 3 已冻结于 `phase3-freeze-2026-07-16`。
