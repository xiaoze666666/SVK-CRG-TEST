    //==================================================
    // rstmgr virtual sequences
    //==================================================

    class rstmgr_base_vseq extends crg_base_vseq;
        `uvm_object_utils(rstmgr_base_vseq)
        `uvm_declare_p_sequencer(rstmgr_virtual_sequencer)
        rstmgr_env env;
        function new(string name="rstmgr_base_vseq"); super.new(name); endfunction
        virtual task pre_body();
            uvm_component c;
            super.pre_body();
            c = p_sequencer.get_parent();
            while (c != null && !$cast(env, c)) c = c.get_parent();
            if (env == null) `uvm_warning("VSEQ", "env not found")
            else rm = env.rm;
        endtask
        task rw(uvm_reg r, uvm_reg_data_t d);
            uvm_status_e status;
            r.write(status, d, UVM_FRONTDOOR, null, this);
        endtask
        task rr(uvm_reg r, output uvm_reg_data_t d);
            uvm_status_e status;
            r.read(status, d, UVM_FRONTDOOR, null, this);
        endtask
    endclass

    // CSR suite
    class rstmgr_common_vseq extends rstmgr_base_vseq;
        `uvm_object_utils(rstmgr_common_vseq)
        function new(string name="rstmgr_common_vseq"); super.new(name); endfunction
        task body();
            string t = "hw_reset";
            if (!$value$plusargs("common_seq_type=%s", t)) t = "hw_reset";
            run_csr_suite(t);
        endtask
    endclass

    class rstmgr_smoke_vseq extends rstmgr_base_vseq;
        `uvm_object_utils(rstmgr_smoke_vseq)
        function new(string name="rstmgr_smoke_vseq"); super.new(name); endfunction
        task body();
            uvm_reg_data_t d;
            // read reason
            rr(env.rm.rst_reason_r_, d);
            `uvm_info("VSEQ", $sformatf("rst_reason=%08h", d), UVM_LOW)
            // toggle sw-rst bit
            rw(env.rm.rst_ctrl_r, 32'h00); // all 8 domains in reset
            #500ns;
            rw(env.rm.rst_ctrl_r, 32'hFF); // all 8 out
            #500ns;
        endtask
    endclass

    class rstmgr_glitch_vseq extends rstmgr_base_vseq;
        `uvm_object_utils(rstmgr_glitch_vseq)
        function new(string name="rstmgr_glitch_vseq"); super.new(name); endfunction
        task body();
            // BUG_005: glitch_th readback = th+1. CSR hw_reset catches this.
            // BUG_003: filter stuck on clk stop — needs TB stimulus (in tb.sv).
            rw(env.rm.rst_glitch_th_r, 32'h4); // 4 cycles
            #1000ns;
        endtask
    endclass

    class rstmgr_sync_vseq extends rstmgr_base_vseq;
        `uvm_object_utils(rstmgr_sync_vseq)
        function new(string name="rstmgr_sync_vseq"); super.new(name); endfunction
        task body();
            // toggle reset enables — async assert / sync release checked in SVA
            for (int i = 0; i < 4; i++) begin
                rw(env.rm.rst_ctrl_r, 32'h00); #300ns;
                rw(env.rm.rst_ctrl_r, 32'hFF); #500ns;
            end
        endtask
    endclass

    class rstmgr_reason_vseq extends rstmgr_base_vseq;
        `uvm_object_utils(rstmgr_reason_vseq)
        function new(string name="rstmgr_reason_vseq"); super.new(name); endfunction
        task body();
            uvm_reg_data_t d;
            rr(env.rm.rst_reason_r_, d);
            `uvm_info("VSEQ", $sformatf("after init: rst_reason=%08h", d), UVM_LOW)
            rw(env.rm.rst_req_r, 32'h1); #500ns;
            rr(env.rm.rst_reason_r_, d);
            `uvm_info("VSEQ", $sformatf("after sw req: rst_reason=%08h", d), UVM_LOW)
        endtask
    endclass

    class rstmgr_stress_vseq extends rstmgr_base_vseq;
        `uvm_object_utils(rstmgr_stress_vseq)
        function new(string name="rstmgr_stress_vseq"); super.new(name); endfunction
        task body();
            for (int i = 0; i < 20; i++) begin
                rw(env.rm.rst_ctrl_r, $urandom_range(0,8'hFF));
                rw(env.rm.rst_glitch_th_r, $urandom_range(0,15));
                #($urandom_range(100, 400));
            end
        endtask
    endclass
