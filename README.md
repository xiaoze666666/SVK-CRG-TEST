# G100 CRG Verification (UT + ST)

G100 AI 芯片 CRG 子系统的 UVM 验证环境，采用 UT/ST 分层验证方法学。

## CRG 架构

**时钟树**：3 PLL（PLL_CPU/SOC/PERI，每个双 CK0/CK1 输出）→ 5:1 glitch-free mux → 动态分频 → 10 叶子时钟（cpu_core/axi_main/ddr_ref/ahb/periph/gmac_tx/qspi_ref 等）+ 硬件频率测量单元。

**复位树**：6 异步源（POR/WDG/DBG/SW/低压/安全）→ 毛刺滤波 → 8 域独立同步器（每域一个 rstmgr_sync）+ 7-bit 复位原因锁存。

**电源管理**：低功耗 FSM（ACTIVE↔PD）+ 唤醒源仲裁 + isolation 控制。

时钟树和复位树结构对称——10 个叶子时钟对应 8 个复位域。

## 目录结构

```
.
├── dv/                 # 验证环境
│   ├── rtl/            # DUT
│   │   ├── clkmgr/     # PLL / mux(2:1+5:1) / div / gate / freq_meas / top
│   │   ├── rstmgr/     # sync / filter / top (8-domain tree)
│   │   ├── pwrmgr/     # low-power FSM / top
│   │   └── crg_top/    # g100_crg_top integration
│   ├── common/         # APB agent / clk_rst_if / CSR 三件套 / base env
│   ├── ut/             # clkmgr/rstmgr/pwrmgr 各自的 UT env
│   ├── st/             # crg_top ST env (跨 IP 验证)
│   ├── sim/            # filelist + Makefile + setup.sh
│   └── doc/            # 验证设计文档 / 面试话术 / bug 案例
├── LICENSE
└── README.md
```

## 快速开始

```bash
cd dv/sim
source setup.sh
make compile_ut_clkmgr
cd work && ./simv_ut_clkmgr +UVM_TESTNAME=clkmgr_smoke_test
```

## 验证结果

| 测试 | UVM_ERROR | 说明 |
|------|-----------|------|
| clkmgr smoke | 0 | 3 PLL all lock |
| rstmgr smoke | 0 | 8-domain reset tree |
| pwrmgr smoke | 0 | low-power FSM |
| crg_top ST smoke | 0 | 3 IP 集成 |
| rstmgr csr_hw_reset | 1 (BUG_005) | glitch_th readback th+1 |

详细验证策略见 [dv/doc/CRG验证设计文档.md](dv/doc/CRG验证设计文档.md)。
