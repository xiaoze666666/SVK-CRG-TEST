    //==================================================
    // clkmgr virtual sequences
    //==================================================

    class clkmgr_base_vseq extends crg_base_vseq;
        `uvm_object_utils(clkmgr_base_vseq)
        `uvm_declare_p_sequencer(clkmgr_virtual_sequencer)
        clkmgr_env env;
        function new(string name="clkmgr_base_vseq"); super.new(name); endfunction
        virtual task pre_body();
            uvm_component c;
            super.pre_body();
            // walk up to find the env
            c = p_sequencer.get_parent();
            while (c != null && !$cast(env, c)) c = c.get_parent();
            if (env == null) `uvm_warning("VSEQ", "env not found, rm may be null")
            else rm = env.rm;
        endtask
        // Convenience register write/read via uvm_reg
        task rw(uvm_reg r, uvm_reg_data_t d);
            uvm_status_e status;
            r.write(status, d, UVM_FRONTDOOR, null, this);
        endtask
        task rr(uvm_reg r, output uvm_reg_data_t d);
            uvm_status_e status;
            r.read(status, d, UVM_FRONTDOOR, null, this);
        endtask
    endclass

    // CSR compliance suite
    class clkmgr_common_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_common_vseq)
        function new(string name="clkmgr_common_vseq"); super.new(name); endfunction
        task body();
            string t = "hw_reset";
            if (!$value$plusargs("common_seq_type=%s", t)) t = "hw_reset";
            run_csr_suite(t);
        endtask
    endclass

    class clkmgr_smoke_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_smoke_vseq)
        function new(string name="clkmgr_smoke_vseq"); super.new(name); endfunction
        task body();
            uvm_reg_data_t d;
            // power-up: bypass PLL, switch to OSC
            rw(env.rm.clk_ctrl_r, 32'h1);
            #200ns;
            // engage PLL int mode
            rw(env.rm.clk_ctrl_r, 32'h0);
            rw(env.rm.pll_cfg_r,  {3'd1, 3'd1, 9'b0, 24'b0, 1'b0, 8'd100, 6'd1});
            #5000ns; // wait lock
            rr(env.rm.pll_status_r, d);
            `uvm_info("VSEQ", $sformatf("pll_status=%08h lock=%0d", d, d[0]), UVM_LOW)
        endtask
    endclass

    class clkmgr_div_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_div_vseq)
        function new(string name="clkmgr_div_vseq"); super.new(name); endfunction
        task body();
            rw(env.rm.clk_ctrl_r, 32'h0);
            rw(env.rm.pll_cfg_r, {3'd1,3'd1,9'b0,24'b0,1'b0,8'd100,6'd1});
            #5000ns;
            for (int i = 0; i < 6; i++) begin
                rw(env.rm.div_cfg_r, {1'b0, i[6:0]});
                #500ns;
            end
            for (int i = 0; i < 4; i++) begin
                rw(env.rm.div_cfg_r, {1'b1, i[6:0]});
                #500ns;
            end
        endtask
    endclass

    class clkmgr_gate_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_gate_vseq)
        function new(string name="clkmgr_gate_vseq"); super.new(name); endfunction
        task body();
            rw(env.rm.clk_ctrl_r, 32'h0);
            rw(env.rm.pll_cfg_r, {3'd1,3'd1,9'b0,24'b0,1'b0,8'd100,6'd1});
            #5000ns;
            // toggle gate bits rapidly — triggers BUG_004 runt pulse
            for (int i = 0; i < 16; i++) begin
                rw(env.rm.gate_cfg_r, {29'b0, i[2:0]});
                #100ns;
            end
        endtask
    endclass

    class clkmgr_mux_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_mux_vseq)
        function new(string name="clkmgr_mux_vseq"); super.new(name); endfunction
        task body();
            rw(env.rm.clk_ctrl_r, 32'h0);
            rw(env.rm.pll_cfg_r, {3'd1,3'd1,9'b0,24'b0,1'b0,8'd100,6'd1});
            #5000ns;
            // repeatedly switch mux — triggers BUG_001 runt pulse
            for (int i = 0; i < 8; i++) begin
                rw(env.rm.mux_cfg_r, 6'b00_00_00); #200ns;
                rw(env.rm.mux_cfg_r, 6'b01_01_01); #200ns;
            end
        endtask
    endclass

    class clkmgr_frequency_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_frequency_vseq)
        function new(string name="clkmgr_frequency_vseq"); super.new(name); endfunction
        task body();
            uvm_reg_data_t d;
            rw(env.rm.clk_ctrl_r, 32'h0);
            // int mode
            rw(env.rm.pll_cfg_r, {3'd1,3'd1,9'b0,24'b0,1'b0,8'd50,6'd1});
            #5000ns;
            // frac mode — triggers BUG_002 freq doubling (2^23 instead of 2^24)
            rw(env.rm.pll_cfg_r, {3'd1,3'd1,9'b0,24'h800000,1'b1,8'd50,6'd1});
            #5000ns;
            rr(env.rm.pll_status_r, d);
            `uvm_info("VSEQ", $sformatf("after frac: status=%08h", d), UVM_LOW)
        endtask
    endclass

    class clkmgr_stress_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_stress_vseq)
        function new(string name="clkmgr_stress_vseq"); super.new(name); endfunction
        task body();
            rw(env.rm.clk_ctrl_r, $urandom_range(0,1));
            rw(env.rm.pll_cfg_r,  $urandom_range(0, 16'h7FFF));
            #3000ns;
            for (int i = 0; i < 20; i++) begin
                rw(env.rm.div_cfg_r,  $urandom_range(0, 255));
                rw(env.rm.gate_cfg_r, $urandom_range(0, 7));
                rw(env.rm.mux_cfg_r,  $urandom_range(0, 63));
                #($urandom_range(100, 500));
            end
        endtask
    endclass
