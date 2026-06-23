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
            uvm_status_e status;
            // Disable bypass, configure PLL int mode with low freq for easy measurement.
            // fbdiv=4, refdiv=1 -> Fvco=160MHz; postdiv1=1,postdiv2=1 -> Fout=160MHz, period=6.25ns
            env.rm.clk_ctrl_r.write(status, 32'h0, UVM_FRONTDOOR, null, this);
            env.rm.pll_cfg_r.write(status, {3'd1,3'd1,9'b0,24'b0,1'b0,8'd4,6'd1}, UVM_FRONTDOOR, null, this);
            #5000ns;
            // Switch to frac mode: frac=0x800000 (0.5 in Q24).
            // Spec: fbdiv_eff = 4 + 0.5 = 4.5 -> period = 25/4.5 = 5.56ns
            // DUT bug (2^23): fbdiv_eff = 4 + 1.0 = 5.0 -> period = 25/5 = 5.0ns
            // Monitor measures the actual DUT output; scoreboard compares to spec -> mismatch.
            env.rm.pll_cfg_r.write(status, {3'd1,3'd1,9'b0,24'h800000,1'b1,8'd4,6'd1}, UVM_FRONTDOOR, null, this);
            #8000ns;
            env.rm.pll_status_r.read(status, d, UVM_FRONTDOOR, null, this);
            `uvm_info("FREQ_VSEQ", $sformatf("pll_status after frac=%08h", d), UVM_LOW)
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
    class clkmgr_coverage_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_coverage_vseq)
        function new(string name="clkmgr_coverage_vseq"); super.new(name); endfunction
        task body();
            uvm_status_e status;
            int pd1_vals[] = '{1, 2, 4};
            int pd2_vals[] = '{1, 2, 4};
            int div_vals[] = '{0, 1, 2, 4, 8};
            int fb_vals[]  = '{4, 50, 100};

            // ---- PLL coverage: bypass x dsmen x postdiv1 x postdiv2 ----
            for (int bp = 0; bp <= 1; bp++) begin
                for (int dm = 0; dm <= 1; dm++) begin
                    foreach (pd1_vals[p1]) foreach (pd2_vals[p2]) begin
                        env.rm.clk_ctrl_r.write(status, bp, UVM_FRONTDOOR, null, this);
                        if (dm == 0)
                            env.rm.pll_cfg_r.write(status, {pd1_vals[p1][2:0], pd2_vals[p2][2:0], 9'b0, 24'b0, 1'b0, 8'd50, 6'd1}, UVM_FRONTDOOR, null, this);
                        else
                            env.rm.pll_cfg_r.write(status, {pd1_vals[p1][2:0], pd2_vals[p2][2:0], 9'b0, 24'h400000, 1'b1, 8'd50, 6'd1}, UVM_FRONTDOOR, null, this);
                        #300ns;
                    end
                end
            end

            // ---- Divider coverage: div_ratio x half_en ----
            env.rm.clk_ctrl_r.write(status, 32'h0, UVM_FRONTDOOR, null, this);
            env.rm.pll_cfg_r.write(status, {3'd1,3'd1,9'b0,24'b0,1'b0,8'd50,6'd1}, UVM_FRONTDOOR, null, this);
            #3000ns;
            foreach (div_vals[dv])
                for (int h = 0; h <= 1; h++) begin
                    env.rm.div_cfg_r.write(status, {h[0], dv[6:0]}, UVM_FRONTDOOR, null, this);
                    #200ns;
                end

            // ---- Gate coverage: cpu x gpu x ddr (all 8 combos) ----
            for (int g = 0; g < 8; g++) begin
                env.rm.gate_cfg_r.write(status, {29'b0, g[2:0]}, UVM_FRONTDOOR, null, this);
                #100ns;
            end

            // ---- Mux coverage: cpu x gpu x ddr (sample of 4^3=64, pick 16) ----
            for (int m = 0; m < 16; m++) begin
                env.rm.mux_cfg_r.write(status, {2'b00, m[3:0], 2'b00}, UVM_FRONTDOOR, null, this);
                #100ns;
            end
            // also exercise each domain independently at each sel value
            for (int s = 0; s < 4; s++) begin
                env.rm.mux_cfg_r.write(status, {2'b00, 2'b00, s[1:0]}, UVM_FRONTDOOR, null, this); #100ns;
                env.rm.mux_cfg_r.write(status, {2'b00, s[1:0], 2'b00}, UVM_FRONTDOOR, null, this); #100ns;
                env.rm.mux_cfg_r.write(status, {s[1:0], 2'b00, 2'b00}, UVM_FRONTDOOR, null, this); #100ns;
            end

            `uvm_info("COV_VSEQ", "coverage sweep done", UVM_LOW)
        endtask
    endclass
