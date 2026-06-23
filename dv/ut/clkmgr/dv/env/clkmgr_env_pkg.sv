/***********************************************************
 * clkmgr_env_pkg - clkmgr UT env (3-PLL clock tree)
 *
 * Reg model: 3 PLLs (each cfg0+cfg1+status), mux, div, gate.
 * Scoreboard: predicts 10 leaf clock periods from reg config, compares
 *             to monitor measurements, reports BUG_002 (PLL frac) on
 *             any leaf whose period diverges from spec.
 *
 * Leaf nodes (id, name):
 *   0 cpu_core_clk   1 cpu_aclk(gated)   2 axi_main_clk   3 ddr_ref_clk
 *   4 ahb_clk        5 apb_clk           6 periph_clk     7 gmac_tx_clk
 *   8 gmac_rx_clk    9 qspi_ref_clk
 ************************************************************/
`ifndef CLKMGR_ENV_PKG__SV
`define CLKMGR_ENV_PKG__SV

`include "apb_if.sv"
`include "clk_rst_if.sv"

package clkmgr_env_pkg;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import csr_utils_pkg::*;
    import crg_base_pkg::*;
    import crg_reg_map_pkg::*;

    // ---- Leaf node ids ----
    typedef enum int {
        LEAF_CPU_CORE = 0, LEAF_CPU_ACLK = 1, LEAF_AXI_MAIN = 2, LEAF_DDR_REF = 3,
        LEAF_AHB = 4, LEAF_APB = 5, LEAF_PERIPH = 6, LEAF_GMAC_TX = 7,
        LEAF_GMAC_RX = 8, LEAF_QSPI_REF = 9
    } leaf_e;

    // ---- Generic registers ----
    class clkmgr_reg extends uvm_reg;
        `uvm_object_utils(clkmgr_reg)
        function new(string name="clkmgr_reg", int unsigned n_bits=32);
            super.new(name, n_bits, UVM_NO_COVERAGE);
        endfunction
    endclass
    class clkmgr_reg_wide extends uvm_reg;
        `uvm_object_utils(clkmgr_reg_wide)
        function new(string name="clkmgr_reg_wide", int unsigned n_bits=32);
            super.new(name, n_bits, UVM_NO_COVERAGE);
        endfunction
    endclass

    // ---- Reg block ----
    class clkmgr_reg_block extends uvm_reg_block;
        `uvm_object_utils(clkmgr_reg_block)

        clkmgr_reg      pll_cpu_cfg0_r,  pll_cpu_cfg1_r,  pll_cpu_status_r;
        clkmgr_reg      pll_soc_cfg0_r,  pll_soc_cfg1_r,  pll_soc_status_r;
        clkmgr_reg      pll_peri_cfg0_r, pll_peri_cfg1_r, pll_peri_status_r;
        clkmgr_reg      mux_cfg_r, div_cfg_r, gate_cfg_r;

        rand uvm_reg_field pll_cpu_bypass, pll_cpu_refdiv, pll_cpu_fbdiv;
        rand uvm_reg_field pll_cpu_dsmen, pll_cpu_frac, pll_cpu_pd1, pll_cpu_pd2;
        uvm_reg_field pll_cpu_lock;
        rand uvm_reg_field pll_soc_bypass, pll_soc_refdiv, pll_soc_fbdiv;
        rand uvm_reg_field pll_soc_dsmen, pll_soc_frac, pll_soc_pd1, pll_soc_pd2;
        uvm_reg_field pll_soc_lock;
        rand uvm_reg_field pll_peri_bypass, pll_peri_refdiv, pll_peri_fbdiv;
        rand uvm_reg_field pll_peri_dsmen, pll_peri_frac, pll_peri_pd1, pll_peri_pd2;
        uvm_reg_field pll_peri_lock;
        rand uvm_reg_field mux_d0, mux_d1, mux_d2;
        rand uvm_reg_field div_d0_ratio, div_d0_half, div_d1_ratio, div_d1_half, div_d2_ratio, div_d2_half;
        rand uvm_reg_field gate_en;

        virtual function void build();
            // create regs
            pll_cpu_cfg0_r   = clkmgr_reg::type_id::create("pll_cpu_cfg0");   pll_cpu_cfg0_r.configure(this);
            pll_cpu_cfg1_r   = clkmgr_reg::type_id::create("pll_cpu_cfg1");   pll_cpu_cfg1_r.configure(this);
            pll_cpu_status_r = clkmgr_reg::type_id::create("pll_cpu_status"); pll_cpu_status_r.configure(this);
            pll_soc_cfg0_r   = clkmgr_reg::type_id::create("pll_soc_cfg0");   pll_soc_cfg0_r.configure(this);
            pll_soc_cfg1_r   = clkmgr_reg::type_id::create("pll_soc_cfg1");   pll_soc_cfg1_r.configure(this);
            pll_soc_status_r = clkmgr_reg::type_id::create("pll_soc_status"); pll_soc_status_r.configure(this);
            pll_peri_cfg0_r  = clkmgr_reg::type_id::create("pll_peri_cfg0");  pll_peri_cfg0_r.configure(this);
            pll_peri_cfg1_r  = clkmgr_reg::type_id::create("pll_peri_cfg1");  pll_peri_cfg1_r.configure(this);
            pll_peri_status_r= clkmgr_reg::type_id::create("pll_peri_status");pll_peri_status_r.configure(this);
            mux_cfg_r        = clkmgr_reg::type_id::create("mux_cfg");        mux_cfg_r.configure(this);
            div_cfg_r        = clkmgr_reg::type_id::create("div_cfg");        div_cfg_r.configure(this);
            gate_cfg_r       = clkmgr_reg::type_id::create("gate_cfg");       gate_cfg_r.configure(this);

            // PLL_CPU cfg0: bypass[0], refdiv[7:2], fbdiv[15:8]
            pll_cpu_bypass = uvm_reg_field::type_id::create("pll_cpu_bypass");
            pll_cpu_refdiv = uvm_reg_field::type_id::create("pll_cpu_refdiv");
            pll_cpu_fbdiv  = uvm_reg_field::type_id::create("pll_cpu_fbdiv");
            pll_cpu_bypass.configure(pll_cpu_cfg0_r, 1, 0,  "RW", 0, PLL_CPU_CFG0_RST[0],     1, 1, 1);
            pll_cpu_refdiv.configure(pll_cpu_cfg0_r, 6, 2,  "RW", 0, PLL_CPU_CFG0_RST[7:2],   1, 1, 1);
            pll_cpu_fbdiv .configure(pll_cpu_cfg0_r, 8, 8,  "RW", 0, PLL_CPU_CFG0_RST[15:8],  1, 1, 1);
            // PLL_CPU cfg1: dsmen[0], frac[25:2], pd1[28:26], pd2[31:29]
            pll_cpu_dsmen = uvm_reg_field::type_id::create("pll_cpu_dsmen");
            pll_cpu_frac  = uvm_reg_field::type_id::create("pll_cpu_frac");
            pll_cpu_pd1   = uvm_reg_field::type_id::create("pll_cpu_pd1");
            pll_cpu_pd2   = uvm_reg_field::type_id::create("pll_cpu_pd2");
            pll_cpu_dsmen.configure(pll_cpu_cfg1_r, 1,  0, "RW", 0, PLL_CPU_CFG1_RST[0],     1, 1, 1);
            pll_cpu_frac .configure(pll_cpu_cfg1_r, 24, 2, "RW", 0, PLL_CPU_CFG1_RST[25:2],  1, 1, 1);
            pll_cpu_pd1  .configure(pll_cpu_cfg1_r, 3, 26, "RW", 0, PLL_CPU_CFG1_RST[28:26], 1, 1, 1);
            pll_cpu_pd2  .configure(pll_cpu_cfg1_r, 3, 29, "RW", 0, PLL_CPU_CFG1_RST[31:29], 1, 1, 1);
            pll_cpu_lock = uvm_reg_field::type_id::create("pll_cpu_lock");
            pll_cpu_lock.configure(pll_cpu_status_r, 1, 0, "RO", 1, 0, 1, 0, 1);

            // PLL_SOC (same layout)
            pll_soc_bypass = uvm_reg_field::type_id::create("pll_soc_bypass");
            pll_soc_refdiv = uvm_reg_field::type_id::create("pll_soc_refdiv");
            pll_soc_fbdiv  = uvm_reg_field::type_id::create("pll_soc_fbdiv");
            pll_soc_bypass.configure(pll_soc_cfg0_r, 1, 0,  "RW", 0, PLL_SOC_CFG0_RST[0],     1, 1, 1);
            pll_soc_refdiv.configure(pll_soc_cfg0_r, 6, 2,  "RW", 0, PLL_SOC_CFG0_RST[7:2],   1, 1, 1);
            pll_soc_fbdiv .configure(pll_soc_cfg0_r, 8, 8,  "RW", 0, PLL_SOC_CFG0_RST[15:8],  1, 1, 1);
            pll_soc_dsmen = uvm_reg_field::type_id::create("pll_soc_dsmen");
            pll_soc_frac  = uvm_reg_field::type_id::create("pll_soc_frac");
            pll_soc_pd1   = uvm_reg_field::type_id::create("pll_soc_pd1");
            pll_soc_pd2   = uvm_reg_field::type_id::create("pll_soc_pd2");
            pll_soc_dsmen.configure(pll_soc_cfg1_r, 1,  0, "RW", 0, PLL_SOC_CFG1_RST[0],     1, 1, 1);
            pll_soc_frac .configure(pll_soc_cfg1_r, 24, 2, "RW", 0, PLL_SOC_CFG1_RST[25:2],  1, 1, 1);
            pll_soc_pd1  .configure(pll_soc_cfg1_r, 3, 26, "RW", 0, PLL_SOC_CFG1_RST[28:26], 1, 1, 1);
            pll_soc_pd2  .configure(pll_soc_cfg1_r, 3, 29, "RW", 0, PLL_SOC_CFG1_RST[31:29], 1, 1, 1);
            pll_soc_lock = uvm_reg_field::type_id::create("pll_soc_lock");
            pll_soc_lock.configure(pll_soc_status_r, 1, 0, "RO", 1, 0, 1, 0, 1);

            // PLL_PERI (same layout)
            pll_peri_bypass = uvm_reg_field::type_id::create("pll_peri_bypass");
            pll_peri_refdiv = uvm_reg_field::type_id::create("pll_peri_refdiv");
            pll_peri_fbdiv  = uvm_reg_field::type_id::create("pll_peri_fbdiv");
            pll_peri_bypass.configure(pll_peri_cfg0_r, 1, 0,  "RW", 0, PLL_PERI_CFG0_RST[0],     1, 1, 1);
            pll_peri_refdiv.configure(pll_peri_cfg0_r, 6, 2,  "RW", 0, PLL_PERI_CFG0_RST[7:2],   1, 1, 1);
            pll_peri_fbdiv .configure(pll_peri_cfg0_r, 8, 8,  "RW", 0, PLL_PERI_CFG0_RST[15:8],  1, 1, 1);
            pll_peri_dsmen = uvm_reg_field::type_id::create("pll_peri_dsmen");
            pll_peri_frac  = uvm_reg_field::type_id::create("pll_peri_frac");
            pll_peri_pd1   = uvm_reg_field::type_id::create("pll_peri_pd1");
            pll_peri_pd2   = uvm_reg_field::type_id::create("pll_peri_pd2");
            pll_peri_dsmen.configure(pll_peri_cfg1_r, 1,  0, "RW", 0, PLL_PERI_CFG1_RST[0],     1, 1, 1);
            pll_peri_frac .configure(pll_peri_cfg1_r, 24, 2, "RW", 0, PLL_PERI_CFG1_RST[25:2],  1, 1, 1);
            pll_peri_pd1  .configure(pll_peri_cfg1_r, 3, 26, "RW", 0, PLL_PERI_CFG1_RST[28:26], 1, 1, 1);
            pll_peri_pd2  .configure(pll_peri_cfg1_r, 3, 29, "RW", 0, PLL_PERI_CFG1_RST[31:29], 1, 1, 1);
            pll_peri_lock = uvm_reg_field::type_id::create("pll_peri_lock");
            pll_peri_lock.configure(pll_peri_status_r, 1, 0, "RO", 1, 0, 1, 0, 1);

            // mux: d0[1:0], d1[3:2], d2[5:4]
            mux_d0 = uvm_reg_field::type_id::create("mux_d0");
            mux_d1 = uvm_reg_field::type_id::create("mux_d1");
            mux_d2 = uvm_reg_field::type_id::create("mux_d2");
            mux_d0.configure(mux_cfg_r, 2, 0, "RW", 0, MUX_CFG_RST[1:0], 1, 1, 1);
            mux_d1.configure(mux_cfg_r, 2, 2, "RW", 0, MUX_CFG_RST[3:2], 1, 1, 1);
            mux_d2.configure(mux_cfg_r, 2, 4, "RW", 0, MUX_CFG_RST[5:4], 1, 1, 1);

            // div: d0_ratio[6:0], d0_half[7], d1_ratio[14:8], d1_half[15], d2_ratio[22:16], d2_half[23]
            div_d0_ratio = uvm_reg_field::type_id::create("div_d0_ratio");
            div_d0_half  = uvm_reg_field::type_id::create("div_d0_half");
            div_d1_ratio = uvm_reg_field::type_id::create("div_d1_ratio");
            div_d1_half  = uvm_reg_field::type_id::create("div_d1_half");
            div_d2_ratio = uvm_reg_field::type_id::create("div_d2_ratio");
            div_d2_half  = uvm_reg_field::type_id::create("div_d2_half");
            div_d0_ratio.configure(div_cfg_r, 7, 0,  "RW", 0, DIV_CFG_RST[6:0],   1, 1, 1);
            div_d0_half .configure(div_cfg_r, 1, 7,  "RW", 0, DIV_CFG_RST[7],     1, 1, 1);
            div_d1_ratio.configure(div_cfg_r, 7, 8,  "RW", 0, DIV_CFG_RST[14:8],  1, 1, 1);
            div_d1_half .configure(div_cfg_r, 1, 15, "RW", 0, DIV_CFG_RST[15],    1, 1, 1);
            div_d2_ratio.configure(div_cfg_r, 7, 16, "RW", 0, DIV_CFG_RST[22:16], 1, 1, 1);
            div_d2_half .configure(div_cfg_r, 1, 23, "RW", 0, DIV_CFG_RST[23],    1, 1, 1);

            // gate: 10 bits
            gate_en = uvm_reg_field::type_id::create("gate_en");
            gate_en.configure(gate_cfg_r, 10, 0, "RW", 0, GATE_CFG_RST[9:0], 1, 1, 1);

            default_map = create_map("default_map", CLKMGR_BASE, 4, UVM_LITTLE_ENDIAN);
            default_map.add_reg(pll_cpu_cfg0_r,   'h00, "RW");
            default_map.add_reg(pll_cpu_cfg1_r,   'h04, "RW");
            default_map.add_reg(pll_cpu_status_r, 'h08, "RO");
            default_map.add_reg(pll_soc_cfg0_r,   'h0C, "RW");
            default_map.add_reg(pll_soc_cfg1_r,   'h10, "RW");
            default_map.add_reg(pll_soc_status_r, 'h14, "RO");
            default_map.add_reg(pll_peri_cfg0_r,  'h18, "RW");
            default_map.add_reg(pll_peri_cfg1_r,  'h1C, "RW");
            default_map.add_reg(pll_peri_status_r,'h20, "RO");
            default_map.add_reg(mux_cfg_r,        'h24, "RW");
            default_map.add_reg(div_cfg_r,        'h28, "RW");
            default_map.add_reg(gate_cfg_r,       'h2C, "RW");
            lock_model();
        endfunction
        function new(string name="clkmgr_reg_block");
            super.new(name, UVM_NO_COVERAGE);
        endfunction
    endclass

    // ---- Sample transaction (monitor -> scoreboard) ----
    class clk_sample_tr extends uvm_object;
        `uvm_object_utils(clk_sample_tr)
        int  leaf_id;
        real period_ns;
        bit  glitch;
        bit  stopped;
        function new(string name="clk_sample_tr"); super.new(name); endfunction
    endclass

    // ---- Scoreboard: multi-leaf period prediction ----
    class clkmgr_scoreboard extends crg_scoreboard;
        `uvm_component_utils(clkmgr_scoreboard)
        clkmgr_reg_block rm;
        real osc_period_ns = 25.0;
        uvm_analysis_imp #(clk_sample_tr, clkmgr_scoreboard) clk_imp;
        function new(string name, uvm_component parent);
            super.new(name, parent); clk_imp = new("clk_imp", this);
        endfunction
        function void write(clk_sample_tr tr);
            real exp = 0, diff; bit has_exp = 1;
            check_count++;
            exp = predict_leaf_period(tr.leaf_id);
            if (tr.glitch) begin
                `uvm_error("CLKMGR_SCB", $sformatf("leaf[%0d] GLITCH (BUG_001/BUG_004 candidate)", tr.leaf_id))
                error_count++;
            end
            if (has_exp && exp > 0) begin
                diff = tr.period_ns - exp; if (diff < 0) diff = -diff;
                if (diff > exp * 0.10 + 1.0) begin  // 10% tolerance
                    `uvm_error("CLKMGR_SCB", $sformatf(
                        "leaf[%0d] period=%0.2fns exp=%0.2fns (BUG_002 candidate: PLL frac 2^23 vs 2^24)",
                        tr.leaf_id, tr.period_ns, exp))
                    error_count++;
                end
            end
        endfunction
        // Predict each leaf's period from reg config.
        function real predict_leaf_period(input int id);
            real pll_cpu_p, pll_soc_p, pll_peri_p;
            real d0_p, d1_p, d2_p;
            pll_cpu_p  = pll_period(rm.pll_cpu_bypass.get(),  rm.pll_cpu_refdiv.get(),
                                     rm.pll_cpu_fbdiv.get(),   rm.pll_cpu_dsmen.get(),
                                     rm.pll_cpu_frac.get(),    rm.pll_cpu_pd1.get());
            pll_soc_p  = pll_period(rm.pll_soc_bypass.get(),  rm.pll_soc_refdiv.get(),
                                     rm.pll_soc_fbdiv.get(),   rm.pll_soc_dsmen.get(),
                                     rm.pll_soc_frac.get(),    rm.pll_soc_pd1.get());
            pll_peri_p = pll_period(rm.pll_peri_bypass.get(), rm.pll_peri_refdiv.get(),
                                     rm.pll_peri_fbdiv.get(),  rm.pll_peri_dsmen.get(),
                                     rm.pll_peri_frac.get(),   rm.pll_peri_pd1.get());
            d0_p = div_apply(domain_select(rm.mux_d0.get(), pll_cpu_p, pll_soc_p, pll_peri_p),
                             rm.div_d0_ratio.get(), rm.div_d0_half.get());
            d1_p = div_apply(domain_select(rm.mux_d1.get(), pll_cpu_p, pll_soc_p, pll_peri_p),
                             rm.div_d1_ratio.get(), rm.div_d1_half.get());
            d2_p = div_apply(domain_select(rm.mux_d2.get(), pll_cpu_p, pll_soc_p, pll_peri_p),
                             rm.div_d2_ratio.get(), rm.div_d2_half.get());
            case (id)
                LEAF_CPU_CORE: return d0_p;
                LEAF_CPU_ACLK: return (rm.gate_en.get()[0]) ? d0_p : 0.0;
                LEAF_AXI_MAIN: return d1_p;
                LEAF_DDR_REF:  return d1_p;
                LEAF_AHB:      return d2_p;
                LEAF_APB:      return d2_p;
                LEAF_PERIPH:   return pll_peri_p;
                LEAF_GMAC_TX:  return pll_period(rm.pll_peri_bypass.get(), rm.pll_peri_refdiv.get(),
                                                 rm.pll_peri_fbdiv.get(),  rm.pll_peri_dsmen.get(),
                                                 rm.pll_peri_frac.get(),   rm.pll_peri_pd2.get());
                LEAF_GMAC_RX:  return 8.0;
                LEAF_QSPI_REF: return pll_peri_p;
                default:       return 0.0;
            endcase
        endfunction
        function real pll_period(input bit bypass, bit[5:0] refdiv, bit[7:0] fbdiv,
                                 input bit dsmen, bit[23:0] frac, input bit[2:0] pd);
            real fbeff, pde;
            if (bypass) return osc_period_ns;
            fbeff = real'(fbdiv);
            if (dsmen) fbeff = real'(fbdiv) + real'(frac) / 2.0**24;  // SPEC
            pde = (pd == 0) ? 1.0 : real'(pd);
            if (fbeff <= 0) return 0.0;
            return osc_period_ns * real'(refdiv) / fbeff * pde;
        endfunction
        function real domain_select(input bit[1:0] sel, input real cpu_p, soc_p, peri_p);
            case (sel[0])
                1'b0: return cpu_p;
                1'b1: return soc_p;
            endcase
        endfunction
        function real div_apply(input real in_p, input bit[6:0] ratio, input bit half);
            real base;
            if (in_p <= 0) return 0.0;
            base = in_p * (real'(ratio) + 1.0);
            return half ? (base - in_p/2.0) : base;
        endfunction
    endclass

    // ---- Coverage ----
    class clkmgr_env_cov extends crg_env_cov;
        `uvm_component_utils(clkmgr_env_cov)
        clkmgr_reg_block rm;
        covergroup cg_pll;
            cp_cpu_byp:  coverpoint rm.pll_cpu_bypass.get();
            cp_soc_byp:  coverpoint rm.pll_soc_bypass.get();
            cp_peri_byp: coverpoint rm.pll_peri_bypass.get();
            cp_cpu_dsm:  coverpoint rm.pll_cpu_dsmen.get();
            cp_peri_dsm: coverpoint rm.pll_peri_dsmen.get();
        endgroup
        covergroup cg_mux;
            cp_d0: coverpoint rm.mux_d0.get();
            cp_d1: coverpoint rm.mux_d1.get();
            cp_d2: coverpoint rm.mux_d2.get();
            cx_d0d1: cross cp_d0, cp_d1;
        endgroup
        covergroup cg_div;
            cp_d0r: coverpoint rm.div_d0_ratio.get() { bins z[] = {[0:4]}; }
            cp_d1r: coverpoint rm.div_d1_ratio.get() { bins z[] = {[0:4]}; }
            cp_d2r: coverpoint rm.div_d2_ratio.get() { bins z[] = {[0:4]}; }
            cp_d0h: coverpoint rm.div_d0_half.get();
            cp_d2h: coverpoint rm.div_d2_half.get();
        endgroup
        covergroup cg_gate;
            cp_g: coverpoint rm.gate_en.get() { bins all_on={16'h3FF}; bins none={0}; bins mid={16'h1FF}; }
        endgroup
        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg_pll=new(); cg_mux=new(); cg_div=new(); cg_gate=new();
        endfunction
        task run_phase(uvm_phase phase);
            forever begin #200ns;
                if (rm != null) begin cg_pll.sample(); cg_mux.sample(); cg_div.sample(); cg_gate.sample(); end
            end
        endtask
    endclass

    // ---- Virtual sequencer + env ----
    class clkmgr_virtual_sequencer extends crg_virtual_sequencer;
        `uvm_component_utils(clkmgr_virtual_sequencer)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    class clkmgr_env extends uvm_env;
        `uvm_component_utils(clkmgr_env)
        apb_agent            apb_agt;
        clkmgr_reg_block     rm;
        apb_reg_adapter      adapter;
        clkmgr_scoreboard    sb;
        clkmgr_env_cov       cov;
        clkmgr_virtual_sequencer vseqr;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            apb_agt = apb_agent::type_id::create("apb_agt", this);
            rm      = clkmgr_reg_block::type_id::create("rm"); rm.build();
            adapter = apb_reg_adapter::type_id::create("adapter");
            sb      = clkmgr_scoreboard::type_id::create("sb", this);
            cov     = clkmgr_env_cov::type_id::create("cov", this);
            vseqr   = clkmgr_virtual_sequencer::type_id::create("vseqr", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            rm.default_map.set_sequencer(apb_agt.sqr, adapter);
            rm.default_map.set_auto_predict(1);
            sb.rm = rm; cov.rm = rm;
            vseqr.apb_sqr = apb_agt.sqr;
        endfunction
    endclass

    `include "seq_lib/clkmgr_vseq_list.sv"
endpackage : clkmgr_env_pkg
`endif
