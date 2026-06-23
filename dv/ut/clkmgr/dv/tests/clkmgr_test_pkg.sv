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

    // One test per vseq, picked by +UVM_TESTNAME
    class clkmgr_smoke_test extends clkmgr_base_test;
        `uvm_component_utils(clkmgr_smoke_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            clkmgr_smoke_vseq v;
            super.run_phase(phase);
            v = clkmgr_smoke_vseq::type_id::create("v");
            v.set_sequencer(env.vseqr);
            v.start(env.vseqr);
            #1000ns; phase.drop_objection(this);
        endtask
    endclass

    class clkmgr_common_test extends clkmgr_base_test;
        `uvm_component_utils(clkmgr_common_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            clkmgr_common_vseq v;
            super.run_phase(phase);
            v = clkmgr_common_vseq::type_id::create("v");
            v.set_sequencer(env.vseqr);
            v.start(env.vseqr);
            #1000ns; phase.drop_objection(this);
        endtask
    endclass

    class clkmgr_div_test extends clkmgr_base_test;
        `uvm_component_utils(clkmgr_div_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            clkmgr_div_vseq v;
            super.run_phase(phase);
            v = clkmgr_div_vseq::type_id::create("v");
            v.set_sequencer(env.vseqr);
            v.start(env.vseqr);
            #1000ns; phase.drop_objection(this);
        endtask
    endclass

    class clkmgr_gate_test extends clkmgr_base_test;
        `uvm_component_utils(clkmgr_gate_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            clkmgr_gate_vseq v;
            super.run_phase(phase);
            v = clkmgr_gate_vseq::type_id::create("v");
            v.set_sequencer(env.vseqr);
            v.start(env.vseqr);
            #1000ns; phase.drop_objection(this);
        endtask
    endclass

    class clkmgr_mux_test extends clkmgr_base_test;
        `uvm_component_utils(clkmgr_mux_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            clkmgr_mux_vseq v;
            super.run_phase(phase);
            v = clkmgr_mux_vseq::type_id::create("v");
            v.set_sequencer(env.vseqr);
            v.start(env.vseqr);
            #1000ns; phase.drop_objection(this);
        endtask
    endclass

    class clkmgr_frequency_test extends clkmgr_base_test;
        `uvm_component_utils(clkmgr_frequency_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            clkmgr_frequency_vseq v;
            super.run_phase(phase);
            v = clkmgr_frequency_vseq::type_id::create("v");
            v.set_sequencer(env.vseqr);
            v.start(env.vseqr);
            #1000ns; phase.drop_objection(this);
        endtask
    endclass

    class clkmgr_stress_test extends clkmgr_base_test;
        `uvm_component_utils(clkmgr_stress_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            clkmgr_stress_vseq v;
            super.run_phase(phase);
            v = clkmgr_stress_vseq::type_id::create("v");
            v.set_sequencer(env.vseqr);
            v.start(env.vseqr);
            #2000ns; phase.drop_objection(this);
        endtask
    endclass

    class clkmgr_coverage_test extends clkmgr_base_test;
        `uvm_component_utils(clkmgr_coverage_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        task run_phase(uvm_phase phase);
            clkmgr_coverage_vseq v;
            super.run_phase(phase);
            v = clkmgr_coverage_vseq::type_id::create("v");
            v.set_sequencer(env.vseqr);
            v.start(env.vseqr);
            #500ns; phase.drop_objection(this);
        endtask
    endclass

endpackage : clkmgr_test_pkg
`endif
