/***********************************************************
 * crg_top_env_pkg - System-test environment
 *
 * Wires g100_crg_top (clkmgr + rstmgr + pwrmgr integrated). The env
 * contains THREE sub-reg_models (one per IP) so cross-IP sequences can
 * drive any register via the shared APB. The scoreboard checks:
 *   - pwrmgr.lowpower -> clkmgr.main_clk_en drops -> rstmgr sees sw_rst
 *   - reset propagation across domains
 *   - clock freq maintained during normal operation
 *
 * This is the SoC top-level verification — instantiate the IP reg models
 * and add cross-IP coverage/checks on top of them.
 ************************************************************/
`ifndef CRG_TOP_ENV_PKG__SV
`define CRG_TOP_ENV_PKG__SV

`include "apb_if.sv"
`include "clk_rst_if.sv"

package crg_top_env_pkg;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import csr_utils_pkg::*;
    import crg_base_pkg::*;
    import crg_reg_map_pkg::*;
    import clkmgr_env_pkg::*;
    import rstmgr_env_pkg::*;
    import pwrmgr_env_pkg::*;

    // One combined reg block aggregating the 3 IP blocks (for cross-IP seqs)
    class crg_top_reg_block extends uvm_reg_block;
        `uvm_object_utils(crg_top_reg_block)
        clkmgr_reg_block clkmgr_rm;
        rstmgr_reg_block rstmgr_rm;
        pwrmgr_reg_block pwrmgr_rm;
        virtual function void build();
            clkmgr_rm = clkmgr_reg_block::type_id::create("clkmgr_rm");
            rstmgr_rm = rstmgr_reg_block::type_id::create("rstmgr_rm");
            pwrmgr_rm = pwrmgr_reg_block::type_id::create("pwrmgr_rm");
            clkmgr_rm.build(); rstmgr_rm.build(); pwrmgr_rm.build();
            lock_model();
        endfunction
        function new(string name="crg_top_reg_block");
            super.new(name, UVM_NO_COVERAGE);
        endfunction
    endclass

    // Cross-IP scoreboard: checks coordination invariants
    class crg_top_scoreboard extends crg_scoreboard;
        `uvm_component_utils(crg_top_scoreboard)
        crg_top_reg_block rm;
        bit last_lowpower;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    class crg_top_virtual_sequencer extends crg_virtual_sequencer;
        `uvm_component_utils(crg_top_virtual_sequencer)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    class crg_top_env extends uvm_env;
        `uvm_component_utils(crg_top_env)
        apb_agent            apb_agt;
        crg_top_reg_block    rm;
        apb_reg_adapter      adapter;
        crg_top_scoreboard   sb;
        crg_top_virtual_sequencer vseqr;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            apb_agt = apb_agent::type_id::create("apb_agt", this);
            rm      = crg_top_reg_block::type_id::create("rm"); rm.build();
            adapter = apb_reg_adapter::type_id::create("adapter");
            sb      = crg_top_scoreboard::type_id::create("sb", this);
            vseqr   = crg_top_virtual_sequencer::type_id::create("vseqr", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            // Each IP block's default_map is hooked to the shared APB agent
            rm.clkmgr_rm.default_map.set_sequencer(apb_agt.sqr, adapter);
            rm.rstmgr_rm.default_map.set_sequencer(apb_agt.sqr, adapter);
            rm.pwrmgr_rm.default_map.set_sequencer(apb_agt.sqr, adapter);
            rm.clkmgr_rm.default_map.set_auto_predict(1);
            rm.rstmgr_rm.default_map.set_auto_predict(1);
            rm.pwrmgr_rm.default_map.set_auto_predict(1);
            sb.rm = rm;
            vseqr.apb_sqr = apb_agt.sqr;
        endfunction
    endclass

    `include "seq_lib/crg_top_vseq_list.sv"
endpackage : crg_top_env_pkg
`endif
