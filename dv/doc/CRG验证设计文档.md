# G100 AI 芯片 CRG 验证设计文档（VFL + 验证策略）

> 项目：G100 CRG 子系统验证（clkmgr + rstmgr + pwrmgr）
> 方法论：UT（单元测试）+ ST（系统测试）分层
> 工具链：SystemVerilog + UVM 1.2 + VCS

---

## 1. CRG 子系统架构

G100 把 CRG 拆成 3 个独立 IP，每个有独立 APB 接口、独立地址段、独立 UT 验证环境。时钟树和复位树结构对称——每个时钟域对应一个复位域。

### 1.1 时钟树（3 PLL + 5:1 mux + 分频链 + 10 叶子）

```
25MHz XTAL
    │
    ├── PLL_CPU   (VCO 2400M) ── CK0[800M] ──┐
    │                           CK1[480M] ──┤
    ├── PLL_SOC   (VCO 2400M) ── CK0[800M] ──┤  5 个候选时钟
    │                           CK1[800M] ──┤  ↓
    └── PLL_PERI  (VCO 250M)  ── CK0[250M] ──┘  [5:1 glitch-free mux]
                                              (per-domain 选源)
                                              ↓
                                         [clk_div_even]
                                         (2~15 动态分频)
                                              ↓
        ┌─────────────────────────────────────┴──────────────────────────┐
        ↓                                     ↓                          ↓
   domain0 (CPU)                         domain1 (SOC)             domain2 (PERI)
   ┌─────┴─────┐                         ┌─────┴─────┐              ┌─────┴─────┐
   ↓           ↓                          ↓           ↓              ↓           ↓
 cpu_core   cpu_aclk                    axi_main   ddr_ref         ahb        periph
 (800M)    (ICG gated)                 (800M)     (1000M)         (250M)     (250M)
                                                                      │           │
                                                                   apb_leaf    gmac_tx
                                                                   (from ahb)  qspi_ref
                                                                   + gmac_rx (外部异步)

   频率测量单元: clkmgr_freq_meas 用 32K aon_clk 数每个叶子时钟周期，
                 超 ±5% 报 recov_err，时钟停振报 fatal_err
```

**3 个 PLL**（每个一 VCO、双 postdiv 输出 CK0/CK1）：
- **PLL_CPU**：VCO 2400M，CK0=800M（CPU 簇）、CK1=480M（AXI 互联）
- **PLL_SOC**：VCO 2400M，CK0=800M（高速总线）、CK1=800M（DDR 接口）
- **PLL_PERI**：VCO 250M，CK0=250M（外设/QSPI）、CK1=125M（GMAC）

**5:1 glitch-free mux**：每个 domain 独立选源（3 PLL × CK0/CK1 = 5 候选 + XTAL 旁路）。每个候选时钟有独立的同步使能链，negedge 锁存，保证切换瞬间无毛刺。

### 1.2 复位树（8 域 + 6 源 + 复位原因锁存）

```
6 个异步复位源 (active-low):
   POR  /  WDG  /  DBG  /  SW  /  低压检测  /  安全违规
                    ↓ AND
              tree_rst_n (async)
                    ↓
         glitch_filter (on apb_clk, threshold 可配)
                    ↓ por_filtered_n
         ┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
         ↓          ↓          ↓          ↓          ↓          ↓          ↓          ↓
     rstmgr_sync rstmgr_sync rstmgr_sync rstmgr_sync rstmgr_sync rstmgr_sync rstmgr_sync rstmgr_sync
     (cpu_core) (cpu_aclk)  (axi_main) (ddr_ref)  (ahb)     (periph)  (gmac)    (qspi)
     clk         clk         clk         clk         clk         clk         clk         clk
         ↓          ↓          ↓          ↓          ↓          ↓          ↓          ↓
     domain_rst_n[0] ...                                                          domain_rst_n[7]

   复位原因锁存: 7-bit 寄存器（por/wdg/dbg/sw/low_volt/sec/sw_req），
                 SoC 启动后软件可查询上次复位由谁触发
```

**为什么 8 个域而不是 10 个？** gmac_rx 是外部输入异步时钟（不需要本地复位同步），cpu_aclk 是 cpu_core 的门控版本（共享同一复位域）。所以 10 个叶子时钟对应 8 个独立复位域。

## 2. 验证功能点列表（VFL）

### 2.1 clkmgr 功能点

| ID | 功能点 | 验证目标 | 覆盖用例 |
|----|--------|----------|----------|
| K1 | 3 PLL 独立锁定 | 每个 PLL 配置后独立 lock，频率符合 spec | smoke, pll_lock |
| K2 | PLL 分数模式 | frac 模式 `Fvco = Fref * (fbdiv + frac/2^24) / refdiv` | frequency（BUG_002） |
| K3 | PLL 失锁恢复 | cfg 改变后 lock=0 → N 周期 → lock=1 | pll_lock |
| K4 | 5:1 mux 切换 | 在 5 个候选时钟间切换，无毛刺 | mux（BUG_001） |
| K5 | 动态分频 | 运行时改 div_ratio，含 0.5 步进 | div |
| K6 | ICG 门控 | gate_en 翻转无 runt pulse | gate（BUG_004） |
| K7 | **硬件频率测量** | freq_meas 检测频率偏差超 ±5% 报 recov_err | （预留） |
| K8 | **时钟停振检测** | freq_meas 检测 target_clk 停振报 fatal_err | （预留） |
| K9 | 10 叶子频率检查 | scoreboard 对每个叶子预测+比对 | smoke + 所有 vseq |
| K10 | CSR 合规 | hw_reset / bit_bash / aliasing 三件套 | common |

### 2.2 rstmgr 功能点

| ID | 功能点 | 验证目标 | 覆盖用例 |
|----|--------|----------|----------|
| R1 | 异步复位同步释放 | 8 个域 sync_rst_n 上升沿落在各自 clk posedge 后 1~2 拍 | sync |
| R2 | 6 复位源组合 | 任一源为 0 → tree_rst_n=0 → 所有域复位 | sync |
| R3 | 8 域独立使能 | domain_en[i]=0 时对应域保持复位 | sync, stress |
| R4 | 毛刺滤波 | < glitch_th 周期的复位脉冲被过滤 | glitch（BUG_003） |
| R5 | **滤波器不被 clk 卡死** | clk 停振时滤波器不锁死复位 | glitch（BUG_003） |
| R6 | **复位原因锁存** | 7 种源触发后 rst_reason 对应 bit 锁存 | reason |
| R7 | 软件复位请求 | rst_req[0]=1 触发 rst_reason[6] | reason |
| R8 | CSR 复位值 | glitch_th 读回等于写入值 | common（BUG_005） |

### 2.3 pwrmgr 功能点

| ID | 功能点 | 验证目标 | 覆盖用例 |
|----|--------|----------|----------|
| P1 | 低功耗 FSM | ACTIVE→ISO_ON→PD_ENTER→PD_WAIT→PD 完整流转 | lowpower |
| P2 | 唤醒流转 | PD→WAKE_CLK→WAKE_RST→ISO_OFF→ACTIVE | lowpower, wake |
| P3 | 隔离控制 | PD 期间 iso=1，ACTIVE 期间 iso=0 | iso |
| P4 | 唤醒源仲裁 | 多个 wake_src 触发锁存到 wake_status | wake |
| P5 | **唤醒 iso 时序** | WAKE_CLK 期间 iso 不能提前 drop | lowpower（BUG_006） |
| P6 | CSR 复位值 | 所有寄存器复位值符合 spec | common |

### 2.4 ST 跨 IP 功能点

| ID | 功能点 | 验证目标 | 覆盖用例 |
|----|--------|----------|----------|
| S1 | 低功耗握手闭环 | pwrmgr.lowpower → clkmgr.main_clk_en=0 → rstmgr.sw_rst | lowpower |
| S2 | 复位风暴恢复 | 6 复位源随机组合注入后 8 域能恢复 | reset_storm |
| S3 | 三 IP 同时扰动 | 随机写 3 IP 所有 RW 寄存器，无 hang | stress |

## 3. 验证策略

### 3.1 分层验证（UT + ST）

```
                  ┌─── UT 层 ───┐         ┌─── ST 层 ───┐
   clkmgr UT  ──▶ │ 验单模块功能 │         │ 验跨IP交互   │ ◀── crg_top ST
   rstmgr UT  ──▶ │ CSR 合规    │         │ 低功耗握手   │
   pwrmgr UT  ──▶ │ 定向+随机   │         │ 复位传播     │
                  └──────────────┘         └──────────────┘
```

**为什么要分两层？**
- UT 层：DUT 范围小，问题定位快；接口干净；独立跑回归；覆盖率容易收
- ST 层：验真实 SoC 集成场景；UT 跑过的功能在集成后可能失效（如 pwrmgr 关 clkmgr 时钟后 rstmgr 的 8 个同步器还能正常工作吗？）；只靠 UT 验不出跨模块交互 bug

### 3.2 检查器三件套

每个 IP 都同时用三种检查器，互补：
1. **uvm_reg 预测 + mirror**（CSR 检查）：自动预测每次读写后的期望值，复位后 mirror 验所有寄存器复位值
2. **Scoreboard 比对**：参考模型按 spec 公式独立算 10 个叶子期望频率，monitor 测真实值，差超 10% 报错
3. **SVA bind 断言**：绑到 DUT 内部节点，检查时序性质（mux 无毛刺、复位同步释放、ICG 无 runt）

**关键原则：参考模型与 DUT 完全解耦**。参考模型只读寄存器配置和外部激励，绝不通过 `uvm_hdl_read` 读 DUT 内部信号——否则 DUT 错了 checker 也跟着错。

### 3.3 CSR 合规三件套

每个 UT 都跑这三个标准序列：

| 序列 | 做什么 | 抓什么 bug |
|------|--------|------------|
| **csr_hw_reset** | 复位后 mirror 每个寄存器，期望等于 spec reset value | 寄存器复位值错（BUG_005） |
| **csr_bit_bash** | 对每个 RW bit 单独写 1 写 0 读回验证 | 某个 bit 不生效或读回错 |
| **csr_aliasing** | 对一个寄存器写全 1 全 0，检查其他寄存器不变 | 寄存器地址译码错 |

### 3.4 覆盖率收集

**代码覆盖率**：VCS `-cm line+cond+fsm+tgl+branch`

**功能覆盖率**（covergroup）：
- PLL 配置交叉：bypass × dsmen × postdiv1 × postdiv2
- 分频比桶：[0:4] 桶 × half_en
- 8 域复位使能：domain_en[7:0] 每个 bit 独立覆盖
- mux 选择：d0 × d1 × d2 交叉
- 门控：10 bit gate_en 各档

### 3.5 硬件频率测量（clkmgr 独有）

`clkmgr_freq_meas` 是真实芯片的安全保护机制：用慢速 aon_clk（~32kHz）作为时间基准，在固定窗口内数目标时钟（如 cpu_core_clk）的周期数。如果实际计数偏离期望值超过 tolerance_pct（默认 5%），置 recov_err；如果目标时钟完全停振，置 fatal_err。

这种硬件测量不依赖 CPU 软件，能在 SoC 启动早期就发现 PLL 失锁或分频器错配。

## 4. 故意植入的 6 个真实 CRG bug

详见 [CRG常见bug案例.md](CRG常见bug案例.md)。

| Bug ID | 位置 | 现象 | 抓它的 testcase |
|--------|------|------|-----------------|
| BUG_001 | clkmgr_mux/mux5 | 切换瞬间产生 runt pulse | mux vseq + SVA |
| BUG_002 | clkmgr_pll | frac 模式用 2^23 而非 2^24，频率偏差 | frequency vseq + scoreboard |
| BUG_003 | rstmgr_filter | clk 停振时滤波器锁死复位 | glitch vseq + SVA |
| BUG_004 | clkmgr_gate | ICG 用 posedge latch 产生 runt | gate vseq + SVA |
| BUG_005 | rstmgr_top | glitch_th 读回返回 th+1 | common vseq（csr_hw_reset） |
| BUG_006 | pwrmgr_top | WAKE_CLK 期间 iso 提前 drop | lowpower vseq + SVA |

## 5. 跑仿真

```bash
cd dv/sim
source setup.sh                    # 设 VCS_HOME / UVM_HOME / DV_ROOT
make compile_ut_clkmgr             # 编译 clkmgr UT
cd work && ./simv_ut_clkmgr +UVM_TESTNAME=clkmgr_smoke_test
```

实测全部 4 个 smoke test（UT×3 + ST×1）**0 errors / 0 fatal**。
