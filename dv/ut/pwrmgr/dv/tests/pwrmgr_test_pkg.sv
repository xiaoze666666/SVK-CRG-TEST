/***********************************************************
 * pwrmgr_test_pkg - pwrmgr UT test classes
 ************************************************************/
`ifndef PWRMGR_TEST_PKG__SV
`define PWRMGR_TEST_PKG__SV

package pwrmgr_test_pkg;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import crg_base_pkg::*;
    import pwrmgr_env_pkg::*;

    class pwrmgr_base_test extends uvm_test;
        `uvm_component_utils(pwrmgr_base_test)
        pwrmgr_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            env = pwrmgr_env::type_id::create("env", this);
        endfunction
        function void end_of_elaboration_phase(uvm_phase phase);
            uvm_top.set_report_verbosity_level(UVM_HIGH);
        endfunction
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            uvm_test_done.set_drain_time(this, 500ns);
        endtask
    endclass

    `define PWRMGR_TEST(NAME, VSEQ, DELAY) \
    class NAME extends pwrmgr_base_test; \
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

    `PWRMGR_TEST(pwrmgr_smoke_test,    pwrmgr_smoke_vseq,    1500ns)
    `PWRMGR_TEST(pwrmgr_common_test,   pwrmgr_common_vseq,   2000ns)
    `PWRMGR_TEST(pwrmgr_lowpower_test, pwrmgr_lowpower_vseq, 8000ns)
    `PWRMGR_TEST(pwrmgr_wake_test,     pwrmgr_wake_vseq,     5000ns)
    `PWRMGR_TEST(pwrmgr_iso_test,      pwrmgr_iso_vseq,      2000ns)
    `PWRMGR_TEST(pwrmgr_stress_test,   pwrmgr_stress_vseq,   5000ns)

    `undef PWRMGR_TEST
endpackage : pwrmgr_test_pkg
`endif
