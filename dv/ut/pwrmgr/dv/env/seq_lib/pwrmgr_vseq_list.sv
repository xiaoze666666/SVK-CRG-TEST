    //==================================================
    // pwrmgr virtual sequences
    //==================================================

    class pwrmgr_base_vseq extends crg_base_vseq;
        `uvm_object_utils(pwrmgr_base_vseq)
        `uvm_declare_p_sequencer(pwrmgr_virtual_sequencer)
        pwrmgr_env env;
        function new(string name="pwrmgr_base_vseq"); super.new(name); endfunction
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

    class pwrmgr_common_vseq extends pwrmgr_base_vseq;
        `uvm_object_utils(pwrmgr_common_vseq)
        function new(string name="pwrmgr_common_vseq"); super.new(name); endfunction
        task body();
            string t = "hw_reset";
            if (!$value$plusargs("common_seq_type=%s", t)) t = "hw_reset";
            run_csr_suite(t);
        endtask
    endclass

    class pwrmgr_smoke_vseq extends pwrmgr_base_vseq;
        `uvm_object_utils(pwrmgr_smoke_vseq)
        function new(string name="pwrmgr_smoke_vseq"); super.new(name); endfunction
        task body();
            uvm_reg_data_t d;
            rr(env.rm.ctrl_r, d);
            `uvm_info("VSEQ", $sformatf("pwr_ctrl=%08h", d), UVM_LOW)
        endtask
    endclass

    // Low-power cycle: request -> wait -> wake
    class pwrmgr_lowpower_vseq extends pwrmgr_base_vseq;
        `uvm_object_utils(pwrmgr_lowpower_vseq)
        function new(string name="pwrmgr_lowpower_vseq"); super.new(name); endfunction
        task body();
            // enable wake sources first
            rw(env.rm.wake_cfg_r, 32'hF);
            // request low-power
            rw(env.rm.ctrl_r, 32'h1);
            // wait FSM to reach PD
            #2000ns;
            // (wake is fired by TB stimulus on wake_src_i; here just rely on tb)
            #5000ns;
            `uvm_info("VSEQ", "lowpower cycle done", UVM_LOW)
        endtask
    endclass

    class pwrmgr_wake_vseq extends pwrmgr_base_vseq;
        `uvm_object_utils(pwrmgr_wake_vseq)
        function new(string name="pwrmgr_wake_vseq"); super.new(name); endfunction
        task body();
            uvm_reg_data_t d;
            rw(env.rm.wake_cfg_r, 32'hF);
            rw(env.rm.ctrl_r, 32'h1);
            #2000ns;
            rr(env.rm.wake_status_r, d);
            `uvm_info("VSEQ", $sformatf("wake_status=%08h", d), UVM_LOW)
            #2000ns;
        endtask
    endclass

    class pwrmgr_iso_vseq extends pwrmgr_base_vseq;
        `uvm_object_utils(pwrmgr_iso_vseq)
        function new(string name="pwrmgr_iso_vseq"); super.new(name); endfunction
        task body();
            rw(env.rm.iso_cfg_r, 32'h1); // sw iso on
            #500ns;
            rw(env.rm.iso_cfg_r, 32'h0);
            #500ns;
        endtask
    endclass

    class pwrmgr_stress_vseq extends pwrmgr_base_vseq;
        `uvm_object_utils(pwrmgr_stress_vseq)
        function new(string name="pwrmgr_stress_vseq"); super.new(name); endfunction
        task body();
            for (int i = 0; i < 20; i++) begin
                rw(env.rm.ctrl_r,     $urandom_range(0,1));
                rw(env.rm.wake_cfg_r, $urandom_range(0,15));
                rw(env.rm.iso_cfg_r,  $urandom_range(0,1));
                #($urandom_range(100, 400));
            end
        endtask
    endclass
