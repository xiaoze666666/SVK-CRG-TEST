/***********************************************************
 * rstmgr_env_pkg - rstmgr unit-test verification environment
 *
 * Same architecture as clkmgr_env_pkg. Tests:
 *   - async reset propagation
 *   - sync release on each domain clk
 *   - glitch filter (BUG_003: filter stuck if clk stops)
 *   - reset reason tracking
 *   - CSR compliance (BUG_005: glitch_th readback = th+1)
 ************************************************************/
`ifndef RSTMGR_ENV_PKG__SV
`define RSTMGR_ENV_PKG__SV

`include "apb_if.sv"
`include "clk_rst_if.sv"

package rstmgr_env_pkg;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import csr_utils_pkg::*;
    import crg_base_pkg::*;
    import crg_reg_map_pkg::*;

    class rstmgr_reg extends uvm_reg;
        `uvm_object_utils(rstmgr_reg)
        function new(string name="rstmgr_reg", int unsigned n_bits=32);
            super.new(name, n_bits, UVM_NO_COVERAGE);
        endfunction
    endclass

    class rstmgr_reg_block extends uvm_reg_block;
        `uvm_object_utils(rstmgr_reg_block)
        rand uvm_reg_field cpu_rst_n, gpu_rst_n, ddr_rst_n;
        rand uvm_reg_field glitch_th;
        uvm_reg_field rst_reason_p, rst_reason_w, rst_reason_d, rst_reason_s, rst_reason_r;
        rand uvm_reg_field rst_req_sw;
        rstmgr_reg rst_ctrl_r, rst_glitch_th_r, rst_reason_r_, rst_req_r;

        virtual function void build();
            rst_ctrl_r      = rstmgr_reg::type_id::create("rst_ctrl");     rst_ctrl_r.configure(this);
            rst_glitch_th_r = rstmgr_reg::type_id::create("rst_glitch_th");rst_glitch_th_r.configure(this);
            rst_reason_r_   = rstmgr_reg::type_id::create("rst_reason");   rst_reason_r_.configure(this);
            rst_req_r       = rstmgr_reg::type_id::create("rst_req");      rst_req_r.configure(this);

            cpu_rst_n = uvm_reg_field::type_id::create("cpu_rst_n");
            gpu_rst_n = uvm_reg_field::type_id::create("gpu_rst_n");
            ddr_rst_n = uvm_reg_field::type_id::create("ddr_rst_n");
            cpu_rst_n.configure(rst_ctrl_r, 1, 0, "RW", 0, RST_CTRL_RST[0], 1, 1, 1);
            gpu_rst_n.configure(rst_ctrl_r, 1, 1, "RW", 0, RST_CTRL_RST[1], 1, 1, 1);
            ddr_rst_n.configure(rst_ctrl_r, 1, 2, "RW", 0, RST_CTRL_RST[2], 1, 1, 1);

            glitch_th = uvm_reg_field::type_id::create("glitch_th");
            glitch_th.configure(rst_glitch_th_r, 8, 0, "RW", 0, RST_GLITCH_TH_RST[7:0], 1, 1, 1);

            rst_reason_p = uvm_reg_field::type_id::create("rst_reason_p");
            rst_reason_w = uvm_reg_field::type_id::create("rst_reason_w");
            rst_reason_d = uvm_reg_field::type_id::create("rst_reason_d");
            rst_reason_s = uvm_reg_field::type_id::create("rst_reason_s");
            rst_reason_r = uvm_reg_field::type_id::create("rst_reason_r");
            rst_reason_p.configure(rst_reason_r_, 1, 0, "RO", 1, RST_REASON_RST[0], 1, 0, 1);
            rst_reason_w.configure(rst_reason_r_, 1, 1, "RO", 1, RST_REASON_RST[1], 1, 0, 1);
            rst_reason_d.configure(rst_reason_r_, 1, 2, "RO", 1, RST_REASON_RST[2], 1, 0, 1);
            rst_reason_s.configure(rst_reason_r_, 1, 3, "RO", 1, RST_REASON_RST[3], 1, 0, 1);
            rst_reason_r.configure(rst_reason_r_, 1, 4, "RO", 1, RST_REASON_RST[4], 1, 0, 1);

            rst_req_sw = uvm_reg_field::type_id::create("rst_req_sw");
            rst_req_sw.configure(rst_req_r, 1, 0, "RW", 0, RST_REQ_RST[0], 1, 1, 1);

            default_map = create_map("default_map", RSTMGR_BASE, 4, UVM_LITTLE_ENDIAN);
            default_map.add_reg(rst_ctrl_r,      RSTMGR_RST_CTRL,      "RW");
            default_map.add_reg(rst_glitch_th_r, RSTMGR_RST_GLITCH_TH, "RW");
            default_map.add_reg(rst_reason_r_,   RSTMGR_RST_REASON,    "RO");
            default_map.add_reg(rst_req_r,       RSTMGR_RST_REQ,       "RW");
            lock_model();
        endfunction
        function new(string name="rstmgr_reg_block");
            super.new(name, UVM_NO_COVERAGE);
        endfunction
    endclass

    // ---- Scoreboard ----
    class rstmgr_scoreboard extends crg_scoreboard;
        `uvm_component_utils(rstmgr_scoreboard)
        rstmgr_reg_block rm;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    // ---- Coverage ----
    class rstmgr_env_cov extends crg_env_cov;
        `uvm_component_utils(rstmgr_env_cov)
        rstmgr_reg_block rm;
        covergroup cg_rst;
            cp_cpu: coverpoint rm.cpu_rst_n.get();
            cp_gpu: coverpoint rm.gpu_rst_n.get();
            cp_ddr: coverpoint rm.ddr_rst_n.get();
            cx_all: cross cp_cpu, cp_gpu, cp_ddr;
        endgroup
        covergroup cg_glitch;
            cp_th: coverpoint rm.glitch_th.get() { bins t[] = {[1:10]}; }
        endgroup
        function new(string name, uvm_component parent);
            super.new(name, parent); cg_rst = new(); cg_glitch = new();
        endfunction
        task run_phase(uvm_phase phase);
            forever begin #200ns;
                if (rm != null) begin cg_rst.sample(); cg_glitch.sample(); end
            end
        endtask
    endclass

    // ---- Virtual sequencer ----
    class rstmgr_virtual_sequencer extends crg_virtual_sequencer;
        `uvm_component_utils(rstmgr_virtual_sequencer)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    // ---- Env ----
    class rstmgr_env extends uvm_env;
        `uvm_component_utils(rstmgr_env)
        apb_agent            apb_agt;
        rstmgr_reg_block     rm;
        apb_reg_adapter      adapter;
        rstmgr_scoreboard    sb;
        rstmgr_env_cov       cov;
        rstmgr_virtual_sequencer vseqr;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            apb_agt = apb_agent::type_id::create("apb_agt", this);
            rm      = rstmgr_reg_block::type_id::create("rm"); rm.build();
            adapter = apb_reg_adapter::type_id::create("adapter");
            sb      = rstmgr_scoreboard::type_id::create("sb", this);
            cov     = rstmgr_env_cov::type_id::create("cov", this);
            vseqr   = rstmgr_virtual_sequencer::type_id::create("vseqr", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            rm.default_map.set_sequencer(apb_agt.sqr, adapter);
            rm.default_map.set_auto_predict(1);
            sb.rm = rm; cov.rm = rm;
            vseqr.apb_sqr = apb_agt.sqr;
        endfunction
    endclass

    `include "seq_lib/rstmgr_vseq_list.sv"
endpackage : rstmgr_env_pkg
`endif
