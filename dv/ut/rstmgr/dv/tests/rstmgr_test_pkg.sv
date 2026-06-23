/***********************************************************
 * rstmgr_test_pkg - rstmgr UT test classes
 ************************************************************/
`ifndef RSTMGR_TEST_PKG__SV
`define RSTMGR_TEST_PKG__SV

package rstmgr_test_pkg;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import crg_base_pkg::*;
    import rstmgr_env_pkg::*;

    class rstmgr_base_test extends uvm_test;
        `uvm_component_utils(rstmgr_base_test)
        rstmgr_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            env = rstmgr_env::type_id::create("env", this);
        endfunction
        function void end_of_elaboration_phase(uvm_phase phase);
            uvm_top.set_report_verbosity_level(UVM_HIGH);
        endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            uvm_test_done.set_drain_time(this, 500ns);
        endtask
    endclass

    `define RSTMGR_TEST(NAME, VSEQ, DELAY) \
    class NAME extends rstmgr_base_test; \
        `uvm_component_utils(NAME) \
        function new(string name, uvm_component parent); super.new(name, parent); endfunction \
        task run_phase(uvm_phase phase); \
            VSEQ v; \
            super.run_phase(phase); \
            v = VSEQ::type_id::create("v"); \
            v.set_sequencer(env.vseqr); \
            v.start(env.vseqr); \
            #DELAY; phase.drop_objection(this); \
        endtask \
    endclass

    `RSTMGR_TEST(rstmgr_smoke_test,  rstmgr_smoke_vseq,  1000ns)
    `RSTMGR_TEST(rstmgr_common_test, rstmgr_common_vseq, 2000ns)
    `RSTMGR_TEST(rstmgr_glitch_test, rstmgr_glitch_vseq, 2000ns)
    `RSTMGR_TEST(rstmgr_sync_test,   rstmgr_sync_vseq,   3000ns)
    `RSTMGR_TEST(rstmgr_reason_test, rstmgr_reason_vseq, 1500ns)
    `RSTMGR_TEST(rstmgr_stress_test, rstmgr_stress_vseq, 3000ns)

    `undef RSTMGR_TEST
endpackage : rstmgr_test_pkg
`endif
