/***********************************************************
 * crg_top_test_pkg - ST test classes
 ************************************************************/
`ifndef CRG_TOP_TEST_PKG__SV
`define CRG_TOP_TEST_PKG__SV

package crg_top_test_pkg;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import crg_base_pkg::*;
    import crg_top_env_pkg::*;

    class crg_top_base_test extends uvm_test;
        `uvm_component_utils(crg_top_base_test)
        crg_top_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            env = crg_top_env::type_id::create("env", this);
        endfunction
        function void end_of_elaboration_phase(uvm_phase phase);
            uvm_top.set_report_verbosity_level(UVM_HIGH);
        endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            uvm_test_done.set_drain_time(this, 500ns);
        endtask
    endclass

    `define CRG_TOP_TEST(NAME, VSEQ, DELAY) \
    class NAME extends crg_top_base_test; \
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

    `CRG_TOP_TEST(crg_top_smoke_test,        crg_top_smoke_vseq,        8000ns)
    `CRG_TOP_TEST(crg_top_lowpower_test,     crg_top_lowpower_vseq,    20000ns)
    `CRG_TOP_TEST(crg_top_reset_storm_test,  crg_top_reset_storm_vseq, 10000ns)
    `CRG_TOP_TEST(crg_top_stress_test,       crg_top_stress_vseq,      15000ns)

    `undef CRG_TOP_TEST
endpackage : crg_top_test_pkg
`endif
