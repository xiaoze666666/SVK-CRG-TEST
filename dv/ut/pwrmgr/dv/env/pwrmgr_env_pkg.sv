/***********************************************************
 * pwrmgr_env_pkg - pwrmgr unit-test verification environment
 *
 * Tests low-power FSM:
 *   - power-down -> iso enable -> clk off -> rst assert
 *   - wake -> clk on -> rst deassert -> iso off
 *   - BUG_006: iso dropped too early during wake (caught by SVA + monitor)
 *   - CSR compliance
 ************************************************************/
`ifndef PWRMGR_ENV_PKG__SV
`define PWRMGR_ENV_PKG__SV

`include "apb_if.sv"
`include "clk_rst_if.sv"

package pwrmgr_env_pkg;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import csr_utils_pkg::*;
    import crg_base_pkg::*;
    import crg_reg_map_pkg::*;

    class pwrmgr_reg extends uvm_reg;
        `uvm_object_utils(pwrmgr_reg)
        function new(string name="pwrmgr_reg", int unsigned n_bits=32);
            super.new(name, n_bits, UVM_NO_COVERAGE);
        endfunction
    endclass

    class pwrmgr_reg_block extends uvm_reg_block;
        `uvm_object_utils(pwrmgr_reg_block)
        rand uvm_reg_field lowpower_req;
        rand uvm_reg_field wake_en0, wake_en1, wake_en2, wake_en3;
        rand uvm_reg_field sw_iso_en;
        uvm_reg_field wake_st0, wake_st1, wake_st2, wake_st3;
        uvm_reg_field main_clk_en, rst_req;
        pwrmgr_reg ctrl_r, wake_cfg_r, wake_status_r, iso_cfg_r;

        virtual function void build();
            ctrl_r        = pwrmgr_reg::type_id::create("ctrl");        ctrl_r.configure(this);
            wake_cfg_r    = pwrmgr_reg::type_id::create("wake_cfg");    wake_cfg_r.configure(this);
            wake_status_r = pwrmgr_reg::type_id::create("wake_status"); wake_status_r.configure(this);
            iso_cfg_r     = pwrmgr_reg::type_id::create("iso_cfg");     iso_cfg_r.configure(this);

            lowpower_req = uvm_reg_field::type_id::create("lowpower_req");
            lowpower_req.configure(ctrl_r, 1, 0, "RW", 0, PWR_CTRL_RST[0], 1, 1, 1);
            main_clk_en  = uvm_reg_field::type_id::create("main_clk_en");
            main_clk_en.configure(ctrl_r, 1, 1, "RO", 1, PWR_CTRL_RST[1], 1, 0, 1);
            rst_req      = uvm_reg_field::type_id::create("rst_req");
            rst_req.configure(ctrl_r, 1, 2, "RO", 1, PWR_CTRL_RST[2], 1, 0, 1);

            wake_en0 = uvm_reg_field::type_id::create("wake_en0");
            wake_en1 = uvm_reg_field::type_id::create("wake_en1");
            wake_en2 = uvm_reg_field::type_id::create("wake_en2");
            wake_en3 = uvm_reg_field::type_id::create("wake_en3");
            wake_en0.configure(wake_cfg_r, 1, 0, "RW", 0, WAKE_CFG_RST[0], 1, 1, 1);
            wake_en1.configure(wake_cfg_r, 1, 1, "RW", 0, WAKE_CFG_RST[1], 1, 1, 1);
            wake_en2.configure(wake_cfg_r, 1, 2, "RW", 0, WAKE_CFG_RST[2], 1, 1, 1);
            wake_en3.configure(wake_cfg_r, 1, 3, "RW", 0, WAKE_CFG_RST[3], 1, 1, 1);

            wake_st0 = uvm_reg_field::type_id::create("ws0");
            wake_st1 = uvm_reg_field::type_id::create("ws1");
            wake_st2 = uvm_reg_field::type_id::create("ws2");
            wake_st3 = uvm_reg_field::type_id::create("ws3");
            wake_st0.configure(wake_status_r, 1, 0, "RC", 1, WAKE_STATUS_RST[0], 1, 0, 1);
            wake_st1.configure(wake_status_r, 1, 1, "RC", 1, WAKE_STATUS_RST[1], 1, 0, 1);
            wake_st2.configure(wake_status_r, 1, 2, "RC", 1, WAKE_STATUS_RST[2], 1, 0, 1);
            wake_st3.configure(wake_status_r, 1, 3, "RC", 1, WAKE_STATUS_RST[3], 1, 0, 1);

            sw_iso_en = uvm_reg_field::type_id::create("sw_iso_en");
            sw_iso_en.configure(iso_cfg_r, 1, 0, "RW", 0, ISO_CFG_RST[0], 1, 1, 1);

            default_map = create_map("default_map", PWRMGR_BASE, 4, UVM_LITTLE_ENDIAN);
            default_map.add_reg(ctrl_r,        'h00, "RW");
            default_map.add_reg(wake_cfg_r,    'h04, "RW");
            default_map.add_reg(wake_status_r, 'h08, "RC");
            default_map.add_reg(iso_cfg_r,     'h0C, "RW");
            lock_model();
        endfunction
        function new(string name="pwrmgr_reg_block");
            super.new(name, UVM_NO_COVERAGE);
        endfunction
    endclass

    class pwrmgr_scoreboard extends crg_scoreboard;
        `uvm_component_utils(pwrmgr_scoreboard)
        pwrmgr_reg_block rm;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    class pwrmgr_env_cov extends crg_env_cov;
        `uvm_component_utils(pwrmgr_env_cov)
        pwrmgr_reg_block rm;
        covergroup cg_lp;
            cp_req: coverpoint rm.lowpower_req.get();
            cp_iso: coverpoint rm.sw_iso_en.get();
        endgroup
        function new(string name, uvm_component parent);
            super.new(name, parent); cg_lp = new();
        endfunction
        task run_phase(uvm_phase phase);
            forever begin #200ns; if (rm != null) cg_lp.sample(); end
        endtask
    endclass

    class pwrmgr_virtual_sequencer extends crg_virtual_sequencer;
        `uvm_component_utils(pwrmgr_virtual_sequencer)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    class pwrmgr_env extends uvm_env;
        `uvm_component_utils(pwrmgr_env)
        apb_agent            apb_agt;
        pwrmgr_reg_block     rm;
        apb_reg_adapter      adapter;
        pwrmgr_scoreboard    sb;
        pwrmgr_env_cov       cov;
        pwrmgr_virtual_sequencer vseqr;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            apb_agt = apb_agent::type_id::create("apb_agt", this);
            rm      = pwrmgr_reg_block::type_id::create("rm"); rm.build();
            adapter = apb_reg_adapter::type_id::create("adapter");
            sb      = pwrmgr_scoreboard::type_id::create("sb", this);
            cov     = pwrmgr_env_cov::type_id::create("cov", this);
            vseqr   = pwrmgr_virtual_sequencer::type_id::create("vseqr", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            rm.default_map.set_sequencer(apb_agt.sqr, adapter);
            rm.default_map.set_auto_predict(1);
            sb.rm = rm; cov.rm = rm;
            vseqr.apb_sqr = apb_agt.sqr;
        endfunction
    endclass

    `include "seq_lib/pwrmgr_vseq_list.sv"
endpackage : pwrmgr_env_pkg
`endif
