    //==================================================
    // clkmgr virtual sequences (3-PLL clock tree)
    //==================================================

    class clkmgr_base_vseq extends crg_base_vseq;
        `uvm_object_utils(clkmgr_base_vseq)
        `uvm_declare_p_sequencer(clkmgr_virtual_sequencer)
        clkmgr_env env;
        function new(string name="clkmgr_base_vseq"); super.new(name); endfunction
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
    endclass

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
            uvm_status_e status;
            #8000ns;
            env.rm.pll_cpu_status_r.read(status, d, UVM_FRONTDOOR, null, this);
            `uvm_info("VSEQ", $sformatf("pll_cpu_status=%08h", d), UVM_LOW)
            env.rm.pll_soc_status_r.read(status, d, UVM_FRONTDOOR, null, this);
            `uvm_info("VSEQ", $sformatf("pll_soc_status=%08h", d), UVM_LOW)
            env.rm.pll_peri_status_r.read(status, d, UVM_FRONTDOOR, null, this);
            `uvm_info("VSEQ", $sformatf("pll_peri_status=%08h", d), UVM_LOW)
        endtask
    endclass

    class clkmgr_pll_lock_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_pll_lock_vseq)
        function new(string name="clkmgr_pll_lock_vseq"); super.new(name); endfunction
        task body();
            uvm_status_e status;
            uvm_reg_data_t d;
            #8000ns;
            env.rm.pll_cpu_dsmen.set(1);
            env.rm.pll_cpu_frac.set(24'h400000);
            env.rm.pll_cpu_cfg1_r.update(status, UVM_FRONTDOOR, null, this);
            #8000ns;
            env.rm.pll_cpu_status_r.read(status, d, UVM_FRONTDOOR, null, this);
            `uvm_info("VSEQ", $sformatf("after frac: pll_cpu_status=%08h", d), UVM_LOW)
        endtask
    endclass

    class clkmgr_mux_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_mux_vseq)
        function new(string name="clkmgr_mux_vseq"); super.new(name); endfunction
        task body();
            #8000ns;
            for (int i = 0; i < 8; i++) begin
                rw(env.rm.mux_cfg_r, 6'b00_00_00);
                #200ns;
                rw(env.rm.mux_cfg_r, 6'b01_01_01);
                #200ns;
            end
        endtask
    endclass

    class clkmgr_div_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_div_vseq)
        function new(string name="clkmgr_div_vseq"); super.new(name); endfunction
        task body();
            #8000ns;
            for (int i = 0; i < 5; i++) begin
                rw(env.rm.div_cfg_r, {8'h0, 8'h0, 1'b0, i[6:0], 1'b0});
                #500ns;
            end
            rw(env.rm.div_cfg_r, {8'h0, 1'b1, 7'd2, 8'h0});
            #500ns;
        endtask
    endclass

    class clkmgr_gate_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_gate_vseq)
        function new(string name="clkmgr_gate_vseq"); super.new(name); endfunction
        task body();
            #8000ns;
            for (int i = 0; i < 16; i++) begin
                rw(env.rm.gate_cfg_r, {22'b0, i[9:0]});
                #100ns;
            end
        endtask
    endclass

    class clkmgr_frequency_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_frequency_vseq)
        function new(string name="clkmgr_frequency_vseq"); super.new(name); endfunction
        task body();
            uvm_status_e status;
            uvm_reg_data_t d;
            #8000ns;
            // PLL_PERI frac mode: frac=0xC00000 (0.75 in Q24)
            // spec: fbdiv_eff=10.75 -> Fvco=268.75M, CK0=268.75M (period 3.72ns)
            // bug:  fbdiv_eff=11.5  -> Fvco=287.5M,  CK0=287.5M  (period 3.48ns)
            // diff ~6.5%, within 10% tol -> use higher frac
            // frac=0xF00000 (~0.94): spec 10.94 -> 273.5M; bug 11.875 -> 296.9M; diff 8.5%
            env.rm.pll_peri_dsmen.set(1);
            env.rm.pll_peri_frac.set(24'hF00000);
            env.rm.pll_peri_cfg1_r.update(status, UVM_FRONTDOOR, null, this);
            #8000ns;
            env.rm.pll_peri_status_r.read(status, d, UVM_FRONTDOOR, null, this);
            `uvm_info("VSEQ", $sformatf("after PERI frac: status=%08h", d), UVM_LOW)
        endtask
    endclass

    class clkmgr_coverage_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_coverage_vseq)
        function new(string name="clkmgr_coverage_vseq"); super.new(name); endfunction
        task body();
            uvm_status_e status;
            for (int b = 0; b <= 1; b++)
                for (int dm = 0; dm <= 1; dm++) begin
                    env.rm.pll_cpu_bypass.set(b);  env.rm.pll_cpu_dsmen.set(dm);
                    env.rm.pll_cpu_cfg0_r.update(status, UVM_FRONTDOOR, null, this);
                    env.rm.pll_cpu_cfg1_r.update(status, UVM_FRONTDOOR, null, this);
                    env.rm.pll_soc_bypass.set(b);  env.rm.pll_soc_dsmen.set(dm);
                    env.rm.pll_soc_cfg0_r.update(status, UVM_FRONTDOOR, null, this);
                    env.rm.pll_soc_cfg1_r.update(status, UVM_FRONTDOOR, null, this);
                    env.rm.pll_peri_bypass.set(b); env.rm.pll_peri_dsmen.set(dm);
                    env.rm.pll_peri_cfg0_r.update(status, UVM_FRONTDOOR, null, this);
                    env.rm.pll_peri_cfg1_r.update(status, UVM_FRONTDOOR, null, this);
                    #300ns;
                end
            for (int m = 0; m < 8; m++) begin
                env.rm.mux_d0.set(m[1:0]); env.rm.mux_d1.set(m[1:0]); env.rm.mux_d2.set(m[1:0]);
                env.rm.mux_cfg_r.update(status, UVM_FRONTDOOR, null, this);
                #100ns;
            end
            for (int i = 0; i < 5; i++)
                for (int h = 0; h <= 1; h++) begin
                    env.rm.div_d0_ratio.set(i); env.rm.div_d0_half.set(h);
                    env.rm.div_d1_ratio.set(i); env.rm.div_d2_ratio.set(i);
                    env.rm.div_cfg_r.update(status, UVM_FRONTDOOR, null, this);
                    #100ns;
                end
            for (int g = 0; g < 4; g++) begin
                env.rm.gate_en.set(g == 0 ? 10'h3FF : (g == 1 ? 0 : (g == 2 ? 10'h1FF : 10'h001)));
                env.rm.gate_cfg_r.update(status, UVM_FRONTDOOR, null, this);
                #100ns;
            end
            `uvm_info("COV_VSEQ", "coverage sweep done", UVM_LOW)
        endtask
    endclass

    class clkmgr_stress_vseq extends clkmgr_base_vseq;
        `uvm_object_utils(clkmgr_stress_vseq)
        function new(string name="clkmgr_stress_vseq"); super.new(name); endfunction
        task body();
            uvm_status_e status;
            for (int i = 0; i < 20; i++) begin
                env.rm.pll_cpu_fbdiv.set($urandom_range(10, 200));
                env.rm.pll_cpu_cfg0_r.update(status, UVM_FRONTDOOR, null, this);
                env.rm.mux_cfg_r.write(status, $urandom_range(0, 63), UVM_FRONTDOOR, null, this);
                env.rm.div_cfg_r.write(status, $urandom_range(0, 32'h00FFFFFF), UVM_FRONTDOOR, null, this);
                env.rm.gate_cfg_r.write(status, $urandom_range(0, 32'h000003FF), UVM_FRONTDOOR, null, this);
                #($urandom_range(100, 500));
            end
        endtask
    endclass
