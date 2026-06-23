/***********************************************************
 * clkmgr_env_pkg - clkmgr unit-test verification environment
 *
 * Layout: env_pkg + seq_lib + sva + tests + tb under ut/clkmgr/dv/.
 * Contains: reg model, scoreboard (period prediction), coverage,
 * virtual sequencer, and 8 vseqs covering all clkmgr behaviors.
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

    // ---- Generic RW register ----
    class clkmgr_reg extends uvm_reg;
        `uvm_object_utils(clkmgr_reg)
        function new(string name="clkmgr_reg", int unsigned n_bits=32);
            super.new(name, n_bits, UVM_NO_COVERAGE);
        endfunction
    endclass

    // ---- Wide register for PLL_CFG (45 bits: frac 24 + divs) ----
    class clkmgr_reg_wide extends uvm_reg;
        `uvm_object_utils(clkmgr_reg_wide)
        function new(string name="clkmgr_reg_wide", int unsigned n_bits=48);
            super.new(name, n_bits, UVM_NO_COVERAGE);
        endfunction
    endclass

    // ---- Reg model ----
    class clkmgr_reg_block extends uvm_reg_block;
        `uvm_object_utils(clkmgr_reg_block)
        rand uvm_reg_field clk_ctrl_bypass, clk_ctrl_src_sel;
        rand uvm_reg_field pll_refdiv, pll_fbdiv, pll_dsmen, pll_frac, pll_pd1, pll_pd2;
        uvm_reg_field pll_lock;
        rand uvm_reg_field div_ratio, div_half;
        rand uvm_reg_field gate_cpu, gate_gpu, gate_ddr;
        rand uvm_reg_field mux_cpu, mux_gpu, mux_ddr;

        clkmgr_reg clk_ctrl_r, pll_status_r, div_cfg_r, gate_cfg_r, mux_cfg_r;
        clkmgr_reg_wide pll_cfg_r;

        virtual function void build();
            clk_ctrl_r    = clkmgr_reg::type_id::create("clk_ctrl");    clk_ctrl_r.configure(this);
            pll_cfg_r     = clkmgr_reg_wide::type_id::create("pll_cfg");  pll_cfg_r.configure(this);
            pll_status_r  = clkmgr_reg::type_id::create("pll_status");  pll_status_r.configure(this);
            div_cfg_r     = clkmgr_reg::type_id::create("div_cfg");     div_cfg_r.configure(this);
            gate_cfg_r    = clkmgr_reg::type_id::create("gate_cfg");    gate_cfg_r.configure(this);
            mux_cfg_r     = clkmgr_reg::type_id::create("mux_cfg");     mux_cfg_r.configure(this);

            // uvm_reg has no build(); field.configure() registers it.

            clk_ctrl_bypass = uvm_reg_field::type_id::create("clk_ctrl_bypass");
            clk_ctrl_src_sel= uvm_reg_field::type_id::create("clk_ctrl_src_sel");
            clk_ctrl_bypass .configure(clk_ctrl_r, 1, 0, "RW", 0, CLK_CTRL_RST[0], 1, 1, 1);
            clk_ctrl_src_sel.configure(clk_ctrl_r, 1, 1, "RW", 0, CLK_CTRL_RST[1], 1, 1, 1);

            pll_refdiv = uvm_reg_field::type_id::create("pll_refdiv");
            pll_fbdiv  = uvm_reg_field::type_id::create("pll_fbdiv");
            pll_dsmen  = uvm_reg_field::type_id::create("pll_dsmen");
            pll_frac   = uvm_reg_field::type_id::create("pll_frac");
            pll_pd1    = uvm_reg_field::type_id::create("pll_pd1");
            pll_pd2    = uvm_reg_field::type_id::create("pll_pd2");
            pll_refdiv.configure(pll_cfg_r,  6,  0, "RW", 0, PLL_CFG_RST[5:0],   1, 1, 1);
            pll_fbdiv .configure(pll_cfg_r,  8,  6, "RW", 0, PLL_CFG_RST[13:6],  1, 1, 1);
            pll_dsmen .configure(pll_cfg_r,  1, 14, "RW", 0, PLL_CFG_RST[14],    1, 1, 1);
            pll_frac  .configure(pll_cfg_r, 24, 15, "RW", 0, PLL_CFG_RST[38:15], 1, 1, 1);
            pll_pd1   .configure(pll_cfg_r,  3, 39, "RW", 0, PLL_CFG_RST[41:39], 1, 1, 1);
            pll_pd2   .configure(pll_cfg_r,  3, 42, "RW", 0, PLL_CFG_RST[44:42], 1, 1, 1);

            pll_lock = uvm_reg_field::type_id::create("pll_lock");
            pll_lock.configure(pll_status_r, 1, 0, "RO", 1, PLL_STATUS_RST[0], 1, 0, 1);

            div_ratio = uvm_reg_field::type_id::create("div_ratio");
            div_half  = uvm_reg_field::type_id::create("div_half");
            div_ratio.configure(div_cfg_r, 7, 0, "RW", 0, DIV_CFG_RST[6:0], 1, 1, 1);
            div_half .configure(div_cfg_r, 1, 7, "RW", 0, DIV_CFG_RST[7],   1, 1, 1);

            gate_cpu = uvm_reg_field::type_id::create("gate_cpu");
            gate_gpu = uvm_reg_field::type_id::create("gate_gpu");
            gate_ddr = uvm_reg_field::type_id::create("gate_ddr");
            gate_cpu.configure(gate_cfg_r, 1, 0, "RW", 0, GATE_CFG_RST[0], 1, 1, 1);
            gate_gpu.configure(gate_cfg_r, 1, 1, "RW", 0, GATE_CFG_RST[1], 1, 1, 1);
            gate_ddr.configure(gate_cfg_r, 1, 2, "RW", 0, GATE_CFG_RST[2], 1, 1, 1);

            mux_cpu = uvm_reg_field::type_id::create("mux_cpu");
            mux_gpu = uvm_reg_field::type_id::create("mux_gpu");
            mux_ddr = uvm_reg_field::type_id::create("mux_ddr");
            mux_cpu.configure(mux_cfg_r, 2, 0, "RW", 0, MUX_CFG_RST[1:0], 1, 1, 1);
            mux_gpu.configure(mux_cfg_r, 2, 2, "RW", 0, MUX_CFG_RST[3:2], 1, 1, 1);
            mux_ddr.configure(mux_cfg_r, 2, 4, "RW", 0, MUX_CFG_RST[5:4], 1, 1, 1);

            default_map = create_map("default_map", CLKMGR_BASE, 4, UVM_LITTLE_ENDIAN);
            default_map.add_reg(clk_ctrl_r,   'h00, "RW");
            default_map.add_reg(pll_cfg_r,    'h04, "RW");
            default_map.add_reg(pll_status_r, 'h08, "RO");
            default_map.add_reg(div_cfg_r,    'h0C, "RW");
            default_map.add_reg(gate_cfg_r,   'h10, "RW");
            default_map.add_reg(mux_cfg_r,    'h14, "RW");
            lock_model();
        endfunction
        function new(string name="clkmgr_reg_block");
            super.new(name, UVM_NO_COVERAGE);
        endfunction
    endclass

    // ---- Sampling structs ----
    typedef struct {
        real period_ns;
        real duty;
        bit  glitch;
        bit  stopped;
    } clk_sample_t;

    class clk_sample_tr extends uvm_object;
        `uvm_object_utils(clk_sample_tr)
        string node;
        clk_sample_t s;
        function new(string name="clk_sample_tr"); super.new(name); endfunction
    endclass

    // ---- Scoreboard: PLL period prediction + glitch flag ----
    class clkmgr_scoreboard extends crg_scoreboard;
        `uvm_component_utils(clkmgr_scoreboard)
        clkmgr_reg_block rm;
        real osc_period_ns = 25.0;
        uvm_analysis_imp #(clk_sample_tr, clkmgr_scoreboard) clk_imp;
        function new(string name, uvm_component parent);
            super.new(name, parent); clk_imp = new("clk_imp", this);
        endfunction
        function void write(clk_sample_tr tr);
            real exp_period = 0, diff;
            bit   found = 0;
            check_count++;
            if (tr.node == "pll_clk") begin
                exp_period = predict_pll_period(); found = 1;
            end else if (tr.node == "cpu_clk") begin
                exp_period = predict_pll_period(); found = 1;
            end
            if (tr.s.glitch) begin
                `uvm_error("CLKMGR_SCB", $sformatf("%s GLITCH detected (BUG_001/BUG_004 candidate)", tr.node))
                error_count++;
            end
            if (found && exp_period > 0) begin
                diff = tr.s.period_ns - exp_period; if (diff < 0) diff = -diff;
                if (diff > exp_period * 0.05 + 1.0) begin
                    `uvm_error("CLKMGR_SCB",
                        $sformatf("%s period=%0.2fns exp=%0.2fns (BUG_002 candidate: PLL frac 2^23 vs 2^24)",
                            tr.node, tr.s.period_ns, exp_period))
                    error_count++;
                end
            end
        endfunction
        function real predict_pll_period();
            bit bypass = rm.clk_ctrl_bypass.get();
            bit [5:0] refdiv = rm.pll_refdiv.get();
            bit [7:0] fbdiv  = rm.pll_fbdiv.get();
            bit dsmen = rm.pll_dsmen.get();
            bit [23:0] frac = rm.pll_frac.get();
            bit [2:0] p1 = rm.pll_pd1.get();
            bit [2:0] p2 = rm.pll_pd2.get();
            real fbeff, post;
            if (bypass) return osc_period_ns;
            fbeff = real'(fbdiv);
            if (dsmen) fbeff = real'(fbdiv) + real'(frac) / 2.0**24; // SPEC
            post = real'(p1) * real'(p2); if (post == 0) post = 1.0;
            if (fbeff <= 0) return 0.0;
            return osc_period_ns * real'(refdiv) / fbeff * post;
        endfunction
    endclass

    // ---- Coverage ----
    class clkmgr_env_cov extends crg_env_cov;
        `uvm_component_utils(clkmgr_env_cov)
        clkmgr_reg_block rm;
        covergroup cg_pll;
            cp_bypass: coverpoint rm.clk_ctrl_bypass.get();
            cp_dsmen : coverpoint rm.pll_dsmen.get();
            cp_pd1   : coverpoint rm.pll_pd1.get() { bins d1={1}; bins d2={2}; bins d4={4}; }
            cx_b_d   : cross cp_bypass, cp_dsmen;
        endgroup
        covergroup cg_div;
            cp_div: coverpoint rm.div_ratio.get() { bins d[] = {[0:8]}; }
            cp_half: coverpoint rm.div_half.get();
            cx_dh: cross cp_div, cp_half;
        endgroup
        covergroup cg_gate;
            cp_cpu: coverpoint rm.gate_cpu.get();
            cp_gpu: coverpoint rm.gate_gpu.get();
            cp_ddr: coverpoint rm.gate_ddr.get();
        endgroup
        covergroup cg_mux;
            cp_cpu: coverpoint rm.mux_cpu.get();
            cp_gpu: coverpoint rm.mux_gpu.get();
            cp_ddr: coverpoint rm.mux_ddr.get();
        endgroup
        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg_pll = new(); cg_div = new(); cg_gate = new(); cg_mux = new();
        endfunction
        task run_phase(uvm_phase phase);
            forever begin #200ns;
                if (rm != null) begin cg_pll.sample(); cg_div.sample(); cg_gate.sample(); cg_mux.sample(); end
            end
        endtask
    endclass

    // ---- Virtual sequencer ----
    class clkmgr_virtual_sequencer extends crg_virtual_sequencer;
        `uvm_component_utils(clkmgr_virtual_sequencer)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    // ---- Env ----
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
