# G100 CRG Verification (UT + ST)

为 G100 AI 芯片的 CRG 子系统（clkmgr + rstmgr + pwrmgr）搭建完整 UVM 验证环境，采用 UT/ST 分层验证方法学。

## 架构

```
g100_crg_top (ST DUT)
├── clkmgr   — PLL / 分频 / ICG / glitch-free mux
├── rstmgr   — 异步同步 / 毛刺滤波 / 复位树 / 复位原因
└── pwrmgr   — 低功耗 FSM / 唤醒仲裁 / isolation

UT (单元测试) ──┐                ┌── ST (系统测试)
clkmgr UT ──┤  验单模块功能  ├  crg_top ST ── 验跨IP交互
rstmgr UT ──┤  CSR 三件套    │
pwrmgr UT ──┘  定向+随机    ┘
```

## 跑仿真

```bash
cd dv/sim
source setup.sh                 # 设 VCS_HOME / UVM_HOME / DV_ROOT
make compile_ut_clkmgr          # 编译 clkmgr UT
cd work && ./simv_ut_clkmgr +UVM_TESTNAME=clkmgr_smoke_test
```

可用的 test（`+UVM_TESTNAME=xxx`）：

| 层 | simv | 可选 TESTNAME |
|----|------|---------------|
| UT | `simv_ut_clkmgr` | clkmgr_smoke_test, clkmgr_common_test, clkmgr_div_test, clkmgr_gate_test, clkmgr_mux_test, clkmgr_frequency_test, clkmgr_stress_test |
| UT | `simv_ut_rstmgr` | rstmgr_smoke_test, rstmgr_common_test, rstmgr_glitch_test, rstmgr_sync_test, rstmgr_reason_test, rstmgr_stress_test |
| UT | `simv_ut_pwrmgr` | pwrmgr_smoke_test, pwrmgr_common_test, pwrmgr_lowpower_test, pwrmgr_wake_test, pwrmgr_iso_test, pwrmgr_stress_test |
| ST | `simv_st`        | crg_top_smoke_test, crg_top_lowpower_test, crg_top_reset_storm_test, crg_top_stress_test |

## 已验证（实跑结果）

| 测试 | UVM_ERROR | UVM_FATAL | sim time |
|------|-----------|-----------|----------|
| clkmgr_smoke | 0 | 0 | 6.99us |
| rstmgr_smoke | 0 | 0 | 2.58us |
| pwrmgr_smoke | 0 | 0 | 2.02us |
| crg_top_smoke | 0 | 0 | 13.7us |

## 植入的 6 个 bug

详见 [doc/CRG常见bug案例.md](doc/CRG常见bug案例.md)：

| ID | 位置 | 现象 |
|----|------|------|
| BUG_001 | clkmgr_mux | A→B 切换瞬间产生 runt pulse |
| BUG_002 | clkmgr_pll | frac 模式用 2^23，频率偏差 |
| BUG_003 | rstmgr_filter | clk 停振时滤波器锁死复位 |
| BUG_004 | clkmgr_gate | ICG 用 posedge latch 产生 runt |
| BUG_005 | rstmgr_top | glitch_th 读回 +1 |
| BUG_006 | pwrmgr_top | WAKE_CLK 期间 iso 提前 drop |

## 目录

```
dv/
├── ARCHITECTURE.md           # 架构总览
├── rtl/                      # DUT
│   ├── clkmgr/               # 4 个子模块 + top
│   ├── rstmgr/               # 2 个子模块 + top
│   ├── pwrmgr/               # top（含 FSM）
│   └── crg_top/              # g100_crg_top 顶层
├── common/                   # 共享组件
│   ├── apb_agent/            # APB UVC
│   ├── clk_rst_if/           # 时钟复位接口
│   ├── csr_utils/            # CSR 三件套
│   └── crg_base/             # base env / vseq / test
├── ut/                       # 单元测试（3 个 IP 各一个 env）
│   ├── clkmgr/dv/
│   ├── rstmgr/dv/
│   └── pwrmgr/dv/
├── st/crg_top/dv/            # 系统测试
├── sim/                      # filelist + Makefile + setup.sh
└── doc/                      # 设计文档 + 面试话术 + bug 案例
```

## 面试资料

- [doc/CRG验证设计文档.md](doc/CRG验证设计文档.md) — VFL + 验证策略
- [doc/CRG面试话术.md](doc/CRG面试话术.md) — 按面试题分类的标准答案
- [doc/CRG常见bug案例.md](doc/CRG常见bug案例.md) — 6 个 bug 的定位过程
