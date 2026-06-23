# G100 CRG Verification (UT + ST)

G100 AI 芯片 CRG 子系统的 UVM 验证环境，采用 UT/ST 分层验证方法学。

## 目录结构

```
.
├── dv/                 # 验证环境
│   ├── rtl/            # DUT: clkmgr / rstmgr / pwrmgr 三个 IP + g100_crg_top 顶层
│   ├── common/         # 共享组件: APB agent / clk_rst_if / CSR 三件套 / base env
│   ├── ut/             # 单元测试 (每个 IP 一个独立 UVM env)
│   ├── st/             # 系统测试 (g100_crg_top 跨 IP 验证)
│   ├── sim/            # filelist + Makefile + setup.sh
│   └── doc/            # 验证设计文档 / 面试话术 / bug 案例
├── LICENSE
└── README.md           # 本文件
```

详细说明见 [dv/README.md](dv/README.md)。

## 快速开始

```bash
cd dv/sim
source setup.sh                 # 设 VCS_HOME / UVM_HOME / DV_ROOT
make compile_ut_clkmgr          # 编译 clkmgr UT
cd work && ./simv_ut_clkmgr +UVM_TESTNAME=clkmgr_smoke_test
```

## 验证方法学

CRG 拆成 clkmgr（时钟管理）、rstmgr（复位管理）、pwrmgr（电源管理）三个独立 IP：

- **UT 层**：每个 IP 有独立 UVM env，验证单模块功能 + CSR 合规（hw_reset / bit_bash / aliasing）
- **ST 层**：g100_crg_top 顶层验证跨 IP 交互（低功耗握手 / 复位传播 / 时钟联动）

详细验证策略见 [dv/doc/CRG验证设计文档.md](dv/doc/CRG验证设计文档.md)。
