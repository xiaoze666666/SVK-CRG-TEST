/***********************************************************
 * crg_base_pkg - Base env / vseq / test layer
 *
 * Provides crg_base_env / crg_base_vseq / crg_base_test that all three
 * UT envs and the ST env specialize via type parameters. Kept small and
 * readable so reviewers can audit the inheritance chain in one pass.
 *
 * Each specialized env overrides:
 *   - CFG_T               (env config)
 *   - COV_T               (coverage)
 *   - VIRTUAL_SEQUENCER_T (per-IP vseqr)
 *   - SCOREBOARD_T        (per-IP scoreboard)
 * And fetches its own virtual interfaces from config_db.
 ************************************************************/
`ifndef CRG_BASE_PKG__SV
`define CRG_BASE_PKG__SV

package crg_base_pkg;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import csr_utils_pkg::*;

    // ---- Base env cfg ----
    class crg_env_cfg extends uvm_object;
        `uvm_object_utils(crg_env_cfg)
        bit has_checks = 1;
        bit has_coverage = 1;
        bit en_cov = 1;
        function new(string name="crg_env_cfg"); super.new(name); endfunction
    endclass

    // ---- Base coverage (empty hook) ----
    class crg_env_cov extends uvm_component;
        `uvm_component_utils(crg_env_cov)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    // ---- Base virtual sequencer ----
    class crg_virtual_sequencer extends uvm_sequencer;
        `uvm_component_utils(crg_virtual_sequencer)
        apb_sequencer apb_sqr;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    // ---- Base scoreboard ----
    class crg_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(crg_scoreboard)
        int check_count = 0;
        int error_count = 0;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual function void report_phase(uvm_phase phase);
            `uvm_info("SCB", $sformatf("checks=%0d errors=%0d", check_count, error_count), UVM_LOW)
        endfunction
    endclass

    // ---- Base env ----
    class crg_base_env extends uvm_env;
        `uvm_component_utils(crg_base_env)
        apb_agent       apb_agt;
        apb_reg_adapter adapter;
        crg_env_cfg     cfg;
        crg_env_cov     cov;
        crg_virtual_sequencer vseqr;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual function void build_phase(uvm_phase phase);
            apb_agt = apb_agent::type_id::create("apb_agt", this);
            adapter = apb_reg_adapter::type_id::create("adapter");
            cfg     = crg_env_cfg::type_id::create("cfg");
            cov     = crg_env_cov::type_id::create("cov", this);
            vseqr   = crg_virtual_sequencer::type_id::create("vseqr", this);
        endfunction
        virtual function void connect_phase(uvm_phase phase);
            vseqr.apb_sqr = apb_agt.sqr;
        endfunction
    endclass

    // ---- Base virtual sequence ----
    class crg_base_vseq extends uvm_sequence;
        `uvm_object_utils(crg_base_vseq)
        `uvm_declare_p_sequencer(crg_virtual_sequencer)
        crg_env_cfg cfg;
        apb_agent_pkg::apb_sequencer apb_sqr;
        uvm_reg_block rm;
        function new(string name="crg_base_vseq"); super.new(name); endfunction
        virtual task pre_body();
            if (p_sequencer != null) apb_sqr = p_sequencer.apb_sqr;
        endtask
        // run a CSR suite by name ("hw_reset", "bit_bash", "aliasing")
        virtual task run_csr_suite(string which);
            uvm_sequence seq;
            case (which)
                "hw_reset": begin
                    csr_hw_reset_seq hw = csr_hw_reset_seq::type_id::create("hw");
                    hw.rm = rm; hw.set_sequencer(p_sequencer.apb_sqr);
                    hw.start(p_sequencer.apb_sqr);
                end
                "bit_bash": begin
                    csr_bit_bash_seq bb = csr_bit_bash_seq::type_id::create("bb");
                    bb.rm = rm; bb.set_sequencer(p_sequencer.apb_sqr);
                    bb.start(p_sequencer.apb_sqr);
                end
                "aliasing": begin
                    csr_aliasing_seq al = csr_aliasing_seq::type_id::create("al");
                    al.set_sequencer(p_sequencer.apb_sqr);
                    al.rm = rm;
                    al.start(p_sequencer.apb_sqr);
                end
            endcase
        endtask
    endclass

    // ---- Base test ----
    class crg_base_test extends uvm_test;
        `uvm_component_utils(crg_base_test)
        crg_base_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual function void build_phase(uvm_phase phase);
            env = crg_base_env::type_id::create("env", this);
        endfunction
        virtual task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            uvm_test_done.set_drain_time(this, 200ns);
        endtask
    endclass

endpackage : crg_base_pkg
`endif
