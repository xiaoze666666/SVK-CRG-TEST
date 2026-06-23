    //==================================================
    // crg_top cross-IP virtual sequences
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

    // smoke: bring up PLL, check status
    class crg_top_smoke_vseq extends crg_top_base_vseq;
        `uvm_object_utils(crg_top_smoke_vseq)
        function new(string name="crg_top_smoke_vseq"); super.new(name); endfunction
        task body();
            uvm_reg_data_t d;
            rw(env.rm.clkmgr_rm.clk_ctrl_r, 32'h0);
            rw(env.rm.clkmgr_rm.pll_cfg_r,  {3'd1, 3'd1, 9'b0, 24'b0, 1'b0, 8'd100, 6'd1});
            #5000ns;
            rr(env.rm.clkmgr_rm.pll_status_r, d);
            `uvm_info("VSEQ", $sformatf("pll_status=%08h", d), UVM_LOW)
            rr(env.rm.rstmgr_rm.rst_reason_r_, d);
            `uvm_info("VSEQ", $sformatf("rst_reason=%08h", d), UVM_LOW)
        endtask
    endclass

    // low-power: pwrmgr drives clkmgr/rstmgr handshake
    class crg_top_lowpower_vseq extends crg_top_base_vseq;
        `uvm_object_utils(crg_top_lowpower_vseq)
        function new(string name="crg_top_lowpower_vseq"); super.new(name); endfunction
        task body();
            uvm_reg_data_t d;
            // setup PLL
            rw(env.rm.clkmgr_rm.clk_ctrl_r, 32'h0);
            rw(env.rm.clkmgr_rm.pll_cfg_r,  {3'd1, 3'd1, 9'b0, 24'b0, 1'b0, 8'd100, 6'd1});
            #5000ns;
            // enable wakes + request low power
            rw(env.rm.pwrmgr_rm.wake_cfg_r, 32'hF);
            rw(env.rm.pwrmgr_rm.ctrl_r, 32'h1);
            // wait several cycles for the handshake
            #10000ns;
            rr(env.rm.pwrmgr_rm.ctrl_r, d);
            `uvm_info("VSEQ", $sformatf("pwr_ctrl after LP=%08h", d), UVM_LOW)
        endtask
    endclass

    // reset storm: random combination of resets + IP reset enables
    class crg_top_reset_storm_vseq extends crg_top_base_vseq;
        `uvm_object_utils(crg_top_reset_storm_vseq)
        function new(string name="crg_top_reset_storm_vseq"); super.new(name); endfunction
        task body();
            rw(env.rm.clkmgr_rm.clk_ctrl_r, 32'h0);
            rw(env.rm.clkmgr_rm.pll_cfg_r,  {3'd1, 3'd1, 9'b0, 24'b0, 1'b0, 8'd100, 6'd1});
            #5000ns;
            for (int i = 0; i < 10; i++) begin
                rw(env.rm.rstmgr_rm.rst_ctrl_r, $urandom_range(0,7));
                #500ns;
            end
        endtask
    endclass

    // stress: random writes to all 3 IPs
    class crg_top_stress_vseq extends crg_top_base_vseq;
        `uvm_object_utils(crg_top_stress_vseq)
        function new(string name="crg_top_stress_vseq"); super.new(name); endfunction
        task body();
            rw(env.rm.clkmgr_rm.clk_ctrl_r, $urandom_range(0,1));
            rw(env.rm.clkmgr_rm.pll_cfg_r,  $urandom_range(0,16'h7FFF));
            #3000ns;
            for (int i = 0; i < 20; i++) begin
                rw(env.rm.clkmgr_rm.gate_cfg_r, $urandom_range(0,7));
                rw(env.rm.clkmgr_rm.mux_cfg_r,  $urandom_range(0,63));
                rw(env.rm.rstmgr_rm.rst_ctrl_r, $urandom_range(0,7));
                rw(env.rm.pwrmgr_rm.ctrl_r,     $urandom_range(0,1));
                #($urandom_range(100, 400));
            end
        endtask
    endclass
