/***********************************************************
 * clkmgr_test_pkg - clkmgr UT test classes
 ************************************************************/
`ifndef CLKMGR_TEST_PKG__SV
`define CLKMGR_TEST_PKG__SV

package clkmgr_test_pkg;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import crg_base_pkg::*;
    import clkmgr_env_pkg::*;

    class clkmgr_base_test extends uvm_test;
        `uvm_component_utils(clkmgr_base_test)
        clkmgr_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            env = clkmgr_env::type_id::create("env", this);
        endfunction
        function void end_of_elaboration_phase(uvm_phase phase);
            uvm_top.set_report_verbosity_level(UVM_HIGH);
        endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            uvm_test_done.set_drain_time(this, 500ns);
        endtask
    endclass

    `define CLKMGR_TEST(NAME, VSEQ, DELAY) \
    class NAME extends clkmgr_base_test; \
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

    `CLKMGR_TEST(clkmgr_smoke_test,     clkmgr_smoke_vseq,     2000ns)
    `CLKMGR_TEST(clkmgr_common_test,    clkmgr_common_vseq,    2000ns)
    `CLKMGR_TEST(clkmgr_pll_lock_test,  clkmgr_pll_lock_vseq, 18000ns)
    `CLKMGR_TEST(clkmgr_mux_test,       clkmgr_mux_vseq,      12000ns)
    `CLKMGR_TEST(clkmgr_div_test,       clkmgr_div_vseq,      12000ns)
    `CLKMGR_TEST(clkmgr_gate_test,      clkmgr_gate_vseq,     12000ns)
    `CLKMGR_TEST(clkmgr_frequency_test, clkmgr_frequency_vseq,18000ns)
    `CLKMGR_TEST(clkmgr_coverage_test,  clkmgr_coverage_vseq, 5000ns)
    `CLKMGR_TEST(clkmgr_stress_test,    clkmgr_stress_vseq,   15000ns)

    `undef CLKMGR_TEST
endpackage : clkmgr_test_pkg
`endif
