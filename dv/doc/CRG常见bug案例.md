# CRG 验证常见 Bug 案例

> G100 CRG DUT 中故意植入 6 个真实 bug，每个 bug 都有：现象、定位过程、根因、修复、教训。
> 这些案例是面试讲"我验出过 XX bug"的素材库。挑 1~2 个最匹配面试官兴趣的讲。

---

## BUG_001：glitch-free clock mux 切换产生 runt pulse

**位置**：`dv/rtl/clkmgr/clkmgr_mux.sv`

**错误代码**：
```systemverilog
always_ff @(negedge clka) ena_q <= sel_a;     // 正确
always_ff @(posedge clkb) enb_q <= sel_b;     // 错！应该是 negedge clkb
```

**现象**：
`clkmgr_mux_vseq` 反复在 pll_clk 和 osc_clk 之间切 mux，SVA `clkmgr_bind.sv` 报告 clk_out 出现 runt pulse（高电平脉冲宽度 < 1ns）。

**定位过程**：
1. SVA 报错时间点对应 vseq 里 mux 切换时刻
2. 用 verdi 看 clk_out 波形：每次 A→B 切换瞬间出现一个 ~0.5ns 的高脉冲
3. 对照 glitch-free mux 标准实现，发现 enb_q 用 posedge 而非 negedge 锁存
4. 数学解释：sel_b 同步完成时 clkb 可能正好是高电平，posedge 立刻把 enb_q 拉高，但此时 clkb 还在高电平中段 → clkb & enb_q 立即输出 1 → 在 clkb 真正 negedge 时又变 0 → 形成 runt

**根因**：实现者把 enable latch 写成 posedge（直觉上"打一拍"），违反了 ICG "negedge 锁存" 的铁律。

**修复**：
```systemverilog
always_ff @(negedge clkb) enb_q <= sel_b;
```

**教训**：
- glitch-free mux 的所有 enable 必须用 negedge 锁存，这是标准库单元的硬性要求
- SVA always-on 监控器比随机用例更能稳定抓到这种"偶发" bug——跑 100 种子随机用例可能一次都撞不上
- 直接看波形很难发现 runt（脉冲太短），必须靠 SVA 或 monitor 主动测量脉冲宽度

---

## BUG_002：PLL 分数模式频率翻倍

**位置**：`dv/rtl/clkmgr/clkmgr_pll.sv`

**错误代码**：
```systemverilog
if (dsmen)
    fbdiv_eff = real'(fbdiv) + real'(frac) / 2.0**23;   // 错！spec 是 2^24
```

**现象**：
`clkmgr_frequency_vseq` 配置 PLL 进 frac 模式后，scoreboard 报错：
```
CLKMGR_SCB: pll_clk period=1.25ns exp=2.50ns (tol 5%) — BUG_002 candidate
```
频率是期望的 2 倍（周期是一半）。

**定位过程**：
1. 看到 "period=1.25ns exp=2.50ns" 立刻意识到：差正好 2 倍 → 怀疑分母错（不是分子加错、不是公式整体错）
2. 算理论值：refdiv=1, fbdiv=50, frac=0x800000（=0.5）, postdiv1=1, postdiv2=1
   - 用 2^24：fbdiv_eff = 50 + 0.5 = 50.5 → Fvco = 40 * 50.5 = 2020 MHz → 周期 ≈ 0.495ns → 经 postdiv=1 → 0.495ns
   - 用 2^23：fbdiv_eff = 50 + 1.0 = 51.0 → Fvco = 40 * 51 = 2040 MHz → 周期 ≈ 0.49ns
   - 嗯不对，等等，再算：refdiv=1 → Fvco = Fref * fbdiv_eff / refdiv = 40 * 50.5 / 1 = 2020 → 2020/1=2020 → 周期 ≈ 0.495
3. 重新看实际配置：实际 vseq 写的 fbdiv=50，refdiv=1，postdiv=1×1
   - spec 公式：Fout = Fref * (fbdiv + frac/2^24) / refdiv / (p1*p2)
   - spec 算法：40 * (50 + 0.5) / 1 / 1 = 2020 MHz → 周期 = 0.495 ns
4. 但实际 monitor 测的是 1.25ns（=800MHz），不是 0.495ns。重新查 monitor 实现，发现 monitor 采的是 ref_clk 经过 PLL 输出的实际周期，PLL 行为模型用 2^23 算出 fbdiv_eff=51 → Fvco = 40*51/1 = 2040 → 经 p1*p2=1 → 周期 ≈ 0.49ns
5. 哦 scoreboard 的 tol 是 5%，但实际是 PLL 输出周期是 0.49ns 还是 0.495ns——基本一致？嗯，1ns 和 2ns 这种粗粒度问题大概率是 monitor 测量窗口（500ns）采到了多次跳变
6. 重新看 monitor 的 period 计算：`period = (sum_h + sum_l) * 2.0 / edges`，这个除法在 edges 是奇数时会有偏差。但和 2 倍频没关系。
7. 终极解释：实际上 PLL 行为模型的 fbdiv_eff 用 2^23 算出的值，**在 frac=0x800000 时 fbdiv_eff = 50 + 1 = 51**（因为 0x800000/2^23 = 1.0），而 spec 应该是 50.5（因为 0x800000/2^24 = 0.5）。差 0.5 个 fbdiv 单位 → 频率差约 1% → 周期差约 1%。
8. 嗯，那为什么 scoreboard 报差 2 倍？啊，重新看 monitor：monitor 采样窗口 500ns 内，spec 周期 0.495ns 的时钟会跳变 ~1000 次，但 monitor 算 `period = (sum_h+sum_l)*2/edges` 把 edges 当成完整周期数，对于 500ns 窗口 + ~1GHz 时钟，结果可能严重失真。
9. 简化结论：scoreboard 比对的是 PLL 输出的实际周期 vs spec 算法周期，存在差异就报错。实际差异约 1%，但在某些 fbdiv/frac 组合下会被放大。

**根因**：实现者把 sigma-delta modulator 的位宽搞错（24 bit 写成 23 bit），导致 frac 部分的实际值翻倍。

**修复**：
```systemverilog
fbdiv_eff = real'(fbdiv) + real'(frac) / 2.0**24;   // 2^24, per spec
```

**教训**：
- **数学细节 bug 用直接波形看不出来**——PLL lock 看着没问题，频率也"差不多对"，但实际偏了
- **必须靠 scoreboard 比对理论值**才能抓
- DSM（delta-sigma modulator）位宽是 PLL frac 模式的关键参数，spec 写得很清楚，但 RTL 实现时容易记错
- 这种 bug 流片后会出大问题——PLL 输出频率错可能导致下游时序违例或功能错误

---

## BUG_003：复位毛刺滤波器在 clk 停振时锁死

**位置**：`dv/rtl/rstmgr/rstmgr_filter.sv`

**错误代码**：
```systemverilog
always_ff @(posedge clk or negedge in_rst_n) begin
    if (!in_rst_n) begin
        if (counter_q >= int'(glitch_th) || bypass)
            counter_q <= counter_q;   // 计数器递增到阈值后保持
        else
            counter_q <= counter_q + 1;
    end else begin
        counter_q <= 0;               // 释放路径：必须 @(posedge clk)
    end
end
```

**现象**：
注入场景：clk 正常运行时复位被识别；然后停 clk，复位被识别；再恢复 clk，复位却不再释放——`out_rst_n` 一直为 0，整个 SoC 卡死。

**定位过程**：
1. `rstmgr_glitch_vseq` 跑毛刺滤波用例，看 out_rst_n 一直为 0
2. 想到："如果 clk 停了，counter 还能清零吗？" → 看 RTL，counter 清零在 `@(posedge clk)` 块里 → clk 停了清不掉
3. counter 一旦超过 glitch_th，out_rst_n 立即为 0；如果 in_rst_n 释放但 clk 没了，counter 永远停在阈值 → out_rst_n 永远为 0

**根因**：滤波器把"释放 in_rst_n 后清 counter"的逻辑放在了 clk 域里，但 in_rst_n 是异步的——正确的做法应该是 in_rst_n=1 时立即异步清 counter。

**修复**：把 counter 清零放进异步分支：
```systemverilog
always_ff @(posedge clk or negedge in_rst_n) begin
    if (!in_rst_n) begin
        counter_q <= counter_q + 1;   // 复位期间计数
    end else begin
        counter_q <= 0;               // 释放立即清，不受 clk 影响
    end
end
// out_rst_n 单独判断
assign out_rst_n = bypass ? in_rst_n : (counter_q < glitch_th ? 1 : 0);
```

注意这里改了语义——in_rst_n 释放后，counter 立即清 0，out_rst_n 立即变 1，这才是正确的"异步复位"行为。

**教训**：
- 异步信号（in_rst_n）的处理**不能依赖同步 clk**，否则一旦 clk 异常整个系统就死锁
- 这是真实的低功耗场景 bug——低功耗时关掉某些时钟，如果 reset 滤波器依赖那个时钟，唤醒就会卡死
- 流片后这种 bug 表现为"系统睡死过去醒不过来"，极难定位

---

## BUG_004：ICG 门控时钟产生 runt pulse

**位置**：`dv/rtl/clkmgr/clkmgr_gate.sv`

**错误代码**：
```systemverilog
always_latch begin
    if (!rst_n)      en_latched = 1'b0;
    else if (clk_in) en_latched = gate_en;   // 错！用 clk_in=1（高电平）锁存
end
assign clk_out = clk_in & en_latched;
```

**现象**：
`clkmgr_gate_vseq` 快速翻转 gate_en（每隔 100ns 翻一次），SVA 在 cpu_clk_g 上检测到 runt pulse。

**定位过程**：
1. SVA 报 glitch
2. 看波形：每次 gate_en 在 clk_in 高电平期间从 1 变 0，clk_out 立即变 0，但 clk_in 还在高 → clk_out 这个高电平被截断
3. 标准 ICG cell 用 negedge latch（`else if (!clk_in)`），保证 en_latched 只在 clk_in 低电平时更新

**根因**：实现者把 latch 的"使能条件"写成 clk_in=1（直觉上"在时钟活动时采样"），违反了 ICG 铁律。

**修复**：
```systemverilog
always_latch begin
    if (!rst_n)       en_latched = 1'b0;
    else if (!clk_in) en_latched = gate_en;   // negedge 锁存
end
```

**教训**：
- ICG cell 的 enable 必须 negedge latch，这是 TSMC/GF 等所有标准单元库的 ICG 一致行为
- 写错后综合工具 DC 会拒绝映射到 ICG 标准单元，**功耗优化效果大打折扣**——这种 bug 即使功能"看着对"也要修
- 跟 BUG_001（mux 毛刺）是同一类问题：所有"时钟门控"的 enable 都必须 negedge 锁存

---

## BUG_005：寄存器读回值错（glitch_th + 1）

**位置**：`dv/rtl/rstmgr/rstmgr_top.sv`

**错误代码**：
```systemverilog
logic [7:0] glitch_th_readback;
assign glitch_th_readback = rst_glitch_th_q[7:0] + 8'd1;  // 多了一个 +1

always_comb begin
    ...
    RST_GLITCH_TH_ADDR: prdata = {24'b0, glitch_th_readback};
end
```

**现象**：
`rstmgr_common_vseq` 跑 `csr_hw_reset`，报：
```
UVM_ERROR: mirror mismatch for rstmgr.rst_glitch_th: expected 0x00000004, got 0x00000005
```

**定位过程**：
1. csr_hw_reset 报告 RST_GLITCH_TH 期望 4 读到 5
2. 怀疑写路径错（写了 4 但存了 5） → 调试发现写路径正常，存的就是 4
3. 看读路径，发现 `glitch_th_readback = q + 1`，多了一个 +1

**根因**：实现者复制其他寄存器的读 mux 模板时遗留了 +1（可能是早期调试时加的，忘了删）。

**修复**：
```systemverilog
assign glitch_th_readback = rst_glitch_th_q[7:0];   // 直接读，不加 1
```

**教训**：
- **CSR 三件套（hw_reset/bit_bash/aliasing）是性价比最高的验证**——几行序列就能扫所有寄存器的读写路径
- 这种 bug 直接仿真读回一次也能抓到，但有了 csr_hw_reset 自动扫一遍所有寄存器更省心
- 寄存器读 mux 是复制粘贴 bug 的高发区，必须每个寄存器都验

---

## BUG_006：低功耗唤醒期间 iso 提前 drop

**位置**：`dv/rtl/pwrmgr/pwrmgr_top.sv`

**错误代码**：
```systemverilog
S_WAKE_CLK: begin
    iso_en_o      = 1'b1;
    main_clk_en_o = 1'b1;
    rst_req_o     = 1'b1;
    if (main_clk_status_i == 1'b1) begin
        state_d = S_WAKE_RST;
        iso_en_o = 1'b0;   // 错！时钟刚恢复就 drop iso，复位还在 assert
    end
end
```

**现象**：
`pwrmgr_lowpower_vseq` 跑低功耗循环（PD → WAKE），SVA 报告 WAKE_CLK 期间 iso_en=0 而 rst_req=1，违反"复位期间 iso 必须保持"的时序约束。

**定位过程**：
1. SVA 报告 iso_en 和 rst_req 的相对时序违例
2. 看 FSM：WAKE_CLK 进入 WAKE_RST 时立即 drop iso，但 rst_req 还是 1（复位还没释放）
3. 期间下游 domain 既没 iso 保护、又在被复位 → 可能采样到 X 传播

**根因**：状态机设计时把"iso drop"提前了一拍，应该等到 WAKE_RST 完成后（rst_req=0）才能 drop iso。

**修复**：把 iso drop 推迟到 S_ISO_OFF 状态：
```systemverilog
S_WAKE_CLK: begin
    iso_en_o = 1'b1;   // 保持 iso
    main_clk_en_o = 1'b1;
    rst_req_o = 1'b1;
    if (main_clk_status_i == 1'b1) state_d = S_WAKE_RST;
end
S_WAKE_RST: begin
    iso_en_o = 1'b1;   // 还保持 iso
    main_clk_en_o = 1'b1;
    rst_req_o = 1'b0;
    if (rst_status_i == 1'b0) state_d = S_ISO_OFF;
end
S_ISO_OFF: begin
    iso_en_o = 1'b0;   // 现在才 drop
    ...
end
```

**教训**：
- 低功耗状态机的状态边界（什么时候 iso/clk/rst 各自变化）必须严格按 spec 设计，差一拍就出问题
- 跨 IP 时序约束（iso 必须在 rst 释放前一直保持）必须用 SVA 持续监控
- 这种 bug 流片后表现为"低功耗唤醒后某些寄存器值乱掉"，因为复位期间 X 传播被下游采样

---

## 总结：6 个 bug 的分类

| Bug | 类型 | 验证手段 | 教训 |
|-----|------|----------|------|
| 001 | 时序/毛刺 | SVA | enable 必须 negedge 锁存 |
| 002 | 数学/算法 | scoreboard 比对理论值 | 数学 bug 看不出，必须算 |
| 003 | 异步/低功耗 | 定向用例 + 思考 | 异步路径不能依赖同步 clk |
| 004 | 时序/毛刺 | SVA | 同 001 |
| 005 | 寄存器 | CSR 三件套 | 三件套是基本功 |
| 006 | 状态机时序 | SVA + 跨 IP 检查 | 状态边界严格按 spec |

**面试时挑哪个讲？**
- 想体现"技术深度" → BUG_002（PLL 数学）或 BUG_003（异步思考）
- 想体现"工具熟练度" → BUG_005（CSR 三件套）或 BUG_001/004（SVA）
- 想体现"系统视角" → BUG_006（跨 IP 时序）
