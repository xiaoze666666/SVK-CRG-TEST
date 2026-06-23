# CRG 验证面试话术（按问题分类）

> 这份文档按面试官常问的问题组织。每题分三块：
> 1. **标准答案**——技术原理，要背熟
> 2. **项目佐证**——你 G100 CRG 项目里怎么做的（具体到代码/序列名）
> 3. **加分点**——主动提一句能体现深度的话

---

## Q1. 你做过的 CRG 验证具体是什么？讲讲架构。

**标准答案**：
CRG（Clock and Reset Generator）是 SoC 里给所有子模块供时钟和复位的"心脏"。我做的 G100 CRG 分成 3 个独立 IP：**clkmgr**（时钟管理，3 个 PLL + 5:1 mux + 分频链 + ICG + 10 个叶子时钟）、**rstmgr**（复位管理，6 复位源 + 毛刺滤波 + 8 域独立同步器 + 复位原因锁存）、**pwrmgr**（电源管理，低功耗 FSM + 唤醒仲裁 + isolation）。三个 IP 共享一条 APB 总线，地址段分开。

**项目佐证**：
时钟树和复位树结构对称——10 个叶子时钟对应 8 个复位域（gmac_rx 是外部异步时钟不单独复位，cpu_aclk 共享 cpu_core 域）。验证上我自己设计的方案，**分 UT 和 ST 两层**：每个 IP 有独立 UVM env 做单元测试，顶层 g100_crg_top 做 ST 验跨 IP 握手。

每个 UT 都跑 **CSR 三件套**（hw_reset / bit_bash / aliasing），加上定向序列覆盖每个功能点。clkmgr 的 scoreboard 对 10 个叶子时钟分别预测期望频率（PLL → mux → div → 叶子整条链路推算），monitor 实测比对。

**加分点**：主动说"我还加了硬件频率测量单元——用 32K 的 aon_clk 数快时钟周期，超 ±5% 报 fatal，这是真实芯片的安全保护机制，不依赖 CPU 软件就能在启动早期发现 PLL 失锁"。

---

## Q2. CRG 验证的关键功能点有哪些？

**标准答案**（按 IP 分）：

**时钟侧（clkmgr）**：
- PLL lock 全过程：cfg 改变后 lock 重置、lock 时间、lock 后频率稳定
- 动态分频：运行时改分频比，包括 0.5 步进的半周期分频
- glitch-free mux 切换：在两个时钟同时跑时切换，输出不能有 runt pulse
- ICG 门控：gate_en 翻转时不能产生短脉冲

**复位侧（rstmgr）**：
- 异步复位同步释放：reset 释放必须落在目标时钟域 posedge 后 1~2 拍
- 复位树：por/wdg/dbg/sw 多源 AND 后分发到各域
- 毛刺滤波：短于阈值的复位脉冲被过滤
- 复位原因记录：每个复位源触发后锁存到 rst_reason 寄存器

**电源侧（pwrmgr）**：
- 低功耗状态机流转（ACTIVE→ISO_ON→PD→WAKE→ACTIVE）
- 唤醒源仲裁
- isolation 控制时序（PD 期间 iso=1，唤醒后 iso=0）

**项目佐证**：G100 CRG 的 VFL 一共 30+ 个功能点，每个对应一个 vseq。比如 clkmgr 的 glitch-free mux 验证用 `clkmgr_mux_vseq` 在 pll_clk 和 osc_clk 之间反复切，配合 SVA 检查输出无毛刺。

---

## Q3. glitch-free clock mux 是什么原理？怎么验？

**标准答案**：
普通 mux 直接用 sel 选 clka/clkb，当 sel 变化时如果正好在一个时钟的高电平中段，输出会瞬间被切走产生 runt pulse。glitch-free mux 的标准做法：

1. sel 先在 clka 域打 2 拍同步得到 sel_a，在 clkb 域打 2 拍同步得到 sel_b（注意 clkb 同步的是反向 sel）
2. **ena = sel_a 用 clka 的 negedge 锁存**，**enb = sel_b 用 clkb 的 negedge 锁存**
3. `clk_out = (clka & ena) | (clkb & enb)`

关键点是**用 negedge 锁存 enable**——这样 enable 只在时钟低电平时变化，永远不可能截断一个高电平。

**项目佐证**：G100 clkmgr 里 `clkmgr_mux.sv` 就是这个结构。验证用 `clkmgr_mux_vseq` 反复切换 sel，配合 `clkmgr_bind.sv` 的 SVA 检查 mux 输出有没有 runt pulse（连续的 $rose → $fell 在 1ns 内算 glitch）。

**加分点**：主动提"如果实现错了 ena_q 的锁存沿（比如写成 posedge），切 mux 时就会出 runt，这种 bug 用仿真器跑很久都不一定撞上，但 SVA 监控器一抓一个准"——暗示你验出过类似 bug。

---

## Q4. 异步复位同步释放是什么？为什么复位释放要同步？

**标准答案**：
异步复位同步释放（async assert, sync deassert）是 CRG 的标准做法，用 2 级 FF：

```
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin ff1 <= 0; ff2 <= 0; end   // 异步断言：立即生效
    else begin ff1 <= 1; ff2 <= ff1; end         // 同步释放：1 移位 2 拍
end
sync_rst_n = ff2;
```

**为什么要同步释放？** 复位 assert 是异步的（任何时刻 rst_n=0 立即触发，让所有 FF 进复位态，安全）；但**复位释放必须同步**——如果释放时机正好在 clk 边沿附近，恢复时间和移除时间违例，部分 FF 可能跳出复位态、部分还在复位态，导致 metastability 和不同步的设计行为（这是 RTL 仿真看不到，但流片后真实硅片会出的 bug）。

**项目佐证**：G100 rstmgr 的 `rstmgr_sync.sv` 就是这个结构。验证用 `rstmgr_sync_vseq` 反复触发复位，SVA 检查 `sync_rst_n` 的 $rose 只能发生在 cpu_clk posedge 后的下一拍。

**加分点**：提"如果是单 FF 同步器，复位释放那一拍还是有 metastability 风险；2 FF 是工业标准，3 FF 用于特别高频或对可靠性要求极高的场景"。

---

## Q4b. 复位树怎么设计？多个时钟域怎么处理？

**标准答案**：
复位树和时钟树结构对称——每个时钟域对应一个独立的复位同步器。G100 有 10 个叶子时钟，对应 8 个复位域（gmac_rx 是外部异步不单独复位，cpu_aclk 共享 cpu_core 域）。

设计：
1. **多源 AND**：POR/WDG/DBG/SW/低压检测/安全违规 6 个异步源 AND 成 tree_rst_n
2. **毛刺滤波**：tree_rst_n 过 glitch_filter（threshold 可配，过滤 < N 周期的毛刺）
3. **每域独立同步**：8 个 rstmgr_sync 实例，每个用自己的域时钟做"异步复位同步释放"
4. **复位原因锁存**：7-bit 寄存器记录是哪个源触发的，SoC 启动后软件可查询

**为什么要每域独立同步？** 如果所有域共用一个同步器，那个同步器的输出要扇出到所有域——但每个域时钟不同，扇出过程中可能再次产生 metastability。每域一个独立同步器，让同步发生在目标域本地，最稳。

**项目佐证**：G100 rstmgr 有 8 个 rstmgr_sync 实例（cpu_core/cpu_aclk/axi_main/ddr_ref/ahb/periph/gmac/qspi），每个接对应域时钟。`rstmgr_sync_vseq` 验证：tree_rst_n 释放后，每个域的 sync_rst_n 只在该域 clk posedge 后 1~2 拍才释放。

**加分点**：提"复位原因锁存很有用——芯片回片后如果用户报'机器死机重启'，软件读 rst_reason 就知道是 WDG 超时、低压检测还是安全违规触发的，不用现场 debug"。

---

## Q5. 你怎么验复位值正确？uvm_reg 怎么做？

**标准答案**：
复位值验证是 CRG 验证的核心之一。用 uvm_reg 的 `mirror()` 配合 `UVM_CHECK` 模式：

```systemverilog
regmodel.reset("HARD");   // 把 reg model 的期望值设为 spec reset value
regmodel.glitch_th.mirror(status, UVM_CHECK, UVM_FRONTDOOR, null, this);
// 内部：发起一次读 → 比对读回值 vs reg model 期望值 → 不等就 UVM_ERROR
```

这要求每个 field 在 `configure()` 时必须传入正确的 reset value。如果 RTL 复位值和 reg model 配的 spec 值不一致，mirror 就报错。

**项目佐证**：G100 rstmgr 的 `RST_GLITCH_TH` 寄存器 spec 复位值是 4，但 RTL 读回路径有 bug 返回 `th+1`（5）。`rstmgr_common_vseq` 跑 `csr_hw_reset` 时，mirror 读到 5 vs 期望 4 → UVM_ERROR，bug 被抓出来。

**加分点**：提"除了 mirror，还跑 csr_bit_bash（每个 RW bit 单独写 1/0/读回）和 csr_aliasing（写一个 reg 不能影响别的 reg），这三个序列是 UVM 寄存器验证的标准三件套"。

---

## Q6. PLL 怎么验？lock 时间怎么测？

**标准答案**：
PLL 验证有几层：
1. **整数模式**：`Fvco = Fref * fbdiv / refdiv`，`Fout = Fvco / (p1*p2)`，lock 后输出周期严格等于这个值
2. **分数模式**：`Fvco = Fref * (fbdiv + frac/2^24) / refdiv`，引入小数分频
3. **lock 过程**：cfg 改变后 lock 立即变 0，经过 N 个 ref 周期后 lock 变 1（N 与 refdiv*fbdiv 成正比，模拟真实模拟 PLL 的相位锁定时间）
4. **失锁恢复**：重复触发 cfg 变化，验证每次都能正确 re-lock

**lock 时间测量**：从 cfg write 完成（用 phase objection 锚点）到 pll_status.lock 读到 1 的 cycle 数 × ref_period。

**项目佐证**：G100 的 PLL 是行为模型（`clkmgr_pll.sv`），lock FSM 用计数器模拟真实锁定时间。`clkmgr_frequency_vseq` 验证整数和分数模式。scoreboard 的 `predict_pll_period()` 按 spec 公式独立算期望周期，与 monitor 实测的周期对比，超 5% tolerance 报错。

**加分点**：主动说"分数模式如果分母写错（比如 2^23 而不是 2^24），频率会翻倍，这种 bug 用直接波形看不出，必须靠 scoreboard 比对理论值"——暗示你验出过这种 bug。

---

## Q7. ICG cell 是什么？enable 的时序要求？

**标准答案**：
ICG（Integrated Clock Gating）是标准单元库提供的门控时钟单元，低功耗设计必备。原理：

```
en_latched = 在 clk 的 negedge 锁存 gate_en
clk_out = clk & en_latched
```

**为什么要 negedge 锁存？** gate_en 是组合逻辑产生的，可能在 clk 高电平期间变化。如果直接 `clk_out = clk & gate_en`，gate_en 在 clk 高电平变 0 时，clk_out 立即被切走，产生 runt pulse。**negedge 锁存**保证 en_latched 只在 clk 低电平时更新，永远不截断高电平。

**项目佐证**：G100 clkmgr 的 `clkmgr_gate.sv` 是 ICG 行为模型。验证用 `clkmgr_gate_vseq` 快速翻转 gate_en 制造"中途切换"场景，SVA 检查 clk_out 的每个高电平脉冲宽度 ≥ 半个周期。

**加分点**：提"综合时 DC 会自动识别这种 latch + AND 的模式，映射到 ICG 标准单元；如果 RTL 写错（用 posedge latch），DC 会映射失败，功耗优化效果大打折扣"。

---

## Q8. 你的参考模型怎么和 DUT 解耦？

**标准答案**：
解耦的核心原则：**参考模型只能读寄存器配置和外部激励，绝不能通过 `uvm_hdl_read` 读 DUT 内部信号**。否则 DUT 错了 checker 也跟着错。

G100 的实现：clkmgr scoreboard 的 `predict_pll_period()` 只读 reg model 里的 `refdiv/fbdiv/dsmen/frac/postdiv1/postdiv2`，按 spec 公式算期望周期。Monitor 独立测真实 clk_out 周期。Scoreboard 比对两者，超 tolerance 报错。

```
ref_model (读 reg 配置 → 算期望)
                    ↓
              scoreboard ← 比对
                    ↑
monitor (测 DUT 真实输出)
```

**项目佐证**：早期版本参考模型用 `uvm_hdl_read` 读 PLL 内部 lock 信号判断是否该输出周期，结果 PLL lock 逻辑错了 checker 也跟着错，bug 抓不出来。后来重构成纯算法预测。

**加分点**：主动说"这是从开源项目 svk_crg_test 学到的反面教训——它就是用 DUT 自身当 reference，所以即使 DUT 有 bug 也永远 self-consistent，验不出真问题"。

---

## Q9. 覆盖率怎么收？covergroup 怎么设计？

**标准答案**：
两层覆盖率：
- **代码覆盖率**：line/cond/fsm/toggle/branch，工具自动收（VCS `-cm`）
- **功能覆盖率**：covergroup 手写，验的不是"代码跑没跑"，而是"组合场景跑没跑"

CRG 的 covergroup 设计要点：
- PLL 配置交叉：bypass × dsmen × postdiv1 × postdiv2（4 维交叉，确保各种组合都跑过）
- 分频比桶：[1:16]/[17:64]/[65:128]/[129:255]（按真实频率范围分桶）
- 复位控制：cpu_rst_n × gpu_rst_n × ddr_rst_n（3 维交叉，每个域独立复位/不复位的 8 种组合）
- mux 选择：cpu_sel × gpu_sel × ddr_sel

**项目佐证**：G100 clkmgr 的 `clkmgr_env_cov.sv` 定义了 4 个 covergroup（PLL/div/gate/mux），每个 IP 都有类似覆盖。

**加分点**：提"功能覆盖率的设计关键是 cover 感兴趣的'组合'而不是单个值——单个值用代码覆盖率就够，covergroup 的价值在于 cross"。

---

## Q10. 你印象最深的 bug 是什么？怎么定位的？

**项目佐证**：选 1~2 个讲（按面试时间决定讲几个）

**BUG_002（PLL frac 频率翻倍）**：
- 现象：分数模式 PLL 锁定后输出频率是 spec 的 2 倍
- 定位：scoreboard 报错 `pll_clk period=Xns exp=Yns (tol 5%)`，差正好 2 倍 → 怀疑分母。grep `2^23` 找到 `clkmgr_pll.sv` 的 `fbdiv_eff = fbdiv + frac/2.0**23`，spec 是 `2^24`。
- 修复：改成 `2^24`。
- 教训：**数学细节 bug 用直接波形看不出来**，必须靠 scoreboard 比对理论值。

**BUG_005（glitch_th 读回值错）**：
- 现象：写 RST_GLITCH_TH=4，读回返回 5
- 定位：`csr_hw_reset` 序列报 mirror mismatch，期望 4 读到 5。看 RTL 读 mux 发现 `assign glitch_th_readback = rst_glitch_th_q[7:0] + 8'd1`，多了一个 +1。
- 修复：删掉 `+1`。
- 教训：**CSR 合规三件套是性价比最高的验证**，几行序列就能抓出所有寄存器读写路径 bug。

**BUG_001（glitch-free mux 毛刺）**：
- 现象：切 mux 时偶发 runt pulse
- 定位：SVA `clkmgr_bind.sv` 报 glitch。看 RTL 发现 `enb_q` 用 `posedge clkb` 锁存（应该用 negedge）。
- 修复：改成 negedge clkb。
- 教训：**这种 bug 跑随机用例要很久才撞上**，SVA 监控器持续在线才能稳定抓到。

---

## Q11. UT 和 ST 分层有什么好处？

**标准答案**：
UT（单元测试）和 ST（系统测试）分层是我做的 CRG 验证的核心方法学，好处：

1. **UT 定位快**：DUT 范围小，问题肯定在这个 IP 内。clkmgr UT 失败了不会怀疑 rstmgr。
2. **ST 验集成**：单 IP 都对了不代表集成对。pwrmgr 关 clkmgr 时钟后，rstmgr 的同步器可能因为没时钟卡死——这种 bug 只有 ST 能发现。
3. **覆盖率独立收**：UT 的功能覆盖率针对单 IP 设计，颗粒度细；ST 的覆盖率针对跨 IP 场景。
4. **回归速度**：UT 编译快、跑得快，CI 每次提交都跑；ST 跑得慢，每晚跑。

**项目佐证**：G100 三个 IP 各有 UT，每个 UT 跑 smoke/common/feature/stress 共 6~8 个 vseq。ST 跑 smoke/lowpower/reset_storm/stress 4 个 vseq。

**加分点**：提"我把 clkmgr/rstmgr/pwrmgr 三个 IP 各自做 UT 放在 ut/ 目录下，SoC 顶层 ST 放在 st/ 目录下，目录组织本身就体现了分层思想。比如 clkmgr UT 验 3 个 PLL 独立 lock、5:1 mux 切换、10 个叶子频率；ST 验 pwrmgr 触发低功耗后 clkmgr 关时钟、rstmgr 的 8 个域同步器在没时钟时怎么处理——这种跨模块时序只有 ST 能暴露"。

---

## Q12. 怎么处理 PLL 等异步/模拟模块的验证？

**标准答案**：
真实 PLL 是模拟 IP，验证时用行为模型代替（数字 RTL 无法仿真模拟电路）。行为模型要保留：
- **lock 时间**：用计数器模拟锁定延迟（N 个 ref 周期）
- **lock 状态机**：unlocked → locking → locked，cfg 变化触发 re-lock
- **频率计算**：按 spec 公式算输出周期
- **抖动（可选）**：加 ±N% 随机抖动模拟真实 PLL 的 phase noise

行为模型本身也需要被验证——所以参考模型还得独立再算一遍期望值，和 DUT 行为模型对比。

**项目佐证**：G100 `clkmgr_pll.sv` 是行为模型，包含 lock FSM + 频率公式。scoreboard 的 `predict_pll_period()` 独立按 spec 算，验证行为模型正确。

---

## Q13. 你怎么用 SVA？跟 monitor 比有什么优势？

**标准答案**：
SVA（SystemVerilog Assertions）和 UVM monitor 互补：
- **Monitor**：采样信号、发 transaction、做复杂比对，灵活但慢
- **SVA**：声明式时序断言，直接绑到 DUT 内部节点，**always-on** 不消耗 UVM phase 开销，跑得快

适合 SVA 的场景：
- 时序性质：`$rose(sync_rst_n) |-> $past(!sync_rst_n)`（复位释放只在 posedge 后）
- 协议性质：APB 的 setup→access 时序
- 不变量：clk_out 高电平脉冲宽度 ≥ 半个周期

**项目佐证**：G100 的 `clkmgr_bind.sv` 用 bind 把 SVA 模块绑到 ICG 实例上，检查 gated clock 的 runt pulse；`rstmgr_bind.sv`（如果有的话）检查 reset 同步释放。

**加分点**：提"SVA 是 always-on 的，跑任何用例都在线，特别适合抓那种'偶发'的时序 bug；monitor 要专门写用例去触发它才看得到"。

---

## Q14. 跑了多少种子？怎么处理随机回归的失败？

**标准答案**：
- 单测：`+ntb_random_seed=1` 到 `+ntb_random_seed=100`，跑 100 种子回归
- 失败定位：用 `verdi -dbdir simv.daidir -ssf waves.fsdb` 打开波形看失败点
- 如果是 DUT bug：报 Jira，等 RTL 修
- 如果是 reference/tb bug：本地修，回归重跑

**项目佐证**：G100 的 `crg_top_stress_vseq` 用 20 次随机配置 + 随机间隔，主要为了撞 corner case。

---

## 应急：如果被问到没准备的问题

1. **CRG 验证流程**：先写 VFL（验证功能点列表）→ 写验证策略文档 → 搭 env → 写 vseq → 跑回归 → 收覆盖率 → 出验证报告
2. **遇到的最复杂的 bug**：选 BUG_002（PLL frac 频率）讲——数学细节，难发现，定位逻辑严密
3. **团队协作**：跟 RTL 设计对 spec、跟架构对 VFL、跟项目经理报进度
4. **如果会 verilog**：可以说"参考模型的算法部分自己写过 RTL，方便对照"
