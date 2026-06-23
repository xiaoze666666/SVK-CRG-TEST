# G100 AI 芯片 CRG 验证设计文档（VFL + 验证策略）

> 项目：G100 CRG 子系统验证（clkmgr + rstmgr + pwrmgr）
> 方法论：UT（单元测试）+ ST（系统测试）分层验证
> 工具链：SystemVerilog + UVM 1.2 + VCS

---

## 1. CRG 子系统架构

G100 把 CRG 拆成 3 个独立 IP，每个有独立 APB 接口、独立地址段、独立 UT 验证环境。

```
                  ┌──────────── g100_crg_top ────────────┐
   APB ─────────▶ │ ┌─────────┐ ┌─────────┐ ┌─────────┐  │ ──▶ cpu_clk/gpu_clk/ddr_clk
                  │ │ clkmgr  │ │ rstmgr  │ │ pwrmgr  │  │ ──▶ cpu_rst_n/gpu_rst_n/ddr_rst_n
                  │ │ 0x0000  │ │ 0x1000  │ │ 0x2000  │  │ ──▶ iso_en / pwr_state
                  │ └────┬────┘ └────▲────┘ └────┬────┘  │
                  │      │ clk_req   │ rst_req   │       │
                  │      ▼           │           ▼       │
                  │  main_clk_status │  rst_status        │
                  └──────────────────────────────────────┘
```

跨 IP 握手：
- **pwrmgr → clkmgr**：`main_clk_en_o` 请求关时钟，`main_clk_status_i` 应答
- **pwrmgr → rstmgr**：`rst_req_o` 请求复位（注入 sw_rst 路径），`rst_status_i` 应答
- **clkmgr → rstmgr**：clkmgr 输出 `cpu_clk/gpu_clk/ddr_clk`，rstmgr 用它们做复位同步的目标时钟

## 2. 验证功能点列表（VFL）

### 2.1 clkmgr 功能点

| ID | 功能点 | 验证目标 | 覆盖用例 |
|----|--------|----------|----------|
| K1 | PLL 整数模式锁定 | lock=1 且输出周期符合 `Fout = Fref * fbdiv / refdiv / (p1*p2)` | smoke, frequency |
| K2 | PLL 分数模式锁定 | frac 模式下 `Fout = Fref * (fbdiv + frac/2^24) / refdiv / (p1*p2)` | frequency |
| K3 | PLL 失锁恢复 | cfg 改变后 lock 重置为 0，N 周期后再次 lock | frequency |
| K4 | 动态分频器 | 运行时改 div_ratio，输出周期立即按 `(div+1)` 倍变化 | div |
| K5 | 半步进分频 | half_en=1 时分频比为 `div+0.5`，验证占空比仍为 50% | div |
| K6 | ICG 门控时钟 | gate_en=0 时 clk_out 停振；gate_en=1 时 clk_out 跟随 | gate |
| K7 | **ICG 无毛刺** | gate_en 在 clk_in 高电平变化时，clk_out 不产生 runt pulse | gate（BUG_004 检查） |
| K8 | glitch-free mux 切换 | 在 clka/clkb 同时跑时切换 sel，输出无毛刺 | mux（BUG_001 检查） |
| K9 | 时钟源切换 | src_sel=0 用 OSC，src_sel=1 用 XTAL | smoke |
| K10 | CSR 寄存器复位值 | 所有寄存器复位后读回等于 spec 值 | common（csr_hw_reset） |

### 2.2 rstmgr 功能点

| ID | 功能点 | 验证目标 | 覆盖用例 |
|----|--------|----------|----------|
| R1 | 异步复位同步释放 | sync_rst_n 上升沿必须落在 cpu_clk posedge 后 1~2 周期 | sync |
| R2 | 复位源组合 | por & wdg & dbg & sw 任一为 0 → 输出复位 | sync |
| R3 | 域复位使能 | rst_ctrl_xxx=0 时对应域保持复位，不受 tree_rst_n 影响 | sync |
| R4 | 复位毛刺滤波 | < glitch_th 周期的复位脉冲被过滤，不传播 | glitch |
| R5 | **滤波器不被 clk 卡死** | clk 停振时滤波器不应锁死复位 | glitch（BUG_003 检查） |
| R6 | 复位原因记录 | 每个复位源触发后 rst_reason 对应 bit 锁存 | reason |
| R7 | 软件复位请求 | rst_req[0]=1 触发 rst_reason[4] 锁存 | reason |
| R8 | CSR 复位值检查 | glitch_th 读回等于写入值 | common（BUG_005 检查） |

### 2.3 pwrmgr 功能点

| ID | 功能点 | 验证目标 | 覆盖用例 |
|----|--------|----------|----------|
| P1 | 低功耗状态机流转 | ACTIVE→ISO_ON→PD_ENTER→PD_WAIT→PD 的时序正确 | lowpower |
| P2 | 唤醒流转 | PD→WAKE_CLK→WAKE_RST→ISO_OFF→ACTIVE | lowpower, wake |
| P3 | 隔离控制 | PD 期间 iso_en=1，ACTIVE 期间 iso_en=0 | iso |
| P4 | 唤醒源仲裁 | 多个 wake_src 同时触发，按 enable mask 锁存到 wake_status | wake |
| P5 | **唤醒 iso 时序** | WAKE_CLK 期间 iso 不能提前 drop | lowpower（BUG_006 检查） |
| P6 | CSR 复位值检查 | 所有寄存器复位值符合 spec | common |

### 2.4 ST 跨 IP 功能点

| ID | 功能点 | 验证目标 | 覆盖用例 |
|----|--------|----------|----------|
| S1 | 低功耗握手闭环 | pwrmgr.lowpower → clkmgr.main_clk_en=0 → rstmgr 看到 sw_rst | lowpower |
| S2 | 复位风暴恢复 | 各种复位组合随机注入后系统能恢复 | reset_storm |
| S3 | 三 IP 同时扰动 | 随机写 3 个 IP 的所有 RW 寄存器，无 hang | stress |

## 3. 验证策略

### 3.1 分层验证（UT + ST）

```
                  ┌─── UT 层 ───┐         ┌─── ST 层 ───┐
   clkmgr UT  ──▶ │  验单模块功能 │         │ 验跨IP交互   │ ◀── crg_top ST
   rstmgr UT  ──▶ │  CSR 合规    │         │ 低功耗握手   │
   pwrmgr UT  ──▶ │  定向 + 随机 │         │ 复位传播     │
                  └──────────────┘         └──────────────┘
```

**为什么要分两层？**
- UT 层：DUT 范围小，问题定位快；接口干净；可以独立跑回归；覆盖率容易收
- ST 层：验真实 SoC 的集成场景；UT 跑过的功能在集成后可能失效（例如 pwrmgr 关了 clkmgr 的时钟，rstmgr 还能正常同步吗？）；只靠 UT 验不出这种交互 bug

**业界经验**：成熟 SoC 项目通常把 clkmgr/rstmgr/pwrmgr 各自做 UT 在 IP 级目录，SoC 顶层做 ST 在 chip 级目录，两者都跑回归。本工程沿用这个分层思路。

### 3.2 检查器三件套

每个 IP 都同时用三种检查器，互补：

1. **uvm_reg 预测 + mirror**（CSR 检查）：自动预测每次读写后的期望值，复位后用 `mirror(status, UVM_CHECK, UVM_FRONTDOOR, null, this)` 验所有寄存器复位值
2. **Scoreboard 比对**：参考模型按 spec 公式独立算期望值，monitor 测真实值，差超 tolerance 报错
3. **SVA bind 断言**：直接绑到 DUT 内部节点，检查时序性质（无毛刺、复位同步释放等）

**关键原则：参考模型与 DUT 完全解耦。** 参考模型只读寄存器配置和外部激励，**绝不**通过 `uvm_hdl_read` 读 DUT 内部信号——否则 DUT 错了 checker 也跟着错。这是从 svk_crg_test 学到的反面教训。

### 3.3 CSR 合规三件套

每个 UT 都跑这三个标准序列，是 UVM 寄存器验证的"基本功"：

| 序列 | 做什么 | 抓什么 bug |
|------|--------|------------|
| **csr_hw_reset** | 复位后 mirror 每个寄存器，期望等于 spec reset value | 寄存器复位值错（BUG_005） |
| **csr_bit_bash** | 对每个 RW bit 单独写 1 写 0 读回验证 | 某个 bit 不生效或读回错 |
| **csr_aliasing** | 对一个寄存器写全 1 全 0，检查其他寄存器不变 | 寄存器地址译码错（aliasing） |

### 3.4 覆盖率收集

**代码覆盖率**：VCS `-cm line+cond+fsm+tgl+branch`

**功能覆盖率**（covergroup）：
- PLL 配置组合：bypass × dsmen × postdiv1 × postdiv2（交叉）
- 分频比桶：[1:16] / [17:64] / [65:128] / [129:255]
- 门控组合：cpu_gate × gpu_gate × ddr_gate
- mux 选择：cpu_sel × gpu_sel × ddr_sel
- 复位控制：cpu_rst_n × gpu_rst_n × ddr_rst_n（交叉）
- 低功耗：lowpower_req × sw_iso_en

### 3.5 随机化

- 复位 cycle 数：`$urandom_range(3,15)`
- PLL 配置：`$urandom_range(1,3)` refdiv、`$urandom_range(20,200)` fbdiv
- 用例间隔：`$urandom_range(100,500)` ns
- 多种子回归：`+ntb_random_seed=N`

## 4. 故意植入的 6 个真实 CRG bug

为了让简历的"发现 N 个 bug"有故事讲，DUT 里故意植入 6 个真实 bug，每个对应一个 testcase 能抓出来。详见 [CRG常见bug案例.md](CRG常见bug案例.md)。

| Bug ID | 位置 | 现象 | 抓它的 testcase |
|--------|------|------|-----------------|
| BUG_001 | clkmgr_mux | A→B 切换瞬间产生 1 周期 runt pulse | clkmgr_mux_vseq + SVA |
| BUG_002 | clkmgr_pll | frac 模式用 2^23 而非 2^24，频率翻倍 | clkmgr_frequency_vseq + scoreboard |
| BUG_003 | rstmgr_filter | clk 停振时滤波器锁死复位 | rstmgr_glitch_vseq + SVA |
| BUG_004 | clkmgr_gate | ICG 用 posedge 而非 negedge latch，产生 runt | clkmgr_gate_vseq + SVA |
| BUG_005 | rstmgr_top | glitch_th 读回返回 th+1 | rstmgr_common_vseq（csr_hw_reset） |
| BUG_006 | pwrmgr_top | WAKE_CLK 期间 iso 提前 drop | pwrmgr_lowpower_vseq + SVA |

## 5. 目录结构

```
dv/
├── rtl/             # DUT（clkmgr/rstmgr/pwrmgr/crg_top）
├── common/          # 共享 UVC（apb_agent / clk_rst_if / csr_utils / crg_base）
├── ut/
│   ├── clkmgr/dv/   # clkmgr UT env（env_pkg + test_pkg + tb + SVA bind）
│   ├── rstmgr/dv/
│   └── pwrmgr/dv/
├── st/
│   └── crg_top/dv/  # ST env（聚合 3 个 IP 的 reg model）
├── sim/             # filelist + Makefile + setup.sh
└── doc/             # 本文档 + 面试话术 + bug 案例
```

## 6. 跑仿真

```bash
cd dv/sim
source setup.sh                    # 设 VCS_HOME / UVM_HOME / DV_ROOT
make compile_ut_clkmgr             # 编译 clkmgr UT
cd work && ./simv_ut_clkmgr +UVM_TESTNAME=clkmgr_smoke_test
```

实测全部 4 个 smoke test（UT×3 + ST×1）**0 errors / 0 fatal**。
