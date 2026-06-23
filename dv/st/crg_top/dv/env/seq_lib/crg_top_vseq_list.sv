    //==================================================
    // crg_top cross-IP virtual sequences (3-PLL tree)
    //==================================================

    class crg_top_base_vseq extends crg_base_vseq;
        `uvm_object_utils(crg_top_base_vseq)
        `uvm_declare_p_sequencer(crg_top_virtual_sequencer)
        crg_top_env env;
        function new(string name="crg_top_base_vseq"); super.new(name); endfunction
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

    class crg_top_smoke_vseq extends crg_top_base_vseq;
        `uvm_object_utils(crg_top_smoke_vseq)
        function new(string name="crg_top_smoke_vseq"); super.new(name); endfunction
        task body();
            uvm_reg_data_t d;
            #10000ns;  // wait all 3 PLLs lock
            rr(env.rm.clkmgr_rm.pll_cpu_status_r, d);
            `uvm_info("VSEQ", $sformatf("pll_cpu_status=%08h", d), UVM_LOW)
            rr(env.rm.clkmgr_rm.pll_soc_status_r, d);
            `uvm_info("VSEQ", $sformatf("pll_soc_status=%08h", d), UVM_LOW)
            rr(env.rm.clkmgr_rm.pll_peri_status_r, d);
            `uvm_info("VSEQ", $sformatf("pll_peri_status=%08h", d), UVM_LOW)
            rr(env.rm.rstmgr_rm.rst_reason_r_, d);
            `uvm_info("VSEQ", $sformatf("rst_reason=%08h", d), UVM_LOW)
        endtask
    endclass

    class crg_top_lowpower_vseq extends crg_top_base_vseq;
        `uvm_object_utils(crg_top_lowpower_vseq)
        function new(string name="crg_top_lowpower_vseq"); super.new(name); endfunction
        task body();
            uvm_reg_data_t d;
            #10000ns;
            // enable wakes + request low power
            rw(env.rm.pwrmgr_rm.wake_cfg_r, 32'hF);
            rw(env.rm.pwrmgr_rm.ctrl_r, 32'h1);
            #10000ns;
            rr(env.rm.pwrmgr_rm.ctrl_r, d);
            `uvm_info("VSEQ", $sformatf("pwr_ctrl after LP=%08h", d), UVM_LOW)
        endtask
    endclass

    class crg_top_reset_storm_vseq extends crg_top_base_vseq;
        `uvm_object_utils(crg_top_reset_storm_vseq)
        function new(string name="crg_top_reset_storm_vseq"); super.new(name); endfunction
        task body();
            #10000ns;
            for (int i = 0; i < 10; i++) begin
                rw(env.rm.rstmgr_rm.rst_ctrl_r, $urandom_range(0,7));
                #500ns;
            end
        endtask
    endclass

    class crg_top_stress_vseq extends crg_top_base_vseq;
        `uvm_object_utils(crg_top_stress_vseq)
        function new(string name="crg_top_stress_vseq"); super.new(name); endfunction
        task body();
            uvm_status_e status;
            #10000ns;
            for (int i = 0; i < 20; i++) begin
                env.rm.clkmgr_rm.mux_cfg_r.write(status, $urandom_range(0,63), UVM_FRONTDOOR, null, this);
                env.rm.clkmgr_rm.gate_cfg_r.write(status, $urandom_range(0,32'h3FF), UVM_FRONTDOOR, null, this);
                env.rm.rstmgr_rm.rst_ctrl_r.write(status, $urandom_range(0,7), UVM_FRONTDOOR, null, this);
                env.rm.pwrmgr_rm.ctrl_r.write(status, $urandom_range(0,1), UVM_FRONTDOOR, null, this);
                #($urandom_range(100, 400));
            end
        endtask
    endclass
