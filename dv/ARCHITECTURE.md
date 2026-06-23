# G100 CRG Verification - v2 Architecture (UT + ST)

## 设计哲学：UT + ST 分层

G100 的 CRG 子系统按功能拆成 3 个独立 IP（clkmgr / rstmgr / pwrmgr），每个 IP 有独立的
UT 验证环境，最后在 SoC top 做 ST 验证跨 IP 交互。这种分层让单模块问题定位快、集成问题
在 ST 暴露。

## 目录结构

```
dv/
├── rtl/                                  # DUT（共享给 UT 和 ST）
│   ├── clkmgr/                           # 时钟管理 IP
│   │   ├── clkmgr_reg_top.sv             # 寄存器 + APB 接口
│   │   ├── clkmgr_div.sv                 # 分频器
│   │   ├── clkmgr_gate.sv                # ICG 门控
│   │   ├── clkmgr_mux.sv                 # glitch-free mux
│   │   └── clkmgr_top.sv                 # 时钟 IP 顶层
│   ├── rstmgr/                           # 复位管理 IP
│   │   ├── rstmgr_reg_top.sv
│   │   ├── rstmgr_sync.sv                # 异步复位同步释放
│   │   ├── rstmgr_filter.sv              # 毛刺滤波
│   │   ├── rstmgr_tree.sv                # 复位树
│   │   └── rstmgr_top.sv
│   ├── pwrmgr/                           # 电源管理 IP
│   │   ├── pwrmgr_reg_top.sv
│   │   ├── pwrmgr_fsm.sv                 # 低功耗状态机
│   │   ├── pwrmgr_wake.sv                # 唤醒源仲裁
│   │   └── pwrmgr_top.sv
│   └── crg_top/                          # CRG SoC 顶层（集成 3 IP）
│       └── g100_crg_top.sv
│
├── ut/                                   # 单元测试（每个 IP 一个独立 env）
│   ├── clkmgr/dv/                        # clkmgr UT env
│   │   ├── tb/tb.sv                      # test harness
│   │   ├── env/
│   │   │   ├── clkmgr_env_pkg.sv
│   │   │   ├── clkmgr_env.sv
│   │   │   ├── clkmgr_env_cfg.sv
│   │   │   ├── clkmgr_env_cov.sv
│   │   │   ├── clkmgr_scoreboard.sv
│   │   │   ├── clkmgr_virtual_sequencer.sv
│   │   │   └── seq_lib/
│   │   │       ├── clkmgr_base_vseq.sv
│   │   │       ├── clkmgr_common_vseq.sv       # CSR 三件套
│   │   │       ├── clkmgr_smoke_vseq.sv
│   │   │       ├── clkmgr_div_vseq.sv
│   │   │       ├── clkmgr_gate_vseq.sv
│   │   │       ├── clkmgr_mux_vseq.sv
│   │   │       ├── clkmgr_frequency_vseq.sv    # 频率测量
│   │   │       └── clkmgr_vseq_list.sv
│   │   ├── sva/
│   │   │   └── clkmgr_bind.sv                  # SVA bind
│   │   └── tests/
│   │       └── clkmgr_test_pkg.sv
│   ├── rstmgr/dv/                        # 同上结构
│   └── pwrmgr/dv/                        # 同上结构
│
├── st/                                   # 系统测试（顶层 g100_crg_top）
│   └── crg_top/dv/
│       ├── tb/tb.sv
│       ├── env/
│       │   ├── crg_top_env_pkg.sv
│       │   ├── crg_top_env.sv            # 包含 3 个 sub-env 或 cross-IP scoreboard
│       │   ├── crg_top_env_cfg.sv
│       │   ├── crg_top_scoreboard.sv     # 跨 IP 交互检查
│       │   ├── crg_top_virtual_sequencer.sv
│       │   └── seq_lib/
│       │       ├── crg_top_base_vseq.sv
│       │       ├── crg_top_lowpower_vseq.sv    # pwrmgr→clkmgr→rstmgr 握手
│       │       ├── crg_top_reset_storm_vseq.sv # 全局复位 + 各 IP 复位混合
│       │       └── crg_top_stress_vseq.sv
│       ├── sva/
│       │   └── crg_top_bind.sv
│       └── tests/
│           └── crg_top_test_pkg.sv
│
├── common/                               # 共享组件
│   ├── apb_agent/                        # APB UVC（所有 env 共用）
│   ├── clk_rst_if/                       # 时钟复位接口
│   └── csr_utils/                        # CSR 三件套简化实现
│
├── sim/
│   ├── filelist_ut_clkmgr.f
│   ├── filelist_ut_rstmgr.f
│   ├── filelist_ut_pwrmgr.f
│   ├── filelist_st.f
│   ├── Makefile                          # make ut_clkmgr / ut_all / st_all
│   └── setup.sh
│
└── doc/
    ├── CRG验证设计文档.md
    ├── CRG面试话术.md
    └── CRG常见bug案例.md
```

## 组件设计要点

| 组件 | 本工程实现 |
|---|---|
| base env / base vseq | 自写 `crg_base_env` / `crg_base_vseq`（轻量抽象，3 个 UT 都继承） |
| CSR 三件套 | 自写 `csr_hw_reset_seq` / `csr_bit_bash_seq` / `csr_aliasing_seq` |
| 总线 agent | APB agent（够用、易讲） |
| SVA | `*_bind.sv` 用 bind 绑进 DUT |
| 测试列表 | Makefile + `+UVM_TESTNAME=xxx` 选 |
| 时钟复位接口 | 一个 `clk_rst_if` per 域 |

## 工作量

- RTL：~12 文件（3 IP × 4 子模块 + crg_top）
- UT：每 IP ~12 文件（env+seq+sva+tests+tb），3 IP 共 ~36 文件
- ST：~10 文件
- common：~6 文件
- doc：3 文件
- sim：5 文件
- **总计 ~72 文件**

分阶段交付，每阶段都能跑。
